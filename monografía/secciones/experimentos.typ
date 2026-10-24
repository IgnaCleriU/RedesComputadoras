#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

// Caja de un diagrama: título en negrita y una línea de detalle debajo.
#let caja(titulo, detalle) = align(center)[*#titulo* \ #text(size: 8pt, detalle)]

// Subtítulo sin numerar dentro de una parte de un experimento (evita un quinto nivel de numeración).
#let subtitulo(cuerpo) = block(above: 1.3em, below: 0.7em, sticky: true, text(weight: "bold", cuerpo))

== Diseño experimental

Para observar el comportamiento del stack más allá del análisis teórico, se diseñaron dos experimentos. El primero pone a prueba MQTT y Protocol Buffers en un problema que se resuelve solo con intercambio de mensajes entre pares: la sincronización de osciladores, al estilo de las luciérnagas que terminan parpadeando al unísono. El segundo compara MQTT con HTTPS en una tarea que ambos resuelven de forma razonable, el envío periódico de telemetría a un servidor, y separa el efecto del transporte del efecto de la serialización.

Cada experimento se presenta en cuatro partes: el planteo (qué se quiere averiguar y por qué), la implementación, los resultados y su análisis.

=== Plataforma común

Los dos experimentos usan la misma plataforma: ocho placas ESP32 emuladas con QEMU, un broker Mosquitto y un backend que registra el tráfico y calcula las métricas.

La emulación impone, a cambio, algunas restricciones que valen para ambos experimentos:

- QEMU no emula WiFi. La red entre los nodos es Ethernet emulado o el stack de red de QEMU, de modo que el comportamiento propio de un enlace inalámbrico queda fuera del estudio.
- La emulación es por software y el timing no es idéntico al de un ESP32 físico. Por eso en cada corrida se mide el _factor de tiempo real_, el cociente entre el tiempo simulado y el tiempo del host.
- Las ocho instancias comparten la CPU del host, que limita la cantidad de nodos más que la memoria. Ese es el motivo del máximo de ocho nodos.

=== Experimento 1: sincronización de luciérnagas

// Estructura (IMRaD): planteo, implementación, resultados y análisis.
// Mientras el experimento no esté hecho, la implementación está en presente; al terminar, pasarla a pasado.

==== Planteo

Cada ESP32 controla hasta cuatro LEDs, y cada LED es un oscilador que parpadea a su propio ritmo. Los LEDs se ajustan entre sí a partir de los mensajes MQTT que publican al disparar, con payload en Protocol Buffers, sin que ningún coordinador central calcule las fases. La pregunta de fondo es si el stack alcanza para que un conjunto de nodos llegue a parpadear al unísono, como lo hacen ciertas especies de luciérnagas, y a qué costo.

#subtitulo[Motivación]

El problema ejercita justamente los rasgos del stack que estudia la monografía. Cada disparo de un LED tiene que llegar, a través del broker, a todos los demás osciladores: es comunicación de muchos a muchos sobre el modelo publicador/suscriptor. Los mensajes son chicos y frecuentes, lo que pone en primer plano el tamaño de la cabecera MQTT y de la codificación de Protocol Buffers. Y la calidad de la sincronización depende de que esos mensajes lleguen, y lleguen a tiempo, de modo que la pérdida y la latencia de la red se traducen en un efecto observable.

// Completar: vincular explícitamente con los objetivos de la Introducción (qué objetivo responde cada pregunta).

#subtitulo[Modelo de osciladores acoplados]

Cada LED $i$ tiene una fase $theta_i$ que avanza con su frecuencia natural $omega_i$. Cuando la fase llega a $2 pi$, el LED dispara, publica un mensaje de _flash_ y reinicia su fase. Al recibir el flash de otro LED $j$, adelanta su fase en una cantidad proporcional al acoplamiento $epsilon$, y de ese modo tiende a alinearse con $j$.

El grado de sincronización se mide con el parámetro de orden de Kuramoto:

$ r = abs(1/M sum_(j=1)^M e^(i theta_j)) $ <ec-kuramoto>

donde $M$ es el número total de LEDs. Si las fases están dispersas, los términos se cancelan y $r$ queda cerca de 0; si están alineadas, se suman y $r$ se acerca a 1. Se considera que la red convergió cuando $r$ ≥ 0,95.

