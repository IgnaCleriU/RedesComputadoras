// Diagramas (Typst Universe).
#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import "@preview/chronos:0.3.0"

// Caja de un diagrama: título en negrita y una línea de detalle debajo.
#let caja(titulo, detalle) = align(center)[*#titulo* \ #text(size: 8pt, detalle)]

// Subtítulo sin numerar dentro de una parte de un experimento (evita un quinto nivel de numeración).
#let subtitulo(cuerpo) = block(above: 1.3em, below: 0.7em, sticky: true, text(weight: "bold", cuerpo))

// Figuras del Experimento 1, generadas por experimentos/comparacion-mqtt-http/analysis/figuras.py.
#let fig-exp1(archivo, ..args) = image("../experimentos/comparacion-mqtt-http/docs/resultados/figs/" + archivo, ..args)

== Diseño experimental

// Presentación de los dos experimentos y de la estructura común (planteo, implementación, resultados y análisis).

=== Plataforma común

// Placas ESP32 emuladas con QEMU, broker Mosquitto y backend; restricciones de la emulación.
// TODO(mapeo tecnológico) El hardware real que reemplazaría a lo emulado se releva en @sec-mapeo-tecnologico; referenciarla acá.
// TODO(revisión PR #322) Explicar las herramientas que el Experimento 1 menciona sin definir:
// QEMU de Espressif, ESP-IDF, lwIP, mbedTLS, esp-mqtt, esp_http_client, nanopb,
// interfaces TAP, puente de Linux, tc netem, dumpcap y TShark. Citar la documentación
// de cada una como entradas @online en bibliografia.bib.

=== Experimento 1: MQTT contra HTTPS para telemetría <sec-exp-mqtt-https>

Este experimento es el caso base de la parte experimental. Mide cuánto cuesta, en bytes y en latencia, enviar una lectura de un sensor por MQTT y por HTTP, y separa ese costo en sus componentes: la conexión, el protocolo de aplicación, el cifrado y la serialización. Sus resultados sirven de referencia para el segundo experimento (@sec-exp-sincronizacion), que compara las mismas combinaciones en la sincronización de osciladores acoplados, una aplicación de tiempo real con intercambio de mensajes a alta frecuencia.

==== Conceptos previos <sec-conceptos-exp1>

Además de lo presentado en el marco teórico, el análisis de este experimento se apoya en dos mecanismos de TCP y en el protocolo con el que se sincronizan los relojes de los nodos. Se resumen a continuación porque explican buena parte de los resultados.

*Algoritmo de Nagle.* Una aplicación entrega datos a TCP con llamadas a `send()` sobre un _socket_, y TCP decide cómo repartirlos en segmentos. Si cada llamada saliera de inmediato en su propio segmento, una aplicación que escribe de a pocos bytes llenaría la red de segmentos casi vacíos, en los que los 40 bytes de encabezados TCP/IP pesan más que los datos. El algoritmo de Nagle evita eso: mientras haya datos enviados sin confirmar, TCP no envía un segmento más chico que el tamaño máximo, sino que acumula los datos nuevos hasta recibir el ACK pendiente @rfc896. Si no hay nada sin confirmar, el segmento sale enseguida. Así, una escritura aislada no se demora, pero la segunda de dos escrituras seguidas espera el ACK de la primera. La especificación vigente de TCP recomienda implementar Nagle, pero exige que cada aplicación pueda desactivarlo en una conexión @rfc9293, opción que en la interfaz de _sockets_ se llama `TCP_NODELAY`.

*ACK retardado.* Del lado del receptor existe una optimización equivalente. En lugar de confirmar cada segmento apenas llega, el receptor puede esperar, hasta 500 ms según la especificación, para enviar el ACK junto con los datos de su respuesta y ahorrar un paquete @rfc1122. Si el temporizador vence antes de que haya una respuesta, el ACK sale solo. Cada mecanismo tiene sentido por separado, pero combinados pueden bloquearse entre sí como sucedió durante el experimento. 

*Sincronización de relojes con SNTP.* Para medir la latencia extremo a extremo, el nodo y el servidor tienen que compartir la hora. NTP (_Network Time Protocol_) sincroniza el reloj de un cliente con el de un servidor: el cliente envía una consulta, el servidor responde con su hora y, con las marcas de tiempo de envío y de recepción de ambos mensajes, el cliente estima el tiempo de viaje y lo descuenta @rfc5905. SNTP (_Simple Network Time Protocol_) es una versión reducida de NTP para dispositivos con pocos recursos, que omite los algoritmos con los que NTP filtra las mediciones y elige entre varios servidores @rfc5905.

==== Planteo

Ocho placas ESP32 emuladas envían telemetría periódica a un servidor por dos caminos: MQTT, a través de un broker, y HTTP, con un POST por lectura. El contenido de cada lectura es idéntico en ambos caminos y se serializa en JSON o en Protocol Buffers, lo que permite separar el efecto del transporte del de la serialización.

A diferencia del experimento de sincronización, el caso de uso es neutral: enviar lecturas de los nodos a un servidor es algo que ambas arquitecturas resuelven de forma razonable, sin que el modelo publicador/suscriptor le dé de antemano una ventaja a MQTT.

#subtitulo[Motivación]

Este experimento corresponde al último de los objetivos específicos (@sec-objetivos): medir el costo en bytes y en latencia de MQTT y Protocol Buffers frente a HTTPS y JSON, y su comportamiento ante pérdidas y latencia. También aporta datos al objetivo que analiza MQTT sobre la capa de transporte, en lo que respecta a TCP y TLS. En el marco teórico se planteó que MQTT envía mensajes más livianos y con menor latencia que HTTP, por su encabezado fijo de dos bytes y su conexión persistente, y que Protocol Buffers produce mensajes más chicos que JSON, por su codificación binaria. Esas ventajas surgen de comparaciones cualitativas y de estudios con otros mensajes y plataformas. El experimento las mide sobre un mismo sistema. Para atribuir cada parte de la diferencia a su causa, incluye dos variantes de HTTP, corridas con y sin TLS y las dos serializaciones.

#subtitulo[Fundamento]

La diferencia principal entre ambos caminos no está en el contenido de la lectura, sino en cómo cada protocolo usa la conexión TCP (@tab-fundamento).

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    table.header[Aspecto][MQTT][HTTP],
    [Conexión], [Una conexión TCP persistente por nodo], [Una conexión por lectura, o una reutilizada para varias],
    [Handshake TLS], [Una vez, al conectar], [En cada conexión nueva],
    [Encabezado por mensaje], [Binario: 2 bytes fijos, más el tópico], [Línea de solicitud y headers en texto],
    [Respuesta], [Ninguna con QoS 0; PUBACK con QoS 1], [Siempre una respuesta HTTP],
    [Garantía de entrega], [QoS 0, 1 o 2, definidos por el protocolo], [La de TCP, más los reintentos que implemente la aplicación],
    [Iniciativa], [El servidor puede enviar al nodo por la misma conexión], [Solo el cliente inicia],
  ),
  caption: [Diferencias entre MQTT y HTTP en el uso de la conexión.],
) <tab-fundamento>

Por eso se prueban dos variantes de HTTP: una conexión nueva por lectura y una conexión reutilizada. La segunda es la comparación justa con MQTT; la primera representa el peor caso, el de un dispositivo que duerme entre envíos y abre una conexión cada vez.

#subtitulo[Preguntas de investigación]

+ ¿Cuántos bytes cuesta enviar una lectura por MQTT y por HTTPS, contando cabeceras y handshakes?
+ ¿Cómo se comparan la latencia extremo a extremo y la tasa de entrega de ambos?
+ ¿Cómo se degradan ambos protocolos con pérdida y latencia en la red?
+ ¿Qué parte de la diferencia viene de la conexión persistente y qué parte de TLS?
+ ¿Cuánto cambia el costo al pasar de JSON a Protocol Buffers en cada transporte?

#subtitulo[Hipótesis]

Antes de las corridas se formularon las siguientes hipótesis, que se contrastan con los resultados al final del análisis (@tab-hipotesis):

