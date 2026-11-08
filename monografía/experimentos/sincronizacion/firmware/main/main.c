// Nodo oscilador de Kuramoto.
//
// Cada T_s (ts_ms) una tarea integra por Euler:
//   theta_i += dt * (omega_i + K/N * sum_{j != i, conocido} sin(hat_j - theta_i))
// con dt = tiempo real transcurrido (esp_timer), no el T_s nominal, para que la
// demora de planificación del emulador no cambie la velocidad de fase. El divisor
// N es fijo aunque falten fases. Cada h otra tarea publica un PhaseReport en los
// instantes t_inicio + desfase + m*h; el próximo instante se calcula desde el
// inicio, así que la publicación no deriva.
//
// Flujo: config -> red -> reloj -> MQTT -> READY -> espera t_inicio -> INICIO ->
// duracion_s -> DONE. Salida por UART: READY, INICIO, DONE y los errores
// CFGERR / SYNCERR / MQTTERR. No se imprime nada por mensaje.
#include <math.h>
#include <stdio.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "kuramoto.pb.h"
#include "node.h"
#include "nvs_flash.h"
#include "pb_encode.h"

#define OSC_DONE BIT0
#define PUB_DONE BIT1
#define TWO_PI 6.283185307179586

static node_config_t cfg;
static EventGroupHandle_t s_done;
static int64_t s_t0_us;   // inicio (t_inicio) en la escala de esp_timer
static int64_t s_fin_us;  // fin (t_inicio + duracion) en la escala de esp_timer

// Estado compartido entre la integración (escribe) y la publicación (lee).
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;
static double s_theta, s_vel;
static uint64_t s_theta_t_us; // epoch en que se calculó s_theta
static volatile uint32_t s_enviados, s_overruns;

// Espera de precisión: un esp_timer de un disparo despierta a la tarea que llama
// (el tick de FreeRTOS es de 10 ms, muy grueso para las publicaciones).
typedef struct { esp_timer_handle_t t; } waiter_t;

static void wake(void *arg) { xTaskNotifyGive((TaskHandle_t)arg); }

static void waiter_init(waiter_t *w)
{
    esp_timer_create_args_t a = {.callback = wake, .arg = xTaskGetCurrentTaskHandle(), .name = "w"};
    ESP_ERROR_CHECK(esp_timer_create(&a, &w->t));
}

// Bloquea hasta el instante abs_us (escala de esp_timer).
static void wait_until(waiter_t *w, int64_t abs_us)
{
    int64_t rel = abs_us - esp_timer_get_time();
    if (rel <= 0) {
        return;
    }
    ulTaskNotifyTake(pdTRUE, 0); // descarta avisos viejos
    esp_timer_start_once(w->t, rel);
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
}

static double wrap(double x)
{
    x = fmod(x, TWO_PI);
    return x < 0 ? x + TWO_PI : x;
}

static void osc_task(void *arg)
{
    waiter_t w;
    waiter_init(&w);
    wait_until(&w, s_t0_us);
    const int64_t ts_us = (int64_t)cfg.ts_ms * 1000;
    const double kn = cfg.k / (double)cfg.n;
    double theta = wrap(cfg.theta0);
    int64_t prev = esp_timer_get_time();
    int64_t prog = prev; // instante programado del paso actual
    TickType_t wake_t = xTaskGetTickCount();

    while (prev < s_fin_us) {
        vTaskDelayUntil(&wake_t, pdMS_TO_TICKS(cfg.ts_ms));
        prog += ts_us;
        int64_t ahora = esp_timer_get_time();
        if (ahora - prog > ts_us) {
            s_overruns++; // el paso arrancó más de un T_s tarde
        }
        double dt = (double)(ahora - prev) * 1e-6;
        prev = ahora;
        double vel = cfg.omega + kn * phases_coupling(&cfg, theta);
        theta = wrap(theta + dt * vel);
        uint64_t t_epoch = now_epoch_us();
        portENTER_CRITICAL(&s_lock);
        s_theta = theta;
        s_vel = vel;
        s_theta_t_us = t_epoch;
        portEXIT_CRITICAL(&s_lock);
    }
    xEventGroupSetBits(s_done, OSC_DONE);
    vTaskDelete(NULL);
}

static void pub_task(void *arg)
{
    waiter_t w;
    waiter_init(&w);
    const int64_t h_us = (int64_t)cfg.h_ms * 1000;
    uint32_t seq = 0;
    for (uint32_t m = 0;; m++) {
        int64_t plazo = s_t0_us + (int64_t)cfg.desfase_ms * 1000 + (int64_t)m * h_us;
        if (plazo >= s_fin_us) {
            break;
        }
        wait_until(&w, plazo);
        double theta, vel;
        uint64_t t_us;
        portENTER_CRITICAL(&s_lock);
        theta = s_theta;
        vel = s_vel;
        t_us = s_theta_t_us;
        portEXIT_CRITICAL(&s_lock);

        kur_PhaseReport r = kur_PhaseReport_init_zero;
        r.id = cfg.id;
        r.theta = (float)theta;
        r.velocidad = (float)vel;
        r.seq = seq++;
        r.t_us = t_us;
        uint8_t buf[kur_PhaseReport_size];
        pb_ostream_t s = pb_ostream_from_buffer(buf, sizeof(buf));
        if (pb_encode(&s, kur_PhaseReport_fields, &r) && mqtt_node_publish(buf, s.bytes_written)) {
            s_enviados++;
        }
    }
    xEventGroupSetBits(s_done, PUB_DONE);
    vTaskDelete(NULL);
}

static void idle(void)
{
    for (;;) {
        vTaskDelay(portMAX_DELAY);
    }
}

void app_main(void)
{
    ESP_ERROR_CHECK(nvs_flash_init());
    if (!config_load(&cfg)) idle();
    if (!net_start(&cfg)) idle();
    if (!timesync_start(&cfg)) idle();
    if (!mqtt_node_start(&cfg)) idle();
    printf("READY id=%lu\n", (unsigned long)cfg.id);

    // t_inicio (epoch o desde el arranque) -> escala de esp_timer.
    int64_t falta = (int64_t)(cfg.t_inicio_ms * 1000ULL) - (int64_t)now_epoch_us();
    s_t0_us = esp_timer_get_time() + falta;
    s_fin_us = s_t0_us + (int64_t)cfg.duracion_s * 1000000;
    s_theta = wrap(cfg.theta0);
    s_vel = cfg.omega;
    s_theta_t_us = now_epoch_us();
    s_done = xEventGroupCreate();
    xTaskCreate(osc_task, "osc", 4096, NULL, 10, NULL);
    xTaskCreate(pub_task, "pub", 4096, NULL, 9, NULL);

    waiter_t w;
    waiter_init(&w);
    wait_until(&w, s_t0_us);
    printf("INICIO\n");
    xEventGroupWaitBits(s_done, OSC_DONE | PUB_DONE, pdFALSE, pdTRUE, portMAX_DELAY);
    printf("DONE id=%lu enviados=%lu recibidos=%lu overruns=%lu\n", (unsigned long)cfg.id,
           (unsigned long)s_enviados, (unsigned long)mqtt_node_received(),
           (unsigned long)s_overruns);
    idle();
}
