// Diagramas (Typst Universe).
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import "@preview/chronos:0.3.0"

// Caja de un diagrama: título en negrita y una línea de detalle debajo.
#let caja(titulo, detalle) = align(center)[*#titulo* \ #text(size: 8pt, detalle)]

// Subtítulo sin numerar dentro de una parte de un experimento (evita un quinto nivel de numeración).
#let subtitulo(cuerpo) = block(above: 1.3em, below: 0.7em, sticky: true, text(weight: "bold", cuerpo))

// Figuras del Experimento 1, generadas por experimentos/comparacion-mqtt-http/analysis/figuras.py.
#let fig-exp1(archivo, ..args) = image("../experimentos/comparacion-mqtt-http/docs/resultados/figs/" + archivo, ..args)

// Figuras del Experimento 2, generadas por experimentos/sincronizacion/host/figuras.py.
#let fig-exp2(archivo, ..args) = image("../experimentos/sincronizacion/docs/resultados/figs/" + archivo, ..args)

== Diseño experimental

Las secciones anteriores analizaron el stack de forma cualitativa. Esta sección lo contrasta con mediciones propias, en dos experimentos que comparten la misma plataforma. En un escenario de telemetría, el experimento de la @sec-exp-mqtt-https compara MQTT con HTTP y mide el costo en bytes y en latencia de cada camino. El de la @sec-exp-sincronizacion, en cambio, usa solo MQTT con Protocol Buffers en una aplicación en la que cada nodo necesita el dato de todos los demás, y ensaya los mecanismos del stack ante pérdidas, cortes de conexión y caídas del broker. Cada experimento se presenta con la misma estructura, que recorre su planteo, su implementación, sus resultados y el análisis de esos resultados.

=== Plataforma común <sec-plataforma-comun>

Los dos experimentos corren sobre el mismo entorno, montado en una sola computadora (distinta en cada experimento), donde cada nodo es un ESP32 emulado con QEMU.

QEMU es un programa que permite ejecutar en una computadora el mismo código que correría en la placa, y se usa la versión que mantiene Espressif, el fabricante del ESP32, que emula su procesador, su memoria y varios periféricos @espressif-qemu. El programa de cada nodo, o _firmware_, está escrito en C con ESP-IDF, el entorno de desarrollo de Espressif @esp-idf. Como el ESP32 emulado no tiene Wi-Fi, QEMU le provee una placa Ethernet emulada. Cada instancia se conecta a una interfaz TAP propia, una interfaz de red virtual de Linux que intercambia las tramas Ethernet con un programa, en este caso QEMU, en lugar de enviarlas por un medio físico @linux-tuntap. Todas se unen en un puente de Linux, que funciona como un conmutador por _software_ @linux-bridge y las comunica con el broker Mosquitto, que corre en la misma computadora. Esta disposición permite aplicar a cada nodo condiciones de red propias con `netem` y capturar todo el tráfico en un único punto.

La emulación impone algunas restricciones. Los tiempos de ejecución no son los de una placa real, porque dependen de la carga de la computadora anfitriona. Cuando llega una difusión, todas las instancias compiten por la CPU, y el retardo de entrega crece alrededor de 0,3 ms por cada nodo agregado. Además, cada instancia ocupa unos 170 MB de memoria, lo que limita la cantidad de nodos que se pueden emular. El hardware real que reemplazaría a lo emulado, y su costo, se releva en la @sec-mapeo-tecnologico.

=== Experimento 1: MQTT contra HTTPS para telemetría <sec-exp-mqtt-https>

Este experimento es el caso base de la parte experimental. Mide cuánto cuesta, en bytes y en latencia, enviar una lectura de un sensor por MQTT y por HTTP, y separa ese costo en sus componentes, que son la conexión, el protocolo de aplicación, el cifrado y la serialización. Sus resultados sirven de referencia para el segundo experimento (@sec-exp-sincronizacion), que aplica el stack MQTT y Protocol Buffers a la sincronización de osciladores acoplados, una aplicación en la que todos los nodos intercambian mensajes entre sí.

==== Conceptos previos <sec-conceptos-exp1>

Además de lo presentado en el marco teórico, el análisis de este experimento se apoya en dos mecanismos de TCP y en el protocolo con el que se sincronizan los relojes de los nodos. Se resumen a continuación porque explican buena parte de los resultados.

*Algoritmo de Nagle.* Una aplicación entrega datos a TCP con llamadas a `send()` sobre un _socket_, y TCP decide cómo repartirlos en segmentos. Si cada llamada saliera de inmediato en su propio segmento, una aplicación que escribe de a pocos bytes llenaría la red de segmentos casi vacíos, en los que los 40 bytes de encabezados TCP/IP pesan más que los datos. El algoritmo de Nagle evita eso, porque, mientras haya datos enviados sin confirmar, TCP no envía un segmento más pequeño que el tamaño máximo, sino que acumula los datos nuevos hasta recibir el ACK pendiente @rfc9293. Si no hay nada sin confirmar, el segmento sale enseguida. Así, una escritura aislada no se demora, pero la segunda de dos escrituras seguidas espera el ACK de la primera. La especificación vigente de TCP recomienda implementar Nagle, pero exige que cada aplicación pueda desactivarlo en una conexión @rfc9293, opción que en la interfaz de _sockets_ se llama `TCP_NODELAY`.

*ACK retardado.* Del lado del receptor existe una optimización equivalente. En lugar de confirmar cada segmento apenas llega, el receptor puede esperar, hasta 500 ms según la especificación, para enviar el ACK junto con los datos de su respuesta y ahorrar un paquete @rfc1122. Si el temporizador vence antes de que haya una respuesta, el ACK sale solo. Cada mecanismo tiene sentido por separado, pero combinados pueden bloquearse entre sí. 

*Sincronización de relojes con SNTP.* Para medir la latencia extremo a extremo, el nodo y el servidor tienen que compartir la hora. SNTP (_Simple Network Time Protocol_), una versión reducida de NTP para dispositivos con pocos recursos, sincroniza el reloj de un cliente con el de un servidor. Para ello, el cliente envía una consulta, el servidor responde con su hora y, con las marcas de tiempo de ambos mensajes, el cliente estima el tiempo de viaje y lo descuenta @rfc5905.

==== Planteo

Ocho placas ESP32 emuladas envían telemetría periódica a un servidor por dos caminos, que son MQTT, a través de un broker, y HTTP, con un POST por lectura. El contenido de cada lectura es idéntico en ambos caminos y se serializa en JSON o en Protocol Buffers, lo que permite separar el efecto del transporte del de la serialización.

A diferencia del experimento de sincronización, el caso de uso es neutral, ya que enviar lecturas de los nodos a un servidor es algo que ambas arquitecturas resuelven de forma razonable, sin que el modelo publicador/suscriptor le dé de antemano una ventaja a MQTT.

#subtitulo[Motivación]

Este experimento corresponde al último de los objetivos específicos (@sec-objetivos), que consiste en medir el costo en bytes y en latencia de MQTT y Protocol Buffers frente a HTTPS y JSON, y su comportamiento ante pérdidas y latencia. También aporta datos al objetivo que analiza MQTT sobre la capa de transporte, en lo que respecta a TCP y TLS. En el marco teórico (@sec-alternativas) se planteó que MQTT envía mensajes más livianos y con menor latencia que HTTP, por su encabezado fijo de dos bytes y su conexión persistente, y que Protocol Buffers produce mensajes más pequeños que JSON, por su codificación binaria. Esas ventajas surgen de comparaciones cualitativas y de estudios con otros mensajes y plataformas. El experimento las mide sobre un mismo sistema. Para atribuir cada parte de la diferencia a su causa, incluye dos variantes de HTTP, corridas con y sin TLS y las dos serializaciones.

#subtitulo[Fundamento]

La diferencia principal entre ambos caminos no está en el contenido de la lectura, sino en cómo cada protocolo usa la conexión TCP. MQTT mantiene una conexión persistente por nodo, con un único handshake TLS y un encabezado binario de dos bytes, mientras que HTTP agrega a cada mensaje una línea de solicitud, encabezados en texto y una respuesta (@tab-comparacion-protocolos). Por eso se prueban dos variantes de HTTP, una con una conexión nueva por lectura y otra con una conexión reutilizada. La segunda es la comparación justa con MQTT; la primera representa el peor caso, el de un dispositivo que duerme entre envíos y abre una conexión cada vez.

#subtitulo[Preguntas de investigación]

+ ¿Cuántos bytes cuesta enviar una lectura por MQTT y por HTTPS, contando encabezados y handshakes?
+ ¿Cómo se comparan la latencia extremo a extremo y la tasa de entrega de ambos?
+ ¿Cómo se degradan ambos protocolos con pérdida y latencia en la red?
+ ¿Qué parte de la diferencia viene de la conexión persistente y qué parte de TLS?
+ ¿Cuánto cambia el costo al pasar de JSON a Protocol Buffers en cada transporte?

#subtitulo[Hipótesis]

Antes de las corridas se formularon las siguientes hipótesis, que se contrastan con los resultados al final del análisis (@tab-hipotesis):

- MQTT envía menos bytes por lectura que HTTPS, y la diferencia crece cuando el período de envío es corto.
- HTTPS con conexión reutilizada reduce gran parte de la diferencia, pero los encabezados HTTP siguen pesando más que el encabezado MQTT.
- HTTPS con una conexión por solicitud es el caso más costoso, sobre todo con TLS y latencia alta, porque cada handshake suma idas y vueltas.
- Con pérdida, MQTT QoS 1 mantiene la entrega a costa de duplicados, mientras que MQTT QoS 0 pierde lecturas.
- Protocol Buffers reduce la carga útil en ambos caminos, pero su efecto sobre el total es mayor en MQTT, donde la carga útil es la mayor parte del mensaje. En HTTPS, los encabezados diluyen el ahorro.

==== Implementación

#subtitulo[Arquitectura]

El experimento corre sobre la plataforma común (@sec-plataforma-comun), con 8 nodos. Cada uno ejecuta un firmware real, por lo que los bytes que se miden son los que producen, sin modificaciones, las bibliotecas que usaría una placa física, que son la pila TCP/IP lwIP @esp-idf-lwip, mbedTLS para TLS, esp-mqtt como cliente MQTT y `esp_http_client` como cliente HTTP.

Se usaron interfaces TAP y no la red de usuario de QEMU porque esta termina las conexiones TCP del nodo dentro del propio emulador, de modo que la red no vería los paquetes tal como los arma el ESP32. Sobre cada interfaz se aplica `tc netem` en ambos sentidos para inyectar pérdida y latencia, y `dumpcap` captura en el puente todo el tráfico de la corrida (@fig-arq-telemetria).

Del lado del servidor hay dos procesos, el broker Mosquitto y un backend escrito en Go. El backend recibe los POST por HTTP y por HTTPS y responde `204 No Content`. Además, está suscrito al broker por una conexión local que no pasa por el puente y, por lo tanto, no entra en la captura. Las lecturas de ambos caminos terminan en la misma función de registro, que anota la hora de llegada, de modo que la latencia se calcula igual para los dos. El backend también funciona como servidor SNTP, para que los nodos sincronicen su reloj con el de la computadora anfitriona.

#figure(
  diagram(
    spacing: (2.2cm, 0.6cm),
    node-stroke: 0.6pt,
    node-corner-radius: 4pt,
    node-inset: 8pt,
    node((0, 1), caja[ESP32 × 8 (QEMU)][Firmware ESP-IDF], name: <esp>),
    node((1, 1), caja[Puente de Linux][netem y dumpcap], name: <puente>),
    node((2, 0), caja[Broker Mosquitto][MQTT 1883, MQTTS 8883], name: <broker>),
    node((2, 2), caja[Backend (Go)][HTTP 80, HTTPS 443, SNTP], name: <backend>),
    edge(<esp>, <puente>, "-|>", text(size: 8pt)[TAP por nodo]),
    edge(<puente>, <broker>, "-|>", text(size: 8pt)[PUBLISH]),
    edge(<puente>, <backend>, "-|>", text(size: 8pt)[POST], label-side: right),
    edge(<broker>, <backend>, "--|>", text(size: 8pt)[suscripción local], label-side: left),
  ),
  caption: [Arquitectura del experimento. La captura se hace en el puente, por donde pasa todo el tráfico de los nodos; la suscripción del backend al broker queda fuera de ella.],
) <fig-arq-telemetria>

#subtitulo[Mensaje y caminos]

Todas las lecturas usan el mismo mensaje `Telemetry`, definido en un archivo `.proto` compartido por el firmware, que lo codifica con nanopb, y por el backend:

```proto
message Telemetry {
  uint32 esp_id = 1;
  uint32 seq    = 2;
  uint64 t_us   = 3;  // hora de creación en el nodo (µs)
  float  value  = 4;
  uint32 status = 5;
}
```

Codificado con Protocol Buffers, el mensaje ocupa entre 16 y 19 bytes (18 en promedio), porque `seq` es un entero de longitud variable. En JSON, con los mismos nombres de campo y sin espacios, ocupa unos 72 bytes, cuatro veces más.

La lectura se envía por uno de los cuatro caminos de la @tab-transportes. En HTTP, el formato se indica en el encabezado `Content-Type` (`application/x-protobuf` o `application/json`).

#figure(
  table(
    columns: (auto, 1fr),
    table.header[Transporte][Qué hace el nodo],
    [MQTT QoS 0], [PUBLISH a `exp/tel/{esp}` con QoS 0, sobre una conexión persistente abierta antes de empezar a medir],
    [MQTT QoS 1], [Igual, con QoS 1: el broker confirma cada mensaje con un PUBACK],
    [HTTP con conexión reutilizada], [POST a `/tel/{esp}` sobre una única conexión que se mantiene abierta (conexión persistente de HTTP/1.1)],
    [HTTP con una conexión por lectura], [Abre una conexión por cada lectura, envía el POST con `Connection: close` y la cierra],
  ),
  caption: [Transportes comparados.],
) <tab-transportes>