- MQTT envía menos bytes por lectura que HTTPS, y la diferencia crece cuando el período de envío es corto.
- HTTPS con conexión reutilizada reduce gran parte de la diferencia, pero los headers HTTP siguen pesando más que la cabecera MQTT.
- HTTPS con una conexión por request es el caso más costoso, sobre todo con TLS y latencia alta, porque cada handshake suma idas y vueltas.
- Con pérdida, MQTT QoS 1 mantiene la entrega a costa de duplicados, mientras que MQTT QoS 0 pierde lecturas.
- Protobuf reduce el payload en ambos caminos, pero su efecto sobre el total es mayor en MQTT, donde el payload es la mayor parte del mensaje. En HTTPS, los headers diluyen el ahorro.

==== Implementación

#subtitulo[Arquitectura]

Cada nodo es un ESP32 emulado con el QEMU de Espressif que ejecuta un firmware real, escrito en C con ESP-IDF. Por eso los bytes que se miden son los que producen las bibliotecas que usaría una placa física, sin modificaciones: la pila TCP/IP lwIP, mbedTLS para TLS, esp-mqtt como cliente MQTT y `esp_http_client` como cliente HTTP. Como QEMU no emula WiFi, cada nodo usa una placa Ethernet emulada.

Cada instancia de QEMU se conecta a una interfaz TAP propia, y todas las interfaces se unen en un puente (_bridge_) de Linux en la computadora anfitriona, que tiene la dirección del servidor (`10.10.0.1`); los nodos usan las direcciones `10.10.0.11` en adelante. Se eligió este esquema, y no la red de usuario de QEMU, por dos motivos. La red de usuario termina las conexiones TCP del nodo dentro del propio emulador, de modo que la red no vería los paquetes tal como los arma el ESP32. Además, una interfaz por nodo permite degradar cada enlace por separado. Sobre cada interfaz se aplica `tc netem` en ambos sentidos para inyectar pérdida y latencia, y `dumpcap` captura en el puente todo el tráfico de la corrida (@fig-arq-telemetria).

Del lado del servidor hay dos procesos: el broker Mosquitto y un backend escrito en Go. El backend atiende `POST /tel/{esp}` por HTTP (puerto 80) y por HTTPS (puerto 443) y responde `204 No Content`. Además, está suscripto al broker en el tópico `exp/tel/+` por una conexión local que no pasa por el puente y, por lo tanto, no entra en la captura. Las lecturas de ambos caminos terminan en la misma función de registro, que anota la hora de llegada, de modo que la latencia se calcula igual para los dos. El backend también funciona como servidor SNTP, para que los nodos sincronicen su reloj con el de la computadora anfitriona.

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

Codificado con Protocol Buffers, el mensaje ocupa entre 16 y 19 bytes (18 en promedio), porque `seq` es un entero de longitud variable. En JSON, con los mismos nombres de campo y sin espacios, ocupa unos 72 bytes, cuatro veces más:

```json
{"esp_id":3,"seq":142,"t_us":1793041765379595,"value":23.4567,"status":0}
```

La lectura se envía por uno de los cuatro caminos de la @tab-transportes. En HTTP, el formato se indica en el header `Content-Type` (`application/x-protobuf` o `application/json`).

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

Los cuatro caminos se corrieron con y sin TLS. Con TLS se usó la misma configuración en el broker y en el backend: TLS 1.2 @rfc5246 con la suite `ECDHE-ECDSA-AES128-GCM-SHA256`, el mismo certificado ECDSA P-256 firmado por una autoridad de certificación propia, que el nodo verifica, y sin reanudación de sesión. El cliente MQTT de ESP-IDF implementa MQTT 3.1.1 @mqtt311, y no la versión 5.0. Para este experimento la diferencia es menor, porque el encabezado fijo es el mismo en ambas versiones y la 5.0 solo agrega a cada PUBLISH un byte con la longitud de sus propiedades.

#subtitulo[Firmware]

En cada nodo, una tarea productora crea una lectura por período con la hora sincronizada (`t_us`) y la encola, y otra tarea, la emisora, la saca de la cola, la serializa y la envía. Separar la creación del envío hace que el tiempo que una lectura espera en la cola, por ejemplo mientras el emisor está bloqueado en un handshake o en una retransmisión, quede incluido en la latencia medida.

Se dejaron los valores por defecto de las bibliotecas, que son los que tendría un ESP32 sin ajustes. En MQTT, el keep-alive es de 60 s y un PUBLISH de QoS 1 se reenvía si su PUBACK no llega en 1 s. En HTTP, cada envío tiene hasta tres intentos con un tiempo de espera de 5 s, y el algoritmo de Nagle (@sec-conceptos-exp1) está activo. El cliente MQTT abre la conexión antes de que empiece la medición, mientras que el cliente HTTP la abre recién al enviar la primera lectura.

La configuración de cada nodo (transporte, TLS, período y serialización) se lee de una partición de la memoria _flash_, de modo que el firmware se compila una sola vez para todas las corridas.

#subtitulo[Diseño de las corridas]

Se tomó una configuración base: 8 nodos, período de envío de 1 s, TLS activado, sin pérdida ni latencia agregadas y serialización con Protocol Buffers. A partir de ella se varió un factor a la vez (@tab-factores-telemetria) para cada uno de los cuatro transportes. Cada configuración se repitió cinco veces, con corridas de 120 s y en orden aleatorio con semilla fija. En total fueron 42 configuraciones y 210 corridas, que llevaron 7 h 40 min.

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

La pérdida se aplica en cada sentido por separado, de forma aleatoria e independiente por paquete. La latencia se expresa como RTT agregado: la mitad se agrega en cada sentido, como un retardo fijo.

HTTP con una conexión por lectura se corrió con un período base de 10 s en lugar de 1 s. Con criptografía emulada, cada handshake TLS tarda entre 3 y 5 s, de modo que con un período de 1 s la cola del nodo crece sin límite y solo se entrega cerca del 27 % de las lecturas. Por eso, cuando se comparan los cuatro caminos en la base, ese camino aparece con 10 s, y se lo compara además con las corridas de 10 s de los otros tres.

Además, para verificar la explicación de la latencia de HTTP, se corrió una matriz complementaria con el algoritmo de Nagle activo y desactivado, que se presenta en el análisis (@tab-nagle).

#subtitulo[Métricas]

Los bytes se miden en la red y no en la aplicación, para incluir todo lo que agregan TCP, TLS y cada protocolo (@tab-metricas-telemetria).

#figure(
  table(
    columns: (auto, 1fr),
    table.header[Métrica][Cómo se calcula],
    [Bytes por lectura], [Bytes de los paquetes IP del puerto del servidor en la captura, divididos por las lecturas entregadas. Incluyen encabezados TCP/IP y TLS, ACK, handshakes, cierres y retransmisiones],
    [Paquetes por lectura], [Paquetes de la captura divididos por las lecturas entregadas],
    [Bytes de handshake], [Bytes de cada conexión antes del primer dato de aplicación],
    [Latencia extremo a extremo], [Hora de llegada al servidor menos `t_us`, de la primera llegada de cada lectura (mediana y percentiles 95 y 99)],
    [Tasa de entrega], [Lecturas distintas recibidas sobre lecturas producidas],
    [Duplicados], [Lecturas recibidas más de una vez],
    [Retransmisiones], [Segmentos TCP retransmitidos en la captura],
    [Factor de tiempo real], [Avance del reloj del nodo sobre avance del reloj de la computadora anfitriona],
  ),
  caption: [Métricas del experimento.],
) <tab-metricas-telemetria>

#subtitulo[Entorno y validez]

La @tab-entorno-telemetria resume el entorno en el que se corrió el experimento.

#figure(
  table(
    columns: (auto, 1fr),
    table.header[Componente][Versión],
    [Computadora anfitriona], [AMD Ryzen 7 5700U (8 núcleos, 16 hilos), 14 GB de RAM, Linux],
    [Emulador], [QEMU de Espressif 9.2.2],
    [Firmware], [ESP-IDF 5.5.6 (lwIP, mbedTLS, esp-mqtt, `esp_http_client`) y nanopb 0.4.9.1],
    [Broker], [Mosquitto 2.1.2],
    [Backend y análisis], [Go 1.27.3 y TShark 4.7.4],
  ),
  caption: [Entorno del experimento.],
) <tab-entorno-telemetria>

