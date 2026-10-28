= Marco teórico

/*
- Las razón de ser de las redes de computadoras es permitir la existencia de aplicaciones de red
- El paradigma cliente servidor es el modelo mas utilizado. Explicar un poco, intuititvo
- Distinguir entre la arquitectura de una red y la arquitectura de una aplicación de red.
- Meter algo de protocolos de transporte.
- Hablar de el tipo de aplicaciones que pub/sub, mqtt y protobuf satisfacen y traducirlo a requerimientos.
  - Definir los que se resuelven con capa de transporte (TCP) y los que se resuelven a nivel de aplicación
  - Pasar a hablar de qué son los protocolos de capa de aplicación. Distinción entre aplicaciones de red y protocolos de capa de aplicación.

- Fuentes:
  - Comer cap 20 habla solo de cliente/servidor, no de pub/sub. Tiene buenos conceptos de la capa 7. Habla de capas.
  - Kurose cap 2: capa 7, aplicaciones y protocolos de capa de aplicación.

NOTE(b-Tomas): En cada sección dejé algunos punteros a fuentes, para quien le toque escribir.
*/

Las redes de computadoras existen para hacer posibles las aplicaciones de red, es decir, programas que se ejecutan en distintos sistemas terminales y que se comunican entre sí a través de la red. La lógica de estas aplicaciones reside únicamente en los sistemas terminales, mientras que los nodos intermedios operan en la capa de red e inferiores. En consecuencia, quien desarrolla una aplicación no modifica la red, sino que utiliza los servicios que esta ofrece y define cómo se organiza la comunicación entre los extremos. MQTT y Protocol Buffers se ubican en este plano.

La forma predominante de organizar la comunicación a nivel de aplicación es el modelo cliente-servidor @comer2014. En este modelo, un servidor permanece activo en una dirección conocida a la espera de solicitudes, y un cliente lo contacta cuando requiere un servicio, envía una solicitud y aguarda la respuesta. La Web constituye el ejemplo característico, en el que el navegador solicita un recurso y el servidor lo devuelve. Se trata de un modelo orientado a la demanda, en el que la información se transmite únicamente cuando es solicitada y el intercambio es iniciado siempre por la parte que la requiere.

Este modelo presenta limitaciones para los sistemas considerados en este trabajo. En ellos, los dispositivos generan datos de manera continua y en instantes que no pueden anticiparse, y deben a su vez recibir comandos originados en la nube. Para que el servidor transmita un comando por iniciativa propia, debería actuar como cliente del dispositivo, lo que requiere que este acepte conexiones entrantes. Esta condición rara vez se cumple cuando el dispositivo se encuentra detrás de un NAT o de un firewall administrado por terceros. La alternativa que ofrece el propio modelo es la consulta periódica por parte del dispositivo, cuyo costo en tráfico y en latencia aumenta con la frecuencia de las consultas.

La capa de transporte ofrece una base para superar esta limitación. TCP establece una conexión persistente _full-duplex_, que permite a ambos extremos transmitir datos en cualquier momento con entrega fiable y ordenada. Si es el dispositivo quien abre la conexión hacia un servidor de dirección conocida, no necesita aceptar conexiones entrantes y conserva el rol de cliente. En ese caso, una vez establecida la conexión, el servidor también puede enviarle mensajes al cliente sin esperar que este realice una solicitud, lo que vuelve innecesaria la consulta periódica.

La conexión TCP, sin embargo, solo garantiza la entrega de una secuencia de bytes entre dos procesos. Qué mensajes se intercambian, con qué formato y en qué momento lo determina el protocolo de la capa de aplicación, que especifica los tipos de mensajes, su sintaxis y su semántica, así como las reglas que indican cuándo y cómo se envía y se responde cada uno de ellos @kurose2017.

En los sistemas estudiados, el diseño de ese protocolo está condicionado en primer lugar por la forma en que circula la información. Un mismo dato suele interesar a varios consumidores y cada consumidor recibe datos de muchos dispositivos, por lo que resulta conveniente que productores y consumidores puedan comunicarse sin conocerse entre sí ni estar conectados simultáneamente, que es la propuesta del modelo publicador/suscriptor implementado por MQTT. A esto se suma la representación de los datos dentro de cada mensaje, que debe ser interpretada de manera unívoca por equipos heterogéneos y ocupar poco ancho de banda en enlaces que suelen ser limitados, problema del que se ocupa Protocol Buffers.