Los cuatro caminos se corrieron con y sin TLS. Con TLS se usó en el broker y en el backend la misma configuración, con TLS 1.2 @rfc5246 y cifrado AES-GCM, un certificado firmado por una autoridad de certificación propia, que el nodo verifica, y sin reanudación de sesión. El cliente MQTT de ESP-IDF admite las versiones 3.1.1 y 5.0 @esp-mqtt, y en este experimento se configuró la 3.1.1 @mqtt311. Para este experimento la diferencia es menor, porque el encabezado fijo es el mismo en ambas versiones y la 5.0 solo agrega a cada PUBLISH un byte con la longitud de sus propiedades.

#subtitulo[Firmware]

En cada nodo, una tarea productora crea una lectura por período con la hora sincronizada (`t_us`) y la encola, y otra tarea, la emisora, la saca de la cola, la serializa y la envía. Separar la creación del envío hace que el tiempo que una lectura espera en la cola, por ejemplo mientras el emisor está bloqueado en un handshake o en una retransmisión, quede incluido en la latencia medida.

Salvo el keep-alive de MQTT, que se fijó en 60 s, más que el período más largo (10 s), para que el cliente no necesite enviar PINGREQ, se dejaron los valores por defecto de las bibliotecas, que son los que tendría un ESP32 sin ajustes. En MQTT, un PUBLISH de QoS 1 se reenvía si su PUBACK no llega en 1 s. En HTTP, cada envío tiene hasta tres intentos con un tiempo de espera de 5 s, y el algoritmo de Nagle (@sec-conceptos-exp1) está activo. El cliente MQTT abre la conexión antes de que empiece la medición, mientras que el cliente HTTP la abre recién al enviar la primera lectura.

#subtitulo[Diseño de las corridas]

Se tomó una configuración base con 8 nodos, período de envío de 1 s, TLS activado, sin pérdida ni latencia agregadas y serialización con Protocol Buffers. A partir de ella se varió un factor a la vez (@tab-factores-telemetria) para cada uno de los cuatro transportes. Cada configuración se repitió cinco veces, con corridas de 120 s y en orden aleatorio con semilla fija. En total fueron 42 configuraciones y 210 corridas, que llevaron 7 h 40 min.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header[Factor][Valores (base en negrita)][Pregunta que responde],
    [Nodos], [2, 4, *8*], [¿Se satura el broker o el backend?],
    [Período de envío], [100 ms, *1 s*, 10 s], [¿Cuándo pesa el handshake?],
    [TLS], [*Con*, sin], [¿Qué parte del costo es cifrado?],
    [Pérdida], [*0 %*, 1 %, 5 %], [¿Cómo se degrada la entrega?],
    [RTT agregado], [*0 ms*, 50 ms, 200 ms], [¿Cómo afecta la latencia de la red a cada camino?],
    [Serialización], [*Protocol Buffers*, JSON], [¿Cuánto ahorra Protocol Buffers en cada camino?],
  ),
  caption: [Factores del experimento.],
) <tab-factores-telemetria>

La pérdida se aplica en cada sentido por separado, de forma aleatoria e independiente por paquete. La latencia se expresa como RTT agregado, del que la mitad se agrega en cada sentido, como un retardo fijo.

HTTP con una conexión por lectura se corrió con un período base de 10 s en lugar de 1 s. Con criptografía emulada, cada handshake TLS tarda entre 3 y 4 s, de modo que con un período de 1 s la cola del nodo crece sin límite y solo se entrega cerca del 27 % de las lecturas. Por eso, cuando se comparan los cuatro caminos en la base, ese camino aparece con 10 s, y se lo compara además con las corridas de 10 s de los otros tres.

Además, para verificar la explicación de la latencia de HTTP, se corrió una matriz complementaria con el algoritmo de Nagle activo y desactivado, que se presenta en el análisis del algoritmo de Nagle y el ACK retardado.

#subtitulo[Métricas]

Los bytes se miden en la red y no en la aplicación, para incluir todo lo que agregan TCP, TLS y cada protocolo. Los bytes por lectura son los de los paquetes IP del puerto del servidor en la captura, divididos por las lecturas entregadas, e incluyen encabezados, ACK, handshakes, cierres y retransmisiones. La latencia es la hora de llegada de cada lectura al servidor menos su hora de creación en el nodo, y se reporta con la mediana y los percentiles 95 y 99. La tasa de entrega es la cantidad de lecturas distintas recibidas sobre las producidas.

#subtitulo[Entorno y validez]

El experimento se corrió en una computadora con un AMD Ryzen 7 5700U y 14 GB de RAM, con QEMU de Espressif 9.2.2, ESP-IDF 5.5.6, nanopb 0.4.9.1, Mosquitto 2.1.2 y un backend en Go. Las 210 corridas resultaron válidas, ya que los nodos nunca corrieron más lento que el tiempo real, ninguno se atrasó al producir lecturas, no quedaron lecturas sin enviar y no hubo desconexiones de MQTT. Dos corridas en las que un nodo no logró sincronizar su reloj con 5 % de pérdida, antes de empezar a medir, se repitieron con más tiempo de espera para la sincronización.

El cliente SNTP de lwIP no descuenta el tiempo de viaje de la respuesta del servidor (@sec-conceptos-exp1), por lo que el reloj del nodo queda atrasado medio RTT y cada latencia medida resulta medio RTT más larga. Sin latencia agregada, ese error es de alrededor de 1 ms. Con latencia agregada, como netem la aplica como un retardo fijo, a cada latencia medida se le restó RTT/2.

==== Resultados

Se presentan la media y el desvío estándar de las cinco repeticiones de cada configuración. Salvo que se indique otra cosa, los valores corresponden a la configuración base con TLS. La entrega fue del 100 % en las 210 corridas.

#subtitulo[Bytes y paquetes por lectura]

La @tab-bytes muestra el costo de una lectura en cada camino. Todas las diferencias entre transportes resultaron significativas (prueba de Welch, _p_ < $10^(-4)$), y los intervalos de confianza del 95 % son estrechos, por ejemplo 165,2 ± 0,1 B en MQTT QoS 0, salvo en HTTP con una conexión por lectura (2596 ± 298B).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Transporte][Bytes sin TLS][Bytes con TLS][Paquetes (TLS)][Subida / bajada (TLS)],
    [MQTT QoS 0], [118,7], [165,2 ± 0,1], [2,25], [109 / 56 B],
    [MQTT QoS 1], [162,1 ± 0,2], [237,7 ± 0,2], [3,19], [150 / 88 B],
    [HTTP, conexión reutilizada], [457,7 ± 0,2], [555,0 ± 0,2], [6,08], [334 / 221 B],
    [HTTP, conexión por lectura], [741,8], [2596 ± 298], [22,5], [1005 / 1591 B],
  ),
  caption: [Bytes IP y paquetes por lectura entregada. HTTP con una conexión por lectura usa un período de 10 s; el resto, 1 s.],
) <tab-bytes>

Con TLS, una lectura por MQTT QoS 0 ocupó 3,4 veces menos bytes que por HTTP con conexión reutilizada y entre 14 y 16 veces menos que por HTTP con una conexión por lectura. HTTP con una conexión por lectura fue además la única configuración con un desvío grande entre repeticiones.

#subtitulo[Latencia en la configuración base]

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Transporte][p50 (ms)][p95 (ms)][p99 (ms)],
    [MQTT QoS 0], [2,9], [5,5], [11,9],
    [MQTT QoS 1], [3,0], [6,3], [9,1],
    [HTTP, conexión reutilizada], [44,8], [48,5], [2737],
    [HTTP, conexión por lectura (10 s)], [3383], [3924], [4129],
  ),
  caption: [Latencia extremo a extremo en la configuración base.],
) <tab-latencia-base>

La @tab-latencia-base muestra tres grupos separados por un orden de magnitud:

- MQTT tuvo una mediana de unos 3 ms con QoS 0 y con QoS 1, y la diferencia entre ambos no resultó significativa (_p_ = 0,06).
- HTTP con conexión reutilizada tuvo una mediana de 44,8 ms y una cola larga en el percentil 99. Esa cola se concentra en las primeras lecturas de cada nodo. La primera tardó 3,6 s en promedio, contra 21 ms en MQTT, y desde la décima lectura en adelante el p99 bajó a 48 ms.
- HTTP con una conexión por lectura tuvo una mediana de 3,4 s con TLS y de 10 ms sin TLS.

#subtitulo[Pérdida de paquetes]

Con 1 % y 5 % de pérdida la entrega siguió siendo del 100 % en todos los caminos. Lo que cambió fueron las retransmisiones, los duplicados y la cola de la latencia (@tab-perdida y @fig-cdf-perdida). Con 5 % de pérdida, el 37 % de las lecturas de HTTP con conexión reutilizada tardó más de 50 ms, contra el 16 % en MQTT QoS 0 y el 10 % en QoS 1. QoS 1 recibió duplicados en el 5,4 % de las lecturas. HTTP con conexión reutilizada tuvo además 1,6 errores por corrida (tiempo de espera de 5 s y reintento de la aplicación), que dejaron 1,4 duplicados.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto),
    table.header[Transporte][Pérdida][Retransm. por corrida][Duplicados por corrida][p95 (ms)][p99 (ms)][Δ bytes],
    table.cell(rowspan: 2)[MQTT QoS 0], [1 %], [12,8], [0], [6,7], [941], [+0,9 %],
    [5 %], [59,2], [0], [1304], [3040], [+4,1 %],
    table.cell(rowspan: 2)[MQTT QoS 1], [1 %], [25,4], [9,0], [6,9], [617], [+1,5 %],
    [5 %], [124,0], [52,0], [1017], [1749], [+7,1 %],
    table.cell(rowspan: 2)[HTTP, conexión reutilizada], [1 %], [30,8], [0], [1238], [3164], [+0,7 %],
    [5 %], [169,4], [1,4], [3810], [6638], [+4,3 %],
    table.cell(rowspan: 2)[HTTP, conexión por lectura], [1 %], [83,2], [0], [4491], [4784], [+9,7 %],
    [5 %], [126,2], [0], [6287], [8492], [+12,8 %],
  ),
  caption: [Efecto de la pérdida de paquetes. La entrega fue del 100 % en todos los casos. Δ bytes es el aumento de los bytes por lectura respecto de la base.],
) <tab-perdida>

#figure(
  fig-exp1("11_cdf_latencia_perdida5.png", width: 65%),
  caption: [Distribución acumulada de la latencia con 5 % de pérdida (escala logarítmica).],
) <fig-cdf-perdida>

#subtitulo[Latencia de la red]

La @tab-rtt muestra la mediana de la latencia, ya corregida por el sesgo del reloj, al agregar 50 y 200 ms de RTT. La última columna expresa el aumento con 200 ms en cantidad de RTT. El tiempo de conexión, desde el SYN hasta el fin del handshake, subió entre 340 y 570 ms con 200 ms de RTT. Los bytes por lectura de los caminos con conexión persistente no cambiaron. Los de HTTP con una conexión por lectura bajaron de 2596 a 2297 B.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto),
    table.header[Transporte][RTT 0][RTT 50 ms][RTT 200 ms][Δ con 200 ms][Δ en RTT],
    [MQTT QoS 0], [2,9 ms], [27,8 ms], [102,7 ms], [+99,8 ms], [*0,5*],
    [MQTT QoS 1], [3,0 ms], [27,9 ms], [102,9 ms], [+99,9 ms], [*0,5*],
    [HTTP, conexión reutilizada], [44,8 ms], [119,5 ms], [344,6 ms], [+299,8 ms], [*1,5*],
    [HTTP, conexión por lectura], [3383 ms], [3728 ms], [4434 ms], [+1051 ms], [*5,3*],
  ),
  caption: [Mediana de la latencia, corregida en −RTT/2, según el RTT agregado (TLS).],
) <tab-rtt>

#subtitulo[Efecto de TLS]

En las conexiones persistentes, TLS sumó entre 46 y 97 B por lectura (entre un 21 % y un 47 %) y menos de 0,6 ms de latencia. El handshake de cada conexión pasó de los 128 B del de TCP a 1525 B en HTTP y 1966 B en MQTT. En HTTP con una conexión por lectura, que paga ese handshake en cada lectura, TLS multiplicó por 3,1 los bytes, tomando el valor de 2296 B sin retransmisiones innecesarias que se explica en el análisis, y sumó 3,4 s de latencia.

#subtitulo[Serialización]

JSON resultó cuatro veces más grande que Protocol Buffers para este mensaje (72 B contra 18 B) y agregó unos 54 B por lectura en todos los caminos, que equivalen a un 33 % más en MQTT QoS 0, un 23 % en QoS 1, un 9 % en HTTP con conexión reutilizada y un 3 % con una conexión por lectura. La latencia no cambió.

#subtitulo[Cantidad de nodos y período de envío]

Con 2, 4 y 8 nodos, los bytes, los paquetes y la latencia por lectura no cambiaron (por ejemplo, 165,1, 165,2 y 165,2 B en MQTT QoS 0). Lo único que creció fue la duración de los handshakes, que pasó de 3,01 a 3,32 s en HTTP con una conexión por lectura y de 3,14 a 3,76 s en MQTT QoS 0.

Al acortar el período, los bytes por lectura de los caminos con conexión persistente bajaron. En MQTT QoS 0 fueron 392, 165 y 143 B con períodos de 10 s, 1 s y 100 ms; en HTTP con conexión reutilizada, 673, 555 y 515 B. Con el mismo período de 10 s que HTTP con una conexión por lectura, MQTT QoS 0 usó 392 B, MQTT QoS 1 450 B y HTTP con conexión reutilizada 673 B, contra 2596 B. La latencia de MQTT no cambió con el período. En HTTP con conexión reutilizada y período de 100 ms, la mediana se mantuvo en 44,5 ms, pero el p95 subió a 705 ms.

==== Análisis de resultados

#subtitulo[Anatomía de una lectura]