Cada LED es un oscilador independiente aunque comparta placa con otros. Con ocho ESP32 de cuatro LEDs hay hasta 32 osciladores.

#subtitulo[Preguntas de investigación]

+ ¿Pueden los nodos sincronizarse usando solo intercambio de mensajes entre pares por MQTT, sin un coordinador que calcule fases?
+ ¿Cómo afectan la cantidad de nodos, los LEDs por nodo, el acoplamiento, la pérdida, la latencia y el QoS a esa sincronización?
+ ¿Cuánto cuesta en mensajes, bytes y latencia la sincronización con Protocol Buffers sobre MQTT?

#subtitulo[Hipótesis]

- Con $epsilon$ por encima de un umbral y sin pérdida, la red converge a $r$ ≥ 0,95.
- Aumentar la latencia retrasa la convergencia, pero no impide llegar a la sincronía.
- Con un 5 % de pérdida la convergencia se degrada, y QoS 1 debería compensar parte de esa pérdida a costa de más mensajes.
- La cantidad de mensajes por segundo crece de forma aproximadamente lineal con la cantidad de nodos, y el tiempo de convergencia depende de la topología y de $epsilon$.

==== Implementación

#subtitulo[Entorno]

El experimento corre sobre la plataforma común: ocho ESP32 emuladas con QEMU y un broker Mosquitto.

// Completar para que sea reproducible:
// - versiones de QEMU, Mosquitto, ESP-IDF (o el framework usado) y nanopb;
// - hardware del host (CPU, núcleos, memoria) y sistema operativo;
// - cómo se conectan las instancias de QEMU a la red (bridge, tap, user networking).

#subtitulo[Arquitectura]

Los nodos no se comunican entre sí de forma directa: todo lo que publican y reciben pasa por el broker (@fig-arq-luciernagas). El backend observa el tráfico, calcula las métricas y envía la configuración de cada corrida; el frontend recibe los datos del backend por WebSocket y muestra en vivo el estado de cada LED, los flashes que circulan por la red y la evolución de las métricas.

#figure(
  {
    // Etiquetas de flechas más chicas para que las cuatro cajas entren en una línea.
    let et(cuerpo) = text(size: 7pt, cuerpo)
    scale(74%, reflow: true, diagram(
      spacing: (1.75cm, 1.1cm),
      node-stroke: 0.6pt,
      node-corner-radius: 4pt,
      node-inset: 5pt,
      node((0, 0), caja[ESP32 × 8 (QEMU)][Osciladores y flashes], name: <esp>),
      node((1, 0), caja[Broker Mosquitto][Solo distribuye], name: <broker>),
      node((2, 0), caja[Backend Python][Decodifica y calcula $r$], name: <backend>),
      node((3, 0), caja[Frontend HTML/JS][Paneles en vivo], name: <frontend>),
      edge(<esp>, <broker>, "-|>", et[flash, fase], shift: 4pt, label-side: left),
      edge(<broker>, <esp>, "-|>", et[flashes vecinos], shift: 4pt, label-side: left),
      edge(<broker>, <backend>, "-|>", et[protobuf], shift: 4pt, label-side: left),
      edge(<backend>, <broker>, "-|>", et[configuración], shift: 4pt, label-side: left),
      edge(<backend>, <frontend>, "-|>", et[WebSocket], label-side: left),
    ))
  },
  caption: [Arquitectura del experimento de sincronización: ocho nodos, un broker, el backend y el frontend.],
) <fig-arq-luciernagas>

// Opcional: captura del frontend durante una corrida.

#subtitulo[Mensajes y tópicos]

Los mensajes se definen en un único archivo `.proto`, compartido por el firmware y por el backend. El más frecuente es el flash, que cada LED publica al disparar:

```proto
message Flash {
  uint32 esp_id = 1;
  uint32 led_id = 2;
  uint32 seq    = 3;
  uint64 t_us   = 4;
}
```

