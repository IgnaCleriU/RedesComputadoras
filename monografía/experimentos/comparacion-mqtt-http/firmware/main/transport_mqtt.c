// Camino MQTT: una sesión TCP persistente con el broker, PUBLISH a exp/tel/{esp}.
//
// Usa esp-mqtt (el cliente MQTT 3.1.1 de ESP-IDF). URI mqtt://10.10.0.1:1883 o
// mqtts://10.10.0.1:8883; con TLS el nodo verifica al broker con la CA embebida.
// La conexión se abre en init, antes de READY, y dura toda la corrida.
//
// Cada lectura sale en un solo segmento TCP: esp_mqtt_client_publish arma el
// PUBLISH completo en un buffer y lo escribe con un solo send(), desde la tarea
// que la llama (el emisor). Por eso Nagle no tiene nada que retener, a diferencia
// de HTTP (ver transport_http.c).
//
// Nota sobre QoS 1: el mensaje queda en el outbox de esp-mqtt hasta su PUBACK. La
// tarea de esp-mqtt lo reenvía (con la marca DUP) si no llega en
// message_retransmit_timeout (1 s por defecto), sobre la misma conexión TCP y
// además de las retransmisiones de TCP. Se deja el valor por defecto de la
// biblioteca: es el comportamiento real de un ESP32 y explica los duplicados.
#include <stdio.h>

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "mqtt_client.h"
#include "node.h"

#define CONNECTED_BIT BIT0

static esp_mqtt_client_handle_t s_client;
static EventGroupHandle_t s_events;
static int s_qos;
static char s_topic[32];

// Eventos del cliente: marca la conexión e informa al runner (que cuenta las
// desconexiones) con MQTT_CONNECTED / MQTT_DISCONNECTED / MQTT_ERROR.
static void on_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    esp_mqtt_event_handle_t ev = data;
    switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
        xEventGroupSetBits(s_events, CONNECTED_BIT);
        printf("MQTT_CONNECTED t_ms=%lld\n", (long long)(esp_timer_get_time() / 1000));
        break;
    case MQTT_EVENT_DISCONNECTED:
        xEventGroupClearBits(s_events, CONNECTED_BIT);
        printf("MQTT_DISCONNECTED t_ms=%lld\n", (long long)(esp_timer_get_time() / 1000));
        break;
    case MQTT_EVENT_ERROR:
        if (ev->error_handle) {
            printf("MQTT_ERROR type=%d tls=0x%x errno=%d\n", ev->error_handle->error_type,
                   ev->error_handle->esp_tls_last_esp_err, ev->error_handle->esp_transport_sock_errno);
        }
        break;
    default:
        break;
    }
}

bool mqtt_transport_init(const node_config_t *cfg)
{
    static char uri[48], client_id[16];
    s_events = xEventGroupCreate();
    s_qos = (cfg->transport == TR_MQTT_QOS1) ? 1 : 0;
    snprintf(s_topic, sizeof(s_topic), "exp/tel/%lu", (unsigned long)cfg->esp_id);
    snprintf(uri, sizeof(uri), "%s://%s:%d", cfg->tls ? "mqtts" : "mqtt", cfg->server_ip,
             cfg->tls ? 8883 : 1883);
    snprintf(client_id, sizeof(client_id), "esp%lu", (unsigned long)cfg->esp_id);

    esp_mqtt_client_config_t mc = {
        .broker.address.uri = uri,
        .broker.verification.certificate = cfg->tls ? ca_crt_start : NULL,
        .credentials.client_id = client_id,
        .session.keepalive = 60,               // > período más largo (10 s): no hay PINGREQ
        .session.disable_clean_session = false, // sesión limpia: sin estado entre conexiones
        .network.reconnect_timeout_ms = 1000,  // si se cae, reintenta al segundo
        .network.timeout_ms = 10000,
    };
    // start crea la tarea de esp-mqtt, que abre el TCP, hace el handshake TLS,
    // manda CONNECT y procesa todo lo que llega (CONNACK, PUBACK).
    s_client = esp_mqtt_client_init(&mc);
    if (!s_client) {
        return false;
    }
    esp_mqtt_client_register_event(s_client, ESP_EVENT_ANY_ID, on_event, NULL);
    if (esp_mqtt_client_start(s_client) != ESP_OK) {
        return false;
    }
    // Con TLS emulado el primer handshake puede tardar varios segundos.
    EventBits_t b = xEventGroupWaitBits(s_events, CONNECTED_BIT, pdFALSE, pdTRUE, pdMS_TO_TICKS(60000));
    return (b & CONNECTED_BIT) != 0;
}

bool mqtt_transport_send(const uint8_t *buf, size_t len)
{
    // Devuelve el id del mensaje (0 en QoS 0) o -1 si falló.
    // QoS 0 sin conexión: la lectura se pierde (no hay outbox para QoS 0).
    // QoS 1 sin conexión: esp-mqtt la guarda en el outbox y la manda al reconectar.
    int id = esp_mqtt_client_publish(s_client, s_topic, (const char *)buf, (int)len, s_qos, 0);
    return id >= 0;
}

void mqtt_transport_finish(void)
{
    // Espera a que el outbox (QoS 1 sin PUBACK) se vacíe, hasta 60 s.
    for (int i = 0; i < 600 && esp_mqtt_client_get_outbox_size(s_client) > 0; i++) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    int left = esp_mqtt_client_get_outbox_size(s_client);
    if (left > 0) {
        printf("MQTT_OUTBOX_LEFT bytes=%d\n", left);
    }
    vTaskDelay(pdMS_TO_TICKS(500)); // que salga lo último por TCP
}
