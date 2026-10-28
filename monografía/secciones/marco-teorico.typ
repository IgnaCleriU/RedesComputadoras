// Diagramas (Typst Universe).
#import "@preview/chronos:0.3.0"

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

MQTT es un protocolo de transporte de mensajes de tipo publicador/suscriptor, basado en una arquitectura cliente-servidor y diseñado para ser liviano, abierto y fácil de implementar @mqtt50. La primera versión estandarizada por OASIS fue la 3.1.1, adoptada también como norma ISO/IEC 20922, y la versión 5.0, en la que se centra este trabajo, incorpora numerosas funcionalidades nuevas sin alterar el núcleo del protocolo. MQTT adopta la arquitectura centralizada descrita en la sección anterior denominando _broker_ al servidor y cliente a todo programa o dispositivo que abre una conexión hacia él para publicar mensajes y/o suscribirse a ellos, y deja a cada implementación la elección de los mecanismos de autenticación, autorización y cifrado. MQTT delega en la capa de transporte la entrega ordenada y sin pérdidas de los datos a la capa de transporte, por lo que funciona sobre TCP, TLS o WebSocket, pero no directamente sobre UDP.

Cada mensaje de aplicación lleva un nombre de tópico, el cual consiste en una cadena de texto que el servidor compara con las suscripciones de los clientes. Los tópicos se organizan en niveles separados por el carácter `/`, y las suscripciones se expresan mediante filtros que se comparan con los tópicos de mensajes entrantes. Las expresiones de suscripción pueden incluir los comodines `+`, que coincide con exactamente un nivel, y `#`, que solo puede ubicarse al final del filtro y coincide con cualquier cantidad de niveles.

De esta manera las expresiones de suscripción permiten, por ejemplo, en una flota de robots que publica en tópicos de la forma `flota/{ID de robot}/{sensor}`, suscribirse con el filtro `flota/+/bateria` que recibe el estado de batería de todos los robots o el filtro `flota/robot1/#`, que recibe todos los mensajes de el robot `robot1`.

Implementar el esquema basado en tópicos, MQTT implementa desacoplamiento en el espacio, ya que el publicador solo conoce el nombre del tópico y es el servidor quien determina qué clientes reciben cada mensaje. La versión 5.0 agrega además las suscripciones compartidas, en las que cada mensaje se entrega a uno solo de los clientes de un grupo, lo que permite repartir el procesamiento entre varios consumidores.

La entrega de los mensajes se rige por tres niveles de calidad de servicio (QoS), cuyos intercambios de paquetes muestra la @fig-qos. Con QoS 0, el mensaje se envía sin confirmación ni reintentos y llega una vez o ninguna. Con QoS 1, el receptor confirma cada mensaje con un paquete PUBACK y el emisor lo conserva hasta recibir esa confirmación, lo que asegura que llegue al menos una vez aunque pueden producirse duplicados. Con QoS 2, un intercambio en dos etapas garantiza que el mensaje llegue exactamente una vez, a costa de una mayor sobrecarga.

El nivel de QoS se aplica por separado entre el publicador y el broker y entre el broker y cada suscriptor, y cada suscriptor recibe el mensaje con el menor nivel de QoS entre el usado al publicarlo y el máximo concedido a su suscripción. La relación entre estos niveles y la confiabilidad que ya ofrece TCP se analiza en la @sec-qos-tcp.

// Flujo de QoS: `mensajes` es una lista de (origen, destino, paquete),
// donde "E" es el emisor y "R" el receptor.
#let flujo-qos(titulo, mensajes) = align(center, {
  text(weight: "bold", titulo)
  chronos.diagram({
    import chronos: *
    _par("E", display-name: "Emisor", show-bottom: false)
    _par("R", display-name: "Receptor", show-bottom: false)
    for (origen, destino, paquete) in mensajes {
      _seq(origen, destino, comment: raw(paquete))
    }
  })
})