El archivo completo, con los mensajes de reporte de fase, de recepción y de configuración, está en el Anexo A. La @tab-topicos-luciernagas muestra qué mensaje viaja por cada tópico; en ellos, `{esp}` y `{led}` son números, de modo que `exp/esp/3/led/2/flash` es el disparo del LED 2 de la ESP 3.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    table.header[Tópico][Quién publica][Quién recibe][Mensaje],
    [`exp/esp/{esp}/led/{led}/flash`], [ESP], [ESP vecinos, backend], [`Flash`],
    [`exp/esp/{esp}/led/{led}/phase`], [ESP], [backend], [`PhaseReport`],
    [`exp/esp/{esp}/rx`], [ESP], [backend], [`RxEvent`],
    [`exp/ctl/config`], [backend], [todos los ESP], [`ExperimentConfig`],
  ),
  caption: [Tópicos del experimento de sincronización.],
) <tab-topicos-luciernagas>

Solo el tópico `flash` forma parte del algoritmo. Los reportes de fase alimentan al frontend, y los mensajes de `rx` confirman cada recepción para medir la entrega; ambos son tráfico propio del experimento, que se mide como overhead y se reporta por separado del costo de la sincronización.

#subtitulo[Firmware]

// Completar al implementar:
// - cómo avanza la fase de cada LED (tarea/timer y período de actualización);
// - cómo se asignan las frecuencias naturales ω_i y las fases iniciales a partir de la semilla;
// - cómo se aplica el ajuste por ε al recibir un flash (regla exacta);
// - qué vecinos escucha cada LED (todos los flashes o un subconjunto) y cómo se suscribe;
// - librerías: cliente MQTT y codificación con nanopb.

#subtitulo[Emulación de la red]

// Completar: cómo se inyectan la pérdida y la latencia entre los nodos y el broker
// (por ejemplo, tc netem sobre la interfaz que usan las instancias) y dónde se aplica.

#subtitulo[Diseño de las corridas]

Se varía un factor a la vez respecto de una configuración base: ocho ESP32 con cuatro LEDs cada una (32 osciladores), $epsilon$ fijo, pérdida del 0 %, latencia de 0 ms y QoS 1. La @tab-factores-luciernagas resume los factores y la pregunta que responde cada uno. Cada configuración se repite cinco veces con semillas fijas, y cada corrida dura 120 s o hasta que $r$ ≥ 0,95 se mantenga durante 30 s. Los mensajes, las métricas y la configuración usada se guardan en CSV o JSON.

// Completar: valores concretos de ε (bajo, medio y alto) y el ε de la configuración base.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header[Factor][Valores a probar][Pregunta que responde],
    [Nodos ESP], [2, 4, 8], [¿Cómo escala el tiempo de convergencia?],
    [LEDs por ESP], [1, 2, 4], [¿Afecta la densidad de osciladores por nodo?],
    [Acoplamiento $epsilon$], [bajo, medio, alto], [¿Hay un umbral para sincronizar?],
    [Pérdida], [0 %, 1 %, 5 %], [¿Cuánto se degrada la convergencia?],
    [Latencia], [0 ms, 50 ms, 200 ms], [¿Cómo afecta el tiempo de propagación?],
    [QoS], [0 y 1], [¿Cuánto pesa la garantía de entrega?],
  ),
  caption: [Factores del experimento de sincronización.],
) <tab-factores-luciernagas>

#subtitulo[Métricas]

Cada métrica responde a una pregunta de la monografía (@tab-metricas-luciernagas). Las de convergencia se calculan sobre $r(t)$; las de costo, sobre cada mensaje publicado.

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header[Métrica][Cómo se calcula][Qué permite concluir],
    [Tiempo de convergencia], [Primer instante con $r$ ≥ 0,95], [Velocidad de sincronización],
    [$r$ final], [Promedio de $r$ en los últimos 10 s], [Si la red queda sincronizada],
    [Bytes por flash (Protobuf)], [Tamaño del mensaje con cabeceras MQTT], [Costo de ancho de banda],
    [Bytes por flash (JSON)], [Mismo mensaje en JSON], [Ahorro de la serialización],
    [Mensajes por segundo], [Total de publicaciones / tiempo], [Carga de la red],
    [Tasa de entrega], [Recibidos / enviados, por par emisor-receptor], [Efecto de la pérdida y del QoS],
    [Latencia flash → recepción], [`RxEvent.t_us` − `Flash.t_us`], [Tiempo real de propagación],
    [Factor de tiempo real], [Tiempo simulado / tiempo del host], [Validez de la corrida],
  ),
  caption: [Métricas del experimento de sincronización.],
) <tab-metricas-luciernagas>

