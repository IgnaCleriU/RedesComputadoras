// Nodo de eco MQTT: devuelve cada mensaje de <id>/ping en <id>/pong, y ante
// "flood N S Q" en <id>/cmd publica N mensajes de S bytes en <id>/flood.
// Difusión: ante "bcast N P S [A]" publica N mensajes de S bytes en eco/todos, uno cada P ms; si
// A = 1 (por defecto) cada nodo que recibe uno lo devuelve en <id>/ack (para medir el fan-out).
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "nvs_flash.h"
#include "mqtt_client.h"
#include "protocol_examples_common.h"
#if CONFIG_EXAMPLE_CONNECT_WIFI
#include "esp_wifi.h"
#endif
#if CONFIG_ECO_TAP
#include "esp_eth.h"
#include "esp_flash.h"
#endif

#define MAX_PAYLOAD 8192
// Mensajes QoS 1 del flood sin PUBACK como máximo (como max_inflight_messages de mosquitto).
// Sin ventana el outbox de esp-mqtt guarda todo el flood y agota el heap.
#define WINDOW 20

static const char *TAG = "eco";
static esp_mqtt_client_handle_t client;
static char t_ping[48], t_pong[48], t_cmd[48], t_flood[48], t_ack[48];
static const char *T_TODOS = "eco/todos";
static uint32_t node_idx; // índice del nodo en modo tap (0 si no)
static SemaphoreHandle_t window;

typedef struct { int n, size, qos; } flood_t;
typedef struct { int n, period, size, ack; } bcast_t;

// Payload de difusión: secuencia (uint32 LE), índice del emisor (uint32 LE), pedido de ack
// (1 byte) y relleno.
static void bcast_task(void *arg)
{
    bcast_t b = *(bcast_t *)arg;
    free(arg);
    static char buf[256];
    memset(buf, 'x', b.size);
    memcpy(buf + 4, &node_idx, 4);
    buf[8] = b.ack;
    for (uint32_t seq = 0; seq < b.n; seq++) {
        memcpy(buf, &seq, 4);
        esp_mqtt_client_publish(client, T_TODOS, buf, b.size, 0, 0);
        vTaskDelay(pdMS_TO_TICKS(b.period));
    }
    ESP_LOGI(TAG, "bcast terminado: %d x %d B", b.n, b.size);
    vTaskDelete(NULL);
}

static void flood_task(void *arg)
{
    flood_t f = *(flood_t *)arg;
    free(arg);
    static char buf[MAX_PAYLOAD];
    memset(buf, 'x', f.size);
    for (uint32_t seq = 0; seq < f.n; seq++) {
        memcpy(buf, &seq, sizeof seq); // los primeros 4 bytes: número de secuencia (little endian)
        if (f.qos) {
            xSemaphoreTake(window, portMAX_DELAY);
        }
        while (esp_mqtt_client_publish(client, t_flood, buf, f.size, f.qos, 0) < 0) {
            vTaskDelay(1); // buffer de salida lleno: reintentar
        }
    }
    ESP_LOGI(TAG, "flood terminado: %d x %d B", f.n, f.size);
    vTaskDelete(NULL);
}

static void on_mqtt(void *args, esp_event_base_t base, int32_t id, void *data)
{
    esp_mqtt_event_handle_t ev = data;
    switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "conectado a %s", CONFIG_ECO_BROKER_URI);
        esp_mqtt_client_subscribe(client, t_ping, 1);
        esp_mqtt_client_subscribe(client, t_cmd, 1);
        esp_mqtt_client_subscribe(client, T_TODOS, 0);
        break;
    case MQTT_EVENT_DATA:
        // Los mensajes más grandes que el buffer llegan fragmentados; no se usan en las pruebas.
        if (ev->data_len != ev->total_data_len) {
            ESP_LOGW(TAG, "mensaje fragmentado (%d B), ignorado", ev->total_data_len);
            break;
        }
        if (ev->topic_len == strlen(T_TODOS) && !strncmp(ev->topic, T_TODOS, ev->topic_len)) {
            uint32_t from;
            if (ev->data_len >= 9 && ev->data[8] == 1 && (memcpy(&from, ev->data + 4, 4), from != node_idx)) {
                esp_mqtt_client_publish(client, t_ack, ev->data, ev->data_len, 0, 0);
            }
        } else if (ev->topic_len == strlen(t_ping) && !strncmp(ev->topic, t_ping, ev->topic_len)) {
            esp_mqtt_client_publish(client, t_pong, ev->data, ev->data_len, ev->qos, 0);
        } else if (ev->topic_len == strlen(t_cmd) && !strncmp(ev->topic, t_cmd, ev->topic_len)) {
            char cmd[48] = {0};
            memcpy(cmd, ev->data, ev->data_len < sizeof cmd - 1 ? ev->data_len : sizeof cmd - 1);
            bcast_t b = {.ack = 1};
            if (sscanf(cmd, "bcast %d %d %d %d", &b.n, &b.period, &b.size, &b.ack) >= 3) {
                if (b.size >= 9 && b.size <= 256 && b.period > 0) {
                    bcast_t *p = malloc(sizeof *p);
                    *p = b;
                    xTaskCreate(bcast_task, "bcast", 4096, p, 5, NULL);
                }
                break;
            }
            flood_t *f = malloc(sizeof *f);
            if (sscanf(cmd, "flood %d %d %d", &f->n, &f->size, &f->qos) == 3 && f->size >= 4 &&
                f->size <= MAX_PAYLOAD && f->qos >= 0 && f->qos <= 1) {
                xTaskCreate(flood_task, "flood", 4096, f, 5, NULL);
            } else {
                ESP_LOGW(TAG, "comando inválido: %s", cmd);
                free(f);
            }
        }
        break;
    case MQTT_EVENT_PUBLISHED: // PUBACK de un QoS 1: libera un lugar de la ventana
        xSemaphoreGive(window);
        break;
    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "desconectado");
        break;
    default:
        break;
    }
}