#figure(
  grid(
    columns: 3,
    column-gutter: 0.6cm,
    flujo-qos("QoS 0", (("E", "R", "PUBLISH"),)),
    flujo-qos("QoS 1", (("E", "R", "PUBLISH"), ("R", "E", "PUBACK"))),
    flujo-qos("QoS 2", (("E", "R", "PUBLISH"), ("R", "E", "PUBREC"), ("E", "R", "PUBREL"), ("R", "E", "PUBCOMP"))),
  ),
  kind: image,
  caption: [Intercambio de paquetes de control en cada nivel de QoS.],
) <fig-qos>

Las confirmaciones de QoS 1 y 2 requieren que cliente y servidor mantengan un estado de sesión. En el servidor, ese estado comprende las suscripciones del cliente y los mensajes destinados a él que aún no fueron enviados o confirmados, y puede conservarse a lo largo de varias conexiones consecutivas. Al conectarse, el cliente indica si inicia una sesión nueva o retoma la anterior, y durante cuánto tiempo debe conservarse el estado una vez cerrada la conexión. Este mecanismo es el que permite el desacoplamiento en el tiempo, ya que el servidor almacena los mensajes dirigidos a un suscriptor desconectado y se los entrega cuando este vuelve a conectarse. Sin embargo, ese desacoplamiento no es incondicional, ya que si la sesión no persiste más allá de la conexión, o si los mensajes se publican con QoS 0 que el servidor no está obligado a almacenar, un suscriptor desconectado nunca recibe los mensajes publicados, por lo que corresponde a la aplicación elegir la combinación adecuada para cada tipo de dato.

Complementando este comportamiento, MQTT suma dos mecanismos más. Un mensaje publicado con el indicador RETAIN se almacena en el servidor como último mensaje retenido de su tópico y se entrega a cada nuevo suscriptor, de modo que un cliente que se suscribe recibe de inmediato el estado más reciente aunque el publicador lo envíe de forma irregular. El mensaje de última voluntad (_Will Message_), por su parte, lo registra el cliente al conectarse y el servidor lo publica a los suscriptores si la conexión se cierra de forma anormal, por ejemplo cuando el cliente deja de comunicarse dentro del intervalo de keep-alive, que es el tiempo máximo que puede transcurrir entre dos paquetes enviados por el cliente. Esto permite notificar a los interesados de la desconexión de un dispositivo.

Por último, toda la comunicación en MQTT se realiza mediante paquetes de control, de los cuales la especificación define quince tipos. Entre ellos se encuentran CONNECT y CONNACK para establecer la conexión, PUBLISH para transportar los mensajes de aplicación, PUBACK y los demás paquetes de confirmación de los niveles de QoS, SUBSCRIBE y UNSUBSCRIBE para gestionar las suscripciones, y PINGREQ y PINGRESP para el keep-alive. Cada paquete se compone de un encabezado fijo, presente en todos ellos, seguido de un encabezado variable y de una carga útil que solo aparecen en algunos tipos. El primer byte del encabezado fijo indica el tipo de paquete y algunos indicadores, como el nivel de QoS y RETAIN en el caso de PUBLISH, y a continuación se codifica la longitud restante del paquete con un entero de longitud variable que ocupa un solo byte para valores de hasta 127. De este modo, el encabezado fijo ocupa apenas dos bytes en los paquetes pequeños, que es también el tamaño total de los paquetes de keep-alive. El uso de este tipo de encabezados resulta en una economización del costo de transporte, la cual se evalúa en el experimento de la @sec-exp-mqtt-https.

El contenido de los mensajes queda fuera del protocolo MQTT, que transporta la carga útil sin interpretarla. La versión 5.0 permite declarar su formato mediante las propiedades de indicador de formato y tipo de contenido, que el servidor reenvía sin modificar, pero no impone ninguno, aspecto que se retoma en la @sec-stack. La representación de los datos queda así a cargo de la aplicación, que es el problema que aborda Protocol Buffers, descrito en la @sec-protobuf.

== Protocol Buffers <sec-protobuf>

