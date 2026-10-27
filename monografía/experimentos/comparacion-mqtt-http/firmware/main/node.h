// Tipos y funciones compartidas del nodo de telemetría.
//
// Módulos del firmware (todos en main/):
//   main.c            flujo principal: arranque, productor, emisor y marcas de tiempo
//   config.c          lee la config del nodo desde la partición "cfg"
//   net.c             Ethernet open_eth de QEMU, MAC propia, IP estática
//   timesync.c        SNTP contra el backend y hora en µs
//   encode.c          serializa una lectura en protobuf (nanopb) o JSON
//   transport_mqtt.c  camino MQTT (esp-mqtt, QoS 0 y 1)
//   transport_http.c  camino HTTP(S) (esp_http_client, por request o reutilizado)
//   telemetry.pb.*    descripción del mensaje Telemetry para nanopb
//
// Los transportes implementan la misma interfaz de tres funciones (ver abajo),
// así main.c no sabe nada del protocolo que se usa.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    TR_MQTT_QOS0,
    TR_MQTT_QOS1,
    TR_HTTP_PER_REQUEST,
    TR_HTTP_REUSE,
} transport_kind_t;

// Configuración del nodo tal como queda después de leer la partición cfg.
typedef struct {
    uint32_t esp_id;      // número de nodo, 1..N
    char ip[16];          // 10.10.0.(10+N)
    char server_ip[16];   // 10.10.0.1: broker, backend, SNTP y gateway
    uint8_t mac[6];       // 02:00:00:00:00:NN (todas las instancias QEMU traen la misma de fábrica)
    transport_kind_t transport;
    bool tls;
    uint32_t period_ms;   // una lectura cada period_ms
    bool json;            // false = protobuf
    uint32_t duration_s;  // segundos produciendo lecturas
    bool nodelay;         // TCP_NODELAY en el socket HTTP (desactiva Nagle)
} node_config_t;

// Una lectura antes de serializar.
typedef struct {
    uint32_t seq;   // número de lectura, desde 0
    uint64_t t_us;  // hora de creación en µs desde 1970, con el reloj sincronizado por SNTP
    float value;    // valor simulado del sensor
    uint32_t status;
} reading_t;

// config.c
bool config_load(node_config_t *cfg);
const char *transport_name(transport_kind_t t);

// net.c
bool net_start(const node_config_t *cfg);

// timesync.c
bool timesync_start(const char *server_ip);
uint64_t now_epoch_us(void);

// encode.c
size_t encode_reading(const node_config_t *cfg, const reading_t *r, uint8_t *buf, size_t cap);

// transport_*.c, la interfaz común de los transportes:
//   *_init(cfg)       prepara el cliente. MQTT además conecta y espera el CONNACK;
//                     HTTP conecta recién en el primer envío.
//   *_send(buf, len)  manda una lectura ya serializada. Devuelve true si quedó
//                     entregada (HTTP: respuesta 2xx) o aceptada por el cliente (MQTT).
//   *_finish()        espera lo que el protocolo tenga pendiente (QoS 1 sin PUBACK).
bool mqtt_transport_init(const node_config_t *cfg);
bool mqtt_transport_send(const uint8_t *buf, size_t len);
void mqtt_transport_finish(void);

bool http_transport_init(const node_config_t *cfg);
bool http_transport_send(const uint8_t *buf, size_t len);
void http_transport_finish(void);

// Certificado de la CA embebido. EMBED_TXTFILES "ca.crt" (main/CMakeLists.txt) hace
// que el enlazador cree el símbolo _binary_ca_crt_start con el contenido del archivo
// terminado en '\0'; asm(...) lo une a esta variable de C.
extern const char ca_crt_start[] asm("_binary_ca_crt_start");