Las 210 corridas resultaron válidas, el factor de tiempo real mínimo fue 1,000 en todas, ningún nodo se atrasó al producir lecturas, no quedaron lecturas sin enviar ni se descartaron lecturas de la cola, y no hubo desconexiones de MQTT. Dos corridas fallaron antes de empezar a medir, porque un nodo no logró sincronizar su reloj con 5 % de pérdida. Se amplió el tiempo de espera de la sincronización de 30 s a 90 s y se repitieron. Ese cambio solo afecta el arranque del nodo, antes de que empiece la medición.

Para calcular la latencia, a la hora de llegada, tomada del reloj del servidor, se le resta la hora de creación de la lectura, tomada del reloj del nodo. Ambos relojes se sincronizan por SNTP (@sec-conceptos-exp1), pero el cliente SNTP de lwIP no descuenta el tiempo de viaje de la respuesta del servidor, así que el reloj del nodo queda atrasado medio RTT y cada latencia medida resulta medio RTT más larga. Sin latencia agregada, ese error es de alrededor de 1 ms. Con latencia agregada, el error crece a la mitad del RTT agregado, pero como netem agrega un retardo fijo se lo puede descontar: a cada latencia medida se le restó RTT/2.

==== Resultados

Se presentan la media y el desvío estándar de las cinco repeticiones de cada configuración. Salvo que se indique otra cosa, los valores corresponden a la configuración base con TLS. La entrega fue del 100 % en las 210 corridas.

#subtitulo[Bytes y paquetes por lectura]

La @tab-bytes y la @fig-bytes muestran el costo de una lectura en cada camino. Todas las diferencias entre transportes resultaron significativas (prueba de Welch, _p_ < $10^(-4)$), y los intervalos de confianza del 95 % son estrechos, por ejemplo 165,2 ± 0,1 B en MQTT QoS 0, salvo en HTTP con una conexión por lectura (2596 ± 298B).

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

#figure(
  fig-exp1("01_bytes_por_lectura_tls.png", width: 65%),
  caption: [Bytes IP por lectura con y sin TLS (8 nodos, Protocol Buffers).],
) <fig-bytes>

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

#figure(
  fig-exp1("09_cdf_latencia_base.png", width: 65%),
  caption: [Distribución acumulada de la latencia en la configuración base (escala logarítmica).],
) <fig-cdf-base>

La @tab-latencia-base y la @fig-cdf-base muestran tres grupos separados por un orden de magnitud:

- MQTT tuvo una mediana de unos 3 ms con QoS 0 y con QoS 1, y la diferencia entre ambos no resultó significativa (_p_ = 0,06).
- HTTP con conexión reutilizada tuvo una mediana de 44,8 ms y una cola larga en el percentil 99. Esa cola se concentra en las primeras lecturas de cada nodo: la primera tardó 3,6 s en promedio, contra 21 ms en MQTT, y desde la décima lectura en adelante el p99 bajó a 48 ms.
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

La @tab-tls compara cada camino con y sin TLS. En las conexiones persistentes, TLS sumó entre 46 y 97 B por lectura y menos de 0,6 ms de latencia. En HTTP con una conexión por lectura triplicó los bytes y sumó 3,4 s de latencia.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    table.header[Transporte][Δ bytes por lectura][Δ relativo][Δ latencia p50][Handshake por conexión],
    [MQTT QoS 0], [+46,5 B], [+39 %], [+0,39 ms], [128 → 1966 B],
    [MQTT QoS 1], [+75,6 B], [+47 %], [+0,38 ms], [128 → 1967 B],
    [HTTP, conexión reutilizada], [+97,3 B], [+21 %], [+0,54 ms], [128 → 1525 B],
    [HTTP, conexión por lectura], [+1555 B], [× 3,1], [+3373 ms], [128 → 1525 B],
  ),
  caption: [Lo que agrega TLS a cada camino. En HTTP con una conexión por lectura se usan las corridas sin retransmisiones innecesarias (ver el análisis).],
) <tab-tls>

#subtitulo[Serialización]

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto),
    table.header[Transporte][Payload Protobuf][Payload JSON][Bytes por lectura (Protobuf)][Bytes por lectura (JSON)][Δ],
    [MQTT QoS 0], [18,0 B], [72,1 B], [165,2], [219,4], [+54,2 B (+32,8 %)],
    [MQTT QoS 1], [18,0 B], [72,1 B], [237,7], [291,9], [+54,2 B (+22,8 %)],
    [HTTP, conexión reutilizada], [18,0 B], [72,1 B], [555,0], [603,2], [+48,2 B (+8,7 %)],
    [HTTP, conexión por lectura], [17,8 B], [71,2 B], [2296,6], [2357,7], [+61 B (+2,7 %)],
  ),
  caption: [Protocol Buffers contra JSON (TLS). En HTTP con una conexión por lectura se usan las corridas sin retransmisiones innecesarias.],
) <tab-serializacion>

JSON resultó cuatro veces más grande que Protocol Buffers para este mensaje y agregó unos 54 B por lectura en todos los caminos (@tab-serializacion). La latencia no cambió.

#subtitulo[Cantidad de nodos y período de envío]

Con 2, 4 y 8 nodos, los bytes, los paquetes y la latencia por lectura no cambiaron (por ejemplo, 165,1, 165,2 y 165,2 B en MQTT QoS 0). Lo único que creció fue la duración de los handshakes: de 3,01 a 3,32 s en HTTP con una conexión por lectura y de 3,14 a 3,76 s en MQTT QoS 0.

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
    [Nodo → servidor], [POST y headers], [203], [134 B de HTTP],
    [Servidor → nodo], [ACK], [40], [Llega 40 ms después (ACK retardado de Linux)],
    [Nodo → servidor], [Cuerpo], [87], [18 B de Protocol Buffers, retenidos por Nagle hasta el ACK anterior],
    [Servidor → nodo], [ACK], [40], [Solo encabezados TCP/IP],
    [Servidor → nodo], [`204 No Content`], [133], [64 B de HTTP],
    [Nodo → servidor], [ACK], [40], [Sale solo, unos 230 ms después (ACK retardado de lwIP)],
  ),
  caption: [Paquetes de una lectura en régimen estable, con TLS.],
) <tab-anatomia>

HTTP con una conexión por lectura abre y cierra una conexión completa en cada lectura, con unos 22 paquetes: el handshake TCP (3 paquetes, 128 B), el handshake TLS 1.2 (unos 1525 B, de los cuales 655 B son el certificado y los demás mensajes del servidor), el POST con su cuerpo, la respuesta, el cierre de TLS y el cierre de TCP. Sin TLS son 12 paquetes y 742 B.

El encabezado de MQTT es tan chico como plantea el marco teórico. El PUBLISH ocupa 31 bytes: 2 del encabezado fijo, 2 de la longitud del tópico, 9 del tópico `exp/tel/3` y 18 de la lectura. La sobrecarga de MQTT por mensaje es entonces de 13 bytes, contra 134 bytes de la línea de solicitud y los headers de HTTP (153 con una conexión por lectura, que agrega `Connection: close`), unas diez veces menos. Además, MQTT QoS 0 no tiene respuesta de aplicación, mientras que HTTP siempre responde (64 B).

Sin embargo, en una lectura de MQTT los encabezados de capa de aplicación no son lo que más pesa. Cada registro TLS agrega 29 bytes (5 de cabecera, 8 del _nonce_ explícito y 16 de la etiqueta de autenticación de AES-GCM) y cada paquete, 40 bytes de TCP/IP. En MQTT QoS 0 con TLS, el payload es solo el 11 % de los bytes de la lectura, y en HTTP con una conexión por lectura, menos del 1 % (@fig-composicion).

