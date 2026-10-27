== Diseño experimental

// Presentación de los dos experimentos y de la estructura común (planteo, implementación, resultados y análisis).

=== Plataforma común

// Placas ESP32 emuladas con QEMU, broker Mosquitto y backend; restricciones de la emulación.

Los dos experimentos corren sobre el mismo entorno, montado en una sola computadora, donde cada nodo es un ESP32 emulado con QEMU.

El ESP32 emulado no tiene WiFi. En su lugar, QEMU le provee una placa Ethernet emulada, que el firmware maneja como cualquier otra interfaz. Cada instancia usa la red de usuario de QEMU, que no requiere permisos de administrador: desde el nodo, la computadora anfitriona se ve en la dirección `10.0.2.2`. Ahí corre el broker Mosquitto, al que se conectan todos los nodos. Para varios nodos se lanzan varias instancias de QEMU en paralelo, cada una con su propia copia de la imagen de flash.

La emulación impone algunas restricciones. Los tiempos de ejecución no son los de una placa real, porque dependen de la carga de la computadora anfitriona. Además, la red de usuario no crea una interfaz en la computadora anfitriona, así que no se puede degradar el enlace de un nodo por separado. Para introducir latencia o pérdida en cada nodo hace falta conectar cada instancia a una interfaz virtual propia unida a un puente, y aplicar `netem` sobre esa interfaz.

=== Experimento 1: MQTT contra HTTPS para telemetría

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