== Modelo publicador/suscriptor

// Buscar papers asociados al modelo, para tenerlos como fuente en la explicación.

El modelo publicador/suscriptor (_publish/subscribe_) ofrece precisamente la posibilidad de que productores y consumidores de información se comuniquen sin conocerse entre sí, lo que lo hace adecuado para los sistemas descritos. En este esquema de interacción, los suscriptores expresan su interés en un evento o en un patrón de eventos, y son notificados de forma asíncrona de todo evento generado por un publicador que coincida con ese interés @eugster2003pubsub. El modelo básico se apoya en un servicio de notificación de eventos, una abstracción que almacena las suscripciones y entrega cada evento publicado a todos los suscriptores interesados. Las suscripciones permanecen en ese servicio y son invisibles a los publicadores.

De esta manera, una de las características principales del modelo y común a todas sus variaciones es el desacoplamiento total de las entidades que se comunican, que puede descomponerse en tres dimensiones @eugster2003pubsub:

- El *desacoplamiento en el espacio* (_space decoupling_) implica que las partes no necesitan conocerse, ya que los publicadores no mantienen referencias a los suscriptores ni saben cuántos participan de la interacción, y lo mismo ocurre en sentido inverso.
- El *desacoplamiento en el tiempo* implica que las partes no necesitan participar de la interacción al mismo tiempo, por lo que un publicador puede publicar eventos mientras un suscriptor está desconectado, y un suscriptor puede recibir la notificación de un evento cuyo publicador ya se desconectó.
- El *desacoplamiento de sincronización* implica que los publicadores no se bloquean al producir eventos y que los suscriptores son notificados mientras realizan otras actividades, fuera del flujo principal de control de ambos.

Este desacoplamiento reduce la coordinación necesaria entre los dispositivos participantes de la comunicación y favorece la escalabilidad en entornos asíncronos por naturaleza.

Estas tres dimensiones permiten contrastar el modelo con el cliente/servidor descrito al comienzo del capítulo. En el caso del paradigma cliente/servidor el cliente debe conocer la dirección del servidor, ambos deben estar activos durante el intercambio y el cliente queda a la espera de la respuesta, por lo que la interacción está acoplada en el espacio, en el tiempo y, del lado del cliente, en la sincronización. La misma comparación puede extenderse a otros paradigmas de comunicación distribuida, como resume la @tab-desacople. La invocación remota de procedimientos (RPC) presenta el mismo acoplamiento que el modelo cliente-servidor, mientras que sus variantes asíncronas y el patrón _observer_ eliminan únicamente el acoplamiento de sincronización. Los espacios de tuplas y las colas de mensajes desacoplan a productores y consumidores en el espacio y en el tiempo, pero obligan a los consumidores a extraer los datos de forma síncrona. El modelo publicador/suscriptor es el único que reúne las tres propiedades.

#figure(
  table(
    columns: 4,
    table.header[Paradigma][Espacio][Tiempo][Sincronización],
    [Pasaje de mensajes], [No], [No], [Solo el productor],
    [RPC/RMI], [No], [No], [Solo el productor],
    [RPC/RMI asíncrona], [No], [No], [Sí],
    [RPC/RMI con futuros], [No], [No], [Sí],
    [Notificaciones (_observer_)], [No], [No], [Sí],
    [Espacios de tuplas], [Sí], [Sí], [Solo el productor],
    [Colas de mensajes (_pull_)], [Sí], [Sí], [Solo el productor],
    [Publicador/suscriptor], [Sí], [Sí], [Sí],
  ),
  caption: [Desacoplamiento que ofrece cada paradigma de comunicación @eugster2003pubsub[p.~121].],
) <tab-desacople>

Las variantes del modelo publicador/suscriptor se distinguen por la forma en que los suscriptores especifican los eventos de interés. En el esquema basado en tópicos, el más antiguo, los eventos se publican bajo nombres que los sistemas modernos organizan en jerarquías, y la sintaxis de comodines permite suscribirse a todos los tópicos de la jerarquía que coincidan con el patrón dado. Este esquema puede implementarse de manera muy eficiente, aunque puede resultar limitado. El esquema basado en contenido clasifica los eventos según sus propias propiedades, mediante filtros que define el suscriptor, y ofrece mayor expresividad a costa de protocolos más complejos y de un mayor costo de ejecución. El esquema basado en tipos clasifica los eventos según su tipo, lo que permite verificar en tiempo de compilación que productores y consumidores coinciden en la estructura de los datos. MQTT, descrito en la @sec-mqtt, adopta el esquema basado en tópicos.