#figure(
  fig-exp1("02_composicion_bytes.png", width: 65%),
  caption: [Composición de los bytes de cada lectura: payload, encabezados (MQTT o HTTP, TCP/IP, TLS y ACK) y handshake amortizado.],
) <fig-composicion>

Los 29 bytes por registro explican casi todo lo que agrega TLS en las conexiones persistentes (@tab-tls). MQTT QoS 0 usa un registro por lectura (29 B), al que se suman 16 B del handshake repartido entre las lecturas, 45 B en total, y se midieron 46,5 B. MQTT QoS 1 usa dos registros, el PUBLISH y el PUBACK (74 B con el handshake; se midieron 75,6 B), y HTTP con conexión reutilizada usa tres, los headers, el cuerpo y la respuesta (100 B; se midieron 97 B). El cifrado simétrico casi no suma latencia: el costo de TLS en tiempo es el handshake, que solo se paga en cada lectura cuando no se reutiliza la conexión.

#subtitulo[Costo fijo por conexión y costo por lectura]

En los caminos con conexión persistente, lo que cambia con el período es cuántas lecturas viajan por la misma conexión. Si $n$ es la cantidad de lecturas por conexión, los bytes por lectura se ajustan a un modelo de dos términos:

$ b(n) = v + C / n $ <ec-costo>

donde $v$ es el costo de cada lectura y $C$ el costo fijo de abrir y cerrar la conexión, que se reparte entre las $n$ lecturas. El ajuste sobre las corridas con distintos períodos, con TLS, dio un $R^2$ entre 0,97 y 1,00 (@tab-costo y @fig-costo).

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

#figure(
  fig-exp1("13_modelo_costo.png", width: 62%),
  caption: [Modelo de costo fijo por conexión y costo por lectura. Los puntos son las mediciones con períodos de 10 s, 1 s y 100 ms; las curvas, el ajuste.],
) <fig-costo>

El valor de $v$ coincide con la anatomía de una lectura: los 140 B de MQTT QoS 0 son exactamente el PUBLISH (100 B) y su ACK (40 B). El valor de $C$ corresponde al handshake TCP y TLS, más el inicio y el cierre de la sesión. El $C$ de MQTT es unos 1250 B mayor que el de HTTP por dos razones: Mosquitto envía, junto con el certificado del servidor, el de la autoridad de certificación (856 B de certificados contra 445 B del backend en Go), y MQTT agrega el intercambio de CONNECT y CONNACK al abrir la sesión.

En consecuencia, MQTT tiene el costo por lectura más bajo pero el costo fijo más alto, y su ventaja depende de cuánto dure la conexión. Igualando los modelos, MQTT QoS 0 envía menos bytes que HTTP con conexión reutilizada mientras la conexión lleve más de tres o cuatro lecturas. Con una sola lectura por conexión, el modelo da unos 3160 B para MQTT, más que los 2296 B de un POST por HTTPS, aunque eso es una extrapolación fuera del rango medido (entre 12 y 1200 lecturas por conexión). Para un nodo que duerme y se reconecta en cada envío, la ventaja de MQTT desaparece, salvo que se use reanudación de sesión TLS, que en este experimento estuvo desactivada en ambos caminos.

#subtitulo[Qué explica la diferencia]

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

Con TLS, la conexión persistente explica cuatro quintos de la diferencia, porque evita un handshake de 1525 B en cada lectura. El protocolo de aplicación (headers, respuesta obligatoria y ACK adicionales) explica el 18 % restante. Sin TLS, el handshake TCP pesa mucho menos y la diferencia se reparte casi por mitades entre la conexión y el protocolo. Es decir, el factor más pesado no es el protocolo de aplicación en sí, sino la decisión de mantener la conexión abierta. A eso se suma una parte que no es del protocolo ni de la conexión, sino de cómo el cliente HTTP usa TCP, que se analiza a continuación.

#subtitulo[Nagle y ACK retardado]

Los dos mecanismos de TCP presentados en la @sec-conceptos-exp1, el algoritmo de Nagle y el ACK retardado, explican buena parte de la latencia de HTTP y varios efectos secundarios observados en el experimento.

*Bloqueo en HTTP con conexión reutilizada.* `esp_http_client` escribe cada solicitud con dos llamadas a `send()`: primero la línea de solicitud con los headers y después el cuerpo, y cada llamada sale como un segmento TCP distinto. La @fig-nagle muestra la secuencia medida en una lectura:

+ Los headers salen y quedan sin confirmar, así que Nagle retiene el cuerpo (18 B) en el ESP32 hasta recibir su ACK.
+ El servidor Linux detecta una conexión de ida y vuelta, en la que contesta cada solicitud, y demora el ACK hasta 40 ms para enviarlo junto con la respuesta. Pero no puede responder, porque todavía no recibió el cuerpo.
+ Cada lado espera al otro, y el bloqueo se rompe recién cuando vence el temporizador de 40 ms del servidor: llega el ACK, Nagle libera el cuerpo y el servidor responde.

#figure(
  chronos.diagram({
    import chronos: *
    _par("E", display-name: "ESP32 (lwIP)", show-bottom: false)
    _par("S", display-name: "Servidor (Linux)", show-bottom: false)
    _seq("E", "S", comment: [0 ms: POST y headers (134 B)])
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

La espera medida entre los headers y el cuerpo fue de 41,5 ms sin TLS y de 41,7 ms con TLS. Con TLS ocurre lo mismo porque mbedTLS cifra cada `send()` en su propio registro, de modo que también salen dos segmentos. Esa espera explica casi toda la mediana de 44,8 ms de HTTP con conexión reutilizada (@tab-latencia-base).

*El mismo bloqueo dentro del handshake TLS.* HTTP con una conexión por lectura sin TLS no sufre la espera: Linux confirma de inmediato los primeros segmentos de una conexión nueva (modo _quickack_), y en la captura el ACK a los headers llega en 44 µs. Con TLS, en cambio, los segmentos del handshake agotan ese modo y la espera aparece dos veces por conexión. La primera es dentro del handshake, porque el ESP32 envía el _Client Key Exchange_ y luego el _Change Cipher Spec_ con el _Finished_ en dos escrituras. La segunda es entre los headers y el cuerpo del POST. Esos 80 ms quedan ocultos detrás de los 3,4 s del handshake con criptografía emulada.

*Prueba con Nagle desactivado.* Para verificar la explicación se corrió una matriz complementaria de 2 × 2 (Nagle activo o desactivado, con y sin TLS) para los dos caminos HTTP, con la configuración base y tres repeticiones. Con Nagle desactivado, el firmware pone `TCP_NODELAY` en el _socket_ apenas se abre la conexión. La @tab-nagle resume los resultados:

- En HTTP con conexión reutilizada, la latencia bajó unas diez veces, de 44 ms a entre 4 y 5 ms, con y sin TLS. Los 40 ms que desaparecen son el ACK retardado del servidor.
- Los bytes bajaron unos 40 B por lectura y hubo un paquete menos: sin la espera, el ACK del servidor a los headers viaja junto con la respuesta. El cuerpo siguió en su propio segmento, porque siguen siendo dos `send()`.
- HTTP con una conexión por lectura sin TLS no cambió (741,8 B en los dos casos), porque no sufría la espera.
- HTTP con una conexión por lectura con TLS ahorró un paquete y unos 35 B por conexión, pero la espera dentro del handshake no desapareció. El cliente HTTP avisa que la conexión está abierta recién cuando terminó el handshake, y `esp_http_client` no ofrece un punto anterior para configurar el _socket_ sin modificar la biblioteca de TLS. La diferencia de latencia, de unos 120 ms, quedó dentro del ruido del handshake emulado.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto),
    table.header[Transporte][TLS][Nagle][p50 (ms)][p95 (ms)][Bytes por lectura][Paquetes por lectura],
    table.cell(rowspan: 4)[HTTP, conexión reutilizada], [No], [Activo], [44,29 ± 0,07], [46,65 ± 0,04], [457,9], [6,03],
    [No], [*Desactivado*], [*4,19 ± 0,05*], [*7,17 ± 0,23*], [*418,3*], [*5,04*],
    [Sí], [Activo], [44,74 ± 0,10], [48,48 ± 0,62], [555,2 ± 0,2], [6,08],
    [Sí], [*Desactivado*], [*5,02 ± 0,05*], [*8,85 ± 0,49*], [*515,0 ± 0,5*], [*5,08*],
    table.cell(rowspan: 4)[HTTP, conexión por lectura], [No], [Activo], [9,77 ± 0,15], [59,37 ± 1,73], [741,8], [12,00],
    [No], [Desactivado], [10,13 ± 0,22], [62,11 ± 3,34], [741,8], [12,00],
    [Sí], [Activo], [3422 ± 146], [4064 ± 278], [2927,7 ± 8,9], [22,92],
    [Sí], [Desactivado], [3304 ± 76], [3765 ± 198], [2892,6 ± 0,6], [21,93],
  ),
  caption: [Prueba con el algoritmo de Nagle activo y desactivado (`TCP_NODELAY`): 8 nodos, 120 s, tres repeticiones, período de 1 s (10 s con una conexión por lectura). La entrega fue del 100 % en todos los casos.],
) <tab-nagle>