Las capturas permiten ver de qué está hecha cada lectura, paquete por paquete. La @tab-anatomia muestra el régimen estable con TLS de los tres caminos con conexión persistente.

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    table.header[Sentido][Paquete][Bytes IP][Composición],
    table.cell(colspan: 4, fill: luma(240))[*MQTT QoS 0: 2 paquetes, 140 B por lectura*],
    [Nodo → servidor], [PUBLISH], [100], [31 B de MQTT, 29 B de TLS y 40 B de TCP/IP],
    [Servidor → nodo], [ACK], [40], [Solo encabezados TCP/IP],
    table.cell(colspan: 4, fill: luma(240))[*MQTT QoS 1: 3 paquetes, unos 215 B por lectura*],
    [Nodo → servidor], [PUBLISH], [102], [33 B de MQTT (2 B más por el identificador de paquete)],
    [Servidor → nodo], [PUBACK], [73], [4 B de MQTT, 29 B de TLS y 40 B de TCP/IP; incluye el ACK de TCP],
    [Nodo → servidor], [ACK], [40], [Sale solo, unos 83 ms después (ACK retardado de lwIP)],
    table.cell(colspan: 4, fill: luma(240))[*HTTP con conexión reutilizada: 6 paquetes, unos 543 B por lectura*],
    [Nodo → servidor], [POST y encabezados], [203], [134 B de HTTP],
    [Servidor → nodo], [ACK], [40], [Llega 40 ms después (ACK retardado de Linux)],
    [Nodo → servidor], [Cuerpo], [87], [18 B de Protocol Buffers, retenidos por Nagle hasta el ACK anterior],
    [Servidor → nodo], [ACK], [40], [Solo encabezados TCP/IP],
    [Servidor → nodo], [`204 No Content`], [133], [64 B de HTTP],
    [Nodo → servidor], [ACK], [40], [Sale solo, unos 230 ms después (ACK retardado de lwIP)],
  ),
  caption: [Paquetes de una lectura en régimen estable, con TLS.],
) <tab-anatomia>

HTTP con una conexión por lectura abre y cierra una conexión completa en cada lectura, con unos 22 paquetes, que corresponden al handshake TCP (3 paquetes, 128 B), al handshake TLS 1.2 (unos 1525 B, de los cuales 655 B son el certificado y los demás mensajes del servidor), al POST con su cuerpo, a la respuesta, al cierre de TLS y al cierre de TCP. Sin TLS son 12 paquetes y 742 B.

El encabezado de MQTT es tan pequeño como plantea el marco teórico. El PUBLISH ocupa 31 bytes, de los cuales 2 son del encabezado fijo, 2 de la longitud del tópico, 9 del tópico `exp/tel/3` y 18 de la lectura. La sobrecarga de MQTT por mensaje es entonces de 13 bytes, contra 134 bytes de la línea de solicitud y los encabezados de HTTP (153 con una conexión por lectura, que agrega `Connection: close`), unas diez veces menos. Además, MQTT QoS 0 no tiene respuesta de aplicación, mientras que HTTP siempre responde (64 B).

Sin embargo, en una lectura de MQTT los encabezados de capa de aplicación no son lo que más pesa. Cada registro TLS agrega 29 bytes (5 de encabezado, 8 del _nonce_ explícito y 16 de la etiqueta de autenticación de AES-GCM) y cada paquete, 40 bytes de TCP/IP. En MQTT QoS 0 con TLS, la carga útil es solo el 11 % de los bytes de la lectura, y en HTTP con una conexión por lectura, menos del 1 %.

Los 29 bytes por registro explican casi todo lo que agrega TLS en las conexiones persistentes. MQTT QoS 0 usa un registro por lectura (29 B), al que se suman 16 B del handshake repartido entre las lecturas, 45 B en total, y se midieron 46,5 B. MQTT QoS 1 usa dos registros, el PUBLISH y el PUBACK (74 B con el handshake; se midieron 75,6 B), y HTTP con conexión reutilizada usa tres, los encabezados, el cuerpo y la respuesta (100 B; se midieron 97 B). El cifrado simétrico casi no suma latencia, ya que el costo de TLS en tiempo es el handshake, que solo se paga en cada lectura cuando no se reutiliza la conexión.

#subtitulo[Costo fijo por conexión y costo por lectura]

En los caminos con conexión persistente, lo que cambia con el período es cuántas lecturas viajan por la misma conexión. Si $n$ es la cantidad de lecturas por conexión, los bytes por lectura se ajustan a un modelo de dos términos:

$ b(n) = v + C / n $ <ec-costo>

donde $v$ es el costo de cada lectura y $C$ el costo fijo de abrir y cerrar la conexión, que se reparte entre las $n$ lecturas. El ajuste sobre las corridas con distintos períodos, con TLS, dio un $R^2$ entre 0,97 y 1,00 (@tab-costo).

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Transporte][$v$ (B por lectura)][$C$ (B por conexión)][$R^2$],
    [MQTT QoS 0], [*140*], [3020], [1,000],
    [MQTT QoS 1], [202], [2983], [0,994],
    [HTTP, conexión reutilizada], [526], [*1772*], [0,973],
  ),
  caption: [Ajuste del modelo de la @ec-costo con TLS.],
) <tab-costo>

El valor de $v$ coincide con la anatomía de una lectura, ya que los 140 B de MQTT QoS 0 son exactamente el PUBLISH (100 B) y su ACK (40 B). El valor de $C$ corresponde al handshake TCP y TLS, más el inicio y el cierre de la sesión. El $C$ de MQTT es unos 1250 B mayor que el de HTTP por dos razones. Por un lado, Mosquitto envía, junto con el certificado del servidor, el de la autoridad de certificación (856 B de certificados contra 445 B del backend en Go). Por otro, MQTT agrega el intercambio de CONNECT y CONNACK al abrir la sesión.

En consecuencia, MQTT tiene el costo por lectura más bajo pero el costo fijo más alto, y su ventaja depende de cuánto dure la conexión. Igualando los modelos, MQTT QoS 0 envía menos bytes que HTTP con conexión reutilizada mientras la conexión lleve más de tres o cuatro lecturas. Con una sola lectura por conexión, el modelo da unos 3160 B para MQTT, más que los 2296 B de un POST por HTTPS, aunque eso es una extrapolación fuera del rango medido (entre 12 y 1200 lecturas por conexión). Para un nodo que duerme y se reconecta en cada envío, la ventaja de MQTT desaparece, salvo que se use reanudación de sesión TLS, que en este experimento estuvo desactivada en ambos caminos.

#subtitulo[Descomposición de la diferencia]

Para separar las causas, la @tab-descomposicion pasa de HTTP con una conexión por lectura a MQTT QoS 0 cambiando una cosa por vez.

#figure(
  table(
    columns: (1fr, auto, auto),
    table.header[Paso][Con TLS (B por lectura)][Sin TLS (B por lectura)],
    [HTTP con una conexión por lectura], [2296], [742],
    [→ HTTP con conexión reutilizada (*conexión persistente*)], [555 (−1741, *82 %*)], [458 (−284, *46 %*)],
    [→ MQTT QoS 1 (*protocolo de aplicación*)], [238 (−317, 15 %)], [162 (−296, 47 %)],
    [→ MQTT QoS 0 (*sin confirmación de aplicación*)], [165 (−73, 3 %)], [119 (−43, 7 %)],
  ),
  caption: [Descomposición de la diferencia entre HTTP con una conexión por lectura y MQTT QoS 0. Los porcentajes son la parte de la diferencia total que explica cada paso.],
) <tab-descomposicion>

Con TLS, la conexión persistente explica cuatro quintos de la diferencia, porque evita un handshake de 1525 B en cada lectura. El protocolo de aplicación (encabezados, respuesta obligatoria y ACK adicionales) explica el 18 % restante. Sin TLS, el handshake TCP pesa mucho menos y la diferencia se reparte casi por mitades entre la conexión y el protocolo. Es decir, el factor más pesado no es el protocolo de aplicación en sí, sino la decisión de mantener la conexión abierta. A eso se suma una parte que no es del protocolo ni de la conexión, sino de cómo el cliente HTTP usa TCP, que se analiza a continuación.

#subtitulo[Nagle y ACK retardado]

Los dos mecanismos de TCP presentados en la @sec-conceptos-exp1, el algoritmo de Nagle y el ACK retardado, explican buena parte de la latencia de HTTP y varios efectos secundarios observados en el experimento.

*Bloqueo en HTTP con conexión reutilizada.* `esp_http_client` escribe cada solicitud con dos llamadas a `send()`, primero la línea de solicitud con los encabezados y después el cuerpo, y cada llamada sale como un segmento TCP distinto. La @fig-nagle muestra la secuencia medida en una lectura:

+ Los encabezados salen y quedan sin confirmar, por lo que Nagle retiene el cuerpo (18 B) en el ESP32 hasta recibir su ACK.
+ El servidor Linux detecta una conexión de ida y vuelta, en la que contesta cada solicitud, y demora el ACK hasta 40 ms para enviarlo junto con la respuesta. Pero no puede responder, porque todavía no recibió el cuerpo.
+ Cada lado espera al otro, y el bloqueo se rompe recién cuando vence el temporizador de 40 ms del servidor. Entonces llega el ACK, Nagle libera el cuerpo y el servidor responde.

#figure(
  chronos.diagram({
    import chronos: *
    _par("E", display-name: "ESP32 (lwIP)", show-bottom: false)
    _par("S", display-name: "Servidor (Linux)", show-bottom: false)
    _seq("E", "S", comment: [0 ms: POST y encabezados (134 B)])
    _delay(name: [Nagle retiene el cuerpo; el servidor demora el ACK])
    _seq("S", "E", comment: [40,3 ms: ACK], dashed: true)
    _seq("E", "S", comment: [41,1 ms: cuerpo (18 B)])
    _seq("S", "E", comment: [41,2 ms: `HTTP/1.1 204 No Content`])
    _delay(name: [El ESP32 demora su ACK])
    _seq("E", "S", comment: [269 ms: ACK], dashed: true)
  }),
  kind: image,
  caption: [Una lectura de HTTP con conexión reutilizada, sin TLS, tomada de una captura. Las flechas punteadas son ACK sin datos.],
) <fig-nagle>

La espera medida entre los encabezados y el cuerpo fue de 41,5 ms sin TLS y de 41,7 ms con TLS. Con TLS ocurre lo mismo porque mbedTLS cifra cada `send()` en su propio registro, de modo que también salen dos segmentos. Esa espera explica casi toda la mediana de 44,8 ms de HTTP con conexión reutilizada (@tab-latencia-base).

*Prueba con Nagle desactivado.* Para verificar la explicación se corrió una matriz complementaria con Nagle activo y desactivado (`TCP_NODELAY`) en los dos caminos HTTP, con tres repeticiones. En HTTP con conexión reutilizada, la latencia bajó unas diez veces, de 44 ms a entre 4 y 5 ms, con y sin TLS, y cada lectura usó un paquete y unos 40 B menos, porque sin la espera el ACK del servidor a los encabezados viaja junto con la respuesta. HTTP con una conexión por lectura sin TLS no cambió, porque Linux confirma de inmediato los primeros segmentos de una conexión nueva y no sufría la espera.

*Efecto de la latencia de la red sobre la penalidad de Nagle.* MQTT pagó medio RTT por lectura (@tab-rtt), el mínimo posible, porque el PUBLISH sale y llega sin esperar nada. En HTTP, en cambio, el ACK de los encabezados tarda un RTT completo en volver, y el cuerpo espera ese tiempo además de los 40 ms del ACK retardado. Por eso HTTP con conexión reutilizada pagó 1,5 RTT por lectura, que corresponden a medio RTT del viaje de ida y a un RTT de la espera de Nagle. HTTP con una conexión por lectura con TLS pagó 5,3 RTT, porque a eso suma los handshakes de TCP y de TLS 1.2 y otra espera de Nagle dentro de este último, porque el ESP32 escribe en dos llamadas separadas el _Client Key Exchange_ y el _Change Cipher Spec_ con el _Finished_.

*Retransmisiones innecesarias.* La variabilidad de HTTP con una conexión por lectura (2596 ± 298 B por lectura) no viene de la red. El ESP32 pasa unos 3 s calculando su parte del handshake TLS con criptografía emulada, y si el tiempo de retransmisión del servidor vence antes de que llegue su ACK, el servidor reenvía los 692 B de sus mensajes de handshake, que no se habían perdido. Los bytes de cada corrida siguen exactamente la cantidad de esas retransmisiones (correlación de 1,000), que ocurrieron en casi todas las conexiones de una corrida o en ninguna. Por eso, en el análisis se toma como referencia de ese camino el valor de 2296 B, sin retransmisiones innecesarias.

*Ausencia del bloqueo en MQTT.* esp-mqtt arma cada PUBLISH completo en un _buffer_ y lo escribe con un solo `send()`, por lo que cada lectura es un único segmento y Nagle no tiene nada que retener. Además, con QoS 0 el broker nunca responde, no detecta una conexión de ida y vuelta y confirma enseguida; con QoS 1, el ACK viaja dentro del PUBACK.

En síntesis, parte de la diferencia entre HTTP y MQTT no se debe al protocolo de aplicación, sino a cómo cada cliente usa TCP. El mismo HTTP cambia su latencia en un orden de magnitud según cómo el cliente reparte los datos en llamadas a `send()`. Con Nagle desactivado, HTTP con conexión reutilizada baja a 5 ms, del mismo orden que MQTT, aunque sigue enviando 3,1 veces más bytes, unos 515 B (40 B menos que con Nagle activo) contra 165 B. En el experimento principal se mantuvo el comportamiento por defecto, con Nagle activo, porque es el que tendría un ESP32 sin ajustes.

#subtitulo[Pérdida de paquetes]

Con hasta 5 % de pérdida no se perdió ninguna lectura, porque TCP retransmitió cada segmento perdido y ninguna conexión se cortó. MQTT QoS 0 solo perdería lecturas si se cortara la conexión, por ejemplo al vencer el keep-alive, por un _reset_ o porque el nodo se reconecta a la red, y eso no ocurrió con pérdidas aleatorias en corridas de 120 s. En estas condiciones, QoS 1 no mejoró la entrega y solo agregó duplicados (@tab-perdida), porque esp-mqtt reenvía el PUBLISH si el PUBACK no llega en 1 s, aunque TCP todavía esté recuperando el segmento original, tal como se anticipó en la @sec-qos-tcp.

Lo que se degradó fue la cola de la latencia, y la @fig-cdf-perdida muestra escalones en valores fijos:

