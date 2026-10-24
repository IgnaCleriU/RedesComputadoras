== Alcance

El análisis se centra en MQTT y Protocol Buffers como protocolos de la capa de aplicación, y en su relación con las capas de transporte y de red. HTTP, CoAP y JSON aparecen como puntos de comparación, no como objetos de estudio en sí mismos.

La parte experimental se realiza sobre placas ESP32 emuladas con QEMU y un broker Mosquitto, sin hardware físico. Los resultados describen, por lo tanto, el comportamiento de los protocolos sobre una red Ethernet emulada, con pérdida y latencia controladas, y no el de un enlace inalámbrico real.
