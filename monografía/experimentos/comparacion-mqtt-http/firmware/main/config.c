// Lee la config del nodo desde la partición "cfg" (texto "clave=valor\n").
// El runner la escribe en la imagen de flash de cada instancia QEMU.
//
// La partición (partitions.csv: tipo 0x40, offset 0x190000, 4 KB) contiene:
//   EXPCFG1
//   esp_id=3
//   ip=10.10.0.13
//   server_ip=10.10.0.1
//   mac=02:00:00:00:00:03
//   transport=http_reuse        mqtt0 | mqtt1 | http_req | http_reuse
//   tls=1
//   period_ms=1000
//   serialization=pb            pb | json
//   duration_s=120
//   nodelay=0
// seguido de '\0' y el resto en 0xFF (flash "vacía").
//
// Sin la cabecera EXPCFG1 el nodo imprime CFGERR y no arranca, así una imagen
// sin configurar no se confunde con una corrida.
//
// Por qué texto y no NVS (el almacenamiento clave-valor de ESP-IDF): el formato
// binario de NVS exige generar la partición con un script de Python de ESP-IDF
// en cada corrida. Con texto plano, el runner en Go la escribe con un copy.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_partition.h"
#include "node.h"

#define CFG_MAGIC "EXPCFG1\n"

const char *transport_name(transport_kind_t t)
{
    switch (t) {
    case TR_MQTT_QOS0: return "mqtt0";
    case TR_MQTT_QOS1: return "mqtt1";
    case TR_HTTP_PER_REQUEST: return "http_req";
    case TR_HTTP_REUSE: return "http_reuse";
    }
    return "?";
}

static bool parse_mac(const char *s, uint8_t mac[6])
{
    unsigned v[6];
    if (sscanf(s, "%x:%x:%x:%x:%x:%x", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6) {
        return false;
    }
    for (int i = 0; i < 6; i++) {
        mac[i] = (uint8_t)v[i];
    }
    return true;
}

// Convierte una clave a su campo. Un transporte o una MAC inválidos devuelven
// false (CFGERR); las claves desconocidas se ignoran.
static bool apply(node_config_t *cfg, const char *k, const char *v)
{
    if (!strcmp(k, "esp_id")) {
        cfg->esp_id = strtoul(v, NULL, 10);
    } else if (!strcmp(k, "ip")) {
        strlcpy(cfg->ip, v, sizeof(cfg->ip));
    } else if (!strcmp(k, "server_ip")) {
        strlcpy(cfg->server_ip, v, sizeof(cfg->server_ip));
    } else if (!strcmp(k, "mac")) {
        return parse_mac(v, cfg->mac);
    } else if (!strcmp(k, "transport")) {
        if (!strcmp(v, "mqtt0")) cfg->transport = TR_MQTT_QOS0;
        else if (!strcmp(v, "mqtt1")) cfg->transport = TR_MQTT_QOS1;
        else if (!strcmp(v, "http_req")) cfg->transport = TR_HTTP_PER_REQUEST;
        else if (!strcmp(v, "http_reuse")) cfg->transport = TR_HTTP_REUSE;
        else return false;
    } else if (!strcmp(k, "tls")) {
        cfg->tls = (v[0] == '1');
    } else if (!strcmp(k, "period_ms")) {
        cfg->period_ms = strtoul(v, NULL, 10);
    } else if (!strcmp(k, "serialization")) {
        cfg->json = !strcmp(v, "json");
    } else if (!strcmp(k, "nodelay")) {
        cfg->nodelay = (v[0] == '1');
    } else if (!strcmp(k, "duration_s")) {
        cfg->duration_s = strtoul(v, NULL, 10);
    }
    return true;
}

// Pasos: buscar la partición, leer 1 KB, verificar la cabecera, poner valores por
// defecto, recorrer las líneas (hasta el primer 0xFF) y exigir las claves mínimas.
bool config_load(node_config_t *cfg)
{
    // 0x40 es uno de los tipos de partición reservados para uso de la aplicación.
    const esp_partition_t *p = esp_partition_find_first(0x40, 0x00, "cfg");
    if (!p) {
        printf("CFGERR no hay particion cfg\n");
        return false;
    }
    static char buf[1024];
    if (esp_partition_read(p, 0, buf, sizeof(buf) - 1) != ESP_OK) {
        printf("CFGERR lectura\n");
        return false;
    }
    buf[sizeof(buf) - 1] = '\0';
    if (strncmp(buf, CFG_MAGIC, strlen(CFG_MAGIC)) != 0) {
        printf("CFGERR sin cabecera (la imagen no fue configurada por el runner)\n");
        return false;
    }
    memset(cfg, 0, sizeof(*cfg));
    cfg->period_ms = 1000;
    cfg->duration_s = 120;

    char *save = NULL;
    for (char *line = strtok_r(buf + strlen(CFG_MAGIC), "\n", &save); line;
         line = strtok_r(NULL, "\n", &save)) {
        if ((unsigned char)line[0] == 0xFF) {
            break; // resto de la partición sin escribir
        }
        char *eq = strchr(line, '=');
        if (!eq) {
            continue;
        }
        *eq = '\0';
        if (!apply(cfg, line, eq + 1)) {
            printf("CFGERR valor invalido para %s\n", line);
            return false;
        }
    }
    if (!cfg->esp_id || !cfg->ip[0] || !cfg->server_ip[0] || !cfg->period_ms) {
        printf("CFGERR faltan claves\n");
        return false;
    }
    return true;
}
