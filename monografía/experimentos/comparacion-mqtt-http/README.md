# Experimento: MQTT vs HTTP(S) para telemetría con ESP32 en QEMU

Experimento de la monografía de WireGuardians: 8 ESP32 emuladas en QEMU mandan la misma lectura
de sensor por MQTT (QoS 0/1) o por HTTP(S) (conexión por request o reutilizada), en protobuf o
JSON. Se mide en la red con `dumpcap` y se inyectan pérdida y latencia con `tc netem`.

Este archivo es el mapa del código: qué partes tiene y qué hace cada una. La explicación
detallada (cómo funciona cada función, por qué se eligió cada opción) está **en los comentarios
del propio código**: cada archivo empieza con un comentario que lo explica. Para Go, también se
puede leer con `go doc` (por ejemplo, `cd backend && go doc ./internal/matrix`).

## Resultados

| Documento | Contenido |
|---|---|
| [Resultados del experimento principal](docs/resultados/results.md) | 210 corridas: bytes, latencia, entrega, TLS, nodos, período, pérdida, RTT, serialización e hipótesis |
| [Nagle y ACK retardado](docs/resultados/nagle.md) | Por qué HTTP reutilizado suma ~40 ms por lectura, y la prueba con `TCP_NODELAY` |
| [Gráficos y tablas](docs/resultados/figs/) | 13 figuras, `tablas.md` con todas las configuraciones, intervalos de confianza y tests de Welch |

Los datos crudos están en `datos/` (`principal/`, `nagle/`, `smoke/` y `pruebas/`).

## Carpetas

```
experimento/
├── README.md        este archivo
├── docs/resultados/ análisis de los resultados, con gráficos y tablas
├── proto/           telemetry.proto: el mensaje, común a firmware y backend
├── firmware/        programa del nodo ESP32 (C, ESP-IDF)
├── backend/         módulo Go: servidor, runner, analizador y testclient (binarios en bin/)
├── analysis/        figuras.py: gráficos, tablas y tests
├── infra/           lo que rodea a los programas
│   ├── net/         bridge, taps y netem
│   ├── broker/      configuración de Mosquitto
│   └── certs/       CA y certificado del servidor
├── matrices/        qué corridas hacer: principal.yaml, nagle.yaml, smoke.yaml
└── datos/           una carpeta por matriz, con las corridas, metrics.csv, summary.csv y runner.log
    ├── principal/   matriz principal (210 corridas)
    ├── nagle/       prueba de Nagle
    ├── smoke/       prueba corta
    └── pruebas/     corridas de desarrollo (por ejemplo, HTTPS por request a 1 s)
```

## Qué hace

N ESP32 emuladas en QEMU corren un firmware real (C, ESP-IDF) que produce una lectura de sensor
por período y la manda al servidor por uno de cuatro caminos:

| Transporte | Qué hace el nodo |
|---|---|
| `mqtt0` | `PUBLISH` MQTT con QoS 0 sobre una conexión persistente |
| `mqtt1` | `PUBLISH` MQTT con QoS 1 (el broker confirma con `PUBACK`) |
| `http_reuse` | `POST` HTTP sobre una conexión que se reutiliza |
| `http_req` | `POST` HTTP abriendo y cerrando una conexión por lectura |

Cada camino puede ir con o sin TLS, en protobuf o JSON. El tráfico pasa por un bridge de Linux
donde se captura, y se le puede agregar pérdida y latencia.

```
                 matrices/principal.yaml  (qué corridas hacer)
                              │
                              ▼
 ┌─────────────────────── runner (Go, root) ───────────────────────────────┐
 │ por corrida: mosquitto → backend → netem → dumpcap → N × QEMU (firmware) │
 └───┬───────────────┬────────────────┬──────────────────┬─────────────────┘
     ▼               ▼                ▼                  ▼
 mosquitto.log   readings.csv    capture.pcapng     uart_espN.log, nodes.csv, config.json
                      \               |                 /
                       ▼              ▼                ▼
                     analyze (Go) → metrics.csv, summary.csv
                              │
                              ▼
                     figuras.py → docs/resultados/figs/
```

## Las partes

### Firmware del nodo — `firmware/`

El programa que corre en cada ESP32 emulado: lee su configuración, levanta la red, sincroniza
el reloj, se conecta y manda una lectura por período. Se compila una sola vez para toda la
matriz; lo que cambia entre corridas lo lee de una partición de flash que escribe el runner.