La implementación del servicio de eventos admite a su vez distintas arquitecturas. En una arquitectura centralizada, los productores envían los mensajes a una entidad que los almacena y los reenvía a los consumidores. En una arquitectura distribuida no existe tal entidad, y los mecanismos de almacenamiento y reenvío residen en los propios procesos de productores y consumidores, mientras que un enfoque intermedio implementa el servicio como una red de servidores dedicados. En la arquitectura centralizada, que es la que adopta MQTT, la entidad central se denomina _broker_. Este suele comunicarse con publicadores y suscriptores mediante canales punto a punto confiables y conservar copias de los eventos en almacenamiento estable, lo que le permite ofrecer persistencia y entrega garantizada. Como contraparte, el uso de un broker agrega un salto a cada mensaje y concentra la carga de todos los participantes en un punto de falla que tiene el potencial de demorar la entrega de los eventos @eugster2003pubsub.

Sobre una red TCP/IP, la arquitectura centralizada se apoya en interacciones cliente-servidor. Tanto los publicadores como los suscriptores establecen la conexión hacia el broker, por lo que todos ellos actúan como clientes, y el broker es el único participante que debe tener una dirección conocida y aceptar conexiones entrantes. Su función es la de un sistema intermedio que mantiene conexiones TCP con cada extremo y retransmite los mensajes entre ellas, de manera análoga a los intermediarios definidos para HTTP @stallings2004. La diferencia con el modelo cliente-servidor aparece una vez registrada la suscripción, ya que el broker entrega cada evento por la conexión que el suscriptor estableció previamente, sin requerir de una solicitud. De este modo, los datos llegan al suscriptor en el momento en que se producen, sin que este deba consultar periódicamente ni aceptar conexiones entrantes. Esta capacidad de entregar datos por iniciativa del otro extremo es común a cualquier canal bidireccional persistente, como una conexión WebSocket, pero lo que distingue al modelo publicador/suscriptor es que, sobre esos canales, el broker determina a qué suscriptores corresponde cada evento de modo que publicadores y suscriptores permanecen desacoplados aun cuando cada uno mantiene una conexión punto a punto con el broker.

== MQTT <sec-mqtt>

// Cómo implementa MQTT el modelo pub/sub: broker, tópicos, niveles de QoS, sesiones y seguridad.

/*
- Historia breve: IBM y Arcom, 1999, telemetría de oleoductos por satélite. OASIS 3.1.1 (2014), ISO/IEC 20922 (2016), 5.0 (2019).
- Mapear cada elemento del modelo pub/sub de Eugster a MQTT: broker = servicio de eventos; un mismo cliente puede publicar y suscribirse.
  - Todos los participantes son clientes TCP del broker (definición de cliente de Kurose p. 73-74). Retomar lo dicho en la sección anterior.
- Tópicos jerárquicos y comodines + y # → es la variante "basada en tópicos" de Eugster.
- Formato del paquete: encabezado fijo (mínimo 2 bytes), longitud restante como entero de longitud variable. Puente con la codificación de Protobuf.
- QoS 0, 1 y 2 y su intercambio de paquetes (PUBACK; PUBREC/PUBREL/PUBCOMP).
  - Relacionar con servicio no confirmado / confirmado de Stallings (p. 36).
- Sesiones (clean session / clean start), mensajes retenidos y Last Will: cómo logra MQTT el desacople temporal.
  - Analogía posible con la capa de sesión de OSI: control del diálogo y recuperación (Stallings p. 39).
- Keep-alive: solo definirlo acá; el análisis va en Desarrollo.
- Seguridad: usuario y contraseña, TLS sobre TCP (Kurose p. 78), certificados de cliente.
- Novedades de MQTT 5: códigos de razón, propiedades, expiración de sesión, shared subscriptions.

- Fuentes:
  - OASIS MQTT 5.0 (@mqtt50). Falta en el .bib: MQTT 3.1.1 / ISO/IEC 20922:2016.
  - Hunkeler, Truong y Stanford-Clark 2008, MQTT-S (Stanford-Clark es co-creador de MQTT). Falta en el .bib.
*/

