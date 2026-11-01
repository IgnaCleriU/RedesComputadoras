// Nodo de telemetría del experimento MQTT vs HTTP(S).
//
// Es firmware ESP-IDF real que corre en el QEMU de Espressif. Se compila una sola
// vez para toda la matriz: lo que cambia entre corridas se lee al arrancar de la
// partición cfg (config.c), que escribe el runner en cada copia de la imagen.
//
// Flujo de app_main:
//   BOOT -> config_load -> net_start -> timesync_start -> *_transport_init -> READY
//   -> crea el productor -> bucle emisor hasta vaciar la cola -> *_transport_finish -> DONE
//
// Tareas durante la corrida (FreeRTOS es expropiativo: la de más prioridad que
// esté lista interrumpe a las demás):
//   producer_task  prio 5  cada period_ms crea una lectura con su t_us y la encola
//   mark_task      prio 3  cada 5 s imprime MARK (factor de tiempo real)
//   app_main       prio 1  emisor: saca de la cola, serializa y envía
//   (lwIP SNTP re-sincroniza cada 15 s; esp-mqtt tiene su propia tarea)
// El productor tiene más prioridad que el emisor, así cada lectura se crea a
// horario aunque el emisor esté bloqueado en un envío lento.
//
// La lectura se crea en una tarea (productor) y se envía en otra (emisor),
// unidas por una cola. Si el envío se atrasa (un handshake TLS, una
// retransmisión), la espera en la cola queda dentro de la latencia extremo a
// extremo (t_recv - t_us): una latencia alta muestra que el transporte no da abasto.
//
// El nodo informa su estado al runner por la UART con líneas simples:
//   BOOT
//   CFG esp_id=1 transport=mqtt1 tls=1 period_ms=1000 ser=pb duration_s=120 nodelay=0
//   NET ip=10.10.0.11 mac=02:00:00:00:00:01
//   SYNC epoch_us=1793041765379595 timer_us=3456789
//   MQTT_CONNECTED t_ms=6789
//   READY t_ms=6790
//   MARK timer_us=11790123
//   ...
//   DONE produced=120 sent=120 failed=0 queue_drops=0 pending=0 overruns=0 t_ms=128001
// Las de error (CFGERR, NETERR, SYNCERR, FAIL) hacen que el runner corte la corrida.
#include <math.h>
#include <stdio.h>

#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "node.h"

#define QUEUE_LEN 256
#define MARK_PERIOD_MS 5000
// Tras duration_s, el emisor tiene este margen para vaciar la cola. Lo que quede
// se informa como "pending" (no entregado). Evita corridas interminables cuando
// el transporte es más lento que el período (p. ej. HTTPS por request en QEMU).
#define DRAIN_GRACE_S 30

static node_config_t s_cfg;
static QueueHandle_t s_queue;              // QUEUE_LEN lecturas entre productor y emisor
static volatile bool s_producer_done;      // lo pone el productor al terminar; lo lee el emisor
static uint32_t s_produced, s_queue_drops, s_overruns; // contadores del productor, van en DONE

// Cada 5 s imprime el tiempo desde el arranque según el reloj del ESP32. El runner
// anota la hora del host al leer cada línea y calcula el factor de tiempo real
// (Δtimer_us / Δhora del host): si QEMU fuera más lento que el tiempo real daría < 1.
// Ojo: QEMU corre sin -icount, así que el reloj del guest sigue al del host y el
// factor da ~1 aun con la CPU saturada. La señal útil de saturación es s_overruns.
static void mark_task(void *arg)
{
    TickType_t last = xTaskGetTickCount();
    for (;;) {
        printf("MARK timer_us=%lld\n", (long long)esp_timer_get_time());
        fflush(stdout);
        vTaskDelayUntil(&last, pdMS_TO_TICKS(MARK_PERIOD_MS));
    }
}

// Productor: crea una lectura por período durante duration_s.
//  - t_us se toma al crear la lectura, no al enviarla.
//  - xQueueSend con espera 0: si la cola está llena, la lectura se descarta y se
//    cuenta en queue_drops (con 256 lugares no pasó en ninguna corrida).
//  - xTaskDelayUntil duerme hasta last + period y actualiza last. A diferencia de
//    vTaskDelay, el período no se desvía aunque el cuerpo del bucle tarde. Si el
//    instante ya pasó (la CPU del host estaba saturada), devuelve pdFALSE y se
//    cuenta un overrun: es la señal útil de que el host no da abasto.
//  - Valor simulado: 25 + 5·sen(seq/20) + ruido, solo para que el payload no sea constante.
static void producer_task(void *arg)
{
    const uint32_t total = (s_cfg.duration_s * 1000) / s_cfg.period_ms; // 120 con 120 s y 1 s
    const TickType_t period = pdMS_TO_TICKS(s_cfg.period_ms);
    TickType_t last = xTaskGetTickCount();

    for (uint32_t seq = 0; seq < total; seq++) {
        reading_t r = {
            .seq = seq,
            .t_us = now_epoch_us(),
            // Sensor simulado: onda lenta + ruido
            .value = 25.0f + 5.0f * sinf((float)seq / 20.0f) + (float)(esp_random() % 100) / 100.0f,
            .status = 0,
        };
        if (xQueueSend(s_queue, &r, 0) != pdTRUE) {
            s_queue_drops++; // el emisor no da abasto; la lectura se pierde
        }
        s_produced++;
        // xTaskDelayUntil devuelve pdFALSE si ya pasó el instante: el nodo se atrasó.
        if (xTaskDelayUntil(&last, period) == pdFALSE) {
            s_overruns++;
        }
    }
    s_producer_done = true;
    vTaskDelete(NULL);
}

