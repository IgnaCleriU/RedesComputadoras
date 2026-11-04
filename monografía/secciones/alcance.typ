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

=== Casos de uso y mapeo tecnológico

Los casos de uso se toman de fuentes públicas, entre ellas la mensajería de Facebook Messenger y las plataformas de robótica de InOrbit y OpenRobOps,
y se analizan a partir de la información que publican las propias empresas, sin acceso a sus implementaciones internas. Además, el trabajo incluye un
mapeo tecnológico con los equipos reales con los que se implementaría el sistema estudiado: dispositivos de borde, el broker (en un servidor propio
o como servicio administrado) y la conectividad. Para cada uno se indica el modelo, el proveedor y un precio de referencia con su fecha y moneda.
El objetivo es estimar la viabilidad de una solución considerando la calidad técnica, el plazo y el presupuesto, y no proponer la alternativa de máxima prestación.

=== Parte experimental

Los experimentos se realizan sobre placas ESP32 emuladas con QEMU, que se comunican con un broker Mosquitto y un backend, estos cumplen la
función de contrastar con mediciones propias lo que el marco teórico y el desarrollo plantean de forma cualitativa. El primero cuantifica la ventaja
en bytes y en latencia que la bibliografía atribuye a MQTT y a Protocol Buffers, y permite separar cuánto aporta cada uno y cuánto cuesta el cifrado.
El segundo ilustra el comportamiento del stack en una aplicación de tiempo real con intercambio a alta frecuencia, en la que las pérdidas, la latencia
y los cortes de conexión analizados en el desarrollo tienen un efecto directo y observable sobre el resultado.

Se plantean dos experimentos en los que se comparan las siguientes combinaciones de protocolo y formato de serialización:
- MQTT con Protocol Buffers
- MQTT con JSON
- HTTP con Protocol Buffers
- HTTP con JSON

El primer experimento se realiza en un escenario de telemetría y mide por separado el costo en bytes y en latencia del transporte y de la serialización.
El segundo compara las mismas combinaciones en la sincronización de osciladores acoplados. En ambos, las condiciones de red, como las pérdidas, la latencia
y los cortes de conexión, se introducen de forma artificial, y cada combinación se evalúa con y sin TLS.

La emulación impone limitaciones que acotan el alcance de los resultados. No reproduce el comportamiento de una radio real, por lo que no se mide el
consumo de energía de los dispositivos y no se incluyen enlaces inalámbricos restringidos como LoRa, NB-IoT o satelitales. Tampoco reproduce los tiempos
de procesamiento de un microcontrolador físico. Los escenarios de ruteo se emulan, en lugar de reproducirse sobre una red con múltiples sistemas
autónomos reales. Por último, no se evalúan la escalabilidad del broker con miles de clientes ni las configuraciones en clúster.
