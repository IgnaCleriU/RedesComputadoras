# Nagle y ACK retardado en HTTP con conexión reutilizada

En la prueba corta del experimento, **HTTP con conexión reutilizada (`http_reuse`) tardó
unos 47 ms por lectura**, mientras que HTTP con una conexión por request tardó 12 ms
y MQTT 5 ms, en la misma red sin pérdida ni latencia agregada. La diferencia no viene
de HTTP ni del servidor. Viene de cómo interactúan en TCP dos optimizaciones: el
algoritmo de Nagle en el ESP32 y el ACK retardado en el servidor Linux.

Este documento explica el caso, con la evidencia de las capturas, y define la prueba
con Nagle desactivado (`TCP_NODELAY`).

## Qué se observa

`esp_http_client` (el cliente HTTP de ESP-IDF) escribe cada request con **dos llamadas
`send()`**: primero la línea de request con los headers y después el cuerpo. Cada
llamada sale como un segmento TCP aparte.

Línea de tiempo de una lectura en `http_reuse` sin TLS (captura de
`datos/smoke/http_reuse_n2_p500_tls0_l0_r0_pb`, nodo 10.10.0.11):

```
t (ms)    sentido           segmento
  0.0     ESP32 → servidor  POST /tel/1 + headers   134 B
 40.3     servidor → ESP32  ACK (sin datos)                 ← ACK retardado
 41.1     ESP32 → servidor  cuerpo protobuf          18 B   ← Nagle lo retuvo hasta el ACK
 41.2     servidor → ESP32  HTTP/1.1 204 No Content  64 B
269.0     ESP32 → servidor  ACK (sin datos)                 ← ACK retardado de lwIP
```

Medianas sobre todas las lecturas de la prueba corta:

| | sin TLS | con TLS |
|---|---|---|
| Segmento de headers | 134 B | 163 B (registro TLS) |
| Segmento del cuerpo | 18 B | 47 B (registro TLS) |
| Espera entre headers y cuerpo | **41,5 ms** | **41,7 ms** |
| ACK del servidor a los headers | 40,9 ms | 40,9 ms |
| ACK del ESP32 después de la respuesta | 228 ms | 228 ms |

Con TLS pasa lo mismo: mbedTLS cifra cada `send()` en su propio registro TLS, así
que también salen dos segmentos (cada uno con 29 B de sobrecarga de TLS: 5 de cabecera,
8 de nonce y 16 de tag de GCM).

## Por qué pasa

1. **Nagle (ESP32, lwIP).** Mientras haya datos enviados sin confirmar, TCP no manda
   un segmento chico, sino que lo acumula hasta recibir el ACK pendiente. Los headers
   salieron y todavía no tienen ACK, así que el cuerpo (18 B) queda retenido.
2. **ACK retardado (servidor, Linux).** En una conexión de ida y vuelta (el servidor
   contesta cada request), Linux entra en modo interactivo y demora el ACK hasta
   40 ms (`TCP_DELACK_MIN`), con la idea de mandarlo junto con la respuesta. Pero el
   servidor no puede responder porque todavía no recibió el cuerpo.
3. **Cada lado espera al otro**, y el bloqueo se rompe recién cuando vence el temporizador
   de 40 ms del servidor: llega el ACK, Nagle libera el cuerpo y el servidor responde.

Además, el ESP32 tampoco confirma la respuesta enseguida: lwIP retrasa el ACK hasta su
temporizador rápido (~250 ms). Como el nodo no tiene más datos para enviar en ese
momento, el ACK sale solo, como un paquete más por lectura.

### Efecto secundario: una retransmisión innecesaria por conexión

Los ~228 ms que tarda el ESP32 en confirmar superan el tiempo mínimo de
retransmisión de Linux (200 ms). En la primera respuesta de cada conexión, el servidor
solo tiene como estimación el RTT del handshake (unos pocos ms), así que usa ese
mínimo de 200 ms y **retransmite la respuesta 204 aunque no se perdió**. Después Linux
ajusta su estimación con esos ACK lentos y no se repite. En una corrida de 15 s con
8 nodos se retransmitieron 7 de 127 respuestas, todas la primera de su conexión, con
y sin `nodelay`.