| Archivo | Qué hace |
|---|---|
| `main/node.h` | Tipos compartidos y la interfaz común de los transportes. **Empezar por acá** |
| `main/main.c` | Arranque, tarea productora (crea las lecturas), emisor (las manda) y marcas de tiempo |
| `main/config.c` | Lee la config del nodo (`clave=valor`) desde la partición `cfg` |
| `main/net.c` | Ethernet emulado (`open_eth`), MAC propia e IP fija |
| `main/timesync.c` | Sincroniza el reloj por SNTP con el backend |
| `main/encode.c` | Serializa la lectura en protobuf (nanopb) o JSON |
| `main/transport_mqtt.c` | Camino MQTT con esp-mqtt |
| `main/transport_http.c` | Camino HTTP(S) con esp_http_client |
| `main/telemetry.pb.{c,h}` | Descripción del mensaje para nanopb |
| `partitions.csv`, `sdkconfig.defaults` | Particiones (con `cfg`) y opciones de compilación |
| `build.sh` | Compila y arma `build/flash.bin` (4 MB). También documenta el entorno instalado |

### Red — `infra/net/`

Una red virtual en el host: un bridge `br-exp` (10.10.0.1, la IP del servidor) con una interfaz
TAP por nodo (10.10.0.11 en adelante). Se usa TAP y no la red interna de QEMU para que la
captura vea los paquetes tal como los arma el ESP32.

| Archivo | Qué hace |
|---|---|
| `setup.sh` | Crea el bridge, los taps y un `ifb` por tap (para poder aplicar netem en los dos sentidos) |
| `netem.sh` | Aplica pérdida y latencia en los dos sentidos; lo llama el runner |
| `teardown.sh` | Borra todo lo anterior |

### Broker MQTT — `infra/broker/mosquitto.conf`

Configuración de Mosquitto: listeners para los nodos (1883 sin TLS, 8883 con TLS 1.2 y la misma
suite que el HTTPS) y uno en `127.0.0.1` para el backend, fuera de la captura. El runner lanza
una instancia nueva en cada corrida.

### Certificados y mensaje — `infra/certs/`, `proto/`

- `infra/certs/gen.sh` genera la CA y un único certificado ECDSA P-256 para `10.10.0.1`, que usan
  Mosquitto y el backend HTTPS.
- `proto/telemetry.proto` define el mensaje `Telemetry` (5 campos), el mismo en todos los
  caminos. De él salen el código de nanopb del firmware y el de Go del backend.

### Backend — `backend/cmd/backend` y `backend/internal/{record,sntp,pb}`

El servidor que recibe las lecturas. Un solo proceso con tres entradas:

- HTTP en el puerto 80 y HTTPS en el 443 (`POST /tel/{esp}`, responde `204`);
- suscripción MQTT al broker (`exp/tel/+`, QoS 1);
- SNTP en el 123/udp, para que los nodos usen el reloj del host.

HTTP y MQTT terminan en la misma función, `record.Record`, que decodifica el payload y escribe
una fila en `readings.csv` con la latencia `hora de llegada − hora de creación`. Eso es lo que
hace comparables los dos caminos.

| Paquete | Qué hace |
|---|---|
| `internal/record` | Registro común: detecta protobuf o JSON y escribe `readings.csv` |
| `internal/sntp` | Servidor SNTP mínimo (50 líneas) |
| `internal/pb` | Tipos Go generados desde el `.proto` |
| `cmd/testclient` | Imita a un nodo, para probar el backend sin QEMU ni root |

### Runner — `backend/cmd/runner` y `backend/internal/matrix`

- `internal/matrix` lee un archivo de `matrices/` (`principal.yaml`, `smoke.yaml`,
  `nagle.yaml`) y arma la lista de corridas: la configuración base más un factor a la vez
  (o todas las combinaciones), repetida y en orden aleatorio con semilla fija.
- `cmd/runner` ejecuta cada corrida: lanza Mosquitto y el backend, aplica netem, arranca la
  captura, escribe la config de cada nodo en su copia de la imagen, lanza los QEMU, lee sus
  consolas hasta que todos terminan y guarda todo en `datos/<matriz>/<config>/rep<k>/`, con su
  propio log en `datos/<matriz>/runner.log`. Si se corta, al relanzarlo saltea las corridas ya
  completas.

### Análisis — `backend/cmd/analyze`, `backend/internal/pcap`, `analysis/figuras.py`

- `cmd/analyze` combina lo que llegó al servidor (`readings.csv`), lo que dijeron los nodos
  (`nodes.csv`) y lo que pasó por la red (la captura) en ~36 métricas por corrida
  (`metrics.csv`) y su media y desvío por configuración (`summary.csv`). La lista de métricas
  con su cálculo está en el comentario inicial del archivo.