Las latencias se calculan con un reloj de referencia común, o con los relojes simulados sincronizados antes de cada corrida, para que la resta de marcas de tiempo de nodos distintos tenga sentido.

// Completar: cuál de las dos opciones de reloj se usó y cómo se sincroniza.

#subtitulo[Validez]

Si el factor de tiempo real cae por debajo de un umbral, la corrida se descarta, porque el timing de la emulación ya no representa al de un ESP32. Como el frontend, el backend y el broker comparten el host con las instancias, también compiten con ellas por la CPU.

// Completar: valor del umbral del factor de tiempo real.

==== Resultados

// Presentar los datos sin interpretarlos (la interpretación va en Análisis). Media y desvío de las cinco repeticiones.
// Ordenar por pregunta de investigación:
// - Convergencia (pregunta 1): gráfico de r(t) de una corrida representativa con la configuración base.
// - Efecto de cada factor (pregunta 2): tiempo de convergencia y r final en función de N, LEDs por ESP, ε, pérdida, latencia y QoS.
// - Costo (pregunta 3): bytes por flash con Protobuf y con JSON; mensajes por segundo en función de N;
//   tasa de entrega y latencia flash → recepción según pérdida y QoS; overhead de rx y phase por separado.
// - Corridas descartadas por factor de tiempo real, si las hubo.

==== Análisis de resultados

// Confrontar cada hipótesis del Planteo con los resultados: se confirma, se descarta o queda abierta.
// Explicar lo observado con los mecanismos del Marco teórico: niveles de QoS, distribución del broker
// a todos los suscriptores (fan-out), tamaño de la codificación de Protocol Buffers frente a JSON.
// Discutir cuánto pueden haber influido las limitaciones de la emulación (sin WiFi, timing, CPU compartida).
// Cerrar con qué implica para un despliegue real de IoT con el stack MQTT + Protocol Buffers.

=== Experimento 2: MQTT y HTTPS para telemetría

// Estructura (IMRaD): planteo, implementación, resultados y análisis.
// Mientras el experimento no esté hecho, la implementación está en presente; al terminar, pasarla a pasado.

==== Planteo

Las mismas ocho ESP32 envían telemetría periódica a un servidor por dos caminos: MQTT a través del broker, y HTTPS con un POST por lectura. El contenido de cada lectura es idéntico en ambos caminos y se serializa en JSON o en Protocol Buffers, lo que permite separar dos efectos: el del transporte y el de la serialización.

A diferencia del experimento anterior, el caso de uso es neutral: enviar lecturas de los nodos al servidor es algo que ambas arquitecturas resuelven de forma razonable.

#subtitulo[Motivación]

El experimento responde a los objetivos que comparan MQTT con HTTP y que relacionan MQTT con la capa de transporte (TCP, keep-alive y TLS). Las dos variantes de HTTPS, las corridas con y sin TLS y las dos serializaciones permiten, además, separar cuánto de la diferencia se debe a la conexión persistente, cuánto a TLS y cuánto al formato del mensaje.

// Completar: vincular explícitamente cada pregunta con un objetivo de la Introducción.

#subtitulo[Fundamento]

La diferencia principal entre ambos caminos no está en el payload, sino en cómo cada protocolo usa la conexión TCP (@tab-fundamento).

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    table.header[Aspecto][MQTT][HTTPS],
    [Conexión], [Una sesión TCP persistente por nodo], [Una conexión por request, o reutilizada con keep-alive],
    [Handshake TLS], [Una vez, al conectar], [En cada conexión nueva],
    [Cabecera por mensaje], [Mínimo 2 bytes, más el tópico], [Headers HTTP en texto, varios cientos de bytes],
    [Respuesta], [PUBACK solo con QoS 1 o 2], [Siempre una respuesta HTTP],
    [Garantía de entrega], [QoS 0, 1 o 2, definidos por el protocolo], [Reintentos implementados por la aplicación],
    [Iniciativa], [El servidor puede enviar al nodo por la misma sesión], [Solo el cliente inicia],
  ),
  caption: [Diferencias entre MQTT y HTTPS en el uso de la conexión.],
) <tab-fundamento>

