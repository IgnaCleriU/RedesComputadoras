// Reloj del nodo. Con sntp=1 se sincroniza con el servidor (SNTP) y
// now_epoch_us() devuelve la hora en µs desde 1970. Con sntp=0 no hay
// sincronización: devuelve esp_timer (µs desde el arranque), útil para pruebas
// locales de un solo nodo.
//
// Nota: el cliente SNTP de lwIP no compensa el viaje de vuelta, así que el
// reloj queda atrasado medio RTT respecto del servidor.
#include <stdio.h>
#include <sys/time.h>

#include "esp_netif_sntp.h"
#include "esp_timer.h"
#include "node.h"

static bool s_sntp;

uint64_t now_epoch_us(void)
{
    if (!s_sntp) {
        return (uint64_t)esp_timer_get_time();
    }
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
}

bool timesync_start(const node_config_t *cfg)
{
    if (!cfg->sntp) {
        s_sntp = false;
        return true;
    }
    s_sntp = true;
    esp_sntp_config_t sc = ESP_NETIF_SNTP_DEFAULT_CONFIG(cfg->server_ip);
    if (esp_netif_sntp_init(&sc) != ESP_OK) {
        printf("SYNCERR init\n");
        return false;
    }
    // Espera hasta 90 s: si se pierde el primer pedido lwIP reintenta a los 15 s.
    for (int i = 0; i < 18; i++) {
        if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(5000)) == ESP_OK) {
            return true;
        }
    }
    printf("SYNCERR sin respuesta de %s\n", cfg->server_ip);
    return false;
}
