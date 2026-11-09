== Alcance

El trabajo se centra en el stack formado por MQTT y Protocol Buffers, considerando distintos transportes para MQTT (TCP, TLS y WebSockets), y
en el recorrido de un mensaje desde el dispositivo que lo genera hasta el broker que lo distribuye. A continuación se precisa qué aspectos
abarca el análisis y cuáles quedan fuera de él.

=== Tecnologías estudiadas

En la capa de aplicación, el estudio considera MQTT en su versión 5.0 y Protocol Buffers en su sintaxis proto3. Del protocolo MQTT
se analizan el modelo de broker, los tópicos y sus comodines, los niveles de calidad de servicio, las sesiones, los mensajes retenidos
y el _last will_. De Protocol Buffers se analizan el esquema, la codificación binaria y la compatibilidad entre versiones. Como puntos
de comparación se toman HTTP (y HTTPS) y CoAP como protocolos de transporte de mensajes, y JSON como formato de serialización.

En la capa de transporte, el análisis se limita a TCP y TLS en la medida en que afectan a MQTT, conceptos como la conexión persistente,
el keep-alive, el costo del establecimiento de la sesión segura y la relación entre la confiabilidad de TCP y los niveles de calidad de
servicio de MQTT. La seguridad se aborda únicamente desde el cifrado del canal y la autenticación de los clientes, sin un análisis integral
de amenazas.

En la capa de red, se estudian NAT y los firewalls, y el ruteo interno y externo por el que los mensajes llegan al broker. Para el ruteo
interno se toma OSPF como protocolo principal y se usan RIP y EIGRP como comparación. Para el ruteo externo se considera BGP. Estos protocolos
se analizan en cuanto a su convergencia y su efecto sobre las conexiones TCP de larga duración, y no en cuanto a su configuración en equipos
concretos.

=== Casos de uso

Los casos de uso abarcan la mensajería (Facebook Messenger), la robótica móvil (InOrbit, OpenRobOps y los estándares VDA 5050 e ISO 21423), la automatización industrial (Eclipse Sparkplug) y las redes de radio LoRa (Meshtastic y ChirpStack). Se analizan a partir de la documentación, las especificaciones y el código fuente que publican sus responsables, con foco en cómo emplean MQTT y Protocol Buffers y no en los detalles de cada dominio. Las redes LoRa, excluidas de la parte experimental, se consideran únicamente en este análisis, en el punto en que sus datos ingresan a una red IP.

=== Mapeo tecnológico

El trabajo incluye además un mapeo tecnológico, desarrollado en la @sec-mapeo-tecnologico, con los equipos reales con los que se implementaría el escenario de telemetría del primer experimento (@sec-exp-mqtt-https) en lugar de los equipos emulados. Se relevan los nodos, el broker, ya sea en un servidor propio o como servicio administrado, y la conectividad, y para cada uno se indica el modelo, el proveedor y un precio de referencia con su fecha y moneda. El objetivo es estimar la viabilidad de una solución considerando la calidad técnica, el plazo y el presupuesto, y no proponer la alternativa de máxima prestación.

=== Parte experimental

Los experimentos se realizan sobre placas ESP32 emuladas con QEMU, que se comunican con un broker Mosquitto en la misma computadora, y contrastan con mediciones propias lo que el marco teórico y el desarrollo plantean de forma cualitativa.

El primero, en un escenario de telemetría, compara MQTT (QoS 0 y QoS 1) con HTTP (con y sin reutilización de la conexión), con carga útil en JSON y en Protocol Buffers y con y sin TLS, y mide por separado el costo en bytes y en latencia. Se le aplican pérdidas y latencia de forma artificial, pero no cortes de conexión.

El segundo no compara protocolos. Usa únicamente MQTT 5.0 con Protocol Buffers, sin TLS, y emplea la sincronización de osciladores acoplados como aplicación en la que cada nodo necesita el dato de todos los demás. Allí se ensayan los mecanismos del stack (QoS, keep-alive, última voluntad, alias de tópico y compatibilidad del esquema) y su comportamiento ante pérdidas y cortes de conexión, que se introducen de forma artificial.

La emulación impone limitaciones que acotan el alcance de los resultados. No reproduce el comportamiento de una radio real, por lo que no se mide el
consumo de energía de los dispositivos y no se incluyen enlaces inalámbricos restringidos como LoRa, NB-IoT o satelitales. Tampoco reproduce los tiempos
de procesamiento de un microcontrolador físico. Los escenarios de ruteo y convergencia de la capa de red no se reproducen experimentalmente: se analizan en el desarrollo, y su efecto sobre la conexión se representa con cortes de duración controlada. Por último, no se evalúan la escalabilidad del broker con miles de clientes ni las configuraciones en clúster.
