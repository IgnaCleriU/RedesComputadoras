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

=== MQTT, HTTP y CoAP

/*
- HTTP: cliente-servidor, pull, sin estado (Stallings p. 780; Kurose p. 83 y p. 100). Conexiones persistentes y no persistentes (Kurose p. 83-85).
- CoAP: modelo REST sobre UDP para dispositivos restringidos; mensajes confirmables y no confirmables. Comer cap. 30 (IoT) lo nombra.
- Ejes de comparación: modelo de interacción, transporte (TCP/UDP), overhead de encabezados, confiabilidad, paso por NAT y firewalls.
  - Kurose p. 79: muchos cortafuegos bloquean UDP.
- Resumir lo que dice la literatura, sin números propios (esos van en Experimentos).

- Fuentes (faltan en el .bib):
  - Naik 2017, IEEE ISSE (MQTT, CoAP, AMQP y HTTP).
  - Thangavel et al. 2014, ISSNIP (MQTT y CoAP con un middleware común).
  - RFC 7252 (CoAP).
*/

=== Protocol Buffers y JSON

/*
- Texto legible contra binario. Kurose p. 86: los mensajes HTTP están en ASCII legible por cualquier persona.
- Autodescriptivo (JSON) contra esquema compartido (Protobuf).
- Tamaño del mensaje y costo de CPU de serializar/deserializar.
- Mencionar al pasar FlatBuffers, CBOR, MessagePack.

- Fuentes (faltan en el .bib):
  - Popić et al. 2016 (Protobuf contra JSON/BSON en IoT).
  - Proos y Carlsson 2020.
  - RFC 8259 (JSON).
*/