#if CONFIG_ECO_TAP
// Varios nodos en QEMU sobre un puente: cada copia de la flash lleva su índice (uint32 LE)
// en NODE_IDX_ADDR, y de ahí salen el ID, la MAC y la IP fija 10.10.0.0 + 10 + índice.
#define NODE_IDX_ADDR 0x3FF000

static uint32_t tap_connect(void)
{
    uint32_t idx;
    ESP_ERROR_CHECK(esp_flash_read(NULL, &idx, NODE_IDX_ADDR, sizeof idx));
    if (idx == UINT32_MAX) {
        idx = 0; // flash sin índice
    }
    esp_netif_config_t ncfg = ESP_NETIF_DEFAULT_ETH();
    esp_netif_t *netif = esp_netif_new(&ncfg);
    eth_mac_config_t mac_cfg = ETH_MAC_DEFAULT_CONFIG();
    eth_phy_config_t phy_cfg = ETH_PHY_DEFAULT_CONFIG();
    phy_cfg.autonego_timeout_ms = 100;
    esp_eth_config_t eth_cfg = ETH_DEFAULT_CONFIG(esp_eth_mac_new_openeth(&mac_cfg),
                                                  esp_eth_phy_new_dp83848(&phy_cfg));
    esp_eth_handle_t eth;
    ESP_ERROR_CHECK(esp_eth_driver_install(&eth_cfg, &eth));
    uint8_t mac[6] = {0x02, 0xec, 0, 0, idx >> 8, idx & 0xff};
    ESP_ERROR_CHECK(esp_eth_ioctl(eth, ETH_CMD_S_MAC_ADDR, mac));
    ESP_ERROR_CHECK(esp_netif_attach(netif, esp_eth_new_netif_glue(eth)));
    esp_netif_dhcpc_stop(netif);
    uint32_t a = idx + 10;
    esp_netif_ip_info_t ip = {
        .ip.addr = ESP_IP4TOADDR(10, 10, a >> 8, a & 0xff),
        .netmask.addr = ESP_IP4TOADDR(255, 255, 0, 0),
        .gw.addr = ESP_IP4TOADDR(10, 10, 0, 1),
    };
    ESP_ERROR_CHECK(esp_netif_set_ip_info(netif, &ip));
    ESP_ERROR_CHECK(esp_eth_start(eth));
    ESP_LOGI(TAG, "nodo q%" PRIu32 ", IP " IPSTR, idx, IP2STR(&ip.ip));
    return idx;
}
#endif

void app_main(void)
{
    ESP_ERROR_CHECK(nvs_flash_init());
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
#if CONFIG_ECO_TAP
    char id[16];
    node_idx = tap_connect();
    snprintf(id, sizeof id, "q%" PRIu32, node_idx);
#else
    ESP_ERROR_CHECK(example_connect());
    const char *id = CONFIG_ECO_NODE_ID;
#endif
#if CONFIG_ECO_WIFI_NO_PS
    esp_wifi_set_ps(WIFI_PS_NONE);
#endif

    window = xSemaphoreCreateCounting(WINDOW, WINDOW);
    snprintf(t_ping, sizeof t_ping, "eco/%s/ping", id);
    snprintf(t_pong, sizeof t_pong, "eco/%s/pong", id);
    snprintf(t_cmd, sizeof t_cmd, "eco/%s/cmd", id);
    snprintf(t_flood, sizeof t_flood, "eco/%s/flood", id);
    snprintf(t_ack, sizeof t_ack, "eco/%s/ack", id);

    esp_mqtt_client_config_t cfg = {
        .broker.address.uri = CONFIG_ECO_BROKER_URI,
        .buffer.size = MAX_PAYLOAD + 128,
        .credentials.client_id = id,
    };
    client = esp_mqtt_client_init(&cfg);
    esp_mqtt_client_register_event(client, ESP_EVENT_ANY_ID, on_mqtt, NULL);
    esp_mqtt_client_start(client);
}
