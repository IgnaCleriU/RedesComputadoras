# Experimento 2: código hecho e ideas de la plataforma

Resume lo trabajado hasta el 27/10/2026 para el experimento de sincronización de osciladores. El
detalle completo de cada medición está en el
[README de eco-mqtt](../../plataforma-comun/eco-mqtt/README.md).

## Estado

**Todavía no existe la implementación de Kuramoto.** Lo hecho es la plataforma sobre la que va a
correr, y las mediciones que fijan sus límites:

| Hecho | Falta |
|---|---|
| Firmware ESP-IDF de medición, para placa real y QEMU | Firmware con la fase, el acoplamiento y el LED |
| Backend Go de latencia y throughput | Backend o analizador de r(t), Ω y K_c |
| Hasta 60 nodos QEMU sobre tap + puente | `.proto` del mensaje de fase |
| Simulación ideal del modelo de los nodos (`simulacion/`) | |
| Delay de difusión, todos-a-todos y ruido con `netem` | Corridas del experimento y su análisis |

El firmware actual publica mensajes con secuencia, índice del emisor y relleno. No calcula ninguna
fase, pero `bcast` ya genera el mismo patrón de tráfico que tendrá el experimento.

## Código

Todo está en [`monografía/plataforma-comun/eco-mqtt/`](../../plataforma-comun/eco-mqtt/), y los
paquetes necesarios en el [README de la plataforma](../../plataforma-comun/README.md).

| Parte | Archivos | Qué hace |
|---|---|---|
| Firmware | `firmware/main/main.c` | Eco `ping`/`pong`, `flood N S Q` y `bcast N P S [A]` en `eco/todos` |
| Variantes | `firmware/sdkconfig.defaults.{real,qemu,tap}` | WiFi en la placa, openeth con red de usuario, u openeth con tap |
| Backend | `backend/main.go` | `eco suite`, `eco multi` y `eco compare` |
| Broker y un nodo | `mosquitto.conf`, `qemu.sh` | Levantan mosquitto y un QEMU |
| Muchos nodos | `nodos.sh`, `escalar.sh`, `monitor.py` | Taps, puente `br-eco`, escalado y registro de RAM y CPU |
| Difusión | `difusion.sh`, `analizar_difusion.py` | Un nodo a todos, medido desde la captura |
| Todos-a-todos | `todos.sh`, `analizar_todos.py` | Los N nodos publicando cada h |
| Ruido | `ruido.sh`, `ruido_medir.sh` | `netem` por nodo en ambos sentidos, usando `ifb` |
| Gráficos | `graficar*.py` | Generan las figuras de `resultados/` |

**Detalles que se reutilizan en el experimento:**

- En modo tap, cada copia de la flash guarda su índice en `0x3FF000`. De ahí salen el ID `q<i>`, la
  MAC y la IP fija `10.10.0.0 + 10 + i`.
- Cada QEMU tiene su propio reloj, así que los tiempos se comparan con el de la PC, capturando el
  tráfico.
- `analizar_difusion.py` reconstruye los flujos TCP a mano, y sirve de base para el analizador.
- Con QoS 1, el flood limita a 20 los mensajes sin PUBACK. Sin esa ventana, el outbox de esp-mqtt
  agota el heap.

No se versionan las capturas `.pcap` (unos 180 MB), los builds, el binario `eco` ni
`sdkconfig.defaults.local`, que tiene la contraseña del WiFi.

## Resultados medidos

Corridas del 27/10/2026 en un Ryzen 5 5600G (6 núcleos, 12 hilos) con 13 GiB de RAM.

**Placa real contra QEMU** (MQTT, QoS 0 y 1):

| | Placa real por WiFi | QEMU |
|---|---|---|
| RTT p50 | 12–44 ms | 2–3 ms |
| Throughput máximo con QoS 0 | unos 0,7 Mbit/s | hasta 40 Mbit/s |

QEMU sirve para validar la lógica del firmware y del protocolo, pero sus tiempos no representan una
placa real.

**Escalado:** cada nodo ocupa unos 170 MB. El límite es la RAM, con unos 60 nodos, y a partir de ahí
el swap agrega ruido.

**Difusión de un emisor a todos:**

| Nodos | 2 | 20 | 40 | 60 |
|---|---|---|---|---|
| Delay p50 [ms] | 2,0 | 5,7 | 11,8 | 19,0 |

Crece unos 0,3 ms por nodo y casi todo es CPU de la PC, no red: es un artefacto de la emulación.

**Todos-a-todos con 40 nodos:**