== Protocol Buffers

// Mecanismo de serialización: esquema .proto, codificación binaria, compatibilidad entre versiones.

/*
- Partir del problema de representación de datos que quedó planteado al final del capítulo:
  - Comer p. 422-423: orden de bytes de red. Stallings p. 39: capa de presentación. TCP/IP no tiene capa de presentación.
- Antecedentes: XDR y ASN.1/BER (Comer cap. 27, SNMP). Protobuf como sucesor moderno de la misma idea.
- Esquema .proto y generación de código.
- Codificación binaria: tag (número de campo + wire type), varints, zigzag para enteros con signo, campos de longitud prefijada. Es un TLV, como BER.
- Compatibilidad hacia adelante y hacia atrás: números de campo, campos desconocidos, reserved.
- Limitaciones: no es autodescriptivo (sin el esquema no se puede leer), no es legible, no delimita los mensajes.
- Relación con la distinción de Kurose (p. 79-80): Protobuf define la sintaxis y parte de la semántica de los mensajes, no las reglas de intercambio.

- Fuentes:
  - Google, Overview (@protobuf-overview). Falta en el .bib: protobuf.dev/programming-guides/encoding.
  - Comer cap. 27 (ASN.1/BER).
*/

== Stack MQTT y Protocol Buffers

// Cómo se combinan: Protobuf como payload de los mensajes MQTT, el esquema compartido entre clientes.

/*
- MQTT trata el payload como bytes opacos: Protobuf entra ahí sin cambios.
- Contrato entre tópico y esquema: qué mensaje .proto corresponde a cada tópico.
  - MQTT 5 agrega Content Type y Payload Format Indicator.
- Eclipse Sparkplug B: especificación industrial que define exactamente esta combinación (MQTT + payload Protobuf + espacio de tópicos estandarizado).
- Casos: InOrbit Edge SDK, OpenRobOps (definiciones .proto públicas).
- Volver a la tabla de requerimientos del inicio del capítulo y mostrar cuál cubre cada pieza del stack.

- Fuentes:
  - @mqtt50, @inorbit-edge-sdk, @openrobops-repo.
  - Falta en el .bib: Eclipse Sparkplug 3.0; Proos y Carlsson 2020 (IFIP Networking, compara MQTT/AMQP/CoAP con Protobuf/FlatBuffers).
*/

== Comparación con alternativas
Para intercambiar datos entre un dispositivo (ya sea un sensor, un celular o un robot) y la nube deben tomarse dos decisiones:
1. Qué protocolo de capa de aplicación implementar (define cómo se intercambian los mensajes).
2. Qué mecanismo de serialización se utiliza para representar los datos dentro de cada mensaje (con qué formato viaja la información).

Las secciones anteriores describieron la combinación de MQTT y Protocol Buffers como respuesta a ambas decisiones para el intercambio de datos en tiempo real con ancho de banda limitado, pero no es la única opción, ya que existen otras alternativas consolidadas. Esta sección analiza esas alternativas para identificar en qué aspectos MQTT y Protocol Buffers aventajan a cada una de ellas y en cuáles resultan inferiores. En particular, se compara MQTT con otros dos protocolos de capa de aplicación: HTTP, sobre el que se apoya gran parte de la Internet comercial, y CoAP, diseñado específicamente para dispositivos restringidos. Del mismo modo, se compara Protocol Buffers con JSON, un mecanismo de serialización basado en texto y de uso extendido.

La comparación de protocolos considera el modelo de interacción, el protocolo de transporte, el tamaño de los encabezados, la confiabilidad y el paso por NAT y firewalls, mientras que la de mecanismos de serialización considera el tamaño de los mensajes, el costo de procesamiento y la necesidad de un esquema compartido. El análisis se apoya en las especificaciones de cada tecnología y en estudios publicados.

=== MQTT, HTTP y CoAP
Se definirán brevemente los protocolos HTTP y CoAP, para posteriormente adentrarse en sus diferencias con MQTT.

==== HTTP