- Entre 1 y 1,5 s, el RTO de lwIP, dado que un segmento perdido se recupera recién cuando vence el temporizador de retransmisión, que lwIP maneja con un reloj de 500 ms. No hay retransmisión rápida, porque requiere tres ACK duplicados y con una lectura por segundo nunca hay tantos segmentos en vuelo.
- Entre 0,05 y 0,5 s, el bloqueo de cabeza de línea, por el que la lectura que sigue a una perdida sale 1 s después y queda retenida hasta que la anterior se recupera. Por eso las lecturas lentas vienen en pares.
- Por encima de 2 s, pérdidas repetidas del mismo segmento, con el RTO duplicado en cada intento @rfc6298.

HTTP salió peor por su esquema de solicitud y respuesta en serie. Cualquier paquete perdido, en cualquier sentido, frena el envío hasta que se recupera, y las lecturas siguientes esperan en la cola. Además, cada lectura usa 6 paquetes (22 con una conexión por lectura), contra 2 o 3 de MQTT, por lo que tiene más probabilidad de perder alguno. Entre los dos niveles de MQTT, QoS 1 tuvo una cola algo menor (p99 de 1,7 s contra 3,0 s), porque su ACK viaja dentro del PUBACK, que Linux retransmite a los 200 ms si se pierde, ya que su temporizador de retransmisión no baja de ese valor, aunque la especificación recomienda un mínimo de 1 s @rfc6298. Con QoS 0, en cambio, un ACK perdido deja a Nagle reteniendo la lectura siguiente hasta que vence el tiempo de retransmisión de lwIP, de al menos 1 s.

El costo en bytes de la pérdida fue bajo, entre 1 % y 13 %. El mayor fue el de HTTP con una conexión por lectura, al que se suman las retransmisiones innecesarias del handshake.

#subtitulo[Serialización]

El ahorro de Protocol Buffers fue de unos 54 B por lectura en todos los caminos, porque el mensaje es el mismo. En HTTP fue 6 B menor, porque `application/json` es más corto que `application/x-protobuf` en el encabezado `Content-Type`. La reducción de la carga útil, del 75 %, está en línea con la de los estudios citados en el marco teórico @viotti2022 @friesel2021.

En términos relativos, en cambio, el efecto depende de cuánto pesa el resto de la lectura, que en MQTT es mucho menos que en HTTP. Esto confirma lo anticipado en el marco teórico, es decir, que una vez que el transporte reduce sus encabezados al mínimo, la serialización pasa a tener un peso importante. Aun así, la elección del transporte pesa más, ya que pasar de HTTP con conexión reutilizada a MQTT QoS 0 ahorra 390 B por lectura, más de siete veces lo que ahorra Protocol Buffers.

#subtitulo[Contraste de hipótesis]

La @tab-hipotesis contrasta las hipótesis del planteo con los resultados.

#figure(
  table(
    columns: (1fr, 1.6fr),
    table.header[Hipótesis][Resultado],
    [MQTT envía menos bytes por lectura que HTTPS, y la diferencia crece cuando el período de envío es corto.],
    [*Se confirma, con un matiz.* MQTT envió menos bytes en todos los casos medidos, y su ventaja frente a HTTP con conexión reutilizada creció al acortar el período, de 1,7 a 3,6 veces. Si la conexión dura menos de tres o cuatro lecturas, la relación se invierte (@tab-costo).],

    [HTTPS con conexión reutilizada reduce gran parte de la diferencia, pero los encabezados HTTP siguen pesando más que el encabezado MQTT.],
    [*Se confirma.* Reutilizar la conexión bajó HTTPS de 2296 a 555 B por lectura, pero siguió costando 3,4 veces MQTT QoS 0.],

    [HTTPS con una conexión por solicitud es el caso más costoso, sobre todo con TLS y latencia alta.],
    [*Se confirma.* Fue el más caro en bytes y en latencia, y con 200 ms de RTT pagó 5,3 RTT por lectura.],

    [Con pérdida, MQTT QoS 1 mantiene la entrega a costa de duplicados, mientras que QoS 0 pierde lecturas.],
    [*Se confirma a medias.* QoS 1 generó duplicados, pero QoS 0 no perdió lecturas, porque TCP recuperó todo y ninguna conexión se cortó.],

    [Protocol Buffers reduce la carga útil en ambos caminos, con efecto relativo mayor en MQTT, donde la carga útil es la mayor parte del mensaje.],
    [*Se confirma, aunque no por la razón prevista.* El ahorro fue de unos 54 B en todos los caminos y el relativo fue mayor en MQTT (33 %), pero porque su lectura es más pequeña, ya que la carga útil es solo el 11 % del mensaje.],
  ),
  caption: [Contraste de las hipótesis con los resultados.],
) <tab-hipotesis>

#subtitulo[Limitaciones]

- *Criptografía emulada.* Los handshakes TLS tardaron entre 3 y 4 s en QEMU, mucho más que en un ESP32 físico, por lo que los tiempos de conexión y la latencia de HTTP con una conexión por lectura deben leerse en términos relativos. Los bytes y los paquetes, en cambio, son los del firmware real.
- *Un factor a la vez.* No se midieron interacciones entre factores, como pérdida y período o latencia y JSON, salvo la de Nagle y TLS.
- *Red emulada.* Se usó Ethernet emulado y pérdida aleatoria independiente, sin ráfagas. Con pérdidas en ráfaga o cortes de conexión, que no formaron parte de la matriz, las sesiones podrían caerse, y entonces QoS 0 sí perdería lecturas. Las corridas de 120 s tampoco permiten observar el keep-alive ni las reconexiones.
- *Un solo sentido.* Solo se midió la telemetría del nodo al servidor. El envío de comandos del servidor al nodo, donde HTTP necesitaría consultas periódicas, quedó fuera de la comparación.

#subtitulo[Implicaciones]

La @tab-proyeccion lleva los resultados a la escala de un despliegue. Supone una conexión que no se corta, por lo que usa el costo por lectura $v$ de la @tab-costo, y una lectura cada 10 s por nodo (8640 por día). El keep-alive no suma tráfico, porque el período es menor que los 60 s configurados. Estos volúmenes son los que determinan el plan de datos necesario en un despliegue sobre una red celular, y sirven de dato de entrada para el mapeo tecnológico.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Transporte (TLS)][Por nodo y por día][1000 nodos, por mes],
    [MQTT QoS 0], [1,2 MB], [36 GB],
    [MQTT QoS 1], [1,7 MB], [52 GB],
    [HTTP, conexión reutilizada], [4,5 MB], [136 GB],
    [HTTP, conexión por lectura], [19,8 MB], [595 GB],
  ),
  caption: [Proyección del tráfico con una lectura cada 10 s.],
) <tab-proyeccion>

Para un sistema de telemetría como el estudiado, los resultados sugieren dos criterios:

- Lo que más importa es mantener la conexión abierta. La ventaja de MQTT depende de que la conexión dure más que unas pocas lecturas; para dispositivos que duermen y se reconectan en cada envío, pesan más la reanudación de sesión TLS o TLS 1.3 que la elección del protocolo de aplicación.
- Si se usa HTTP, conviene reutilizar la conexión y desactivar Nagle, o escribir cada solicitud con una sola llamada a `send()`. Con eso la latencia queda en el mismo orden que la de MQTT, aunque el costo en bytes sigue siendo unas tres veces mayor.

=== Experimento 2: sincronización de osciladores acoplados <sec-exp-sincronizacion>

La sincronización colectiva aparece cuando un conjunto de osciladores, cada uno con su propio ritmo, termina funcionando a una frecuencia común sin que nadie la imponga, como ocurre con las luciérnagas que destellan al unísono @strogatz2000. En este experimento, cada ESP32 ejecuta un oscilador con una frecuencia natural distinta a la de los demás y corrige su fase con las fases que recibe de los otros nodos a través del broker. Cuando esa corrección es suficientemente intensa, el grupo se engancha y todos pasan a girar a una misma frecuencia, sin ningún nodo que actúe de coordinador.

Esa sincronía existe solo a través de los mensajes que intercambian los nodos, y por eso sirve para evaluar el stack. El modelo matemático predice cómo debería comportarse el grupo si la comunicación fuera ideal, de modo que comparar esa predicción con lo que se mide en los nodos muestra qué efecto tiene cada mecanismo del stack sobre la aplicación. A diferencia del experimento de la @sec-exp-mqtt-https, que mide el costo de enviar lecturas desde muchos nodos hacia un único servidor, aquí cada nodo produce un dato que les interesa a todos los demás y consume los de todos ellos, que es la forma de circulación de la información para la que se propone el modelo publicador/suscriptor (@sec-pubsub).

==== Planteo

#subtitulo[Motivación]

Este experimento corresponde al último de los objetivos específicos (@sec-objetivos), en lo que respecta al comportamiento del stack ante pérdidas y cortes de conexión. Somete a prueba, en una misma aplicación, el desacoplamiento entre participantes, la compacidad del mensaje, la compatibilidad del esquema, el broker como punto único de falla y el papel del keep-alive y de la última voluntad, que son varias de las virtudes y limitaciones que el marco teórico y el desarrollo atribuyen al stack de forma cualitativa.

#subtitulo[Fundamento]

*El modelo.* El experimento se basa en el modelo de osciladores acoplados que propuso Kuramoto @kuramoto1975. Se consideran $N$ osciladores, cada uno descrito solo por su fase y acoplado a todos los demás con el mismo peso. El oscilador $i$ tiene una frecuencia natural $omega_i$, en rad/s, que es fija, y una fase $theta_i$, en radianes, que evoluciona según

$ dot(theta)_i = omega_i + K/N sum_(j=1)^N sin(theta_j - theta_i), quad i = 1, dots, N $ <ec-kuramoto>

donde el punto indica la derivada respecto del tiempo. El acoplamiento es la influencia que los osciladores ejercen entre sí, representada por el término de la sumatoria, que depende de las diferencias de fase. Su intensidad es $K$, en rad/s. Con $K = 0$, cada oscilador avanza a su frecuencia natural sin afectar a los demás. El acoplamiento cambia la velocidad instantánea $dot(theta)_i$. Si el oscilador $j$ va adelantado menos de media vuelta, $sin(theta_j - theta_i) > 0$ y el oscilador $i$ se acelera; si va atrasado menos de media vuelta, se frena.

*Parámetro de orden.* El grado de sincronía se mide con el centroide de las fases sobre el círculo unitario:

$ r e^(upright(i) psi) = 1/N sum_(j=1)^N e^(upright(i) theta_j) $ <ec-orden>

donde $upright(i)$ es la unidad imaginaria. El módulo $r$, entre 0 y 1, se denomina parámetro de orden y vale 0 si las fases están dispersas y 1 si coinciden. El ángulo $psi$ es la fase media del grupo @strogatz2000. La @fig-orden muestra ambas situaciones.

// Dibuja N fases (en grados) sobre el círculo unitario con su centroide, calculado a partir de esas mismas fases.
#import "@preview/cetz:0.4.2"
#let circulo-orden(fases, detalle: false) = cetz.canvas(length: 1.5cm, {
  import cetz.draw: *
  let n = fases.len()
  let cx = fases.map(t => calc.cos(t * 1deg)).sum() / n
  let cy = fases.map(t => calc.sin(t * 1deg)).sum() / n
  let r = calc.sqrt(cx * cx + cy * cy)
  let media = calc.atan2(cx, cy)
  let eje = 0.4pt + gray
  line((-1.25, 0), (1.25, 0), stroke: eje)
  line((0, -1.25), (0, 1.25), stroke: eje)
  circle((0, 0), radius: 1, stroke: 0.7pt)
  for t in fases {
    circle((calc.cos(t * 1deg), calc.sin(t * 1deg)), radius: 0.06, fill: white, stroke: 0.7pt)
  }
  line((0, 0), (cx, cy), stroke: 1pt, mark: (end: ">", fill: black, scale: 0.6))
  circle((cx, cy), radius: 0.04, fill: black, stroke: none)
  if detalle {
    arc((0, 0), start: 0deg, stop: media, radius: 0.3, anchor: "origin", stroke: 0.6pt)
    content((0.47 * calc.cos(media / 2), 0.47 * calc.sin(media / 2)), $psi$)
    content((cx / 2 - 0.14 * calc.sin(media), cy / 2 + 0.14 * calc.cos(media)), $r$)
    let t = fases.last()
    content((1.26 * calc.cos(t * 1deg), 1.26 * calc.sin(t * 1deg)), $theta_j$)
  }
  content((0, -1.5), [$r approx$ #str(calc.round(r, digits: 2)).replace(".", ",")])
})

#figure(
  grid(
    columns: 2,
    column-gutter: 2.5em,
    circulo-orden((12, 68, 128, 172, 233, 262, 308, 349)),
    circulo-orden((22, 34, 47, 60, 71, 84, 97, 116), detalle: true),
  ),
  caption: [Fases de ocho osciladores sobre el círculo unitario (círculos vacíos) y su centroide $r e^(upright(i) psi)$ (punto negro). A la izquierda, fases dispersas; a la derecha, fases agrupadas.],
) <fig-orden>

*Frecuencia común y acoplamiento crítico.* Se dice que el grupo está enganchado cuando todos los osciladores giran a una misma frecuencia, que se denota $Omega$, y sus diferencias de fase permanecen constantes. Sin retardo, esa frecuencia es la media de las frecuencias naturales, $Omega = overline(omega)$, porque el acoplamiento redistribuye las velocidades entre los osciladores sin cambiar su suma @verwoerd2008. Las desintonías $Delta_i = omega_i - overline(omega)$ indican cuánto se aparta cada frecuencia natural de la media.

Se denomina acoplamiento crítico $K_c$ al menor valor de $K$ para el que existe un estado enganchado. Para una cantidad finita de osciladores, ese estado existe si y solo si tiene solución la condición de autoconsistencia @verwoerd2008

$ r = u/K = f(u) = 1/N sum_(i=1)^N sqrt(1 - (Delta_i/u)^2), quad u >= max_i |Delta_i| $ <ec-autoconsistencia>

donde $u = K r$ es la fuerza con la que el grupo atrae a cada oscilador. El menor acoplamiento para el que hay solución es

$ K_c = min_(u >= max_i |Delta_i|) u/f(u) $ <ec-kc-finito>