*Latencia de la red: la penalidad de Nagle crece con el RTT.* MQTT pagó medio RTT por lectura (@tab-rtt), el mínimo posible: el PUBLISH sale y llega sin esperar nada. En HTTP, en cambio, el ACK de los headers tarda un RTT completo en volver, y el cuerpo espera ese tiempo además de los 40 ms del ACK retardado. Por eso HTTP con conexión reutilizada pagó 1,5 RTT por lectura: medio RTT del viaje de ida y un RTT de la espera de Nagle. HTTP con una conexión por lectura con TLS pagó unos 5,5 RTT antes de que el cuerpo llegara al servidor: uno del handshake TCP, dos del handshake TLS 1.2, uno de la espera de Nagle dentro del handshake, medio de los headers y uno de la espera entre headers y cuerpo. Se midieron 5,3 RTT con 200 ms de RTT agregado; con 50 ms dio 6,9 RTT, pero su desvío, de 100 a 160 ms, es del orden de lo que se mide. Sin Nagle serían 3,5 RTT, y con TLS 1.3, que ahorra un RTT en el handshake @rfc8446, 2,5. El tiempo de conexión, en cambio, subió solo entre dos y tres RTT, poco frente a los 3,3 s de la criptografía emulada.

*El ACK retardado del ESP32 y las retransmisiones innecesarias.* El ESP32 tampoco confirma enseguida: lwIP demora el ACK hasta su temporizador rápido, de unos 250 ms. Como en ese momento el nodo no tiene más datos para enviar, el ACK sale solo y suma un paquete por lectura en HTTP con conexión reutilizada y en MQTT QoS 1 (@tab-anatomia). Con un período de 100 ms, ese ACK viaja dentro del mensaje siguiente, y los paquetes por lectura bajan de 6,08 a 5,25 en HTTP y de 3,19 a 2,43 en QoS 1. Esto también explica que el ajuste de la @ec-costo sea algo peor en esos dos caminos.

Esa demora tiene un segundo efecto. Linux retransmite un segmento si no recibe su ACK dentro del tiempo de retransmisión (RTO), que calcula a partir del RTT medido y que nunca baja de 200 ms, aunque la especificación recomienda un mínimo de 1 s @rfc6298. Si el ACK del ESP32 tarda más que ese RTO, el servidor retransmite datos que no se perdieron. Ocurrió en dos casos:

- En la primera respuesta de cada conexión de HTTP con conexión reutilizada. El servidor solo conoce el RTT del handshake, de pocos milisegundos, así que usa el mínimo de 200 ms, menor que los 230 ms que tarda el ACK del ESP32. Después ajusta su estimación y no se repite.
- En el handshake TLS de HTTP con una conexión por lectura. El ESP32 recibe el certificado y los demás mensajes del servidor (692 B) y pasa unos 3 s calculando su parte del handshake. Su ACK sale con el temporizador de lwIP, y si el RTO del servidor es menor, el servidor retransmite ese bloque completo.

El segundo caso explica toda la variabilidad de HTTP con una conexión por lectura (2596 ± 298 B por lectura): los bytes de cada corrida siguen exactamente la cantidad de retransmisiones (correlación de 1,000), a razón de 692 B por retransmisión. Por corrida hubo 0, unas 43 o unas 87 retransmisiones, es decir, el fenómeno ocurrió en casi todas las conexiones de una corrida o en ninguna. La causa más probable es que Linux guarda métricas TCP por destino, como el RTT y su variación, entre conexiones: un RTT alto heredado de una corrida anterior eleva el RTO inicial por encima de la demora del ESP32 y evita la retransmisión. Eso explica que con 50 y 200 ms de RTT agregado nunca hubo retransmisiones (2296 ± 1 B), mientras que sin latencia agregada el resultado dependió de qué corrida se había ejecutado antes. Esta explicación no se aisló con un experimento aparte. Por eso, en el análisis se toma como valor de referencia de HTTP con una conexión por lectura el de 2296 B, que no incluye retransmisiones innecesarias.

*Por qué MQTT no sufre el bloqueo.* esp-mqtt arma cada PUBLISH completo en un _buffer_ y lo escribe con un solo `send()`, así que cada lectura es un único segmento y Nagle no tiene nada que retener. Además, con QoS 0 el broker nunca responde, no detecta una conexión de ida y vuelta y confirma enseguida; con QoS 1, el ACK viaja dentro del PUBACK.

*Nagle con pérdida: por qué QoS 1 tuvo mejor cola que QoS 0.* MQTT sí se ve afectado por Nagle cuando se pierde un ACK. Con QoS 0, el broker solo envía ACK sin datos. Si uno se pierde, el ESP32 no lo sabe hasta que vence su propio RTO, de al menos 1 s, y mientras tanto Nagle retiene la lectura siguiente, porque hay datos sin confirmar. En las capturas con 5 % de pérdida, el ESP32 reenvió en promedio 54 segmentos por corrida que ya habían llegado al servidor con QoS 0, contra 4,6 con QoS 1, lo que coincide con perder el 5 % de los 960 ACK que bajan en una corrida. Con QoS 1, el ACK viaja dentro del PUBACK, que lleva datos: si se pierde, lo retransmite Linux con su RTO de unos 200 ms, mucho antes que lwIP. Por eso, con 5 % de pérdida, el p99 de QoS 1 fue de 1,7 s contra 3,0 s de QoS 0, aunque la diferencia en el p95 no resultó significativa (_p_ = 0,16).

En síntesis, parte de la diferencia entre HTTP y MQTT no se debe al protocolo de aplicación, sino a cómo cada cliente usa TCP. El mismo HTTP cambia su latencia en un orden de magnitud según cómo el cliente reparte los datos en llamadas a `send()`: con Nagle desactivado, HTTP con conexión reutilizada baja a 5 ms, del mismo orden que MQTT, aunque sigue enviando 3,1 veces más bytes (515 B contra 165 B). En el experimento principal se mantuvo el comportamiento por defecto, con Nagle activo, porque es el que tendría un ESP32 sin ajustes.

#subtitulo[Pérdida de paquetes]

Con hasta 5 % de pérdida no se perdió ninguna lectura, porque TCP retransmitió cada segmento perdido y ninguna conexión se cortó. MQTT QoS 0 solo perdería lecturas si se cortara la conexión, por ejemplo al vencer el keep-alive, por un _reset_ o porque el nodo se reconecta a la red, y eso no ocurrió con pérdidas aleatorias en corridas de 120 s. En estas condiciones, QoS 1 no mejoró la entrega y solo agregó duplicados: esp-mqtt reenvía el PUBLISH si el PUBACK no llega en 1 s, aunque TCP todavía esté recuperando el segmento original. Es lo que se plantea en la @sec-qos-tcp: mientras la conexión se mantiene, la confiabilidad la aporta TCP, y la ventaja de QoS 1 aparece cuando la conexión se corta.

Lo que se degradó fue la cola de la latencia, y la @fig-cdf-perdida muestra escalones en valores fijos:

- Entre 1 y 1,5 s, el RTO de lwIP: un segmento perdido se recupera recién cuando vence el temporizador de retransmisión, que lwIP maneja con un reloj de 500 ms. No hay retransmisión rápida, porque requiere tres ACK duplicados y con una lectura por segundo nunca hay tantos segmentos en vuelo.
- Entre 0,05 y 0,5 s, el bloqueo de cabeza de línea: la lectura que sigue a una perdida sale 1 s después y queda retenida hasta que la anterior se recupera. Por eso las lecturas lentas vienen de a pares.
- Por encima de 2 s, pérdidas repetidas del mismo segmento, con el RTO duplicado en cada intento @rfc6298.

HTTP salió peor por su esquema de solicitud y respuesta en serie. Cualquier paquete perdido, en cualquier sentido, frena el envío hasta que se recupera, y las lecturas siguientes esperan en la cola. Además, cada lectura usa 6 paquetes (22 con una conexión por lectura), contra 2 o 3 de MQTT, así que tiene más chances de perder alguno. La diferencia entre QoS 0 y QoS 1 se debe a la combinación de Nagle con los ACK perdidos, descrita en el apartado anterior.

El costo en bytes de la pérdida fue bajo, entre 1 % y 13 %. El mayor fue el de HTTP con una conexión por lectura, al que se suman las retransmisiones innecesarias del handshake.

#subtitulo[Serialización]

El ahorro de Protocol Buffers fue de unos 54 B por lectura en todos los caminos, porque el mensaje es el mismo. En HTTP fue 6 B menor, porque `application/json` es más corto que `application/x-protobuf` en el header `Content-Type`. La reducción del payload, del 75 %, está en línea con la de los estudios citados en el marco teórico @viotti2022 @friesel2021.

En términos relativos, en cambio, el efecto depende de cuánto pesa el resto de la lectura. JSON aumentó un 33 % los bytes de MQTT QoS 0, un 9 % los de HTTP con conexión reutilizada y un 3 % los de HTTP con una conexión por lectura. Esto confirma lo anticipado en el marco teórico: una vez que el transporte reduce sus encabezados al mínimo, la serialización pasa a tener un peso importante. Aun así, la elección del transporte pesa más: pasar de HTTP con conexión reutilizada a MQTT QoS 0 ahorra 390 B por lectura, más de siete veces lo que ahorra Protocol Buffers.

#subtitulo[Contraste de hipótesis]

La @tab-hipotesis contrasta las hipótesis del planteo con los resultados.

#figure(
  table(
    columns: (1fr, 1.6fr),
    table.header[Hipótesis][Resultado],
    [MQTT envía menos bytes por lectura que HTTPS, y la diferencia crece cuando el período de envío es corto.],
    [*Se confirma, con un matiz.* MQTT envió menos bytes en todos los casos medidos (12 lecturas por conexión o más), y su ventaja frente a HTTP con conexión reutilizada creció al acortar el período: 1,7 veces a 10 s, 3,4 a 1 s y 3,6 a 100 ms. Pero si la conexión dura menos de tres o cuatro lecturas, la relación se invierte (@tab-costo).],

    [HTTPS con conexión reutilizada reduce gran parte de la diferencia, pero los headers HTTP siguen pesando más que la cabecera MQTT.],
    [*Se confirma.* Reutilizar la conexión bajó HTTPS de 2296 a 555 B por lectura (−76 %), pero siguió costando 3,4 veces MQTT QoS 0, por los headers (134 B contra 13 B), la respuesta obligatoria y los ACK adicionales, a los que se suman 40 ms por la espera de Nagle.],

    [HTTPS con una conexión por request es el caso más costoso, sobre todo con TLS y latencia alta.],
    [*Se confirma.* Fue el más caro en bytes y en latencia, y el único que con 200 ms de RTT pagó unos 5,5 RTT por lectura.],

    [Con pérdida, MQTT QoS 1 mantiene la entrega a costa de duplicados, mientras que QoS 0 pierde lecturas.],
    [*Se confirma a medias.* QoS 1 generó duplicados (5,4 % de las lecturas con 5 % de pérdida), pero QoS 0 no perdió ninguna lectura: TCP recuperó todo porque ninguna conexión se cortó. QoS 1 sí tuvo mejor cola de latencia.],

    [Protobuf reduce el payload en ambos caminos, con efecto relativo mayor en MQTT, donde el payload es la mayor parte del mensaje.],
    [*Se confirma, aunque no por la razón prevista.* El ahorro absoluto fue el mismo en todos los caminos (unos 54 B) y el relativo fue mayor en MQTT (33 %), pero porque su lectura es más chica, no porque el payload sea la mayor parte del mensaje: es el 11 %.],
  ),
  caption: [Contraste de las hipótesis con los resultados.],
) <tab-hipotesis>

#subtitulo[Limitaciones]

- *Criptografía emulada.* Los handshakes TLS tardaron entre 3 y 3,8 s en QEMU, mucho más que en un ESP32 físico, por lo que los tiempos de conexión y la latencia de HTTP con una conexión por lectura deben leerse en términos relativos. Los bytes y los paquetes, en cambio, son los del firmware real.
- *Reloj.* Las latencias con RTT agregado se corrigieron restando RTT/2. Sin RTT agregado, la incertidumbre absoluta es de 1 ms, del orden de la latencia de MQTT, aunque no afecta las comparaciones entre transportes.
- *Estado compartido entre corridas.* Las métricas TCP que Linux guarda por destino afectaron las retransmisiones innecesarias, que solo pesan en HTTP con una conexión por lectura.
- *Un factor a la vez.* No se midieron interacciones entre factores, como pérdida y período o latencia y JSON, salvo la de Nagle y TLS.
- *Configuración concreta.* Otras configuraciones darían otros números, en especial para el costo fijo por conexión y la latencia de HTTP: Nagle activo en HTTP, Mosquitto enviando el certificado de la autoridad de certificación (411 B más por handshake), sin reanudación de sesión TLS, TLS 1.2 (TLS 1.3 ahorraría un RTT en el handshake y 7 B por registro), MQTT 3.1.1 y un cliente HTTP que abre la conexión en el primer envío.
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

Para un sistema de telemetría como el estudiado, los resultados sugieren cuatro criterios:

- Lo que más importa es mantener la conexión abierta. La ventaja de MQTT depende de que la conexión dure más que unas pocas lecturas; para dispositivos que duermen y se reconectan en cada envío, pesan más la reanudación de sesión TLS o TLS 1.3 que la elección del protocolo de aplicación.
- Si se usa HTTP, conviene reutilizar la conexión y desactivar Nagle, o escribir cada solicitud con una sola llamada a `send()`. Con eso la latencia queda en el mismo orden que la de MQTT, aunque el costo en bytes sigue siendo unas tres veces mayor.
- Mientras la conexión TCP se mantiene, QoS 1 no mejora la entrega y agrega duplicados, por lo que la aplicación debe poder descartarlos, por ejemplo con el número de secuencia. Su valor aparece ante cortes de conexión, que este experimento no midió.
- Protocol Buffers ahorra lo mismo en todos los transportes, pero su efecto relativo es mayor justamente en MQTT, donde el resto de la lectura ya es chico.

=== Experimento 2: sincronización de osciladores acoplados <sec-exp-sincronizacion>

La sincronización colectiva aparece cuando un conjunto de osciladores, cada uno con su propio ritmo, termina funcionando a una frecuencia común sin que nadie la imponga. Las diferencias entre las frecuencias naturales no desaparecen, pero la interacción alcanza para compensarlas. En biología se observa en las células marcapasos del corazón, en las células del núcleo supraquiasmático que regulan los ritmos circadianos, en suspensiones de levaduras, en las luciérnagas que destellan al unísono y en los grillos que cantan a la vez. En física e ingeniería aparece en arreglos de láseres, en osciladores de microondas y en uniones de Josephson @strogatz2000.