Por eso se prueban dos variantes de HTTPS: una conexión nueva por request y una conexión reutilizada. La segunda es la comparación justa; la primera muestra el peor caso, el de los dispositivos que duermen entre envíos.

#subtitulo[Preguntas de investigación]

+ ¿Cuántos bytes cuesta enviar una lectura por MQTT y por HTTPS, contando cabeceras y handshakes?
+ ¿Cómo se comparan la latencia extremo a extremo y la tasa de entrega de ambos?
+ ¿Cómo se degradan ambos protocolos con pérdida y latencia en la red?
+ ¿Qué parte de la diferencia viene de la conexión persistente y qué parte de TLS?
+ ¿Cuánto cambia el costo al pasar de JSON a Protocol Buffers en cada transporte, y cómo depende ese ahorro del tamaño y la forma del mensaje?

#subtitulo[Hipótesis]

- MQTT envía menos bytes por lectura que HTTPS, y la diferencia crece cuando el período de envío es corto.
- HTTPS con conexión reutilizada reduce gran parte de la diferencia, pero los headers HTTP siguen pesando más que la cabecera MQTT.
- HTTPS con una conexión por request es el caso más costoso, sobre todo con TLS y latencia alta, porque cada handshake suma idas y vueltas.
- Con pérdida, MQTT QoS 1 mantiene la entrega a costa de duplicados, mientras que MQTT QoS 0 pierde lecturas.
- Protobuf reduce el payload en ambos caminos, pero su efecto sobre el total es mayor en MQTT, donde el payload es la mayor parte del mensaje. En HTTPS, los headers diluyen el ahorro.
- El ahorro de Protobuf crece con la cantidad de valores numéricos, porque JSON repite los nombres de campo y escribe los números como texto. Con texto corto, la diferencia debería ser menor.
- El tiempo de serialización en el nodo es menor con Protobuf (nanopb) que con una librería JSON, aunque la diferencia es chica frente a la latencia de red.

==== Implementación

#subtitulo[Entorno]

El experimento corre sobre la plataforma común: ocho ESP32 emuladas con QEMU y un broker Mosquitto.

// Completar para que sea reproducible:
// - versiones de QEMU, Mosquitto, servidor HTTPS usado, ESP-IDF (o el framework usado), nanopb y librería JSON;
// - versión de TLS y suite de cifrado;
// - hardware del host (CPU, núcleos, memoria) y sistema operativo;
// - cómo se conectan las instancias de QEMU a la red (bridge, tap, user networking).

#subtitulo[Arquitectura]

En cada corrida se usa un solo camino. El backend recibe las lecturas de los dos con el mismo código de registro, de modo que las mediciones son comparables, y una captura con tcpdump registra los bytes que circulan por ambos (@fig-arq-telemetria).

#figure(
  diagram(
    spacing: (1.8cm, 0.5cm),
    node-stroke: 0.6pt,
    node-corner-radius: 4pt,
    node-inset: 8pt,
    node((0, 1), caja[ESP32 × 8 (QEMU)][Telemetry en protobuf], name: <esp>),
    node((1, 0), caja[Broker Mosquitto][Sesión TCP persistente], name: <broker>, fill: rgb("#e8f0fb"), stroke: 0.8pt + rgb("#3b7dd8")),
    node((1, 2), caja[Servidor HTTPS][Un POST por lectura], name: <https>),
    node((2, 1), caja[Backend][Registra y mide], name: <backend>),
    edge(<esp>, <broker>, "-|>", text(size: 8pt)[PUBLISH]),
    edge(<esp>, <https>, "-|>", text(size: 8pt)[POST], label-side: right),
    edge(<broker>, <backend>, "-|>"),
    edge(<https>, <backend>, "-|>"),
  ),
  caption: [La misma lectura llega al backend por dos caminos; tcpdump captura los bytes de ambos.],
) <fig-arq-telemetria>

#subtitulo[Mensaje, tópicos y endpoints]