y, para un $K$ dado, la @ec-autoconsistencia da el valor de $r$ del estado enganchado y el desfasaje de cada oscilador respecto de la fase media, $arcsin(Delta_i\/u)$ @verwoerd2008. Para los 20 osciladores que se usan, con frecuencias naturales a intervalos iguales entre 1,005 y 1,508 rad/s, resulta $K_c = #"0,335"$ rad/s, y en el umbral $r = #"0,773"$, por lo que el enganche aparece con el grupo ya muy ordenado. El cálculo de los autovalores de la matriz jacobiana del modelo linealizado alrededor del estado enganchado da estable el estado enganchado en todos los valores de $K$ usados en el experimento. Es una estabilidad local, que no asegura que el sistema llegue a ese estado desde cualquier condición inicial, y eso se comprueba por simulación.

*El modelo en los nodos.* El modelo anterior supone que cada oscilador conoce en todo instante la fase exacta de los demás. En la implementación esto no se cumple, porque la fase de cada nodo llega a los otros como un mensaje MQTT, con demora y solo cada cierto tiempo. Si $tau_(i j)(t)$ es la antigüedad, en el instante $t$, de la última fase del nodo $j$ que conoce el nodo $i$, la evolución de cada nodo está dada por

$ dot(theta)_i (t) = omega_i + K/N sum_(j != i) sin(theta_j (t - tau_(i j)(t)) - theta_i (t)) $ <ec-nodo>

La suma excluye $j = i$ porque cada nodo conoce su propia fase sin demora, y ese término es nulo. El divisor $N$ es la cantidad total de nodos y permanece fijo aunque falte alguna fase, de modo que un mensaje ausente no altera el peso de los demás. Con todos los retardos nulos, la @ec-nodo coincide con la @ec-kuramoto.

La antigüedad $tau_(i j)$ reúne varias demoras. Una fase recorre dos conexiones TCP, del publicador al broker y del broker al suscriptor (@sec-pubsub), y pasa por la cola del broker. Además, entre dos publicaciones sucesivas la fase conocida envejece. Si cada nodo publica con período $h$, la fase guardada envejece desde casi cero hasta casi $h$, en forma de diente de sierra, y esa espera agrega en promedio alrededor de $h\/2$. Por último, MQTT delega la entrega en TCP (@sec-mqtt), de modo que un paquete descartado en la red no se pierde, sino que se retransmite y llega más tarde. Mientras la conexión se mantiene, la pérdida de paquetes se manifiesta entonces como un aumento y una variación de $tau_(i j)$. Si un mensaje no llega, el nodo sigue usando la última fase recibida, cuya antigüedad continúa creciendo.

Cada nodo integra la @ec-nodo con el método de Euler y un paso $T_s$ de 10 ms, que no tiene por qué coincidir con $h$. En el firmware, $T_s$ es el tiempo que realmente transcurrió entre dos pasos, para que una demora en la planificación del emulador no cambie la velocidad de la fase:

$ theta_i [k + 1] = theta_i [k] + T_s (omega_i + K/N sum_(j != i) sin(hat(theta)_j [k] - theta_i [k])) $ <ec-nodo-discreta>

donde $hat(theta)_j [k]$ es la última fase recibida del nodo $j$ al llegar el paso $k$.

*Efecto del retardo.* El modelo de Kuramoto con un retardo $tau$ constante e igual para todos los pares, incluido el término de cada oscilador consigo mismo, se analiza en el trabajo de Yeung y Strogatz @yeung1999. Para osciladores idénticos, con $omega_i = omega_0$, existe una solución en la que todos giran en fase a una frecuencia $Omega$ que cumple

$ Omega = omega_0 - K sin(Omega tau) $ <ec-retardo-omega>

y esa solución es estable si $cos(Omega tau) > 0$ @yeung1999. El retardo, por lo tanto, corre la frecuencia común respecto de la natural, y lo que determina la estabilidad no es $tau$ por sí solo, sino el producto $Omega tau$. Con acoplamiento débil, $Omega approx omega_0$ y la condición se cumple mientras el retardo sea menor que un cuarto del período de oscilación, que a los 0,2 Hz de este experimento equivale a 1,25 s. El retardo se compara, entonces, con el período de oscilación y no con la desintonía. La condición es periódica en $tau$, de modo que superar $Omega tau = pi\/2$ no implica por sí solo perder la estabilidad @yeung1999. Para frecuencias distribuidas y un número infinito de osciladores, el retardo multiplica además el acoplamiento crítico por $1\/cos(Omega_c tau)$, donde $Omega_c$ es la frecuencia común en el umbral @yeung1999.

Estos resultados no se aplican de forma directa a la @ec-nodo, y se utilizan como referencia. La diferencia del término propio es menor, porque al repetir el planteo para osciladores idénticos sin ese término quedan $N - 1$ sumandos con retardo, y la condición pasa a ser $Omega = omega_0 - K (N - 1)\/N sin(Omega tau)$, que tiende a la @ec-retardo-omega cuando $N$ crece. No se dispone, en cambio, de un resultado cerrado para frecuencias arbitrarias, $N$ finito y retardos que varían en el tiempo. Se espera que la variación del retardo, o _jitter_, actúe como un ruido sobre las fases recibidas, baje $r$ en régimen y suba el $K_c$ medido, aunque no equivale al ruido blanco que se agrega a las frecuencias en el modelo de Yeung y Strogatz @yeung1999. Ese caso se estudia comparando la simulación del modelo con las mediciones.

*Retardo uniforme con frecuencias distintas.* Los resultados anteriores no alcanzan para las frecuencias del experimento, pero el mismo razonamiento se puede extender. Esta extensión no proviene de las fuentes citadas, sino que es propia de este trabajo. Se supone en la @ec-nodo un retardo $tau$ constante e igual para todos los pares y un estado enganchado, $theta_i (t) = Omega t + a_i$, y se llaman $r$ y $psi$ al módulo y al ángulo del centroide de los $a_j$. Con $beta_i = a_i - psi + Omega tau$, cada oscilador debe cumplir

$ omega_i + K/N sin(Omega tau) - Omega = K r sin beta_i $ <ec-nodo-retardo>

y, promediando sobre todos los osciladores, la frecuencia común resulta

$ Omega = overline(omega) - K (r^2 - 1/N) sin(Omega tau) $ <ec-omega-retardo-distintas>

Con $tau = 0$ se recupera $Omega = overline(omega)$. Con retardo, $Omega$ queda por debajo de la media, de modo que los osciladores más rápidos quedan más lejos de la frecuencia común y son los primeros en no poder seguirla. Resolviendo numéricamente las ecuaciones para las 20 frecuencias, con $tau = 255$ ms ($h\/2$ más unos 5 ms de transporte), la primera solución aparece en $K = #"1,17" K_c$, mientras que el factor $1\/cos(Omega tau)$ solo sugeriría un aumento cercano al 5 %. La diferencia es justamente el corrimiento de $Omega$. Se trata de una aproximación, porque la antigüedad real no es constante sino un diente de sierra alrededor de $h\/2$, y se contrasta con la simulación y las mediciones.

*Acoplamiento fijo y efecto de la red.* $K$ es una ganancia del software de cada nodo, que se fija al comienzo de cada corrida y no cambia durante ella. Tampoco modifica el tráfico, que depende de $h$ y del tamaño de los mensajes. La red no altera $K$, pero sí el efecto que tiene sobre la dinámica, de modo que hace falta un acoplamiento mayor que el teórico para lograr el enganche. Por eso, comparar lo que predice el modelo con lo que se mide indica qué efecto tiene cada mecanismo del stack sobre la aplicación, y el experimento se organiza por mecanismos y no en torno a un único valor de $K_c$.

*Interrupción de la comunicación.* Los resultados anteriores suponen que las fases siguen llegando. Cuando dejan de hacerlo, lo que ocurra depende de qué haga cada nodo con las que ya tiene. Si detecta la desconexión y las descarta, la sumatoria se anula y cada oscilador avanza a su frecuencia natural, $dot(theta)_i = omega_i$. Si parte de un estado enganchado, con desfasajes $phi_i = arcsin(Delta_i \/ u)$ respecto de la fase media, el parámetro de orden evoluciona como

$ r(t) = lr(|1/N sum_(i=1)^N e^(upright(i) (phi_i + omega_i t))|) $ <ec-libre>

Las frecuencias distintas hacen que las fases se dispersen, y $r$ cae en un tiempo del orden de $pi \/ b$, donde $b$ es la mitad del rango de las frecuencias naturales. Si solo un nodo pierde la comunicación, se separa de los demás a una velocidad $omega_i - Omega$.

Si, en cambio, el nodo no advierte la interrupción, sigue sumando las últimas fases recibidas, que ya no cambian. El acoplamiento deja de apuntar a la fase actual del grupo y atrae al nodo hacia un valor fijo, mientras el grupo sigue girando, de modo que el nodo se atrasa respecto de él hasta que se detecta el corte.

*Datos incorrectos.* El modelo supone también que $hat(theta)_j$ es efectivamente una fase. Si la mitad de los nodos interpreta de forma incorrecta los mensajes de la otra mitad, cada nodo solo se acopla de manera coherente con los $N\/2$ de su grupo. Como el divisor sigue siendo $N$, el acoplamiento dentro del grupo se reduce a $K\/2$, y el grupo solo puede engancharse si ese valor supera el $K_c$ de sus propias frecuencias.

#subtitulo[Preguntas de investigación]

+ ¿Se sincronizan los nodos como predice el modelo cuando la red no agrega perturbaciones?
+ ¿De qué está hecho un mensaje de fase y cuánto pesa cada parte?
+ ¿Qué ocurre si dos participantes usan versiones distintas del esquema?
+ ¿Cómo responde el grupo a la caída del broker y a la interrupción del enlace de un nodo?
+ ¿Qué aporta QoS 1 frente a QoS 0 con pérdida de paquetes, en una aplicación cuyos datos se reemplazan?
+ ¿Cuánto reduce el alias de tópico el tráfico, y cómo crece la carga del broker con la cantidad de nodos?

#subtitulo[Hipótesis]

Antes de las corridas se formularon las siguientes hipótesis, que se contrastan con los resultados al final del análisis (@tab-contraste-sincronizacion):

- Por encima de $K_c$, los nodos se enganchan con un $r$ algo menor que el teórico, por la antigüedad que introduce el período de publicación.
- Un campo que el receptor no conoce no afecta la sincronía, y dos campos del mismo tipo cruzados se decodifican sin error, pero impiden sincronizar.
- Al caer el broker, el grupo pierde la sincronía y la recupera sin intervención cuando el broker vuelve.
- Un corte de enlace menor que una vez y media el keep-alive no cierra la conexión, y uno mayor la cierra y publica la última voluntad.
- Con pérdida de paquetes, QoS 1 no mejora la sincronización y genera más tráfico que QoS 0.
- El alias de tópico reduce en unos 13 bytes cada mensaje que entrega el broker.

==== Implementación

El objetivo de la implementación no es sincronizar osciladores de la mejor manera posible, sino construir una aplicación en la que cada mecanismo de MQTT y de Protocol Buffers tenga una consecuencia visible. Los nodos ejecutan la @ec-nodo-discreta tal como se planteó, y lo único que les permite acoplarse es el intercambio de mensajes. Por eso, una decisión del stack, como el nivel de QoS o el intervalo de keep-alive, se puede observar en el parámetro de orden $r$ (@ec-orden), que mide cuán agrupadas están las fases, y en la frecuencia común $Omega$ del grupo, y el modelo indica qué debería verse si la comunicación fuera ideal.

#subtitulo[Arquitectura]

El experimento corre sobre la plataforma común (@sec-plataforma-comun), con 20 nodos. En la computadora anfitriona corren además un servidor SNTP con el que los nodos sincronizan su reloj (@sec-conceptos-exp1) y un registrador, `mosquitto_sub`, un cliente MQTT de línea de comandos suscrito a todas las fases. El registrador se conecta por la interfaz local, de modo que no pasa por el puente, no aparece en las capturas ni sufre las condiciones de red que se aplican a los nodos (@fig-arq-sincronizacion). Las capturas se hacen sobre el puente con `tcpdump`.

En lo que afecta a la entrega de los mensajes, Mosquitto mantiene sus valores por defecto salvo en cuatro ajustes. Desactiva el algoritmo de Nagle (`set_tcp_nodelay`), para que cada mensaje salga apenas se publica. Amplía la cola de mensajes por cliente (`max_queued_messages` a 100.000 y `max_queued_bytes` sin límite), para que las ráfagas no produzcan descartes. Y admite hasta 128 alias de tópico hacia los nodos (`max_topic_alias_broker`). Se conserva, en cambio, el límite por defecto de 20 mensajes en tránsito por cliente (`max_inflight_messages`), que solo afecta a QoS 1. Mientras un cliente tenga 20 mensajes sin confirmar, el broker no le envía el siguiente y lo deja en la cola.

#figure(
  diagram(
    spacing: (1.5cm, 0.5cm),
    node-stroke: 0.6pt,
    node-corner-radius: 4pt,
    node-inset: 8pt,
    node((0, 1), caja[ESP32 × 20 (QEMU)][Oscilador y cliente MQTT 5], name: <esp>),
    node((1, 1), caja[Puente de Linux][netem y tcpdump], name: <puente>),
    node((2, 0), caja[Broker Mosquitto][Una conexión TCP por nodo], name: <broker>),
    node((2, 2), caja[Servidor SNTP][Hora común], name: <sntp>),
    node((2, -1), caja[Registrador][`mosquitto_sub`], name: <logger>),
    edge(<esp>, <puente>, "<|-|>", text(size: 8pt)[TAP]),
    edge(<puente>, <broker>, "<|-|>", text(size: 8pt)[PUBLISH]),
    edge(<puente>, <sntp>, "<|-|>", text(size: 8pt)[SNTP], label-side: right),
    edge(<broker>, <logger>, "--|>", text(size: 8pt)[local], label-side: left),
  ),
  caption: [Arquitectura del experimento. Cada nodo se comunica solo con el broker; la suscripción del registrador no pasa por el puente.],
) <fig-arq-sincronizacion>

#subtitulo[Implementación del modelo en el firmware]