// app_main es la tarea principal que crea ESP-IDF (prioridad 1). Hace el arranque
// y después se convierte en el emisor. Si algo del arranque falla imprime FAIL y
// termina: el runner lo ve en la UART y corta la corrida.
void app_main(void)
{
    printf("BOOT\n");
    if (!config_load(&s_cfg)) {
        return;
    }
    printf("CFG esp_id=%lu transport=%s tls=%d period_ms=%lu ser=%s duration_s=%lu nodelay=%d\n",
           (unsigned long)s_cfg.esp_id, transport_name(s_cfg.transport), s_cfg.tls,
           (unsigned long)s_cfg.period_ms, s_cfg.json ? "json" : "pb", (unsigned long)s_cfg.duration_s,
           s_cfg.nodelay);

    if (!net_start(&s_cfg) || !timesync_start(s_cfg.server_ip)) {
        printf("FAIL init\n");
        return;
    }

    bool is_mqtt = s_cfg.transport == TR_MQTT_QOS0 || s_cfg.transport == TR_MQTT_QOS1;
    bool ok = is_mqtt ? mqtt_transport_init(&s_cfg) : http_transport_init(&s_cfg);
    if (!ok) {
        printf("FAIL transport\n");
        return;
    }

    s_queue = xQueueCreate(QUEUE_LEN, sizeof(reading_t));
    xTaskCreate(mark_task, "mark", 2048, NULL, 3, NULL);
    printf("READY t_ms=%lld\n", (long long)(esp_timer_get_time() / 1000));
    fflush(stdout);
    // El productor tiene más prioridad que el emisor (app_main, prioridad 1)
    xTaskCreate(producer_task, "producer", 3072, NULL, 5, NULL);

    // Emisor: corre en app_main. Manda una lectura por vez y espera a que termine
    // (HTTP espera la respuesta; MQTT, que el send() se complete). Si el transporte
    // es más lento que el período, las lecturas se acumulan en la cola.
    // Dos salidas del bucle:
    //  - normal: el productor terminó y la cola está vacía;
    //  - emergencia: pasaron DRAIN_GRACE_S después de duration_s. Lo que queda en
    //    la cola se informa como pending y cuenta como no entregado.
    // El xQueueReceive con timeout de 100 ms permite revisar esas condiciones.
    const int64_t drain_deadline_us =
        esp_timer_get_time() + ((int64_t)s_cfg.duration_s + DRAIN_GRACE_S) * 1000000LL;
    uint32_t sent = 0, failed = 0;
    uint8_t buf[160];
    reading_t r;
    for (;;) {
        if (s_producer_done && esp_timer_get_time() > drain_deadline_us) {
            break; // se acabó el margen: lo que queda en la cola no se envía
        }
        if (xQueueReceive(s_queue, &r, pdMS_TO_TICKS(100)) != pdTRUE) {
            if (s_producer_done && uxQueueMessagesWaiting(s_queue) == 0) {
                break;
            }
            continue;
        }
        size_t len = encode_reading(&s_cfg, &r, buf, sizeof(buf));
        bool delivered = len > 0 && (is_mqtt ? mqtt_transport_send(buf, len) : http_transport_send(buf, len));
        if (delivered) {
            sent++;
        } else {
            failed++;
            printf("SENDFAIL seq=%lu\n", (unsigned long)r.seq);
        }
    }
    if (is_mqtt) {
        mqtt_transport_finish();
    } else {
        http_transport_finish();
    }
    unsigned long pending = (unsigned long)uxQueueMessagesWaiting(s_queue);
    printf("DONE produced=%lu sent=%lu failed=%lu queue_drops=%lu pending=%lu overruns=%lu t_ms=%lld\n",
           (unsigned long)s_produced, (unsigned long)sent, (unsigned long)failed,
           (unsigned long)s_queue_drops, pending, (unsigned long)s_overruns,
           (long long)(esp_timer_get_time() / 1000));
    fflush(stdout);
    // El runner apaga la instancia QEMU cuando todos los nodos terminaron.
}