| h | CPU | Entregas a tiempo | τ p50 |
|---|---|---|---|
| **1 s** | 47 % | 100 % | **15,9 ms**, estable |
| 500 ms | 83 % | 90 % | 58 → 377 ms, crece |
| 250 ms | 94 % | 30 % | unos 700 ms |
| 100 ms | 95 % | 12 % | no medible |

**Ruido con 39 nodos y h = 1 s** (uno no llegó a conectarse):

| Perfil | τ por par p50 / p95 / p99 [ms] | Pares > 150 ms |
|---|---|---|
| Sin ruido | 13 / 16 / 17 | 0 % |
| Jitter | 27 / 36 / 40 | 0 % |
| WiFi | 24 / 37 / 42 | 0 % |
| WiFi + 1 % de pérdida | 29 / 749 / 1372 | 7 % |
| WiFi + 5 % de pérdida | 30 / 1537 / 2106 | 20 % |

En TCP la pérdida aparece como retardo, y el bloqueo en cabeza de línea la amplifica, porque cada
nodo tiene una sola conexión con el broker.

## Decisiones

| Decisión | Motivo |
|---|---|
| N = 40 nodos | Entra en RAM sin depender del swap; 60 deja la PC al límite |
| Un oscilador y un LED por nodo | Varios por nodo mezclarían acoplamientos sin retardo y con retardo |
| h = 1 s | Es el único período medido que la PC sostiene con 40 nodos |
| τ de red ≈ 16 ms | Medido con todos publicando; los 12 ms eran con un solo emisor |
| Bajar la frecuencia de parpadeo | Con h = 1 s, la información vieja suma unos h/2 = 500 ms y a 1 Hz rompe el estado en fase |
| Tap + puente para varios nodos | Da a cada nodo una interfaz propia donde aplicar `netem` |
| `netem` con `slot` | `delay X Y` reordena paquetes y dispara retransmisiones |
| Dos configuraciones de frecuencias | Iguales para medir Ω con retardo (K_c = 0); equiespaciadas para medir K_c |
| Divisor N fijo y última fase recibida | Un mensaje ausente no cambia el peso de los demás |
| Fuentes del modelo | Strogatz 2000, Verwoerd y Mason 2008, Yeung y Strogatz 1999 |

## Ideas

**Salida del LED.** En la placa real se usaría el LED integrado (normalmente GPIO2, sin verificar en
esta placa). En QEMU no hay LEDs físicos: cada nodo publicaría su fase o un evento de parpadeo, y el
backend dibujaría una grilla de 40 LEDs. De esos mismos datos sale r(t).

**Separar h del paso de integración.** h es cada cuánto se publica la fase; el paso es cada cuánto el
nodo actualiza la suya.

**Prueba propuesta:**

1. Calibrar τ₀ con todos-a-todos y el h elegido.
2. Barrer K sin retardo agregado y comparar el K_c medido con el exacto para N finito.
3. Agregar retardo con `netem` (τ₀ + 0 a 250 ms) y medir K_c(τ) contra la predicción. Para frecuencias
   equiespaciadas y N = 40 no hay fórmula cerrada: la predicción sale de la simulación.

**Descartado o reemplazado:**

- Diseño del 24/10 (rama `monografia/contenido/igna`): hasta 4 LEDs por ESP32, 8 placas y hasta 32
  osciladores.
- 60 nodos: el swap vuelve irrepetibles las mediciones.
- 1 Hz con h = 1 s: ω̄·h/2 queda cerca de π.
- Bajar a unos 20 nodos para usar h ≈ 250 ms: es una extrapolación, no se midió.

## Trampas de método

- `netem delay X Y` reordena paquetes aun con `pfifo`: hubo unas 7000 retransmisiones sin pérdida
  configurada. La corrida quedó en `resultados/ruido-reordena/`.
- El disector MQTT de `tshark` se desalinea tras una retransmisión y parecía perderse hasta el 86 %
  de las entregas.
- Con `set -euo pipefail`, un `grep` sin coincidencias corta el script.
- Una corrida de QEMU hecha en paralelo con una compilación quedó contaminada y se descartó.
- El puerto 1883 estaba cerrado por el firewall: la placa real usó el listener 53317.

## Pendiente de definir

- **Valor exacto de la frecuencia y su dispersión.** Se acordó bajarla. La simulación favorece 0,1 Hz con
  ±20 % (ver la tabla de abajo); falta decidirlo.
- **Entrega propia.** Un nodo suscrito con comodín recibe su propia fase: son N² entregas por ronda, salvo
  que se active No Local de MQTT 5.
