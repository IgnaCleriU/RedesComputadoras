// Lee la config del nodo desde la partición "cfg" (texto "clave=valor\n").
// El lanzador la escribe en la imagen de flash de cada instancia QEMU.
//
// La partición (partitions.csv: tipo 0x40, offset 0x190000, 4 KB) contiene:
//   KURCFG1
//   id=3                    1..n
//   n=40                    cantidad total de nodos
//   ip=10.10.0.13           solo red=tap
//   server_ip=10.10.0.1     broker, SNTP y gateway
//   mac=02:00:00:00:00:03
//   omega=1.234             rad/s
//   k=2.0                   rad/s
//   theta0=0.5              rad
//   h_ms=100  ts_ms=10  desfase_ms=0
//   t_inicio_ms=1793041765000   epoch (sntp=1) o ms desde el arranque (sntp=0)
//   duracion_s=60
//   extrapolar=0            0 | 1
//   sntp=1                  0 | 1
//   red=tap                 tap | user
//   keepalive_s=5  qos=0  will=0  alias=0  esquema=0  t_union_s=0   (opcionales)
// seguido de '\0' y el resto en 0xFF (flash "vacía").
//
// Sin la cabecera KURCFG1 el nodo imprime CFGERR y no arranca. Texto y no NVS
// para que el lanzador la escriba con un simple copy.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_partition.h"
#include "node.h"

#define CFG_MAGIC "KURCFG1\n"

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

// Convierte una clave a su campo. Un valor inválido devuelve false (CFGERR);
// las claves desconocidas se ignoran.
static bool apply(node_config_t *c, const char *k, const char *v)
{
    if (!strcmp(k, "id")) c->id = strtoul(v, NULL, 10);
    else if (!strcmp(k, "n")) c->n = strtoul(v, NULL, 10);
    else if (!strcmp(k, "ip")) strlcpy(c->ip, v, sizeof(c->ip));
    else if (!strcmp(k, "server_ip")) strlcpy(c->server_ip, v, sizeof(c->server_ip));
    else if (!strcmp(k, "mac")) { c->mac_set = parse_mac(v, c->mac); return c->mac_set; }
    else if (!strcmp(k, "omega")) c->omega = strtod(v, NULL);
    else if (!strcmp(k, "k")) c->k = strtod(v, NULL);
    else if (!strcmp(k, "theta0")) c->theta0 = strtod(v, NULL);
    else if (!strcmp(k, "h_ms")) c->h_ms = strtoul(v, NULL, 10);
    else if (!strcmp(k, "ts_ms")) c->ts_ms = strtoul(v, NULL, 10);
    else if (!strcmp(k, "desfase_ms")) c->desfase_ms = strtoul(v, NULL, 10);
    else if (!strcmp(k, "t_inicio_ms")) c->t_inicio_ms = strtoull(v, NULL, 10);
    else if (!strcmp(k, "duracion_s")) c->duracion_s = strtoul(v, NULL, 10);
    else if (!strcmp(k, "extrapolar")) c->extrapolar = (v[0] == '1');
    else if (!strcmp(k, "sntp")) c->sntp = (v[0] == '1');
    else if (!strcmp(k, "keepalive_s")) c->keepalive_s = strtoul(v, NULL, 10);
    else if (!strcmp(k, "qos")) c->qos = strtoul(v, NULL, 10);
    else if (!strcmp(k, "will")) c->will = (v[0] == '1');
    else if (!strcmp(k, "alias")) c->alias = (v[0] == '1');
    else if (!strcmp(k, "esquema")) c->esquema = strtoul(v, NULL, 10);
    else if (!strcmp(k, "t_union_s")) c->t_union_s = strtoul(v, NULL, 10);
    else if (!strcmp(k, "red")) {
        if (!strcmp(v, "tap")) c->red_tap = true;
        else if (!strcmp(v, "user")) c->red_tap = false;
        else return false;
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
        printf("CFGERR sin cabecera (la imagen no fue configurada)\n");
        return false;
    }
    memset(cfg, 0, sizeof(*cfg));
    cfg->h_ms = 100;
    cfg->ts_ms = 10;
    cfg->sntp = true;
    cfg->red_tap = true;

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
    if (!cfg->id || !cfg->n || cfg->n > MAX_N || cfg->id > cfg->n || !cfg->server_ip[0] ||
        !cfg->h_ms || !cfg->ts_ms || (cfg->ts_ms % 10) || !cfg->duracion_s || !cfg->t_inicio_ms ||
        cfg->qos > 1 || cfg->esquema > ESQ_CRUZADO ||
        (cfg->red_tap && (!cfg->ip[0] || !cfg->mac_set))) {
        printf("CFGERR faltan claves o valores fuera de rango\n");
        return false;
    }
    return true;
}