La frecuencia natural $omega_i$, el acoplamiento $K$, la fase inicial y el período de publicación $h$ no están fijados en el código, sino que se leen de la memoria _flash_ del nodo, de modo que el firmware se compila una sola vez para todas las corridas. Dos tareas reparten el trabajo. La de integración avanza la fase según la @ec-nodo-discreta cada 10 ms, y la de publicación toma la última fase cada $h = 500$ ms, la serializa y la entrega al cliente MQTT. Al estar separadas, un envío demorado no detiene la integración, que es el desacoplamiento de sincronización de la @sec-pubsub llevado al código. Cada nodo publica con un desfase propio, elegido al azar dentro de $h$, de modo que los nodos no publican todos a la vez y la fase conocida de cada otro nodo envejece de manera repartida, como supone la antigüedad media cercana a $h\/2$ estimada en el planteo.

#subtitulo[Recorrido de una fase]

Una fase atraviesa el stack completo antes de influir en otro nodo, y cada paso aporta a la antigüedad $tau_(i j)$:

+ La tarea de publicación copia la fase, su velocidad y el instante en que se calculó.
+ La fase se serializa con Protocol Buffers mediante nanopb, una biblioteca en C pensada para sistemas con muy poca memoria @nanopb.
+ El cliente esp-mqtt, la biblioteca MQTT de ESP-IDF @esp-mqtt, arma un paquete PUBLISH de QoS 0, sin confirmación de entrega (@sec-mqtt), con esos bytes como carga útil, en el tópico `kuramoto/phase/<id>`, y lo escribe en la única conexión TCP del nodo, que administra lwIP, la pila TCP/IP liviana que incluye ESP-IDF.
+ El broker recibe el paquete y compara el tópico con las suscripciones. Sin interpretar la carga útil, reenvía una copia a cada nodo suscrito al filtro `kuramoto/phase/+`, donde el comodín `+` coincide con cualquier identificador. El emisor no recibe su propia fase gracias a la opción _No Local_ de MQTT 5.0, que pide al broker no devolverle al cliente sus propias publicaciones.
+ Cada receptor decodifica la carga útil. Descarta el mensaje si no es más nuevo que el último de ese nodo, comparando el número de secuencia, y si lo es, reemplaza la entrada de la tabla.
+ En el siguiente paso de integración, a lo sumo 10 ms después, esa fase ya participa de la sumatoria, y sigue envejeciendo hasta que llegue la próxima.

El mensaje es el mismo para todos los nodos, y su definición en un único archivo `.proto` funciona como contrato entre ellos (@sec-stack):

```proto
message PhaseReport {
  uint32  id = 1;         // nodo emisor, 1..N
  float   theta = 2;      // fase en [0, 2*pi), en el instante t_us
  float   velocidad = 3;  // último valor de la derivada de theta, en rad/s
  uint32  seq = 4;        // número de reporte, desde 0
  fixed64 t_us = 5;       // instante de muestreo, en microsegundos
}
```

Codificado, ocupa entre 21 y 24 bytes, porque `seq` es un entero de longitud variable y, en proto3, la versión del lenguaje de esquemas que se usa, su valor inicial 0 no se transmite (@sec-protobuf). El encabezado MQTT del PUBLISH suma otros 21 o 22 bytes, de los cuales 16 o 17 son el nombre del tópico. Como cada PUBLISH contiene exactamente un mensaje, la delimitación queda resuelta por MQTT (@sec-stack), y el tópico alcanza para saber qué esquema aplicar. Con 20 nodos publicando cada 500 ms, el broker realiza $N (N - 1) \/ h = 760$ entregas por segundo.

Se publica con QoS 0 y sin mensajes retenidos, es decir, sin pedirle al broker que guarde la última fase para futuros suscriptores (@sec-mqtt), por el criterio de la @sec-casos-sintesis, porque cada fase queda reemplazada por la siguiente.

#subtitulo[Conexión y desconexión]

El cliente vuelve a suscribirse cada vez que se conecta, porque el broker no conserva su sesión, es decir, sus suscripciones, entre una conexión y la siguiente (@sec-mqtt). Si la conexión se pierde, vuelve a intentarla. El tiempo de reconexión por defecto de esp-mqtt es de 10 s, pero la tarea del cliente lo comprueba cada 5 s y exige superarlo, de modo que en la práctica el intento siguiente ocurre 15 s después de la desconexión, como confirman las mediciones. Cuando recibe el aviso de desconexión, invalida toda la tabla de fases. A partir de ahí la sumatoria no tiene términos y el nodo avanza a su frecuencia natural, que es el comportamiento previsto en el planteo para un corte detectado.

Ese aviso no llega apenas se interrumpe la red. Si el broker cierra la conexión, el nodo se entera enseguida. Si el camino simplemente deja de transportar paquetes, el nodo sigue usando las últimas fases recibidas hasta que el keep-alive o TCP detecten el problema, por lo que durante un tiempo se acopla a valores congelados. El keep-alive es el tiempo máximo que puede pasar entre dos paquetes enviados por el cliente (@sec-mqtt). Si el broker no recibe nada durante una vez y media ese intervalo, cierra la conexión (@sec-convergencia). En los ensayos de corte se configura en 5 s, en lugar de los 120 s por defecto de esp-mqtt, para que los regímenes de la @tab-regimenes-corte se puedan recorrer en pocos minutos.

También se puede registrar un mensaje de última voluntad en el tópico `kuramoto/estado/<id>`. Es un mensaje que el cliente deja registrado al conectarse y que el broker publica si la conexión se cierra de forma anormal (@sec-mqtt). Cuando el broker lo publica, los demás nodos invalidan solo la fase de ese nodo, sin esperar a detectar nada por su cuenta. Es el mismo patrón que usa Sparkplug para marcar como desactualizados los datos de un nodo caído (@sec-caso-industria). La fase vuelve a usarse cuando llega un mensaje nuevo.

#subtitulo[Punto de operación]

Se usan 20 nodos, con frecuencias naturales repartidas a intervalos iguales, y no sorteadas, dentro de un 20 % hacia cada lado de $overline(f) = #"0,2"$ Hz, y $h = 500$ ms. Las frecuencias van de 1,005 a 1,508 rad/s, y para ellas el acoplamiento crítico exacto de la @ec-kc-finito vale $K_c = #"0,335"$ rad/s. Al ser un conjunto fijo, $K_c$ se calcula de forma exacta y cada corrida usa las mismas frecuencias. Los valores de $K$ se expresan como múltiplos de ese $K_c$, el umbral sin retardo, también en las corridas en las que el umbral real es otro.

La elección responde a la capacidad de la computadora anfitriona y al modelo. Las 760 entregas por segundo son la mitad de las 1560 que la plataforma sostuvo de forma estable con 40 nodos publicando cada 1 s. Del lado del modelo, lo que importa es el producto de la frecuencia por la antigüedad. Con una antigüedad media cercana a $h\/2 = 250$ ms y la frecuencia media de las frecuencias naturales, resulta $Omega tau approx #"0,31"$ rad (#"0,29" rad con la frecuencia común que se mide después), lejos de $Omega tau = pi\/2$, el valor en el que deja de cumplirse la condición de estabilidad $cos(Omega tau) > 0$ asociada a la @ec-retardo-omega. Es el mismo valor que con 0,1 Hz y 1 s, pero con todos los transitorios, es decir, el tiempo que tarda el grupo en llegar al régimen, reducidos a la mitad.

Salvo en el barrido de $K$, donde interesa observar cómo se sincroniza el grupo, cada corrida arranca con las fases del estado enganchado que predice la teoría, $theta_i - psi = arcsin(Delta_i \/ u)$, donde $Delta_i$ es la desintonía del nodo y $u = K r$ es la fuerza con la que el grupo lo atrae, con lo cual no hace falta esperar el transitorio para aplicar cada perturbación.

#subtitulo[Automatización y condiciones de red]

Un programa en Python lee una matriz de corridas en JSON. Para cada corrida calcula las frecuencias y el acoplamiento, escribe la configuración en una copia de la imagen _flash_ por nodo, levanta el broker, el servidor SNTP y el registrador, lanza las instancias de QEMU y espera a que todos los nodos terminen. El instante de inicio es una hora común, que cada nodo conoce por SNTP. Las acciones programadas, como detener el broker o cortar un enlace, se ejecutan a su instante y quedan registradas con su hora.

La pérdida y el corte de un enlace se aplican con `tc netem`, una función del kernel de Linux que emula condiciones de red como retardo y pérdida @tc-netem, en los dos sentidos de cada nodo. Un corte es una pérdida del 100 %. Las condiciones de red se aplican recién cuando todos los nodos terminaron de arrancar, para que la primera sincronización del reloj no se vea afectada.

#subtitulo[Medición]

La fase de cada nodo se escribe por su puerto serie (UART), una salida de texto que QEMU guarda en un archivo por nodo, cada 500 ms y desde la tarea de integración. El registrador no alcanza para esto, porque recibe las fases a través del broker y no ve nada cuando este se detiene o cuando un enlace está cortado, que son justamente los momentos de interés. Además, el puerto serie muestra la fase real aunque el nodo esté publicando con un esquema distinto. De esas muestras se reconstruye la fase continua de cada nodo, usando la velocidad para resolver las vueltas completas, y se interpola a una grilla común para calcular $r(t)$ y $psi(t)$. El $r$ en régimen es la media de $r(t)$ en el último 20 % de la corrida, y la frecuencia efectiva de cada nodo es la pendiente de su fase en esa ventana. Se considera que el grupo engancha si la mayor y la menor frecuencia efectiva difieren en menos de 0,01 rad/s. Los bytes, la anatomía del PUBLISH, la antigüedad de cada entrega y las retransmisiones se obtienen de las capturas en el puente, y los tiempos de detección, reconexión y última voluntad, de los registros de los nodos y del registrador.

Como `netem` actúa sobre los paquetes que salen de una interfaz, la pérdida de la bajada se aplica después del puente, a la salida hacia el nodo, y la de la subida antes de llegar a él. Por eso, la captura en el puente ve la bajada antes de que se apliquen las pérdidas y la subida después. Por eso, un segmento que se pierde en la subida no aparece en la captura, y las retransmisiones que se reportan corresponden a la bajada.

#subtitulo[Simulación del modelo]

Además de la emulación se usó una simulación en Python, sin red real, que integra la @ec-nodo-discreta con un paso de 10 ms. Muestra qué hace el modelo de los nodos cuando la única imperfección de la comunicación es la que se le programa. Cada nodo publica su fase cada $h$, con un desfase propio sorteado dentro de $h$, y cada copia llega a cada receptor con un retardo. El receptor conserva la última fase recibida de cada nodo, y mientras no reciba ninguna, ese término no aporta a la sumatoria. El criterio de enganche es el mismo que en la emulación.

La simulación de referencia usa las frecuencias del experimento, $h = 500$ ms y 150 s de duración. Repite cada valor de $K$ con 5 conjuntos de fases iniciales al azar y calcula $r$ y las frecuencias efectivas en los últimos 30 s. El retardo de cada copia se sortea entre 13 y 17 ms, a partir de lo medido en la plataforma común con 39 nodos, y se redondea hacia arriba al paso siguiente de la simulación, por lo que resulta de 20 ms. Los análisis puntuales del umbral usan, en cambio, un retardo fijo de un paso (10 ms) y arrancan del estado enganchado teórico.

#subtitulo[Diseño de las corridas]