- **Reloj común para r(t).** Captura de tráfico en la PC, o SNTP como en el experimento 1.
- **Extrapolar la fase recibida.** Quedó como alternativa a bajar la frecuencia, y cambia el modelo.
- **`.proto` del experimento.** El de `contenido/igna` (`Flash`, `PhaseReport`, `RxEvent` y
  `ExperimentConfig`) sirve de punto de partida, pero está pensado para varios LEDs por placa.
- **Validar con TLS.** Todas las mediciones de todos-a-todos son sin TLS.
- **Texto de la plataforma común** en `secciones/experimentos.typ`: describe la red de usuario de
  QEMU y las mediciones con varios nodos usan tap, puente y `netem`.

## Simulación ideal

Integra la ecuación discreta del nodo sin red real, con período de publicación, desfase por nodo, retardo
y los percentiles medidos en la sección de ruido. Requiere Python 3 con `numpy` y `scipy`.

| Archivo | Qué hace |
|---|---|
| `simulacion/teoria.py` | K_c para N finito, r, desfasajes y frecuencia común con retardo |
| `simulacion/simulador.py` | Modelo de los nodos y modelo de entrega de los mensajes |
| `simulacion/verificar.py` | Compara teoría y simulador con los resultados conocidos |
| `simulacion/barrido.py` | Barre K y escribe un CSV (`simulacion/datos/`, no se versiona) |

```bash
cd simulacion
python3 verificar.py
python3 barrido.py --config distintas --n 40 --f 0.1 --ancho 0.2 --perfil sin-ruido --salida datos/d.csv
python3 barrido.py --config iguales --n 40 --f 0.1 --k 0.05 0.2 --perfil sin-ruido --salida datos/i.csv
```

`verificar.py` comprueba K_c con N = 2 y N = 40, r contra la autoconsistencia, el umbral de N = 2 con retardo y Ω
de osciladores idénticos con retardo. El retardo adicional de h/2 es una aproximación: con h = 100 ms y nodos
desfasados, Ω dio 6,0230 rad/s contra 6,0165 de la predicción.

### Puntos de operación con N = 40, h = 1 s y el retardo medido sin ruido

Corridas con 3 semillas por punto. Cantidad de corridas enganchadas, de 3:

| f̄ | Dispersión | 1,05·K_c | 1,2·K_c | 1,5·K_c | 2·K_c | Tiempo de sincronización a 1,5·K_c |
|---|---|---|---|---|---|---|
| 1 Hz | ±5 % | 0 | 0 | 0 | 0 | no sincroniza (r ≈ 0,12) |
| 0,25 Hz | ±20 % | 0 | 0 | 0 | 3 | no sincroniza |
| 0,1 Hz | ±5 % | 0 | 3 | 3 | 3 | 78–222 s |
| 0,1 Hz | ±20 % | 0 | 2 | 3 | 3 | 20–56 s |
| 0,1 Hz | ±40 % | 0 | 3 | 3 | 3 | 10–34 s |

Con osciladores iguales a 0,1 Hz, Ω coincide con la predicción usando τ + h/2. Con el perfil WiFi con 1 % de
pérdida, ±20 % y 1,5·K_c, las 3 corridas engancharon.

Limitaciones: pocas semillas, y cada copia sortea su retardo de forma independiente, por lo que no reproduce la
correlación del bloqueo en cabeza de línea de TCP. No emula el costo de CPU de los nodos.

### Frecuencias iguales y distintas, con y sin ruido

N = 40, h = 1 s, f̄ = 0,1 Hz, 3 semillas. Corridas enganchadas de 3, y Ω medida contra la predicción con τ + h/2 en el caso de iguales:

| Perfil | Distintas ±20 %: 1,2·K_c | 1,5·K_c | 2·K_c | Iguales, K = 0,2: Ω / predicción |
|---|---|---|---|---|
| Sin ruido | 2 | 3 | 3 | 0,572 / 0,572 |
| Jitter | 1 | 3 | 3 | 0,571 / 0,571 |
| WiFi | 2 | 3 | 3 | 0,571 / 0,571 |
| WiFi + 1 % de pérdida | 0 | 3 | 3 | 0,553 / 0,570 |
| WiFi + 5 % de pérdida | 0 | 2 | 3 | 0,541 / 0,570 |

### Extrapolar la fase recibida

Si el receptor adelanta cada fase con la velocidad publicada y su antigüedad, el efecto de h casi desaparece: a 1 Hz, ±5 % y h = 1 s engancharon las 3 semillas desde 1,05·K_c, con r igual a la teoría (sin extrapolar, ninguna). Requiere relojes sincronizados y reduce justamente el efecto de la red que el experimento quiere medir, así que se plantea como comparación aparte.