Se trata de un protocolo de aplicación *sin estado* de *solicitud y respuesta*. Cada solicitud se interpreta de manera independiente, por lo que el servidor no conserva información sobre los clientes entre una solicitud y la siguiente @kurose2017 @stallings2004[p.~780]. Es el protocolo de la Web y el ejemplo característico del modelo cliente-servidor: el cliente envía una solicitud que indica un método (como GET o POST) y el recurso al que se refiere (identificado por una URI), y el servidor devuelve una respuesta con un código de estado y, eventualmente, el contenido solicitado @rfc9110.

HTTP utiliza TCP como protocolo de transporte, del que obtiene la entrega fiable y ordenada de los datos @kurose2017. En el modelo de solicitud y respuesta, el servidor no puede iniciar una conexión con el cliente ni enviarle una respuesta que no haya sido solicitada. Por eso, un cliente que necesita enterarse de eventos nuevos debe consultar periódicamente al servidor, técnica conocida como _polling_ @rfc6202.

==== CoAP

CoAP (_Constrained Application Protocol_) es un protocolo de transferencia web estandarizado por el IETF (_Internet Engineering Task Force_) para nodos y redes restringidos, como microcontroladores con poca memoria que operan sobre redes de bajo consumo y con pérdidas. Está orientado a aplicaciones máquina a máquina (M2M) @rfc7252.

Adopta el mismo modelo de solicitud y respuesta que HTTP, con recursos identificados por URI, métodos como GET, POST, PUT y DELETE, y códigos de respuesta. Sin embargo, no busca comprimir HTTP, sino implementar el subconjunto de esa arquitectura que necesitan las aplicaciones M2M, y está diseñado para traducirse fácilmente a HTTP mediante _proxies_, lo que facilita su integración con la Web @rfc7252.

CoAP funciona sobre UDP, con DTLS como mecanismo de seguridad, y codifica sus mensajes en un formato binario compacto @rfc7252. Como UDP no garantiza la entrega, el propio protocolo incorpora una confiabilidad liviana: los mensajes confirmables (CON) se retransmiten hasta que el receptor responde con un acuse de recibo (ACK), mientras que los no confirmables (NON) se envían sin confirmación, lo que resulta adecuado, por ejemplo, para cada lectura de un flujo de datos de un sensor @rfc7252.

Por último, la extensión Observe permite que un cliente se registre en un recurso para que el servidor le envíe una nueva representación cada vez que ese recurso cambia, lo que evita el _polling_ @rfc7641.

==== Comparación

De las descripciones anteriores y de los estudios que comparan estos protocolos se desprenden las siguientes diferencias:

1. *Modelo de interacción.* HTTP y CoAP siguen el modelo de solicitud y respuesta, en el que el cliente aplica métodos sobre recursos y recibe códigos de respuesta. En ese modelo, el dato viaja cuando el cliente lo pide, por lo que para enterarse de eventos nuevos debe recurrir al _polling_, cuyo costo crece con la frecuencia de las consultas, o al _long polling_, en el que cada notificación sigue siendo un mensaje HTTP completo, con todos sus encabezados @rfc6202. La extensión Observe acerca CoAP a un modelo de notificaciones, pero sin un broker que desacople a las partes, y su propia especificación aclara que no pretende reemplazar a los sistemas publicador/suscriptor @rfc7641. MQTT, en cambio, implementa el modelo publicador/suscriptor: el broker entrega cada mensaje en el momento en que se publica, mediante la conexión que el suscriptor estableció previamente, y puede conservar los mensajes destinados a un cliente desconectado mediante sesiones persistentes y mensajes retenidos @mqtt50, algo que HTTP y CoAP no prevén.
2. *Protocolo de transporte.* HTTP y MQTT funcionan sobre TCP, del que heredan la entrega fiable y ordenada, pero deben establecer una conexión antes de intercambiar datos. MQTT la establece una sola vez y la mantiene abierta, mientras que HTTP puede abrir una conexión por cada solicitud o reutilizarla para varias @kurose2017. CoAP, en cambio, funciona sobre UDP y no necesita establecer una conexión, de modo que una transacción se resuelve con dos datagramas, uno en cada sentido @naik2017.
3. *Tamaño de los encabezados.* HTTP utiliza encabezados de texto de longitud variable, mientras que los de CoAP y MQTT son binarios: el encabezado fijo de CoAP ocupa cuatro bytes @rfc7252 y el de MQTT, dos bytes como mínimo @mqtt50. Sin embargo, la conexión TCP que requiere MQTT aumenta su sobrecarga total. Por eso, en las comparaciones cualitativas, HTTP resulta el más pesado en tamaño de mensaje, consumo de energía, ancho de banda y latencia, CoAP el más liviano y MQTT ocupa una posición intermedia (esas comparaciones no consideran las retransmisiones) @naik2017.
4. *Confiabilidad.* HTTP depende exclusivamente de la confiabilidad de TCP. MQTT le agrega tres niveles de calidad de servicio y el mensaje de última voluntad, mientras que CoAP ofrece, mediante sus mensajes no confirmables y confirmables, dos niveles aproximadamente equivalentes a QoS 0 y QoS 1 @naik2017. Ante pérdidas, MQTT presenta menor retardo que CoAP cuando las pérdidas son bajas y mayor cuando son elevadas, y con mensajes pequeños y pérdidas de hasta el 25% CoAP genera menos tráfico adicional para garantizar la entrega @thangavel2014. En un estudio sobre la comunicación entre vehículos y la nube, CoAP obtuvo las menores latencias y la menor sobrecarga, pero no logró entregar todos los mensajes con pérdidas elevadas, ni siquiera con mensajes confirmables, mientras que los protocolos basados en TCP, entre ellos MQTT, los entregaron todos @proos2020.
5. *Paso por NAT y firewalls.* Muchos firewalls están configurados para bloquear el tráfico UDP @kurose2017. Entre el 2% y el 4% de las redes de acceso terrestres lo bloquean por completo, y las restricciones se concentran en las redes empresariales; además, los NAT descartan las asociaciones UDP mucho antes que las TCP (en promedio, a los 160 segundos frente a los 386 minutos), lo que obliga a enviar mensajes de mantenimiento con mayor frecuencia @rfc8323. Esto favorece a HTTP y a MQTT frente a CoAP, que para estos casos cuenta con una variante sobre TCP, TLS y WebSocket, a costa de un mayor tamaño de código, más memoria y más intercambios @rfc8323.
6. *Seguridad.* HTTP y MQTT se protegen con TLS sobre TCP, mientras que CoAP utiliza DTLS sobre UDP @naik2017. MQTT, además, deja a cada implementación la elección de los mecanismos de autenticación y autorización @mqtt50.
7. *Interoperabilidad y formato de los datos.* HTTP es el protocolo más interoperable, ya que basta con disponer de una pila HTTP en cada extremo @naik2017, y CoAP se integra con la Web mediante _proxies_ que traducen a HTTP @rfc7252. MQTT, en cambio, requiere un broker y no indica en sus mensajes el formato del contenido, por lo que todos los clientes deben conocerlo de antemano @naik2017; la versión 5.0 agrega propiedades opcionales para declararlo, pero no impone ninguno @mqtt50. Ninguno de los tres protocolos impone un mecanismo de serialización, aspecto que se analiza en la siguiente subsección.

==== Ventajas y desventajas

Frente a HTTP, la principal ventaja de MQTT es que el broker puede entregarle datos al dispositivo sin que este los solicite, lo que evita el _polling_. A esto se suman encabezados mínimos, una única conexión que se mantiene abierta y sirve en ambos sentidos, niveles de calidad de servicio propios y la posibilidad de conservar los mensajes de un cliente desconectado. Como contrapartida, MQTT es menos interoperable que HTTP, requiere un broker, que agrega un salto a cada mensaje y concentra la carga de todos los participantes, como se señaló al describir el modelo publicador/suscriptor, y obliga a que los clientes acuerden de antemano el formato de los datos.

Frente a CoAP, la ventaja de MQTT es la confiabilidad: al funcionar sobre TCP, en los estudios citados entregó todos los mensajes aun con pérdidas elevadas, y atraviesa con menos dificultad los NAT y firewalls, y su broker ofrece un desacoplamiento completo entre publicadores y suscriptores, que las notificaciones de mejor esfuerzo de Observe no alcanzan. Como contrapartida, CoAP es más liviano: genera menos sobrecarga, no requiere la pila TCP y admite solicitudes _multicast_ @rfc7252, para las que MQTT no está diseñado @naik2017. Para redes en las que TCP no es viable, como algunas redes inalámbricas de sensores, existe una variante, MQTT-SN, que funciona sobre un servicio de datagramas y se conecta al broker mediante un _gateway_ @mqttsn2013.