Una conexión TCP entrega una secuencia de bytes, y un broker MQTT reenvía el contenido de cada mensaje sin interpretarlo. Para que un dato producido por un microcontrolador sea leído correctamente por un servicio escrito en otro lenguaje y ejecutado en otra arquitectura, ambos extremos deben acordar cómo se traduce una estructura de datos a bytes y viceversa, incluyendo el orden de los bytes, el tamaño de los enteros y la forma de delimitar cada campo. En el modelo OSI esta tarea corresponde a la capa de presentación @stallings2004, pero la arquitectura TCP/IP no la incluye, por lo que cada aplicación debe resolverla por su cuenta @comer2014.

Protocol Buffers, también conocido como Protobuf, es un mecanismo para serializar datos estructurados que es neutral respecto del lenguaje de programación y de la plataforma @protobuf-overview. Fue desarrollado por Google, que lo publicó como software libre y mantiene implementaciones oficiales para una variedad de lenguajes @protobuf-repo. Su propuesta es comparable a la de JSON, pero con mensajes más pequeños, un procesamiento más rápido y la generación de código nativo para cada lenguaje. Según su documentación, ofrece un formato de serialización para paquetes de datos estructurados y tipados de hasta unos pocos megabytes, adecuado tanto para el tráfico de red efímero como para el almacenamiento de datos a largo plazo, y que puede extenderse con nueva información sin invalidar los datos existentes ni obligar a actualizar el código @protobuf-overview. Estas propiedades explican su amplia adopción por parte de grandes empresas de internet y en arquitecturas de microservicios @emqx-protobuf-mqtt.

=== Esquema y generación de código

La estructura de los datos se define una única vez en un archivo de esquema con extensión `.proto`, en el que cada mensaje se describe como un conjunto de campos con un tipo, un nombre y un número que lo identifica. Por ejemplo, la lectura de un sensor ambiental podría definirse así:

```proto
syntax = "proto3";

message Lectura {
  float temperatura = 1;
  float humedad     = 2;
  uint32 bateria    = 3;
}
```

A partir de este archivo, el compilador `protoc` genera el código fuente que permite construir, serializar y deserializar el mensaje en cada lenguaje de destino. De este modo, el `.proto` cumple a la vez la función de documentación y la de contrato explícito entre los equipos o servicios que intercambian los datos, y un mismo esquema produce implementaciones compatibles en todos los lenguajes soportados.

=== Codificación binaria

En la codificación binaria de Protobuf, cada campo se transmite precedido de una etiqueta (_tag_) que combina el número de campo definido en el esquema con un tipo de codificación (_wire type_), que indica cómo leer el valor a continuación, como un entero de longitud variable, un valor de 32 o de 64 bits de longitud fija, o un bloque precedido de su longitud, que se usa para cadenas, bytes y mensajes anidados @protobuf-encoding. Se trata, en esencia, de una codificación de tipo-longitud-valor (TLV), como la de BER.

Los enteros se codifican como _varints_, en los que cada byte aporta siete bits del valor y utiliza el bit más significativo para indicar si el número continúa en el byte siguiente. Así, los valores pequeños, que son los más frecuentes, ocupan un solo byte. Por ejemplo, un campo número 1 con el valor 150 se codifica en tres bytes, `08 96 01`: el primero es la etiqueta y los dos restantes el valor @protobuf-encoding. Para los enteros con signo existe además la codificación _zigzag_, que intercala positivos y negativos para que los valores negativos pequeños también resulten cortos. El mensaje no incluye los nombres de los campos, que solo existen en el esquema, y en proto3 los campos que tienen su valor por defecto directamente no se transmiten @protobuf-proto3. Esta combinación es la que hace que un mensaje Protobuf pese varias veces menos que su equivalente en JSON y que se procese más rápido.

=== Compatibilidad entre versiones

Dado que los campos se identifican por número y no por posición ni por nombre, el esquema puede evolucionar sin romper a quienes usan versiones anteriores. Un programa que recibe un campo cuyo número no conoce simplemente lo ignora, de modo que los clientes viejos pueden leer mensajes nuevos (compatibilidad hacia adelante). En sentido inverso, un programa nuevo que lee un mensaje viejo encuentra los valores por defecto en los campos ausentes (compatibilidad hacia atrás). La condición para que esto funcione es no reutilizar números de campo, para lo cual el lenguaje ofrece la palabra clave `reserved`, que impide volver a asignar los números o nombres de campos eliminados @protobuf-proto3. Esta compatibilidad en ambos sentidos es la principal fortaleza de Protobuf frente a otros formatos binarios.