Cada mecanismo del stack se activa desde la configuración del nodo, sin recompilar, y cada variante se comparó contra la teoría o contra una corrida de referencia (@tab-corridas-sincronizacion). Cada condición se corrió una vez, salvo QoS con pérdida, que se corrió con tres semillas. Las corridas de umbral, de período, de QoS sin pérdida, las repeticiones de QoS y el corte con captura se agregaron después de analizar la primera tanda, para aislar efectos que esta no permitía separar. Las emulaciones aportan una realización por condición, y la dispersión entre condiciones iniciales se estima con la simulación del modelo. Con 5 fases iniciales distintas, $r$ varía entre #"0,863" y #"0,871" a #"1,2" $K_c$, y menos de #"0,0001" a #"1,5" y $2 K_c$.

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header[Corrida][Condición][Duración],
    [Calibración], [$K = #"1,5" K_c$, sin eventos, con captura], [60 s],
    [Modelo], [$K = #"0,8"$; $#"1,2"$; $#"1,5"$ y $2 K_c$, con fases iniciales al azar], [150 s],
    [Iguales], [Frecuencias iguales, $K = #"0,4"$ rad/s. Los nodos impares agregan al mensaje un campo 6, que los demás no conocen y deben ignorar (@sec-protobuf-compat)], [90 s],
    [Esquema cruzado], [Los nodos impares intercambian los campos 2 y 3 al escribir y al leer. Como ambos son `float`, el mensaje se decodifica sin error, con datos equivocados (@sec-stack)], [120 s],
    [Broker], [Se detiene el broker durante 5 s y durante 20 s (@sec-casos-sintesis)], [240 s],
    [Unión], [Un nodo arranca con los demás, pero se conecta al broker a los 45 s, sin que nadie más se reconfigure (@sec-pubsub)], [90 s],
    [Keep-alive], [Cortes de 2 s y 15 s del enlace de un nodo, con y sin última voluntad (dos corridas) (@sec-convergencia)], [150 s],
    [QoS], [QoS 0 y QoS 1, con 5 % de pérdida por sentido (dos corridas)], [90 s],
    [Alias], [El broker usa alias de tópico en sus entregas (@sec-stack), con captura], [30 s],
    [Escala], [$N = 5$ y $N = 10$, con captura. Como cada $N$ tiene su propio $K_c$, $K$ vale #"0,572" y #"0,525" rad/s], [45 s],
    [Umbral], [$K = #"1,05"$; $#"1,1"$; $#"1,15"$ y $#"1,25" K_c$, desde el estado enganchado], [200 s],
    [Período], [$h = 250$ ms, con $K = #"1,1"$ y $#"1,5" K_c$, desde el estado enganchado], [200 s],
    [QoS sin pérdida], [QoS 1 sin pérdida, con captura], [90 s],
    [Repetición de QoS], [QoS 0 y QoS 1 con 5 % de pérdida, con otras dos semillas (cuatro corridas)], [90 s],
    [Corte con captura], [Corte de 2 s de un nodo, keep-alive de 5 s y captura], [60 s],
  ),
  caption: [Corridas del experimento. Salvo que se indique otra cosa, $N = 20$ y $K = #"1,5" K_c$.],
) <tab-corridas-sincronizacion>

#subtitulo[Entorno y validez]

El experimento se corrió en una computadora con un AMD Ryzen 5 5600G y 13 GB de RAM, con QEMU de Espressif 9.2.2, ESP-IDF 5.5.6, nanopb 0.4.9.1 y Mosquitto 2.1.2. Los tiempos internos de un ESP32 emulado no son los de una placa real, y la computadora anfitriona ejecuta todos los nodos a la vez. Por eso cada corrida registra si la tarea de integración se atrasó y a qué intervalo se producen las muestras de fase, y se controla la carga de la computadora, que durante la primera tanda de corridas estuvo en promedio un 88 % ociosa, con un mínimo del 66 %. Cada nodo resincroniza su reloj por SNTP cada 15 s. Como en el experimento anterior, el cliente SNTP de lwIP no descuenta el tiempo de viaje, de modo que la hora de cada nodo queda atrasada en el tiempo que tarda en llegar la respuesta. Ese error no afecta a la dinámica, que usa solo las fases y las diferencias de tiempo del propio nodo, y su efecto en las curvas de $r(t)$ es despreciable frente a los períodos de oscilación.

==== Resultados

Las 28 corridas terminaron sin fallos. La tarea de integración solo se atrasó en 4 pasos, todos en una misma corrida, sobre millones en total, y las muestras de fase de cada nodo llegaron cada 500 ms, con un máximo de 510 ms entre dos consecutivas. La corrida con alias de tópico se repitió una vez, porque en la primera el broker quedó limitado a sus 10 alias por defecto.

#subtitulo[Sincronización con la red limpia]

Partiendo de fases al azar y con la red sin perturbaciones, el grupo se comporta como predice el modelo de los nodos. Con $K$ por debajo del umbral, $r$ fluctúa sin estabilizarse, y por encima crece hasta un valor que depende de $K$. Las corridas que arrancan del estado enganchado muestran que ese umbral no es el $K_c$ sin retardo, ya que a 1,05, 1,1 y 1,15 $K_c$ el grupo pierde el enganche, y a 1,25 $K_c$ lo conserva. La @fig-modelo-r-k compara el régimen medido con la autoconsistencia de la @ec-autoconsistencia, que no contempla retardo, con la condición con retardo de la @ec-nodo-retardo y con la simulación del modelo de los nodos.

#figure(
  fig-exp2("02_modelo_r_k.png", width: 100%),
  caption: [Parámetro de orden en régimen: teoría sin retardo y con retardo, simulación del modelo y emulación. Los círculos rellenos arrancan de fases al azar, y los vacíos, del estado enganchado teórico.],
) <fig-modelo-r-k>

La corrida con frecuencias iguales, $K = #"0,4"$ rad/s y la mitad de los nodos publicando un campo adicional alcanzó $r = #"1,000"$, con una frecuencia común de 1,1510 rad/s. Para esa corrida, la frecuencia común que predice la condición con retardo, usando la antigüedad media estimada, es 1,1468 rad/s.

#subtitulo[Período de publicación]

Con $h = 250$ ms y la misma red, el grupo engancha a $#"1,1" K_c$, con $r = #"0,860"$ y $Omega = #"1,219"$ rad/s, un valor de $K$ en el que con $h = 500$ ms no engancha. A $#"1,5" K_c$ resulta $r = #"0,944"$ y $Omega = #"1,195"$ rad/s, frente a #"0,937" y #"1,142" rad/s con $h = 500$ ms.

#subtitulo[Anatomía de una fase]

La @tab-anatomia-fase descompone, a partir de la captura de la corrida de calibración, una entrega típica de una fase con identificador de dos cifras. A diferencia del experimento de la @sec-exp-mqtt-https, que cuenta bytes IP, aquí se cuentan las tramas completas, que agregan los 14 B del encabezado Ethernet.

#figure(
  table(
    columns: (1fr, auto, auto),
    align: (left, right, right),
    table.header[Parte][Bytes][Proporción],
    [Encabezados Ethernet, IP y TCP], [54], [54,5 %],
    [Encabezado fijo MQTT, largo de tópico y largo de propiedades], [5], [5,1 %],
    [Nombre del tópico], [17], [17,2 %],
    [Mensaje de Protocol Buffers], [23], [23,2 %],
    [*Trama completa*], [*99*], [*100 %*],
  ),
  caption: [Composición de una trama que entrega una fase, sin alias de tópico.],
) <tab-anatomia-fase>

#subtitulo[Contrato de datos]

En la corrida con un campo desconocido, los nodos recibieron las 3420 fases esperadas por nodo y la sincronía no se vio afectada, porque los lectores ignoraron el campo 6.

En la corrida con los campos 2 y 3 cruzados, cada nodo recibió las 4560 fases esperadas y ninguno informó un error, pero el grupo no se sincronizó (@fig-esquema-cruzado). En la ventana final, $r$ valió 0,159 en el conjunto, 0,428 entre los nodos con el esquema normal y 0,653 entre los que tenían el esquema cruzado.

#figure(
  fig-exp2("03_esquema_cruzado.png", width: 100%),
  caption: [Parámetro de orden con la mitad de los nodos usando el esquema con los campos cruzados.],
) <fig-esquema-cruzado>

#subtitulo[Caída del broker]

La @fig-broker muestra el efecto de detener el broker. Antes de cada caída, $r$ valía 0,937, y llegó a 0,013 en la de 5 s y a 0,004 en la de 20 s. En ambas caídas, los nodos se enteraron enseguida y, cuando el broker volvió, tardaron unos 10 s más en reconectarse (10,9 y 9,8 s desde la vuelta real del broker). La primera caída estaba programada en 5 s, pero duró #"4,2" s, porque la orden de detener el broker se ejecutó 1,05 s tarde; la segunda duró #"20,2" s. La figura usa los instantes programados. Desde que volvió el broker, $r$ tardó 27,7 y 37,0 s en mantenerse por encima del 95 % de su valor previo.

#figure(
  fig-exp2("04_broker.png", width: 100%),
  caption: [Parámetro de orden durante dos caídas del broker, y la predicción de la @ec-libre mientras los nodos están desconectados.],
) <fig-broker>

#subtitulo[Keep-alive y última voluntad]

Con un keep-alive de 5 s, se cortó el enlace de un nodo durante 2 s y después el de otro durante 15 s, con y sin última voluntad (@tab-keepalive-sincronizacion). El efecto sobre $r$ es moderado, porque solo un nodo de 20 queda afuera, por lo que la @fig-keepalive-nodo muestra la fase del nodo cortado respecto de la fase media del grupo.

#figure(
  table(
    columns: 7,
    align: (left, left, right, right, right, right, right),
    table.header[Corte][Última voluntad][El nodo detecta][Reconexión tras el corte][Voluntad publicada][$r$ mínimo][Desfase final (rad)],
    [2 s], [No], [4,5 s], [17,5 s], [--], [0,897], [0,51],
    [2 s], [Sí], [3,1 s], [16,1 s], [3,3 s], [0,917], [0,51],
    [15 s], [No], [4,1 s], [4,1 s], [--], [0,874], [1,07],
    [15 s], [Sí], [5,0 s], [5,0 s], [6,9 s], [0,854], [1,40],
  ),
  caption: [Efecto de cortar el enlace de un nodo. La detección y la publicación se miden desde el comienzo del corte, la reconexión desde su fin, y el desfase es el del nodo respecto de $psi$ al terminar.],
) <tab-keepalive-sincronizacion>

#figure(
  fig-exp2("05_keepalive_nodo.png", width: 100%),
  caption: [Desfase del nodo 11 respecto de la fase media durante su corte de 15 s.],
) <fig-keepalive-nodo>

#subtitulo[Incorporación de un nodo]

El nodo 20 arrancó junto con los demás, pero se conectó al broker a los 45 s. Hasta entonces avanzó a su frecuencia natural y, 7,5 s después de conectarse, su fase ya estaba estabilizada en el valor que le corresponde dentro del grupo, es decir, a menos de 0,15 rad de su desfase final, sin que ningún otro nodo cambiara su configuración.

#subtitulo[QoS con pérdida de paquetes]

Con un 5 % de pérdida en cada sentido, los dos niveles de QoS se comportaron de forma muy distinta (@fig-qos-sincronizacion y @tab-qos-sincronizacion). No hubo desconexiones en ninguna de las dos corridas. La antigüedad de una entrega es la diferencia entre el instante en que el broker la envía a la red y el instante en que se calculó la fase. Con otras dos semillas, QoS 0 alcanzó $r = #"0,913"$ y $#"0,878"$, y enganchó en la primera de ellas; QoS 1 quedó en $r = #"0,094"$ y $#"0,064"$, con antigüedades medianas de #"13,1" y #"12,5" s.

#figure(
  fig-exp2("07_qos.png", width: 100%),
  caption: [Parámetro de orden con 5 % de pérdida por sentido, para QoS 0 y QoS 1, y con QoS 1 sin pérdida.],
) <fig-qos-sincronizacion>

#figure(
  table(
    columns: 4,
    align: (left, right, right, right),
    table.header[][QoS 0, 5 %][QoS 1, 5 %][QoS 1, sin pérdida],
    [$r$ en régimen], [0,800], [0,148], [0,936],
    [Engancha], [No], [No], [Sí],
    [Fases recibidas por nodo (de 3420)], [3409 a 3416], [1759 a 2611], [3418 y 3419],
    [Antigüedad de la entrega, mediana], [8,6 ms], [13,4 s], [21,7 ms],
    [Antigüedad de la entrega, percentil 95], [1,2 s], [29,2 s], [46,9 ms],
    [Segmentos retransmitidos en la bajada], [3041], [3421], [0],
    [Tráfico total], [101,5 kB/s], [88,0 kB/s], [164,2 kB/s],
    [Bytes por entrega en la captura], [134 B], [149 B], [216 B],
  ),
  caption: [QoS 0 y QoS 1 con 5 % de pérdida por sentido (semilla 1), y QoS 1 sin pérdida. Sin pérdida y con QoS 0, cada entrega cuesta 133 B.],
) <tab-qos-sincronizacion>

#subtitulo[Alias de tópico]

Con alias de tópico en las entregas del broker, el PUBLISH que recibe cada nodo pasa de 45 a 31 bytes, y su trama de 99 a 85. El 98 % de las entregas de la corrida ya lleva el alias, y solo la primera por cada par de nodos transporta todavía el tópico. El tráfico de bajada por nodo baja de 3767 a 3269 B/s, un 13,2 %, y el total de 100,8 a 91,0 kB/s, un 9,7 %.

#subtitulo[Carga del broker]

Sin perturbaciones, la cantidad de entregas crece con $N (N - 1)$, y la mayor parte del tráfico sale del broker (@tab-carga-sincronizacion). Cada nodo publica la misma cantidad de mensajes sin importar cuántos otros haya; la subida crece menos que la bajada y también incluye las confirmaciones TCP de lo que el nodo recibe.

#figure(
  table(
    columns: 6,
    align: (right, right, right, right, right, right),
    table.header[$N$][Entregas/s][Total (kB/s)][Subida por nodo (B/s)][Bajada por nodo (B/s)][Antigüedad mediana (ms)],
    [5], [40], [6,7], [462], [876], [2,3],
    [10], [180], [25,6], [736], [1820], [3,7],
    [20], [760], [100,8], [1274], [3767], [5,0],
  ),
  caption: [Tráfico y antigüedad de las entregas según la cantidad de nodos, con $h = 500$ ms.],
) <tab-carga-sincronizacion>

==== Análisis de resultados

#subtitulo[Umbral de sincronización y efecto del stack]

Con la red limpia, la emulación coincide con la simulación del modelo de los nodos, con diferencias de hasta 0,007 en $r$ a 1,2, 1,5 y 2 $K_c$. Las dos quedan por debajo de la teoría sin retardo, y la diferencia de la emulación respecto de ella crece al acercarse a $K_c$, ya que es de 0,031 a 1,2 $K_c$ y de 0,0035 a 2 $K_c$. Con una antigüedad media de unos 250 ms, la información vieja desplaza el umbral hacia arriba, y ese corrimiento se midió. El grupo no engancha a 1,05, 1,1 ni 1,15 $K_c$, aunque sin retardo allí existe un estado enganchado estable, y sí engancha a 1,2 y 1,25 $K_c$. La corrida de 1,15 $K_c$ queda muy cerca del criterio de enganche, con una dispersión de 0,012 rad/s contra el límite de 0,01. El umbral medido queda así entre 1,15 y 1,2 $K_c$, en acuerdo con el $#"1,17" K_c$ que predice la @ec-nodo-retardo y con la simulación del modelo de los nodos con retardo fijo de 10 ms, que deja de derivar entre 1,18 y 1,19 $K_c$. El corrimiento, cercano al 18 %, es más de tres veces el 5 % que sugeriría el factor $1\/cos(Omega tau)$, porque la mayor parte se debe a la baja de la frecuencia común. Una consecuencia es que la corrida de 1,2 $K_c$ está apenas por encima del umbral real, y eso explica que su diferencia con la teoría sin retardo sea la mayor.

La frecuencia común también refleja el retardo. Baja de 1,176 a 1,098 rad/s al pasar de 1,2 a 2 $K_c$, por debajo de la media de 1,257 rad/s, y el freno aumenta con $K$, como indica la @ec-omega-retardo-distintas. Resuelta con $tau = 255$ ms, esa relación reproduce las frecuencias medidas con un error menor que el 0,5 %, y los valores de $r$ con diferencias de hasta 0,007.

En este punto de operación, la antigüedad con la que el broker emite cada entrega, de unos 5 ms, es muy pequeña frente a los 250 ms de envejecimiento entre publicaciones. Esa medida no incluye el último tramo hasta el nodo ni su procesamiento, pero eso no cambia el orden de magnitud. De los dos componentes de la antigüedad, el que depende del período de publicación, una decisión de la aplicación, es por lejos el mayor. Las corridas con $h = 250$ ms aíslan ese efecto. Para esa antigüedad, de unos 131 ms, la @ec-nodo-retardo predice el umbral en $#"1,06" K_c$, por lo que $#"1,1" K_c$ ya debería enganchar, y así ocurre, mientras que con $h = 500$ ms no engancha. También predice $r$ y $Omega$ con diferencias de a lo sumo 0,001 y 0,004 rad/s. Reducir el período de publicación a la mitad, sin tocar la red, es lo que permitió enganchar con menor acoplamiento, al costo de duplicar la cantidad de mensajes.