En síntesis, MQTT resulta preferible cuando se necesita una entrega confiable de datos en ambos sentidos sobre redes que no se controlan, con dispositivos detrás de NAT o firewalls; CoAP conviene para dispositivos muy restringidos que envían actualizaciones pequeñas sin necesidad de entrega garantizada @proos2020; y HTTP, para intercambios puntuales iniciados por el cliente o cuando la integración con la Web es prioritaria. La @tab-comparacion-protocolos resume la comparación.

#figure(
  table(
    columns: 4,
    table.header[Criterio][HTTP][CoAP][MQTT],
    [*Modelo de interacción*],
    [Solicitud y respuesta],
    [Solicitud y respuesta (con Observe, notificaciones de mejor esfuerzo)],
    [Publicador/suscriptor],

    [*Entrega sin solicitud previa*], [No (requiere _polling_)], [Solo con Observe], [Sí, a través del broker],
    [*Clientes desconectados*],
    [Sin entrega posterior],
    [Sin entrega posterior],
    [Sesiones persistentes y mensajes retenidos],

    [*Transporte*], [TCP], [UDP], [TCP],
    [*Encabezado*], [Texto, de longitud variable], [Binario, 4 bytes fijos], [Binario, 2 bytes fijos como mínimo],
    [*Confiabilidad*], [La de TCP], [Mensajes confirmables y no confirmables], [La de TCP y QoS 0, 1 y 2],
    [*Paso por NAT y firewalls*], [Favorable (TCP)], [Desfavorable (UDP)], [Favorable (TCP)],
    [*Seguridad*], [TLS], [DTLS], [TLS],
    [*Interoperabilidad*], [La más alta], [Alta, mediante _proxies_ a HTTP], [Requiere un broker y un formato acordado],
  ),
  caption: [Comparación entre HTTP, CoAP y MQTT.],
) <tab-comparacion-protocolos>

=== Protocol Buffers y JSON

Se definirá brevemente JSON, para posteriormente contrastarlo con Protocol Buffers.

==== JSON

JSON (_JavaScript Object Notation_) es un formato de intercambio de datos liviano, basado en texto e independiente del lenguaje de programación, derivado del estándar del lenguaje ECMAScript @rfc8259. Representa los datos mediante objetos, que son conjuntos de pares nombre-valor, y arreglos, cuyos elementos pueden ser cadenas de texto, números, valores booleanos, el valor nulo u otros objetos y arreglos. Fuera de un ecosistema cerrado, los textos JSON deben codificarse en UTF-8 @rfc8259. Por ejemplo, una lectura de un sensor con su temperatura y su nivel de batería puede representarse así:

```json
{"temperatura":23.5,"bateria":80}
```

Como cada mensaje incluye los nombres de sus campos, JSON es autodescriptivo: puede leerse e interpretarse sin conocer de antemano la estructura de los datos, del mismo modo que los mensajes de HTTP/1.1, escritos en texto legible @kurose2017. Esa característica determina su principal ventaja y su principal desventaja:

- *Ventaja:* cualquier persona o programa puede leer el mensaje sin un acuerdo previo sobre su estructura, lo que facilita la depuración y la interoperabilidad.
- *Desventaja:* los nombres de los campos viajan en cada mensaje y los números se representan como texto decimal. El ejemplo anterior ocupa 33 bytes, de los cuales 22 corresponden a los nombres de los campos y sus comillas. Además, la especificación recomienda no esperar más precisión que la de un número de punto flotante de doble precisión, por lo que solo garantiza la interoperabilidad de los enteros de hasta $2^53 - 1$ en valor absoluto @rfc8259.

==== Contraste con Protocol Buffers

De la descripción anterior, de la presentada para Protocol Buffers y de los estudios que comparan ambos mecanismos se desprenden las siguientes diferencias:

1. *Representación.* JSON codifica los datos como texto, mientras que Protocol Buffers utiliza un formato binario en el que cada campo se codifica como un registro de tipo, longitud y valor, identificado por un número de campo en lugar de su nombre @protobuf-encoding.
2. *Esquema compartido.* JSON no requiere un esquema previo. Protocol Buffers, en cambio, requiere que emisor y receptor compartan el archivo `.proto` que define la estructura de los mensajes, ya que sin él no es posible interpretar los datos recibidos. A cambio, ese esquema permite generar código para cada lenguaje y fijar el tipo de cada campo @protobuf-overview.
3. *Tamaño de los mensajes.* Al reemplazar los nombres por números de campo y codificar los valores en binario, Protocol Buffers produce mensajes considerablemente más pequeños. En un relevamiento sobre 27 documentos JSON de distintos ámbitos, Protocol Buffers redujo el tamaño con una mediana del 70,6% @viotti2022; con cargas reales tomadas de mensajes MQTT públicos, el tamaño medio pasó de 111 bytes en JSON a 40 bytes @friesel2021; y con mensajes de producción de vehículos conectados, de 12.187 a 1.157 bytes en promedio @proos2020. La reducción, sin embargo, no es universal: en uno de los 27 documentos, formado por arreglos muy anidados y casi sin nombres de campo, Protocol Buffers resultó más grande que JSON @viotti2022.
4. *Costo de procesamiento.* Aunque la documentación presenta a Protocol Buffers como más rápido que JSON @protobuf-overview, en microcontroladores la diferencia no es clara: en algunas arquitecturas, la biblioteca de JSON evaluada serializó más rápido. Aun así, con radios lentas transmitir un byte consume unas diez mil veces más energía que un ciclo de CPU, por lo que Protocol Buffers resultó la opción más eficiente en energía, a costa de un mayor uso de memoria RAM @friesel2021.
5. *Tipado y evolución.* JSON ofrece solo tipos genéricos y no impone una estructura, por lo que nada garantiza que emisor y receptor interpreten los datos de la misma manera. Protocol Buffers asigna un tipo concreto a cada campo y controla la evolución de los mensajes: el código nuevo puede leer mensajes antiguos, y los campos ausentes toman un valor por defecto @protobuf-overview.
6. *Estandarización y alcance.* JSON es un estándar del IETF @rfc8259, mientras que Protocol Buffers no es un estándar formal de ningún organismo, lo que puede ser una limitación en entornos que exigen basarse en estándares. Además, Protocol Buffers supone que cada mensaje entra completo en memoria, por lo que no resulta adecuado para datos de más de unos pocos megabytes @protobuf-overview.

==== Ventajas y desventajas

La principal ventaja de Protocol Buffers frente a JSON es el tamaño de los mensajes, que en los estudios citados resulta de casi tres a más de diez veces menor. Esta diferencia es especialmente relevante en los sistemas considerados, que envían mensajes pequeños a alta frecuencia por enlaces limitados: de poco sirve que MQTT o CoAP reduzcan sus encabezados a unos pocos bytes si la carga útil se codifica en texto. A esto se suman el tipado de los campos y la evolución controlada del esquema. Como contrapartida, Protocol Buffers sacrifica la legibilidad, obliga a distribuir y mantener el esquema entre todos los participantes, lo que introduce un acoplamiento en el formato de los datos que el modelo publicador/suscriptor no elimina, y no es un estándar formal. JSON, por su parte, conviene cuando la legibilidad, la depuración o la integración con sistemas existentes, como las aplicaciones web, pesan más que el tamaño de los mensajes.

En síntesis, Protocol Buffers resulta preferible cuando el tamaño de los mensajes y el costo de transmitirlos son críticos y es posible distribuir un esquema común entre los participantes, mientras que JSON conviene cuando se priorizan la legibilidad, la flexibilidad y la interoperabilidad sin acuerdos previos. La @tab-comparacion-serializacion resume la comparación.

#figure(
  table(
    columns: 3,
    table.header[Criterio][JSON][Protocol Buffers],
    [*Representación*], [Texto (UTF-8)], [Binaria],
    [*Esquema*], [No requiere], [Requiere un archivo `.proto` compartido],
    [*Autodescriptivo*], [Sí: incluye los nombres de los campos], [No: incluye números de campo],
    [*Legibilidad*], [Legible por personas], [Requiere herramientas y el esquema],
    [*Números*], [Texto decimal], [Binarios, de longitud variable o fija],
    [*Tamaño de los mensajes*], [Mayor], [De casi tres a más de diez veces menor],
    [*Tipado*], [Genérico], [Un tipo concreto por campo],
    [*Evolución*], [Sin control], [Controlada por números de campo y valores por defecto],
    [*Estandarización*], [Estándar del IETF], [Sin estandarización formal],
  ),
  caption: [Comparación entre JSON y Protocol Buffers.],
) <tab-comparacion-serializacion>