=== Limitaciones

Las mismas decisiones que reducen el tamaño de los mensajes tienen costos. En primer lugar, el formato no es legible por personas, por lo que la depuración requiere herramientas como `protoc --decode` o conversores a JSON. En segundo lugar, no es autodescriptivo: sin el esquema no es posible interpretar los datos, ya que el binario no indica qué mensaje contiene ni qué significa cada campo. En tercer lugar, la codificación no delimita los mensajes, por lo que el protocolo que los transporta debe indicar dónde termina cada uno. Por último, agrega al proyecto un paso de compilación y de generación de código, y resulta menos práctico que JSON para APIs públicas simples o para su uso directo desde navegadores, aunque para ese caso existen alternativas como gRPC-Web.

== Stack MQTT y Protocol Buffers <sec-stack>

// Cómo se combinan: Protobuf como payload de los mensajes MQTT, el esquema compartido entre clientes.
// TODO(prometido en Marco teórico, @sec-mqtt) Retomar las propiedades Payload Format Indicator y Content Type de MQTT 5 como forma de declarar que el payload es un mensaje Protobuf (y de qué tipo).

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

MQTT y Protocol Buffers resuelven problemas distintos y complementarios. MQTT define cómo se distribuyen los mensajes entre los participantes, pero no impone ningún formato para su contenido: la carga útil de cada paquete PUBLISH es una secuencia de bytes cuyo contenido y formato son específicos de la aplicación @mqtt50. Protocol Buffers, por su parte, define cómo representar datos estructurados en una secuencia de bytes compacta, pero no cómo transportarla. La combinación consiste, entonces, en serializar cada mensaje con Protocol Buffers y publicarlo como carga útil de un paquete PUBLISH, que el broker reenvía a los suscriptores sin interpretarlo.

Esta división de tareas resulta complementaria también en la delimitación de los mensajes. El formato binario de Protocol Buffers no es autodelimitante, es decir, un decodificador no puede determinar por sí solo dónde termina un mensaje, por lo que, si se envían varios por un mismo flujo, la aplicación debe indicar antes el tamaño de cada uno @protobuf-techniques. Sobre una conexión TCP, que solo entrega una secuencia continua de bytes, esa tarea quedaría a cargo de la aplicación. MQTT, en cambio, transporta cada mensaje de aplicación en un único paquete PUBLISH, cuya longitud se obtiene de su encabezado fijo @mqtt50, de modo que cada paquete contiene exactamente un mensaje de Protocol Buffers.

Como un mensaje de Protocol Buffers no indica a qué tipo pertenece y no puede interpretarse sin su esquema @protobuf-overview, el receptor debe saber de antemano qué mensaje del archivo `.proto` contiene cada carga útil. La práctica habitual es asociar cada tópico, o cada patrón de tópicos, a un único tipo de mensaje, de modo que el tópico cumple una doble función: determina a qué suscriptores se entrega el mensaje e identifica el esquema con el que se interpreta su contenido. Por ejemplo, en la flota de robots que publica en tópicos de la forma `flota/{ID de robot}/{sensor}`, el tópico `flota/robot1/bateria` puede transportar siempre un mensaje `EstadoBateria`, y un suscriptor con el filtro `flota/+/bateria` sabe que todo lo que recibe se interpreta con ese mismo esquema.

