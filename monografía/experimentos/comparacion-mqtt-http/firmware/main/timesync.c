// Sincroniza el reloj del nodo con el SNTP del backend, así t_us y la hora de
// recepción del servidor salen del mismo reloj. Se re-sincroniza cada 15 s
// (CONFIG_LWIP_SNTP_UPDATE_DELAY, el mínimo que admite) y cada ajuste se informa
// por UART.
//
// La latencia que calcula el backend es t_recv_us - t_us, por eso los dos relojes
// tienen que coincidir. El servidor SNTP es el propio backend
// (backend/internal/sntp), que responde con la hora del host.
//
// Error del reloj: el cliente SNTP de lwIP se compila con SNTP_COMP_ROUNDTRIP = 0.
// Toma la hora que manda el servidor sin sumar el viaje de vuelta, así que el
// reloj del nodo queda atrasado medio RTT. Sin latencia agregada es ~1 ms; con
// RTT agregado por netem es exactamente RTT/2 y se corrige en el análisis
// (analysis/figuras.py).
//
// El runner compara epoch_us de cada línea SYNC con la hora del host al leerla:
// esa diferencia es una cota superior del error, porque incluye el paso por la
// UART emulada.
#include <stdio.h>
#include <sys/time.h>

#include "esp_netif_sntp.h"
#include "esp_timer.h"
#include "node.h"

// Hora actual en µs desde 1970. Después de sincronizar ya está en la escala del host.
uint64_t now_epoch_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
}

static void on_sync(struct timeval *tv)
{
    // El runner compara epoch_us con la hora del host al recibir la línea.
    printf("SYNC epoch_us=%llu timer_us=%lld\n", (unsigned long long)now_epoch_us(),
           (long long)esp_timer_get_time());
}

bool timesync_start(const char *server_ip)
{
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG(server_ip);
    cfg.sync_cb = on_sync;
    if (esp_netif_sntp_init(&cfg) != ESP_OK) {
        return false;
    }
    // Espera hasta 90 s. Si se pierde el primer pedido (o el ARP) lwIP reintenta a
    // los 15 s y después duplica la espera, así que con 5 % de pérdida 30 s no alcanzan.
    for (int i = 0; i < 18; i++) {
        if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(5000)) == ESP_OK) {
            return true;
        }
    }
    printf("SYNCERR sin respuesta de %s\n", server_ip);
    return false;
}
