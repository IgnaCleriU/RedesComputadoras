// Cliente MQTT 5 del nodo y tabla de fases de los demás nodos.
//
//  - Publica en kuramoto/phase/<id> (QoS 0, sin retain).
//  - Se suscribe a kuramoto/phase/+ (QoS 0) con la opción No Local, así el
//    broker no devuelve las propias publicaciones. Igual se ignora id == propio.
//  - En cada MQTT_EVENT_CONNECTED vuelve a suscribirse (el broker puede haber
//    perdido la sesión). En MQTT_EVENT_DISCONNECTED invalida todas las fases:
//    el acoplamiento pasa a ser cero y el nodo corre a su frecuencia natural.
//  - La tabla la escribe el handler de MQTT y la lee la tarea de integración;
//    se protege con un portMUX y la sección crítica es solo una copia.
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "kuramoto.pb.h"
#include "mqtt_client.h"
#include "node.h"
#include "pb_decode.h"

#define SUBSCRIBED_BIT BIT0

typedef struct {
    bool valid;
    uint32_t seq;
    float theta, vel;
    uint64_t t_us;
} peer_t;

static esp_mqtt_client_handle_t s_client;
static EventGroupHandle_t s_events;
static const node_config_t *s_cfg;
static char s_topic_pub[40];
static peer_t s_tab[MAX_N + 1]; // indexada por id
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;
static volatile uint32_t s_recibidos;

static void on_data(const esp_mqtt_event_handle_t ev)
{
    // Los mensajes fragmentados no se usan (el payload ocupa ~30 B): se ignoran.
    if (ev->data_len != ev->total_data_len) {
        return;
    }
    kur_PhaseReport m = kur_PhaseReport_init_zero;
    pb_istream_t s = pb_istream_from_buffer((const uint8_t *)ev->data, ev->data_len);
    if (!pb_decode(&s, kur_PhaseReport_fields, &m)) {
        return;
    }
    if (m.id == s_cfg->id || m.id < 1 || m.id > s_cfg->n) {
        return;
    }
    portENTER_CRITICAL(&s_lock);
    peer_t *p = &s_tab[m.id];
    if (!p->valid || m.seq > p->seq) { // se descarta un reporte que no es más nuevo
        p->valid = true;
        p->seq = m.seq;
        p->theta = m.theta;
        p->vel = m.velocidad;
        p->t_us = m.t_us;
        s_recibidos++;
    }
    portEXIT_CRITICAL(&s_lock);
}

static void on_mqtt(void *args, esp_event_base_t base, int32_t id, void *data)
{
    esp_mqtt_event_handle_t ev = data;
    switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED: {
        esp_mqtt5_subscribe_property_config_t sp = {.no_local_flag = true};
        esp_mqtt5_client_set_subscribe_property(s_client, &sp);
        esp_mqtt_client_subscribe(s_client, "kuramoto/phase/+", 0);
        break;
    }
    case MQTT_EVENT_SUBSCRIBED:
        xEventGroupSetBits(s_events, SUBSCRIBED_BIT);
        break;
    case MQTT_EVENT_DATA:
        on_data(ev);
        break;
    case MQTT_EVENT_DISCONNECTED:
        portENTER_CRITICAL(&s_lock);
        for (int i = 0; i <= MAX_N; i++) {
            s_tab[i].valid = false;
        }
        portEXIT_CRITICAL(&s_lock);
        break;
    default:
        break;
    }
}

bool mqtt_node_start(const node_config_t *cfg)
{
    s_cfg = cfg;
    s_events = xEventGroupCreate();
    char uri[40], cid[16];
    snprintf(uri, sizeof(uri), "mqtt://%s:1883", cfg->server_ip);
    snprintf(cid, sizeof(cid), "k%lu", (unsigned long)cfg->id);
    snprintf(s_topic_pub, sizeof(s_topic_pub), "kuramoto/phase/%lu", (unsigned long)cfg->id);

    esp_mqtt_client_config_t mc = {
        .broker.address.uri = uri,
        .credentials.client_id = cid,
        .session.protocol_ver = MQTT_PROTOCOL_V_5,
    };
    s_client = esp_mqtt_client_init(&mc);
    esp_mqtt_client_register_event(s_client, ESP_EVENT_ANY_ID, on_mqtt, NULL);
    if (esp_mqtt_client_start(s_client) != ESP_OK) {
        printf("MQTTERR start\n");
        return false;
    }
    if (!(xEventGroupWaitBits(s_events, SUBSCRIBED_BIT, pdFALSE, pdTRUE, pdMS_TO_TICKS(30000)) &
          SUBSCRIBED_BIT)) {
        printf("MQTTERR sin conexion o suscripcion a %s\n", uri);
        return false;
    }
    return true;
}

bool mqtt_node_publish(const uint8_t *buf, size_t len)
{
    return esp_mqtt_client_publish(s_client, s_topic_pub, (const char *)buf, len, 0, 0) >= 0;
}

uint32_t mqtt_node_received(void)
{
    return s_recibidos;
}

// sum_{j != i, conocido} sin(hat_j - theta_i). Se copia la tabla bajo el lock y
// los sin() se calculan afuera. Con extrapolar, hat_j = theta_j + vel_j * edad,
// con edad = ahora - t_us del reporte (en segundos, negativa => 0).
double phases_coupling(const node_config_t *cfg, double theta_i)
{
    static peer_t copia[MAX_N + 1];
    portENTER_CRITICAL(&s_lock);
    memcpy(copia, s_tab, sizeof(peer_t) * (cfg->n + 1));
    portEXIT_CRITICAL(&s_lock);

    uint64_t ahora = cfg->extrapolar ? now_epoch_us() : 0;
    double suma = 0;
    for (uint32_t j = 1; j <= cfg->n; j++) {
        if (j == cfg->id || !copia[j].valid) {
            continue;
        }
        double hat = copia[j].theta;
        if (cfg->extrapolar) {
            double edad = ahora > copia[j].t_us ? (double)(ahora - copia[j].t_us) * 1e-6 : 0.0;
            hat += (double)copia[j].vel * edad;
        }
        suma += sin(hat - theta_i);
    }
    return suma;
}