La idea del experimento es reproducir ese fenómeno con una red de nodos que se comportan como luciérnagas. Cada ESP32 ejecuta un único oscilador, con una frecuencia natural distinta a la de los demás: su fase avanza a su propio ritmo y cada vuelta completa equivale a un destello. Si los nodos no se comunican, cada uno destella a su frecuencia. Si cada uno conoce la fase de los otros y corrige la propia, a partir de cierto acoplamiento el grupo se engancha en un ritmo común, sin ningún nodo que actúe de coordinador.

Esa sincronía existe solo a través de los mensajes que intercambian los nodos, y por eso sirve para evaluar el stack. El modelo matemático predice cómo debería comportarse el grupo si la comunicación fuera ideal, de modo que la sincronización funciona como una carga de referencia con un comportamiento teórico conocido. Comparar esa predicción con lo que se mide en los nodos permite observar qué tan bien cumple el transporte con lo que la aplicación necesita.

La prueba se implementa sobre la plataforma común, con un oscilador por cada ESP32 emulada. Cada nodo integra periódicamente su fase, la serializa con Protocol Buffers junto con su identificador y una marca de tiempo, y la publica por MQTT en un tópico propio, por ejemplo `kuramoto/phase/7`. Además, se suscribe con un comodín a `kuramoto/phase/+`, de modo que recibe las fases de todos los demás a través del broker. Con esas fases calcula la corrección que aplica a su propia evolución, y el ciclo se repite.

Este esquema aprovecha las características del stack presentadas en el marco teórico. Es un intercambio de muchos a muchos: ningún nodo necesita conocer la dirección de los otros, y sumar uno nuevo no requiere modificar a los que ya están, porque el modelo publicador/suscriptor desacopla a quienes envían de quienes reciben. También exige mucho del broker, que entrega cada publicación a los otros $N - 1$ nodos, lo que da $N(N - 1)$ entregas por cada ronda de publicaciones. Como los mensajes son cortos y muy frecuentes, el tamaño reducido de la codificación binaria de Protocol Buffers y el encabezado pequeño de MQTT tienen un efecto directo sobre el tráfico total.

// TODO(rebase sobre master) Reemplazar las menciones al marco teórico por referencias: @sec-pubsub, @sec-mqtt, @sec-protobuf y @sec-ruteo-topicos (comodines).

==== Planteo

*El modelo.* El experimento se basa en el modelo de osciladores acoplados que propuso Kuramoto @kuramoto1975. Para presentarlo se sigue la revisión de Strogatz @strogatz2000, y para el caso de una cantidad finita de osciladores, el trabajo de Verwoerd y Mason @verwoerd2008. Cada oscilador se describe solo por su fase y está acoplado a todos los demás con el mismo peso. Tiene una frecuencia natural $omega_i$, que es fija, y una fase $theta_i$, que evoluciona según

$ dot(theta)_i = omega_i + K/N sum_(j=1)^N sin(theta_j - theta_i), quad i = 1, dots, N $ <ec-kuramoto>

donde $K$ es la intensidad del acoplamiento, en rad/s. El acoplamiento cambia la velocidad instantánea $dot(theta)_i$: si el oscilador $j$ va adelantado, $sin(theta_j - theta_i) > 0$ y el oscilador $i$ se acelera; si va atrasado, se frena.

*Parámetro de orden y campo medio.* El grado de sincronía se mide con el centroide de las fases sobre el círculo unitario:

$ r e^(i psi) = 1/N sum_(j=1)^N e^(i theta_j) $ <ec-orden>

$r$ vale 0 si las fases están dispersas y 1 si coinciden; $psi$ es la fase media @strogatz2000. La @fig-orden muestra ambas situaciones.

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
  caption: [Fases de ocho osciladores sobre el círculo unitario (círculos vacíos) y su centroide $r e^(i psi)$ (punto negro). A la izquierda, fases dispersas; a la derecha, fases agrupadas.],
) <fig-orden>

Si se multiplica la @ec-orden por $e^(-i theta_i)$ y se toma la parte imaginaria, resulta

$ r sin(psi - theta_i) = 1/N sum_(j=1)^N sin(theta_j - theta_i) $

Al reemplazar esa suma en la @ec-kuramoto se obtiene la forma de campo medio @strogatz2000, que vale para cualquier $N$:

$ dot(theta)_i = omega_i + K r sin(psi - theta_i) $ <ec-campo-medio>

Cada oscilador es atraído hacia la fase media con una fuerza $K r$. Es la forma que se implementa en los nodos. El promedio de fases tiene que ser circular: se suman los vectores $(cos theta_j, sin theta_j)$ y se toman el módulo y el ángulo de la suma. Promediar los ángulos directamente falla en el corte entre $2 pi$ y 0.

*Frecuencia común.* Para saber a qué frecuencia gira el grupo cuando se engancha, se suma la @ec-kuramoto sobre todos los osciladores:

$ sum_(i=1)^N dot(theta)_i = sum_(i=1)^N omega_i + K/N sum_(i=1)^N sum_(j=1)^N sin(theta_j - theta_i) $

La suma doble vale cero. Como el seno es impar, $sin(theta_j - theta_i) = -sin(theta_i - theta_j)$, de modo que el término del par $(i, j)$ se cancela con el del par $(j, i)$, y los términos con $i = j$ ya son nulos. Queda entonces

$ d/(d t) sum_(i=1)^N theta_i = sum_(i=1)^N omega_i $ <ec-suma-fases>

Esta relación vale siempre, haya o no enganche: el acoplamiento redistribuye las velocidades entre los osciladores, pero no cambia su suma. Si además todos están enganchados, $dot(theta)_i = Omega$ para todo $i$, y la @ec-suma-fases da $N Omega = sum_i omega_i$, es decir

$ Omega = overline(omega) = 1/N sum_(i=1)^N omega_i $ <ec-frecuencia-comun>

Verwoerd y Mason llegan al mismo resultado: en un estado enganchado, cada oscilador avanza a una velocidad constante igual a la media de las frecuencias naturales @verwoerd2008. Desde ahí se trabaja con las desintonías $Delta_i = omega_i - overline(omega)$.

*Límite de infinitos osciladores.* El primer resultado sobre el umbral de sincronización es el análisis de Kuramoto para $N -> infinity$, que se resume siguiendo a Strogatz @strogatz2000. Las desintonías se toman de una densidad $g(Delta)$ unimodal y simétrica, y se buscan soluciones estacionarias, con $r$ constante y $psi$ girando a velocidad uniforme. Si las fases se miden desde $psi$, la @ec-campo-medio se reduce a

$ dot(theta)_i = Delta_i - K r sin theta_i $

Según el valor de $Delta_i$, los osciladores se separan en dos grupos. Los que cumplen $|Delta_i| <= K r$ tienden a un punto fijo con $Delta_i = K r sin theta_i$ y $|theta_i| <= pi\/2$, y quedan enganchados. Los que tienen $|Delta_i| > K r$ no alcanzan ningún punto fijo y derivan alrededor del círculo.

El valor de $r$ tiene que ser coherente con estas dos poblaciones. La simetría de $g$ anula la contribución de los osciladores a la deriva al centroide, y también la parte imaginaria de la contribución de los enganchados. Solo queda el promedio de $cos theta$ sobre los enganchados, y con el cambio de variable $Delta = K r sin theta$ resulta

$ r = integral_(-K r)^(K r) cos theta(Delta) thin g(Delta) dif Delta = K r integral_(-pi\/2)^(pi\/2) cos^2 theta thin g(K r sin theta) dif theta $

Esta ecuación siempre admite la solución $r = 0$, que corresponde al estado incoherente. Las demás soluciones, con sincronización parcial, se obtienen dividiendo por $r$:

$ 1 = K integral_(-pi\/2)^(pi\/2) cos^2 theta thin g(K r sin theta) dif theta $ <ec-rama-parcial>

El acoplamiento crítico es el valor en el que esta rama nace desde $r = 0$. Al tomar $r -> 0^+$ en la @ec-rama-parcial, $g$ se evalúa en 0 y la integral de $cos^2 theta$ vale $pi\/2$, de modo que $1 = K_c g(0) pi\/2$, es decir

$ K_c = 2/(pi g(0)) $ <ec-kc-infinito>

