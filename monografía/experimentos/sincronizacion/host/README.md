# Herramientas del host para el experimento de sincronización

Corren una matriz de experimentos de Kuramoto sobre nodos ESP32 emulados con QEMU, registran las
fases que publican por MQTT y las analizan. Todo es Python (numpy y scipy) y bash. El firmware y el
formato del mensaje (`firmware/`, `proto/`) son de otra parte del trabajo; acá solo se los usa.

| Archivo | Qué hace |
|---|---|
| `red.sh` | Puente `br-kur` (10.10.0.1/24), taps `tapk1..N` y `netem` en ambos sentidos |
| `mosquitto.conf` | Broker en 10.10.0.1 y 127.0.0.1, sin persistencia, sin Nagle, colas grandes |
| `mosquitto-local.conf` | Broker en 0.0.0.0 para la prueba local sin privilegios |
| `sntp_server.py` | Servidor SNTP mínimo (puerto 123 por defecto) |
| `correr.py` | Corre una matriz JSON: una carpeta por corrida en `resultados/<matriz>/` |
| `analizar.py` | Decodifica `fases.log`, calcula r(t), Omega, enganche y escribe `resumen.csv` |
| `probar_analisis.py`, `probar_sntp.py` | Pruebas sintéticas del análisis y del SNTP |

## Pasos en la PC de destino

Hace falta `qemu-system-xtensa` con soporte de ESP32 (el de Espressif), `mosquitto`,
`mosquitto_sub`, `iproute2`/`tc` y, para `--captura`, `tcpdump`. Se corre desde
`monografía/experimentos/sincronizacion/`.

1. **Compilar el firmware** con `firmware/build.sh`, que deja la imagen de 4 MB en
   `firmware/build/flash.bin`. Necesita internet la primera vez, para bajar nanopb. `correr.py` agrega
   en cada copia la config del nodo en `0x190000`. Antes de usar `correr.py`, cargar el entorno con
   `. ~/esp/esp-idf/export.sh` para que `qemu-system-xtensa` esté en el PATH, o pasar `--qemu RUTA`.
2. **Probar sin privilegios** con dos nodos y red de usuario (no usa taps, SNTP ni netem; los
   nodos llegan al broker por 10.0.2.2 y el reloj de cada uno es el suyo):
   ```
   python3 host/correr.py --matriz matrices/smoke.json --local
   python3 host/analizar.py resultados/smoke
   ```
   Con `--dry-run` se ve el plan y se verifican las imágenes sin arrancar nada.
3. **Levantar la red** para 40 nodos. Además de crear puente y taps, `up` baja
   `ip_unprivileged_port_start` a 123 para que el SNTP corra sin root (`down` lo restaura):
   ```
   sudo host/red.sh up 40
   sudo ufw allow in on br-kur    # si el firewall está activo: MQTT (1883) y SNTP (123) desde los nodos
   sudo -v        # los perfiles de netem se aplican con sudo -n; correr.py renueva el ticket
   ```
   **Validar antes de las corridas largas**, en este orden: `tap2` comprueba tap, SNTP y netem con dos
   nodos (unos 3 min); `carga40` comprueba 40 nodos con el firmware real (unos 4 min). En las dos,
   revisar `nodos.csv` (`overruns` en 0 y `recibidos` esperados) y `resumen.csv`.
   ```
   python3 host/correr.py --matriz matrices/tap2.json && python3 host/analizar.py resultados/tap2
   python3 host/correr.py --matriz matrices/carga40.json && python3 host/analizar.py resultados/carga40
   ```
   Si algún nodo no llega a `READY`, subir el margen de arranque con `--margen 150`.
4. **Correr la matriz.** Se puede cortar con Ctrl-C y retomar: se saltean las corridas con
   `fin.ok`.
   ```
   python3 host/correr.py --matriz matrices/principal.json
   python3 host/correr.py --matriz matrices/extrapolacion.json
   ```
   Opciones útiles: `--solo 'distintas_k1.05*'` (patrón sobre entrada o corrida), `--captura`
   (pcap de `br-kur`), `--margen S` (segundos hasta `t_inicio_ms`; por defecto `max(20, 2.25 N)`,
   o sea 90 con 40 nodos), `--qemu RUTA`, `--flash RUTA`.
5. **Analizar:**
   ```
   python3 host/analizar.py resultados/principal
   ```
   Deja `resumen.csv` en la matriz y `serie.csv` (r y psi en el tiempo) y `nodos_analisis.csv` en
   cada corrida. Las columnas usan `;` como separador.
6. **Apagar la red:** `sudo host/red.sh down`.

Con más de 50 nodos `correr.py` avisa: la CPU de la PC de referencia no alcanza.

## Qué queda en cada corrida

`config.json` (parámetros, omega, theta0 y desfase de cada nodo, `t_inicio_ms`), `fases.log`
(`<hora de llegada> <tópico> <payload en hex>`), `uart<i>.log`, `nodos.csv` (si cada nodo
terminó y sus contadores de DONE), `mosquitto.log`, y `fin.ok` si todos terminaron o `fallo.txt`
con el motivo. Todo el azar (theta0, desfase) sale de un generador de numpy sembrado con la
semilla. Con perfil de netem, el ruido vale también para el SNTP de arranque.

## Duraciones esperadas

Cada corrida dura margen de arranque + duración + unos 15 s de cierre. Con 40 nodos, 90 s + 600 s
+ 15 s = 705 s (11.75 min).

| Matriz | Corridas | Cálculo | Total |
|---|---|---|---|
| `smoke` (2 nodos, `--local`) | 1 | 20 + 40 + 15 s | 1.3 min |
| `tap2` | 2 | 2 perfiles, 2 nodos | 3 min |
| `carga40` | 1 | 40 nodos, 120 s | 4 min |
| `principal` | 108 | 72 distintas (6 K x 4 perfiles x 3 semillas) + 36 iguales (3 K x 4 x 3) | 21.1 h |
| `extrapolacion` | 108 | igual, con `extrapolar=1` y f = 0.25 Hz | 21.1 h |

Las dos matrices grandes juntas son unas 42 horas. Para una primera pasada conviene una semilla
(`--solo '*_s1'`): 36 corridas, unas 7 h por matriz.

## Qué no está verificado

Probado con 2 nodos reales en QEMU y red de usuario: arranque, intercambio de fases, enganche,
No Local (el broker no devuelve la propia fase), extrapolación y reconexión tras caer el broker (unos
10 s sin fases, sin fallos). Falta verificar en la PC de destino, porque requiere root: tap, SNTP,
netem, y la carga con 40 nodos usando el firmware real.
