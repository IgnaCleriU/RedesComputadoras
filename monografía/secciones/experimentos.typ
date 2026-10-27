== Diseño experimental

// Presentación de los dos experimentos y de la estructura común (planteo, implementación, resultados y análisis).

=== Plataforma común

// Placas ESP32 emuladas con QEMU, broker Mosquitto y backend; restricciones de la emulación.
// TODO(mapeo tecnológico) Indicar qué hardware real reemplazaría a lo emulado (modelo de placa, dónde se compra y precio) (pedido del profesor, mail del 27/10). Ver nota en desarrollo.typ.

=== Experimento 1: MQTT contra HTTPS para telemetría <sec-exp-mqtt-https>

// TODO(prometido en Marco teórico, @sec-mqtt) Medir la sobrecarga de los encabezados de MQTT (encabezado fijo de 2 bytes en paquetes pequeños) frente a la de HTTPS.

// Caso base. Mide el costo del transporte y de la serialización por separado,
// El experimento 2 se apoya en esos números.

==== Planteo

==== Implementación

==== Resultados

==== Análisis de resultados

=== Experimento 2: sincronización de osciladores acoplados

==== Planteo

==== Implementación

==== Resultados

==== Análisis de resultados