La versión 5.0 de MQTT permite, además, declarar el formato en el propio mensaje mediante propiedades opcionales que el broker reenvía sin modificar @mqtt50. El indicador de formato de la carga útil distingue entre bytes sin especificar, como un mensaje de Protocol Buffers, y texto codificado en UTF-8, como un documento JSON, mientras que el tipo de contenido es una cadena que definen las aplicaciones y que puede usarse para nombrar el tipo de mensaje transportado. Las propiedades de usuario admiten, a su vez, pares nombre-valor definidos por la aplicación, como la versión del esquema, y el alias del tópico reemplaza un nombre de tópico largo y repetido por un entero de dos bytes dentro de una misma conexión, lo que complementa, en el encabezado, la reducción de tamaño que Protocol Buffers logra en el contenido @mqtt50.

El esquema compartido constituye así el contrato entre todos los participantes: a partir de un mismo archivo `.proto` se genera el código de cada uno, ya sea el firmware de un microcontrolador o un servicio en la nube @protobuf-overview. Ese contrato introduce un acoplamiento en el formato de los datos que el modelo publicador/suscriptor no elimina, ya que publicadores y suscriptores no se conocen ni se actualizan al mismo tiempo. Protocol Buffers lo atenúa con sus reglas de compatibilidad: agregar un campo no afecta a los receptores que usan el esquema anterior, que simplemente lo ignoran, y los mensajes antiguos pueden leerse con el esquema nuevo, que asigna valores por defecto a los campos ausentes, siempre que no se modifiquen ni se reutilicen los números de campo existentes @protobuf-proto3. Como contrapartida, el broker solo puede encaminar los mensajes según su tópico, ya que no interpreta su contenido, lo que corresponde a la menor expresividad del esquema basado en tópicos frente al basado en contenido @eugster2003pubsub.

La madurez de esta combinación se refleja en su estandarización. La especificación Eclipse Sparkplug, adoptada como norma ISO/IEC 20237 @sparkplug-iso, define para los sistemas industriales precisamente lo que MQTT deja abierto: un espacio de tópicos, la gestión del estado de las sesiones y la codificación de la carga útil, que en su versión B se basa en Protocol Buffers @sparkplug30. En ella, el primer nivel de cada tópico identifica el esquema de codificación de la carga útil y otro nivel indica el tipo de mensaje, como el aviso de conexión, los datos o los comandos de un nodo; el mensaje de última voluntad de MQTT transporta el aviso de desconexión, y los nombres de las variables pueden reemplazarse por alias numéricos para reducir el tamaño de los mensajes @sparkplug30.

En síntesis, cada pieza del stack cubre una parte de los requisitos planteados al comienzo, como resume la @tab-stack-requisitos.

#figure(
  table(
    columns: 2,
    table.header[Requisito][Pieza del stack que lo cubre],
    [*Enviar datos al dispositivo sin que acepte conexiones entrantes*],
    [Conexión TCP abierta por el dispositivo y entrega por parte del broker],

    [*Comunicar productores y consumidores que no se conocen*], [MQTT: broker y tópicos],
    [*Tolerar desconexiones*], [MQTT: sesiones persistentes, mensajes retenidos y mensaje de última voluntad],
    [*Delimitar cada mensaje*], [MQTT: un paquete PUBLISH por mensaje],
    [*Identificar el tipo de cada mensaje*], [Asociación entre tópico y esquema; en MQTT 5.0, tipo de contenido],
    [*Interpretar los datos de forma unívoca entre equipos heterogéneos*],
    [Protocol Buffers: esquema compartido y código generado para cada lenguaje],

    [*Reducir el uso de ancho de banda*],
    [MQTT: encabezado fijo mínimo y alias de tópico; Protocol Buffers: codificación binaria],

    [*Modificar los mensajes sin afectar a los demás participantes*],
    [Protocol Buffers: reglas de compatibilidad del esquema],
  ),
  caption: [Requisitos de los sistemas estudiados y pieza del stack que cubre cada uno.],
) <tab-stack-requisitos>

Algunas empresas y proyectos que aplican este stack son InOrbit, en robótica @inorbit-edge-sdk; OpenRobOps, plataforma de código abierto para flotas de robots @openrobops-repo; Meshtastic, en redes LoRa @meshtastic-mqtt; y Amazon Web Services, cuyo servicio AWS IoT Core decodifica mensajes de Protocol Buffers recibidos por MQTT @aws-iot-protobuf.

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
