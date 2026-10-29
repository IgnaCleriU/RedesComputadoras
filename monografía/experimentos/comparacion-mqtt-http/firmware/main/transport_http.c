// Camino HTTP(S): un POST /tel/{esp} por lectura, con esp_http_client.
//   http_req:   cliente nuevo por lectura y "Connection: close" (peor caso,
//               como un dispositivo que duerme entre envíos)
//   http_reuse: un único cliente; la conexión TCP/TLS se reutiliza (keep-alive)
// Reintentos de la aplicación: hasta HTTP_ATTEMPTS intentos con timeout de 5 s.
// Content-Type: application/x-protobuf o application/json. El servidor responde
// 204 sin cuerpo (backend/cmd/backend).
//
// Conexión perezosa: esp_http_client abre la conexión recién en el primer
// perform(), no en init. Por eso la primera lectura de http_reuse paga el
// handshake TLS completo (~3,6 s en QEMU), mientras que en MQTT la conexión ya
// está abierta antes de READY.
//
// Nagle: esp_http_client escribe los headers y el cuerpo con dos send(). Con una
// conexión reutilizada, Nagle retiene el cuerpo hasta el ACK de los headers, que
// el servidor demora (ACK retardado, ~40 ms en Linux). Con nodelay=1 se pone
// TCP_NODELAY en el socket apenas conecta. Ver docs/resultados/nagle.md.
#include <stdio.h>

#include "esp_http_client.h"
#include "lwip/sockets.h"
#include "node.h"

#define HTTP_ATTEMPTS 3
#define HTTP_TIMEOUT_MS 5000

static const node_config_t *s_cfg;
static esp_http_client_handle_t s_reuse;
static char s_url[64];

// Con nodelay=1 pone TCP_NODELAY en el socket recién conectado. Este evento llega
// cuando el handshake TLS ya terminó, así que la espera de Nagle dentro del
// handshake no se elimina (esp_http_client no ofrece un punto anterior).
static esp_err_t on_http_event(esp_http_client_event_t *evt)
{
    if (evt->event_id == HTTP_EVENT_ON_CONNECTED && s_cfg->nodelay) {
        int fd = esp_http_client_get_socket(evt->client);
        int one = 1;
        if (fd < 0 || setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)) != 0) {
            printf("NODELAY_ERR fd=%d\n", fd);
        }
    }
    return ESP_OK;
}

static esp_http_client_handle_t make_client(void)
{
    esp_http_client_config_t hc = {
        .url = s_url,
        .method = HTTP_METHOD_POST,
        .cert_pem = s_cfg->tls ? ca_crt_start : NULL,
        .timeout_ms = HTTP_TIMEOUT_MS,
        .disable_auto_redirect = true,
        .keep_alive_enable = false, // keep-alive de TCP; la reutilización HTTP es aparte
        .event_handler = on_http_event,
    };
    esp_http_client_handle_t c = esp_http_client_init(&hc);
    if (!c) {
        return NULL;
    }
    esp_http_client_set_header(c, "Content-Type",
                               s_cfg->json ? "application/json" : "application/x-protobuf");
    if (s_cfg->transport == TR_HTTP_PER_REQUEST) {
        esp_http_client_set_header(c, "Connection", "close");
    }
    return c;
}

// perform() hace todo el intercambio de forma bloqueante: conecta si hace falta
// (TCP y TLS), escribe la línea de request con los headers, escribe el cuerpo en
// un segundo send() y lee la respuesta. Errores al runner: HTTP_ERR (falló
// perform) o HTTP_STATUS (código fuera de 2xx).
static bool post(esp_http_client_handle_t c, const uint8_t *buf, size_t len)
{
    esp_http_client_set_post_field(c, (const char *)buf, (int)len);
    esp_err_t err = esp_http_client_perform(c);
    if (err != ESP_OK) {
        printf("HTTP_ERR %s\n", esp_err_to_name(err));
        return false;
    }
    int st = esp_http_client_get_status_code(c);
    if (st < 200 || st >= 300) {
        printf("HTTP_STATUS %d\n", st);
        return false;
    }
    return true;
}

bool http_transport_init(const node_config_t *cfg)
{
    s_cfg = cfg;
    snprintf(s_url, sizeof(s_url), "%s://%s/tel/%lu", cfg->tls ? "https" : "http", cfg->server_ip,
             (unsigned long)cfg->esp_id);
    if (cfg->transport == TR_HTTP_REUSE) {
        s_reuse = make_client();
        return s_reuse != NULL;
    }
    return true;
}

// Hasta HTTP_ATTEMPTS intentos. En http_req cada intento es una conexión nueva
// (cleanup la cierra). En http_reuse, si un intento falla se cierra la conexión
// compartida para que el siguiente abra otra. HTTP_RETRY_OK avisa al runner que
// un reintento salió bien.
bool http_transport_send(const uint8_t *buf, size_t len)
{
    for (int attempt = 1; attempt <= HTTP_ATTEMPTS; attempt++) {
        bool ok;
        if (s_cfg->transport == TR_HTTP_PER_REQUEST) {
            esp_http_client_handle_t c = make_client();
            if (!c) {
                return false;
            }
            ok = post(c, buf, len);
            esp_http_client_cleanup(c); // cierra la conexión
        } else {
            ok = post(s_reuse, buf, len);
            if (!ok) {
                esp_http_client_close(s_reuse); // el próximo intento reconecta
            }
        }
        if (ok) {
            if (attempt > 1) {
                printf("HTTP_RETRY_OK attempt=%d\n", attempt);
            }
            return true;
        }
    }
    return false;
}

// HTTP no deja nada pendiente: cada send espera la respuesta.
void http_transport_finish(void)
{
}