El mismo mecanismo aparece en cualquier conexión nueva en la que el primer envío del
servidor no tiene respuesta rápida del nodo. En `http_req` con TLS se retransmite el
primer bloque de mensajes del servidor en el handshake (ServerHello, certificado y
ServerKeyExchange, ~654 B): el ESP32 tarda segundos en calcular su parte del
handshake en QEMU y su ACK retardado llega después de los 200 ms (11 retransmisiones
en 80 conexiones en la prueba corta). En `http_req` sin TLS no pasa, porque el nodo
confirma enseguida el FIN que llega junto con la respuesta.

## Qué pasa en los otros caminos

- **HTTP por request (`http_req`) sin TLS**: la conexión es nueva en cada lectura, y Linux
  confirma de inmediato los primeros segmentos de una conexión (modo *quickack*). En la
  captura, el ACK a los headers llega en 44 µs y el cuerpo sale unos 4 ms después.
  Paga el handshake TCP en cada lectura, pero no la espera de Nagle.
- **HTTP por request con TLS sí lo sufre, y dos veces por conexión.** Los segmentos del
  handshake TLS agotan el modo *quickack* del servidor, así que:
  1. dentro del handshake, el ESP32 manda el Client Key Exchange y el Change Cipher Spec
     con Finished en dos escrituras, y el segundo espera ~41 ms el ACK retardado;
  2. después, los headers y el cuerpo del POST tienen la misma espera de ~41 ms que en
     `http_reuse`.

  En `http_req` con TLS estos ~80 ms quedan escondidos detrás de los ~3,4 s que tarda el
  handshake con criptografía emulada.
- **MQTT**: esp-mqtt arma el PUBLISH completo en un buffer y lo escribe con un solo
  `send()`. Cada lectura es un segmento (31 B sin TLS: 2 de cabecera fija, 2 de largo
  del tópico, 9 del tópico `exp/tel/1` y 18 del payload), así que Nagle no tiene nada
  que retener. Con QoS 0 el broker nunca contesta, no entra en modo interactivo y
  confirma enseguida. Con QoS 1 el ACK viaja junto con el PUBACK.

## Efecto en las métricas

- **Latencia**: unos +41 ms por lectura en `http_reuse`, con y sin TLS. Pesa más que
  todo el resto del camino en una red local.
- **Paquetes y bytes**: el cuerpo en un segmento propio suma una cabecera TCP/IP
  (40 B) y el servidor manda un ACK sin datos. A eso se suma el ACK solo del ESP32.
  En la prueba corta, `http_reuse` dio unos 6 paquetes por lectura, contra 2 de MQTT
  QoS 0.
- No cambia la tasa de entrega.

Es un efecto de capa de transporte (objetivo 2 de la monografía): el mismo protocolo
de aplicación cambia su latencia en un orden de magnitud según cómo el cliente reparte
los datos en llamadas a `send()` y cómo interactúa eso con TCP.

## Prueba con Nagle desactivado

El firmware tiene la opción `nodelay` (config del nodo, factor `nodelay` en la matriz).
Con `nodelay=1`, apenas se abre la conexión HTTP se pone `TCP_NODELAY` en el socket
(`firmware/main/transport_http.c`, evento `HTTP_EVENT_ON_CONNECTED`), así el cuerpo
sale sin esperar el ACK de los headers. Solo afecta a los caminos HTTP. MQTT no lo
necesita porque escribe cada mensaje de una vez.

`matrices/nagle.yaml` es un diseño factorial 2 × 2 (`nodelay` × TLS) para `http_reuse` y
`http_req`, con la configuración base del experimento: 8 nodos, 120 s, período de 1 s
(10 s para `http_req`) y 3 repeticiones.

```bash
sudo ./backend/bin/runner -matrix matrices/nagle.yaml -runs datos/nagle
./backend/bin/analyze -runs datos/nagle
```