El mismo contenido se envía en dos formatos. El campo repetido permite variar el tamaño del mensaje sin cambiar el esquema.

```proto
syntax = "proto3";

message Telemetry {
  uint32 esp_id          = 1;
  uint32 seq             = 2;
  uint64 t_us            = 3;
  uint32 status          = 4;
  repeated float values  = 5;
}
```

// Completar: confirmar el esquema definitivo del mensaje Telemetry.

Su equivalente en JSON compacto, sin espacios, es:

```json
{"esp_id":5,"seq":142,"t_us":1729690000000000,"status":0,"values":[23.4]}
```

La @tab-caminos indica el destino, el método y el cuerpo de cada combinación. En ambos casos `{esp}` es el número de nodo. En MQTT el formato se indica en el tópico, porque el protocolo no tiene un campo de tipo de contenido como el de HTTP, salvo a partir de MQTT 5.

#figure(
  table(
    columns: (auto, 1fr, auto, 1fr, 1fr),
    table.header[Camino][Destino][Método][Cuerpo con Protobuf][Cuerpo con JSON],
    [MQTT], [Tópico `exp/tel/{esp}/pb` o `exp/tel/{esp}/json`], [PUBLISH con QoS 0 o 1], [`Telemetry` en binario], [Texto JSON],
    [HTTPS], [Endpoint `/tel/{esp}`], [POST], [`Content-Type: application/x-protobuf`], [`Content-Type: application/json`],
  ),
  caption: [Destino y formato de cada camino.],
) <tab-caminos>

#subtitulo[Firmware]

// Completar al implementar:
// - cómo se genera cada lectura y con qué período se envía;
// - librerías: cliente MQTT y cliente HTTPS usados;
// - cómo se reutiliza o se abre la conexión en cada variante de HTTPS;
// - reintentos ante error;
// - codificación con nanopb y con la librería JSON;
// - cómo se mide el tiempo de serialización (contador de ciclos).

#subtitulo[Emulación de la red]

La pérdida y la latencia se inyectan con `tc netem` sobre la red Ethernet emulada.

// Completar: en qué interfaz y dirección se aplica netem, y cómo se configura cada valor.

#subtitulo[Diseño de las corridas]

El núcleo del experimento es una matriz de transporte por serialización: cuatro transportes por dos formatos dan ocho combinaciones (@tab-matriz). Todas se corren con la configuración base: ocho ESP32, período de envío de 1 s, TLS activado, pérdida del 0 %, latencia de 0 ms y un valor por mensaje.

#figure(
  table(
    columns: (auto, auto, auto),
    table.header[Transporte][JSON][Protobuf],
    [MQTT QoS 0], [Combinación 1], [Combinación 2],
    [MQTT QoS 1], [Combinación 3], [Combinación 4],
    [HTTPS reutilizado], [Combinación 5], [Combinación 6],
    [HTTPS por request], [Combinación 7], [Combinación 8],
  ),
  caption: [Matriz de transporte por serialización.],
) <tab-matriz>

Después se varía un factor a la vez (@tab-factores-telemetria). Para no multiplicar las corridas, esas variaciones se aplican solo a MQTT con QoS 1 y a HTTPS con conexión reutilizada, cada uno con ambos formatos.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header[Factor][Valores a probar][Pregunta que responde],
    [Valores por mensaje], [1, 10, 50], [¿Cómo cambia el ahorro de Protobuf con el tamaño del mensaje?],
    [Tipo de dato], [Enteros chicos, floats, texto corto], [¿Para qué datos ahorra más Protobuf?],
    [Nodos ESP], [2, 4, 8], [¿Cómo escala la carga del servidor?],
    [Período de envío], [100 ms, 1 s, 10 s], [¿Cuándo pesa el handshake?],
    [TLS], [Con y sin TLS], [¿Qué parte del costo es cifrado?],
    [Pérdida], [0 %, 1 %, 5 %], [¿Cómo se degrada la entrega?],
    [Latencia], [0 ms, 50 ms, 200 ms], [¿Cómo afecta a cada handshake?],
  ),
  caption: [Factores del experimento de telemetría.],
) <tab-factores-telemetria>

