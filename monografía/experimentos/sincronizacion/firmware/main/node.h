// Tipos y funciones compartidas del nodo oscilador de Kuramoto.
//
// Módulos del firmware (todos en main/):
//   main.c        flujo principal, integración de Euler y publicación periódica
//   config.c      lee la config del nodo desde la partición "cfg"
//   net.c         Ethernet open_eth de QEMU (tap: IP estática; user: DHCP)
//   timesync.c    SNTP contra el servidor y hora en µs
//   mqtt.c        cliente MQTT 5, tabla de fases recibidas y acoplamiento
//   kuramoto.pb.* descripción del mensaje PhaseReport para nanopb
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MAX_N 128 // cantidad máxima de nodos (tamaño de la tabla de fases)

// Variantes del contrato de datos, para ensayar la compatibilidad de Protocol Buffers.
#define ESQ_NORMAL 0
#define ESQ_V2 1      // agrega al mensaje un campo 6 que los demás no conocen
#define ESQ_CRUZADO 2 // en la red, theta va en el campo 3 y velocidad en el 2

typedef struct {
    uint32_t id;          // número de nodo, 1..n
    uint32_t n;           // cantidad total de nodos (divisor del acoplamiento)
    char ip[16];          // IP estática (red=tap)
    char server_ip[16];   // broker, SNTP y gateway
    uint8_t mac[6];       // MAC propia del nodo
    bool mac_set;
    double omega;         // frecuencia natural, rad/s
    double k;             // fuerza de acoplamiento, rad/s
    double theta0;        // fase inicial, rad
    uint32_t h_ms;        // período de publicación
    uint32_t ts_ms;       // paso de integración (múltiplo del tick de 10 ms)
    uint32_t desfase_ms;  // desfase de la primera publicación respecto de t_inicio
    uint64_t t_inicio_ms; // inicio: epoch (sntp=1) o ms desde el arranque (sntp=0)
    uint32_t duracion_s;
    bool extrapolar;
    bool sntp;
    uint32_t keepalive_s; // keep-alive de MQTT; 0 = el valor por defecto de esp-mqtt (120 s)
    uint32_t qos;         // QoS de publicación y de suscripción: 0 | 1
    bool will;            // última voluntad en kuramoto/estado/<id> y reacción a la de los demás
    bool alias;           // acepta alias de tópico del broker hacia el nodo
    uint32_t esquema;     // ESQ_NORMAL, ESQ_V2 o ESQ_CRUZADO
    uint32_t t_union_s;   // si no es 0, se conecta al broker recién t_union_s después de t_inicio
    bool red_tap;         // true = tap (IP estática), false = user (DHCP)
} node_config_t;

// config.c
bool config_load(node_config_t *cfg);

// net.c
bool net_start(const node_config_t *cfg);

// timesync.c
bool timesync_start(const node_config_t *cfg);
uint64_t now_epoch_us(void);

// mqtt.c
bool mqtt_node_start(const node_config_t *cfg);   // conecta, suscribe y espera el SUBACK
bool mqtt_node_publish(const uint8_t *buf, size_t len);
// Suma de sin(hat_j - theta_i) sobre los nodos j != i con fase conocida.
double phases_coupling(const node_config_t *cfg, double theta_i);
uint32_t mqtt_node_received(void);