#subtitulo[Composición de los bytes]

De los 99 bytes de una entrega, 23 son la fase. Protocol Buffers cumple lo prometido, ya que codifica cinco campos, entre ellos un `fixed64` y dos `float`, en 23 bytes. El encabezado fijo de MQTT también es pequeño. Pero el costo restante se reparte en 54 bytes de encabezados de las capas inferiores y 17 del nombre del tópico, que se repite en cada mensaje y pesa casi tanto como el dato, dos partes que MQTT y Protocol Buffers no reducen por sí solos. En mensajes tan cortos, el costo por mensaje queda dominado por lo que rodea al dato. Por eso resulta adecuado limitar la frecuencia de publicación, como hacen los casos de la @sec-casos-sintesis, y resulta útil el alias de tópico, que recorta 14 bytes por entrega a cambio de que el broker mantenga una tabla por conexión. Como se aplica solo por conexión, y el alias se usa en la mayor parte de las entregas, en este patrón todos-a-todos alcanza con activarlo en el tramo del broker hacia los nodos.

#subtitulo[El contrato de datos]

El ensayo muestra las dos caras de un mensaje identificado por números de campo. Agregar un campo es inocuo, porque los lectores que no lo conocen lo ignoran, y el sistema sigue funcionando (@sec-protobuf-compat). Cruzar dos campos del mismo tipo, en cambio, no se detecta en ninguna capa. El broker no interpreta la carga útil, TCP la entrega intacta y el decodificador encuentra dos `float` válidos. La única señal es que la aplicación deja de funcionar. El modelo explica por qué no engancha cada mitad. Cada nodo solo se acopla de forma coherente con la suya, con un acoplamiento efectivo $K\/2 = #"0,251"$ rad/s, por debajo de los 0,3315 rad/s del $K_c$ de cada subgrupo. Los mensajes de la otra mitad traen un valor cercano a la velocidad, casi constante, que tira hacia un ángulo fijo. Su amplitud, de $K\/2$, es menor que la frecuencia natural de cualquier nodo, por lo que no detiene la rotación, sino que modula su velocidad. Es la consecuencia práctica de que el mensaje no sea autodescriptivo (@sec-protobuf). La compatibilidad depende, entonces, de una disciplina sobre el esquema, que el protocolo no puede verificar.

#subtitulo[El broker como punto único de falla]

Con el broker detenido, ningún nodo puede saber nada de los demás, y el grupo pierde la sincronía en pocos segundos, como anticipa la @sec-pubsub. Una vez desconectados, cada nodo oscila libremente, y $r(t)$ sigue casi exactamente la @ec-libre. La diferencia cuadrática media con la curva predicha es de 0,014, y el primer mínimo aparece a los 9,6 s del corte, contra 9,8 s de la predicción (@fig-broker). Con $b = #"0,251"$ rad/s, el tiempo característico $pi \/ b$ es de 12,5 s. Tanto en la caída de 5 s como en la de 20 s, $r$ llegó cerca de 0, y la recuperación fue más larga en la segunda. En ambas, la reconexión llegó en múltiplos de 15 s desde la desconexión, a los 15 s en la primera caída y a los 30 s en la segunda, después de un intento fallido a los 15 s. Por eso los nodos tardaron unos 10 s en reconectarse después de que volvió el broker, una demora que no es el período de reintento, sino lo que restaba de él. Durante ese tiempo siguen desacoplados aunque el broker ya esté disponible, de modo que la caída del servicio dura, para la aplicación, más que la del broker. El experimento no probó otros valores de ese período. Una vez reconectados, el grupo vuelve a sincronizarse sin intervención, gracias a que cada nodo se vuelve a suscribir por su cuenta. Descontada la espera hasta reconectarse, tarda entre 17 y 27 s, del mismo orden que los 13 s que tardó en sincronizarse desde fases al azar en las corridas con la red limpia, porque tras una caída larga las fases quedan prácticamente dispersas.

#subtitulo[Cortes de un enlace y última voluntad]

El corte de 15 s se comporta como anticipa la @tab-regimenes-corte. El nodo y el broker cierran la conexión, la última voluntad se publica a los 6,9 s, muy cerca de los 7,5 s que corresponden a una vez y media el keep-alive, y el nodo se reconecta 4 a 5 s después de que vuelve el enlace, es decir, 15 s después de haber detectado la desconexión.

El corte de 2 s muestra un matiz que esa tabla no contempla. Aunque dura menos que el umbral de 7,5 s del broker, el nodo igual cerró la conexión, a los 3 a 4,5 s de comenzado el corte. El umbral de una vez y media el keep-alive es el del broker, pero el cliente esp-mqtt envía un PINGREQ a la mitad del intervalo y da la conexión por perdida si la respuesta no llega antes de que se complete el intervalo. Con un keep-alive de 5 s, la respuesta tiene un margen de 2,5 s, y un corte breve alcanza para perder ese intercambio. Una corrida adicional con captura, con el mismo corte de 2 s, muestra por qué el fin del corte no alcanza para evitarlo. El último PINGRESP pasa 2,2 s antes del corte y el siguiente PINGREQ no llega al broker. Medido desde el comienzo programado del corte, el broker retransmite a los 0,3, 0,8 y 1,7 s, con esperas cada vez mayores, de modo que su intento siguiente recién sale a los 3,5 s. Así, aunque el enlace vuelve a los 2 s, durante más de un segundo no circula nada por la conexión, y a los 3,1 s el cliente agota su plazo y la cierra. Es el mismo efecto de los reintentos de TCP cada vez más espaciados de la @sec-convergencia. La conexión del lado del cliente es, entonces, más frágil de lo que indica el umbral del broker, y la reconexión cuesta más que el propio corte. Como el cliente espera 15 s desde que detecta la desconexión, el nodo tardó entre 16 y 17,5 s en volver después de terminado el corte. Además, como el cliente cierra la conexión sin enviar DISCONNECT, el broker publica la última voluntad, a los 3,3 s del comienzo del corte, aunque el enlace ya esté restablecido.

Con un solo nodo cortado sobre 20, el efecto en el grupo es pequeño, y $r$ baja como mucho a 0,854. El comportamiento del nodo cortado coincide con el planteo. Mientras no detecta la desconexión, sigue acoplado a fases congeladas y se atrasa hasta 0,5 rad respecto del grupo. Una vez desconectado, avanza a su frecuencia natural y se adelanta a 0,115 y 0,117 rad/s, cerca de los 0,128 rad/s de $omega_i - Omega$. La última voluntad cumplió su función de avisar la caída, pero en estas corridas no mejoró la sincronía, ya que los valores con y sin ella son del mismo orden y, con una sola corrida por condición, sus diferencias no permiten sacar una conclusión.

#subtitulo[QoS y frescura de los datos]

El resultado más llamativo es que, con pérdida, QoS 1 empeoró la sincronización de forma drástica respecto de QoS 0, que ya sufría. Con QoS 0, las retransmisiones de TCP hacen que algunas fases lleguen tarde. La mediana se mantiene en milisegundos, pero el percentil 95 llega a 1,2 s. Casi todas las fases llegan. En la corrida de la tabla, dos nodos, el 18 y el 20, entre los de mayor desintonía, se separan del grupo, y el valor de $r$ de 0,80 corresponde a una ventana final que coincide con el peor tramo, ya que durante los primeros 60 s $r$ se mantuvo entre 0,87 y 0,93. El grupo enganchó en una sola de las tres corridas, de modo que, con esta pérdida, queda en el límite del enganche.

Con QoS 1, el broker entregó las fases con una antigüedad mediana de 13,4 s, y cada nodo recibió entre la mitad y las tres cuartas partes de lo publicado, sin que se cortara ninguna conexión. La captura muestra una acumulación en el broker. En los 20 nodos, las entregas sin confirmar llegan a 20, el límite de Mosquitto, y permanecen en él entre el 87 % y el 96 % del tiempo, es decir, la ventana está saturada casi siempre. Con ese límite, cuando una pérdida frena la conexión TCP de un nodo, tampoco salen mensajes nuevos hacia él. El broker atiende unas 600 entregas por segundo contra las 760 que se publican, y el resto se acumula en la cola, que está ampliada a 100.000 mensajes. La antigüedad crece entonces de forma sostenida, desde una mediana de unos 2 s en los primeros 10 s hasta unos 26 s en los últimos 10 s, de modo que los 13,4 s de la tabla no describen un régimen estable. Las fases que faltan no se perdieron, sino que quedaron en cola al terminar la corrida.

Las condiciones de estabilidad de la @ec-retardo-omega no aplican aquí, porque valen para un retardo constante y son periódicas en $tau$. En este caso $tau$ crece durante toda la corrida y varía entre una entrega y otra, y no existe un retardo alrededor del cual el grupo pueda engancharse.

La corrida sin pérdida separa los efectos. QoS 1 sin pérdida engancha igual que QoS 0, con $r = #"0,936"$, sin acumulación, con a lo sumo 5 mensajes en tránsito y una antigüedad mediana de 21,7 ms. El problema no es QoS 1 en sí, sino su combinación con la pérdida. El límite de 20 mensajes no se varió, por lo que el experimento no lo aísla como causa única, aunque la saturación permanente lo señala.

La conclusión práctica coincide con la de la @sec-casos-sintesis y la amplía. La confirmación de entrega asegura que un mensaje llegue, y en esta aplicación, cuando hay pérdida, esa garantía es contraproducente, porque una fase vieja no sirve y además retrasa a las más nuevas. Sin pérdida no perjudicó la sincronía, pero cada entrega costó unos 216 B, frente a unos 133 B de QoS 0 sin pérdida, cerca de un 63 % más. Para datos que se reemplazan continuamente, importa la frescura y no la entrega de cada muestra.

#subtitulo[Contraste de hipótesis]

La @tab-contraste-sincronizacion contrasta las hipótesis del planteo con los resultados.

#figure(
  table(
    columns: (1fr, 1fr),
    table.header[Hipótesis][Resultado],
    [Por encima de $K_c$, los nodos se enganchan con un $r$ algo menor que el teórico.], [*Se confirma en parte.* Engancharon a 1,2, 1,25, 1,5 y 2 $K_c$, con $r$ 0,0035 a 0,031 menor que la teoría sin retardo y hasta 0,007 respecto de la simulación. Pero entre $K_c$ y 1,15 $K_c$ no engancharon: el umbral real está entre 1,15 y 1,2 $K_c$.],
    [Un campo desconocido no afecta la sincronía, y dos campos cruzados se decodifican sin error, pero impiden sincronizar.], [*Se confirma.* Con el campo adicional $r = #"1,000"$. Con los campos cruzados, $r = #"0,159"$, sin errores de decodificación.],
    [Al caer el broker, el grupo pierde la sincronía y la recupera sin intervención.], [*Se confirma.* $r$ cae hasta 0,013 y se recupera por sí solo; la caída sigue la oscilación libre prevista.],
    [Un corte menor que una vez y media el keep-alive no cierra la conexión, y uno mayor la cierra y publica la última voluntad.], [*Se confirma a medias.* El corte de 15 s cerró la conexión y publicó la voluntad a los 6,9 s. El de 2 s también cerró la conexión, del lado del cliente.],
    [Con pérdida, QoS 1 no mejora la sincronización y genera más tráfico que QoS 0.], [*Se confirma.* QoS 1 fue mucho peor ($r$ de 0,148 contra 0,800, en la primera semilla). El tráfico total fue menor (88,0 contra 101,5 kB/s) solo porque se entregaron menos fases: por entrega costó 149 B contra 134 B. Sin pérdida, QoS 1 no perjudica la sincronía.],
    [El alias de tópico reduce unos 13 bytes por entrega.], [*Se confirma.* El PUBLISH entregado pasa de 45 a 31 bytes, 14 menos, y el tráfico total baja un 9,7 %.],
  ),
  caption: [Contraste de las hipótesis con los resultados.],
) <tab-contraste-sincronizacion>

#subtitulo[Limitaciones]

- *Una realización por condición.* Salvo QoS con pérdida, cada ensayo se corrió una vez. Las diferencias grandes, como las de QoS, son claras, pero las pequeñas, como el efecto de la última voluntad, no se pueden distinguir de la variación entre corridas.
- *Emulación.* El broker, los 20 nodos y la red comparten una computadora. Los retardos internos no son los de una placa física con Wi-Fi.
- *Perturbaciones sintéticas.* La pérdida de 5 % es aleatoria e independiente y no representa la de un enlace real, en el que suele darse en ráfagas.
- *Un punto de operación acotado.* $overline(f)$ y el ancho de las frecuencias se fijaron, y $h$ solo se varió en dos corridas, por la capacidad de la computadora y el tiempo disponible. Otros valores cambian el peso relativo del período de publicación y de la red.
- *Sin TLS.* Las corridas no usan cifrado, cuyo costo se analiza en el experimento de la @sec-exp-mqtt-https.

#subtitulo[Implicaciones]

Para una aplicación en la que todos los nodos necesitan el dato de todos, los resultados sugieren los siguientes criterios:

- La frescura importa más que la entrega de cada mensaje. Conviene usar QoS 0 y descartar lo viejo con un número de secuencia. QoS 1 no perjudicó la sincronía sin pérdida, pero aumentó el costo por mensaje y, con pérdida, generó una cola que crece sin límite si el broker la permite.
- El período de publicación pesó mucho más que el retardo de la red en este punto de operación, y corrió el umbral de enganche en cerca de un 18 %. Se lo debe elegir en función de la dinámica de la aplicación, y no solo del ancho de banda.
- Tras una interrupción, el tiempo de reconexión del cliente puede pesar más que la propia interrupción, y es un parámetro que debe ajustarse. Hay que medirlo en el cliente real, ya que en esp-mqtt un valor configurado de 10 s dio un reintento efectivo de 15 s.
- Un keep-alive muy corto detecta antes una caída, pero vuelve frágil la conexión ante cortes breves.
- El esquema es parte del sistema. Los cambios incompatibles no producen errores, por lo que necesitan control de versiones y pruebas propias.