Qué se espera si la explicación es correcta:
- `http_reuse` con `nodelay`: la latencia baja de ~47 ms a unos pocos ms, y desaparece
  el ACK sin datos del servidor a los headers, porque ahora viaja junto con la respuesta.
- `http_req`: casi sin cambio, porque ya no sufría la espera.
- Los bytes por lectura casi no cambian: siguen siendo dos `send()`, o sea dos segmentos.

### Resultados

`datos/nagle/summary.csv`: 8 nodos, 120 s, 3 repeticiones por configuración (media ± desvío),
período de 1 s para `http_reuse` y 10 s para `http_req`. La entrega fue del 100 % en todas.

| Transporte | TLS | `nodelay` | Latencia p50 (ms) | Latencia p95 (ms) | Bytes IP / lectura | Paquetes / lectura |
|---|---|---|---|---|---|---|
| `http_reuse` | no | no | 44,29 ± 0,07 | 46,65 ± 0,04 | 457,9 | 6,03 |
| `http_reuse` | no | **sí** | **4,19 ± 0,05** | **7,17 ± 0,23** | **418,3** | **5,04** |
| `http_reuse` | sí | no | 44,74 ± 0,10 | 48,48 ± 0,62 | 555,2 ± 0,2 | 6,08 |
| `http_reuse` | sí | **sí** | **5,02 ± 0,05** | **8,85 ± 0,49** | **515,0 ± 0,5** | **5,08** |
| `http_req` | no | no | 9,77 ± 0,15 | 59,37 ± 1,73 | 741,8 | 12,00 |
| `http_req` | no | sí | 10,13 ± 0,22 | 62,11 ± 3,34 | 741,8 | 12,00 |
| `http_req` | sí | no | 3422 ± 146 | 4064 ± 278 | 2927,7 ± 8,9 | 22,92 |
| `http_req` | sí | sí | 3304 ± 76 | 3765 ± 198 | 2892,6 ± 0,6 | 21,93 |

**Se confirma la explicación:**

- **`http_reuse`: la latencia baja unas 10 veces** (de ~44 ms a ~4-5 ms), con y sin TLS. Los
  ~40 ms que desaparecen son exactamente el ACK retardado de Linux. Con `nodelay`, HTTP
  reutilizado sin TLS queda en el mismo orden que MQTT (~5 ms en la prueba corta).
- **Los bytes también bajan, ~40 B por lectura**, y hay un paquete menos. Es el ACK sin
  datos del servidor a los headers: sin la espera, el ACK viaja junto con la respuesta. El
  cuerpo sigue en su propio segmento (siguen siendo dos `send()`), tal como se esperaba.
- **`http_req` sin TLS no cambia**: misma latencia dentro del desvío y bytes idénticos (741,8),
  porque ya no sufría la espera.
- **`http_req` con TLS ahorra un paquete y ~35 B por conexión**, de nuevo el ACK de los
  headers. La mejora de latencia (~120 ms) queda dentro del ruido del handshake emulado.
  La espera dentro del handshake TLS no desaparece: `nodelay` se aplica en
  `HTTP_EVENT_ON_CONNECTED`, que esp_http_client dispara cuando el handshake ya terminó.
  Para eliminarla habría que poner `TCP_NODELAY` antes del handshake, y esp_http_client
  no ofrece un punto para hacerlo sin modificar esp-tls.
- Las retransmisiones son las del efecto secundario descrito arriba (la primera respuesta
  de cada conexión en `http_reuse`, el primer bloque de mensajes del servidor en el
  handshake de `http_req` con TLS). `nodelay` no las cambia.

**Para el experimento principal** (`matrices/principal.yaml`) se mantiene el comportamiento por defecto
del cliente (con Nagle), que es lo que haría un ESP32 sin ajustes. Estos resultados permiten
separar en la monografía qué parte de la diferencia entre HTTP y MQTT es del protocolo y qué
parte es de cómo el cliente HTTP usa TCP.