Para una distribución de Lorentz de ancho $gamma$, $g(0) = 1\/(pi gamma)$, por lo que $K_c = 2 gamma$ y, por encima del umbral, $r = sqrt(1 - K_c\/K)$ @strogatz2000. Estas expresiones valen en el límite de infinitos osciladores. Con $N$ finito, $r$ fluctúa con una amplitud del orden de $N^(-1\/2)$ @strogatz2000. Por eso, en este trabajo la @ec-kc-infinito queda solo como contexto, y $K_c$ se calcula como se muestra a continuación.

*Umbral exacto con $N$ finito.* Verwoerd y Mason estudian el mismo modelo para una cantidad finita de osciladores @verwoerd2008, y definen el acoplamiento crítico como el menor $K$ para el que existe un estado enganchado. No es el mismo umbral que el de la @ec-kc-infinito: aquel marca el comienzo de la sincronización parcial, y este, el enganche de todos los osciladores.

En un estado enganchado, $dot(theta)_i = overline(omega)$ para todo $i$. Reemplazando en la @ec-campo-medio se obtiene

$ Delta_i = u sin(theta_i - psi), quad u = K r $

Por lo tanto, cada oscilador necesita $|Delta_i| <= u$. De la parte real de la @ec-orden, multiplicada por $e^(-i psi)$, sale $r = 1\/N sum_i cos(theta_i - psi)$, y cada coseno vale $plus.minus sqrt(1 - (Delta_i\/u)^2)$. Verwoerd y Mason demuestran que existe un estado enganchado si y solo si la ecuación resultante tiene solución con todos los signos positivos @verwoerd2008, lo que da la condición de autoconsistencia:

$ r = u/K = f(u) = 1/N sum_(i=1)^N sqrt(1 - (Delta_i/u)^2), quad u >= max_i |Delta_i| $ <ec-autoconsistencia>

Despejando, $K = u\/f(u)$, y el menor acoplamiento para el que hay solución es

$ K_c = min_(u >= max_i |Delta_i|) u/f(u) $ <ec-kc-finito>

Al derivar $u\/f(u)$ e igualar a cero, el mínimo queda en el valor $u^*$ que cumple

$ 2 dot 1/N sum_(i=1)^N sqrt(1 - (Delta_i/u^*)^2) = 1/N sum_(i=1)^N 1/sqrt(1 - (Delta_i/u^*)^2) $

Esa ecuación tiene una única solución @verwoerd2008, y entonces $K_c = u^* \/ f(u^*)$. El resultado garantiza que el estado enganchado existe, pero no que el sistema lo alcance desde cualquier condición inicial, porque el trabajo no aborda la estabilidad. Ese punto se comprueba con la simulación.

Con esto se calculan, para las frecuencias concretas de cada corrida, el umbral de enganche total, el $r$ final y el desfasaje de cada nodo. Con $N = 2$ se obtiene $K_c = |Delta omega|$.

*Enganche parcial y normalización.* Con $N >= 3$ y frecuencias asimétricas, puede engancharse un subgrupo mientras otro oscilador deriva. Este caso no tiene fórmula simple y se estudia por simulación, comparando las frecuencias efectivas de cada oscilador. Como el acoplamiento se divide por $N$, al agregar osciladores con el mismo $K$ cada interacción individual se debilita.

/* PENDIENTE: efectos de la red sobre el modelo. Queda fuera del documento hasta retomarlo.

Frases sacadas de los párrafos anteriores:
- Con retardo en el acoplamiento, la frecuencia común deja de ser igual a la media.
- Si cada nodo dividiera por la cantidad de fases recibidas en lugar de un $N$ fijo, el modelo cambiaría cuando se pierden mensajes; por eso conviene usar $N$ fijo.

*Efecto de la red: retardo.* En la red, cada nodo conoce las fases de los demás con un retardo $tau$:

$ dot(theta)_i = omega_i + K/N sum_(j != i) sin(theta_j (t - tau) - theta_i (t)) $ <ec-retardo>

La suma excluye $j = i$ porque cada nodo conoce su propia fase sin demora. Para osciladores idénticos, si se incluyera ese término propio, la frecuencia común cumpliría $Omega = omega - K sin(Omega tau)$, y el estado en fase sería estable si $K cos(Omega tau) > 0$. En la implementación ese término no existe.

*$N = 2$ con retardo.* Con $phi = theta_2 - theta_1$ y $Delta omega = omega_2 - omega_1$, el estado enganchado de la @ec-retardo cumple

$ Delta omega = K sin phi cos(Omega tau), quad Omega = overline(omega) - K/2 cos phi sin(Omega tau) $

La primera condición solo tiene solución si $K |cos(Omega tau)| >= |Delta omega|$. Aproximando $Omega approx overline(omega)$:

$ K_c (tau) approx (|Delta omega|)/(|cos(overline(omega) tau)|) $ <ec-kc-retardo>

Una simulación con $overline(omega) = 2 pi$ rad/s y $Delta omega =$ 0,2 rad/s dio el primer $K$ con enganche en 0,200 sin retardo, 0,247 con $tau =$ 100 ms y 0,647 con $tau =$ 200 ms, y la frecuencia común bajó de 6,283 a 6,178 rad/s. La @ec-kc-retardo da así una predicción de $K_c$ y de $Omega$ en función de la latencia.

El retardo entra multiplicado por la frecuencia absoluta de parpadeo $overline(omega)$, no por la desintonía. A 1 Hz, con 250 ms de latencia ya no hay enganche con un $K$ moderado; a 0,5 Hz el límite pasa a 500 ms. La frecuencia de parpadeo define cuánta latencia tolera el sistema.

*Pérdida de paquetes.* MQTT viaja sobre TCP: si se descarta un paquete, TCP lo retransmite y el mensaje llega igual, más tarde, aun con QoS 0. La pérdida de paquetes se traduce en retardo adicional y jitter, no en mensajes perdidos. Los mensajes se pierden de verdad solo si se descartan en la aplicación o si se corta la conexión. En ese caso, el efecto depende de la política del nodo:
- si mantiene la última fase recibida, la pérdida aumenta la edad de la información y actúa como retardo adicional;
- si usa solo lo recibido en cada paso, con $N$ fijo, el acoplamiento efectivo baja a aproximadamente $K(1 - p)$.

*Actualización discreta.* Cada nodo integra su fase con un paso propio y publica con un período $h$. Son dos parámetros distintos. Con integración de Euler, el lazo es estable si $0 < K h < 2$, pero con valores reales $K h approx$ 0,05, así que ese límite no influye. El período de publicación determina cada cuánto llega información nueva, y actúa como un retardo adicional de alrededor de $h\/2$.

*Jitter y caída del broker.* La variación del retardo actúa como ruido en la fase: baja $r$ en régimen y sube el $K_c$ medido. Si cae el broker, el acoplamiento se anula y cada nodo vuelve a su frecuencia natural.

*Acoplamiento efectivo.* $K$ es una ganancia del software de cada nodo: se fija al comienzo de cada corrida y no cambia durante ella. No depende de la red y no cambia el tráfico, que lo determinan $h$ y el tamaño de los mensajes. La red no modifica $K$, pero sí el acoplamiento efectivo (@tab-acople-efectivo). Por eso hace falta un $K$ mayor que el teórico para lograr el enganche, y la diferencia entre el $K_c$ teórico y el medido es lo que el stack le quita a la sincronización.

#figure(
  table(
    columns: (auto, 1fr),
    table.header[Efecto de la red][Acoplamiento efectivo],
    [Latencia $tau$], [Con $N = 2$, el enganche exige $K |cos(overline(omega) tau)| >= |Delta omega|$],
    [Pérdida de mensajes (solo lo recibido, $N$ fijo)], [Aproximadamente $K(1 - p)$],
    [Período de publicación $h$], [Información vieja: retardo adicional de alrededor de $h\/2$],
    [Caída del broker], [Nulo],
  ),
  caption: [Efecto de la red sobre el acoplamiento efectivo.],
) <tab-acople-efectivo>
*/

==== Implementación

==== Resultados

==== Análisis de resultados