Cada configuración se repite cinco veces, y de las repeticiones se informan la media y el desvío. Cada corrida dura 120 s. El broker Mosquitto y el servidor HTTPS usan el mismo certificado de prueba, y una captura con tcpdump en la interfaz que usan las instancias registra los bytes de la corrida. Los mensajes, las métricas y la configuración usada se guardan en CSV o JSON. Los dos transportes nunca corren a la vez, para que no compitan por la CPU ni por la red.

#subtitulo[Métricas]

Los bytes se miden en la red y no en la aplicación, para incluir las cabeceras de TCP, de TLS y del protocolo (@tab-metricas-telemetria).

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header[Métrica][Cómo se mide][Qué permite concluir],
    [Bytes por lectura], [Captura con tcpdump: total de bytes / lecturas entregadas], [Costo real de ancho de banda],
    [Bytes de payload], [Tamaño del cuerpo serializado, en JSON y en Protobuf], [Ahorro de la serialización sola],
    [Proporción payload / total], [Bytes de payload / bytes por lectura], [Cuánto pesa la serialización frente al transporte],
    [Tiempo de serialización], [Contador de ciclos en el firmware, al codificar y al decodificar], [Costo de CPU de cada formato],
    [Bytes de handshake], [Bytes antes del primer dato en cada conexión], [Peso de TCP y TLS],
    [Paquetes por lectura], [Captura con tcpdump], [Overhead de acuses y respuestas],
    [Latencia extremo a extremo], [Recepción en el servidor − `t_us`], [Rapidez de entrega],
    [Tasa de entrega], [Lecturas recibidas / enviadas, por `seq`], [Efecto de la pérdida],
    [Tiempo de conexión], [Desde el SYN hasta el fin del handshake TLS], [Costo de abrir conexiones],
    [Factor de tiempo real], [Tiempo simulado / tiempo del host], [Validez de la corrida],
  ),
  caption: [Métricas del experimento de telemetría.],
) <tab-metricas-telemetria>

El número de secuencia permite detectar pérdidas y también duplicados, que son esperables con MQTT QoS 1.

#subtitulo[Validez]

Además de las restricciones de la plataforma común, este experimento tiene las suyas:

- El handshake TLS en QEMU es más lento que en un ESP32 real, porque la criptografía se emula por software. Los tiempos de conexión con TLS se reportan como relativos, no absolutos.
- Solo se mide telemetría del nodo al servidor. El envío de comandos del servidor al nodo, donde HTTP necesita polling, queda fuera de esta comparación.
- El servidor HTTPS y el broker son implementaciones concretas; otras pueden dar números distintos.

// Completar: umbral del factor de tiempo real para descartar corridas.

==== Resultados

// Presentar los datos sin interpretarlos (la interpretación va en Análisis). Media y desvío de las cinco repeticiones.
// Ordenar por pregunta de investigación:
// - Bytes (pregunta 1): bytes por lectura y bytes de handshake para cada combinación de la matriz.
// - Latencia y entrega (preguntas 2 y 3): latencia extremo a extremo y tasa de entrega en función de la pérdida, la latencia y el QoS;
//   duplicados de MQTT QoS 1.
// - Conexión persistente y TLS (pregunta 4): efecto del período de envío y de TLS (con y sin) sobre los bytes y el tiempo de conexión.
// - Serialización (pregunta 5): proporción payload / total y bytes de payload en JSON frente a Protobuf, según los valores por mensaje
//   y el tipo de dato; tiempo de serialización en el nodo.
// - Corridas descartadas por factor de tiempo real, si las hubo.

==== Análisis de resultados

// Confrontar cada hipótesis del Planteo con los resultados: se confirma, se descarta o queda abierta.
// Explicar lo observado con los mecanismos del Marco teórico: conexión persistente, handshake TCP y TLS,
// cabecera MQTT frente a headers HTTP, niveles de QoS, codificación de Protocol Buffers frente a JSON.
// Separar qué parte de la diferencia corresponde al transporte y qué parte a la serialización.
// Discutir cuánto pueden haber influido las limitaciones de la emulación (TLS más lento en QEMU, red emulada, CPU compartida).
// Cerrar con qué implica para elegir el stack en un despliegue real de IoT.