- `internal/pcap` lee las capturas con `tshark`: bytes, paquetes, handshakes y retransmisiones
  por conexión.
- `analysis/figuras.py` genera los gráficos, las tablas y los tests estadísticos de
  [docs/resultados/](docs/resultados/results.md).

## Recorrido de una lectura

Una lectura del nodo 3 en una corrida `mqtt1` con TLS:

1. **Firmware.** El productor crea `{seq, t_us, value}` con la hora sincronizada y la encola. El
   emisor la saca, la serializa (18 B en protobuf) y la publica en `exp/tel/3`.
2. **Red.** La trama sale por `tap2`, pasa por netem si corresponde y entra al bridge, donde la
   captura `dumpcap`.
3. **Broker.** Mosquitto contesta `PUBACK` al nodo y le pasa el mensaje al backend por `127.0.0.1`.
4. **Backend.** Anota la hora de llegada y escribe la fila en `readings.csv`.
5. **Análisis.** La cuenta como entregada, usa su latencia para los percentiles y reparte los
   bytes de la captura entre todas las lecturas entregadas.

En HTTP cambia el paso 3: el nodo hace `POST /tel/3` directo al backend, sin broker.

## Puesta en marcha

Desde esta carpeta:

```bash
# 1. Paquetes del sistema (libslirp lo necesita el QEMU de Espressif)
sudo pacman -S --needed libslirp mosquitto
#    No habilitar el servicio de mosquitto: el runner lanza su propia instancia.

# 2. Certificados (las claves privadas no están en el repositorio)
./infra/certs/gen.sh                      # -> infra/certs/{ca,server}.{key,crt}

# 3. Firmware (ESP-IDF v5.5.6 en ~/esp/esp-idf, QEMU en ~/esp/qemu; ver firmware/build.sh)
./firmware/build.sh                       # -> firmware/build/flash.bin

# 4. Herramientas en Go
(cd backend && go build -o bin/ ./cmd/...)

# 5. Red (se pierde al reiniciar la máquina)
sudo ./infra/net/setup.sh 8
sudo ufw allow in on br-exp comment "experimento MQTT vs HTTP"   # si ufw está activo

# 6. Prueba corta (en otra carpeta, para no mezclar con los datos reales)
sudo ./backend/bin/runner -matrix matrices/smoke.yaml -runs datos/smoke
./backend/bin/analyze -runs datos/smoke

# 7. Matriz completa (~7 h 40 min; se puede cortar y retomar)
#    (sin flags: matrices/principal.yaml → datos/principal → docs/resultados/figs)
sudo ./backend/bin/runner
./backend/bin/analyze
uv run --with pandas --with matplotlib --with scipy analysis/figuras.py
```

## Decisiones de diseño

Cada una está explicada en el comentario del archivo donde se aplica.

| Decisión | Dónde |
|---|---|
| Firmware real en QEMU, no clientes simulados: los bytes son los de lwIP, mbedTLS, esp-mqtt y esp_http_client sin cambios | `firmware/main/main.c` |
| Red TAP + bridge, no slirp (slirp termina el TCP del ESP32 dentro de QEMU) | `infra/net/setup.sh` |
| IPv6 desactivado, MAC propia por nodo, IP fija | `firmware/main/net.c`, `sdkconfig.defaults` |
| Config por nodo en una partición de texto, sin recompilar | `firmware/main/config.c` |
| TLS igual en los dos caminos: 1.2, `ECDHE-ECDSA-AES128-GCM-SHA256`, mismo certificado, sin reanudación de sesión | `sdkconfig.defaults`, `infra/broker/mosquitto.conf`, `backend/cmd/backend` |
| El backend se suscribe con QoS 1 por `127.0.0.1`, fuera de la captura | `backend/cmd/backend`, `infra/broker/mosquitto.conf` |
| Productor y emisor separados: la espera en cola entra en la latencia; 30 s de margen para vaciar | `firmware/main/main.c` |
| MQTT QoS 1 con el reenvío de 1 s por defecto de esp-mqtt (fuente de duplicados) | `firmware/main/transport_mqtt.c` |
| HTTP con Nagle por defecto; `nodelay` como variante | `firmware/main/transport_http.c`, [nagle.md](docs/resultados/nagle.md) |
| HTTPS por request con período base de 10 s: con 1 s satura en QEMU (cada handshake TLS tarda 3-5 s y solo se entrega ~27 %) | `matrices/principal.yaml`, `backend/internal/matrix` |
| Pérdida y latencia en los dos sentidos; "X ms" es RTT extra | `infra/net/netem.sh` |
| Orden aleatorio de corridas con semilla fija | `backend/internal/matrix` |
