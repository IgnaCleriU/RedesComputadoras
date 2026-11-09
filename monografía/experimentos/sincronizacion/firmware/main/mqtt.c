// Cliente MQTT 5 del nodo y tabla de fases de los demás nodos.
//
//  - Publica en kuramoto/phase/<id> (QoS 0, sin retain).
//  - Se suscribe a kuramoto/phase/+ (QoS 0) con la opción No Local, así el
//    broker no devuelve las propias publicaciones. Igual se ignora id == propio.
//  - En cada MQTT_EVENT_CONNECTED vuelve a suscribirse (el broker puede haber
//    perdido la sesión). En MQTT_EVENT_DISCONNECTED invalida todas las fases:
//    el acoplamiento pasa a ser cero y el nodo corre a su frecuencia natural.
//  - Con will=1 registra una última voluntad en kuramoto/estado/<id> y se suscribe a
//    kuramoto/estado/+: al llegar la de otro nodo, invalida solo la fase de ese nodo.
//  - La tabla la escribe el handler de MQTT y la lee la tarea de integración;
//    se protege con un portMUX y la sección crítica es solo una copia.
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "kuramoto.pb.h"
#include "mqtt_client.h"
#include "node.h"
#include "pb_decode.h"

#define SUBSCRIBED_BIT BIT0
#define PREFIJO_ESTADO "kuramoto/estado/"

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
static char s_topic_est[40];
static volatile bool s_listo;
static int s_subacks;
static peer_t s_tab[MAX_N + 1]; // indexada por id
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;
static volatile uint32_t s_recibidos;

// Última voluntad de otro nodo: su fase deja de usarse hasta que llegue una nueva.
static void on_will(const esp_mqtt_event_handle_t ev)
{
    const int pre = strlen(PREFIJO_ESTADO);
    char num[8] = {0};
    int largo = ev->topic_len - pre;
    if (largo <= 0 || largo >= (int)sizeof(num)) {
        return;
    }
    memcpy(num, ev->topic + pre, largo);
    uint32_t j = strtoul(num, NULL, 10);
    if (j < 1 || j > s_cfg->n || j == s_cfg->id) {
        return;
    }
    portENTER_CRITICAL(&s_lock);
    s_tab[j].valid = false;
    portEXIT_CRITICAL(&s_lock);
    printf("EV WILL %lu %" PRIu64 "\n", (unsigned long)j, now_epoch_us());
}

static void on_data(const esp_mqtt_event_handle_t ev)
{
    // Los mensajes fragmentados no se usan (el payload ocupa ~30 B): se ignoran.
    if (ev->data_len != ev->total_data_len) {
        return;
    }
    if (ev->topic && ev->topic_len > (int)strlen(PREFIJO_ESTADO) &&
        !memcmp(ev->topic, PREFIJO_ESTADO, strlen(PREFIJO_ESTADO))) {
        on_will(ev);
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
    if (s_cfg->esquema == ESQ_CRUZADO) { // quien lee con el esquema cruzado también intercambia
        float t = m.theta;
        m.theta = m.velocidad;
        m.velocidad = t;
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
        printf("EV CONN %" PRIu64 "\n", now_epoch_us());
        s_subacks = 0;
        // La propiedad se consume en cada suscripción: hay que fijarla antes de cada una.
        esp_mqtt5_subscribe_property_config_t sp = {.no_local_flag = true};
        esp_mqtt5_client_set_subscribe_property(s_client, &sp);
        esp_mqtt_client_subscribe(s_client, "kuramoto/phase/+", (int)s_cfg->qos);
        if (s_cfg->will) {
            esp_mqtt5_client_set_subscribe_property(s_client, &sp);
            esp_mqtt_client_subscribe(s_client, PREFIJO_ESTADO "+", 0);
        }
        break;
    }
    case MQTT_EVENT_SUBSCRIBED:
        if (++s_subacks >= (s_cfg->will ? 2 : 1)) {
            xEventGroupSetBits(s_events, SUBSCRIBED_BIT);
        }
        break;
    case MQTT_EVENT_DATA:
        on_data(ev);
        break;
    case MQTT_EVENT_DISCONNECTED:
        printf("EV DESC %" PRIu64 "\n", now_epoch_us());
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
    snprintf(s_topic_est, sizeof(s_topic_est), PREFIJO_ESTADO "%lu", (unsigned long)cfg->id);

    esp_mqtt_client_config_t mc = {
        .broker.address.uri = uri,
        .credentials.client_id = cid,
        .session.protocol_ver = MQTT_PROTOCOL_V_5,
    };
    if (cfg->keepalive_s) {
        mc.session.keepalive = (int)cfg->keepalive_s;
    }
    if (cfg->will) {
        mc.session.last_will.topic = s_topic_est;
        mc.session.last_will.msg = "0";
        mc.session.last_will.msg_len = 1;
        mc.session.last_will.qos = 0;
    }
    s_client = esp_mqtt_client_init(&mc);
    if (cfg->alias) { // el nodo declara cuántos alias acepta; el broker decide cuáles crear
        esp_mqtt5_connection_property_config_t cp = {.topic_alias_maximum = MAX_N};
        esp_mqtt5_client_set_connect_property(s_client, &cp);
    }
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
    s_listo = true;
    return true;
}

bool mqtt_node_publish(const uint8_t *buf, size_t len)
{
    if (!s_listo) { // nodo que todavía no se sumó
        return false;
    }
    return esp_mqtt_client_publish(s_client, s_topic_pub, (const char *)buf, len, (int)s_cfg->qos, 0) >= 0;
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
