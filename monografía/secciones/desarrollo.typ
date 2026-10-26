= Desarrollo

// Requisito de la cátedra: el desarrollo tiene que incluir contenido de ruteo (RIP, EIGRP, OSPF, BGP)
// y de capa de aplicación (protocolos), siempre relacionado con el tema. No hace falta cubrir todo.
//
// Estructura: `==` para cada sección numerada (1., 2., ...) y `===` para las subsecciones (1.1., 1.2., ...).
//
// El marco teórico explica qué es cada tecnología de la capa 7, mientras que el desarrollo analiza cómo se comporta el stack
// en las capas de transporte y de red. Luego en diseño experimental se mide.

== MQTT sobre TCP y TLS

=== Conexión persistente y keep-alive

// Una sola conexión TCP saliente por cliente, que se mantiene abierta. Cómo detecta el broker un cliente caído, cuánto tarda.

=== Cifrado con TLS

// Handshake una sola vez al conectar. Comparación con HTTPS con handshake  una vez por conexión, con y sin conexión reusable.
// Costo en bytes y tiempo.

=== QoS MQTT sobre la confiabilidad de TCP

// TCP garantiza entrega ordenada dentro de una conexión, no que la aplicación procesó el mensaje. Si la conexión se cae, lo que estaba en tránsito se pierde.
// Publisher -> broker -> siscriber son dos conexiones TCP distintas

== Capa de red

=== NAT y firewalls

// El dispositivo abre la conexión hacia el broker (saliente), así que no necesita aceptar conexiones
// entrantes. Timeouts de NAT, relación con keep-alive.

=== Ruteo interno

// Cómo llega el tráfico dentro de un sistema autónomo y cuánto tarda cada protocolo en converger.
// OSPF, RIP, EIGRP

=== Ruteo externo

// Trayectos entre sistemas en el edge hasta el broker en la nube.
// BGP.

=== Convergencia y conexiones de larga duración

// Qué le pasa a una conexión TCP abierta mientras la red reconverge.
// Retransmisiones, keep-alive, reconexión, mensajes perdidos, QoSS, sesión.
// Qué se medirá en los epxerimentos en relación a cortes de enlace.

== Ruteo por tópicos y ruteo IP

// El router decide por dirección IP de destino. el broker decide por tópico.
// Comparar tablas de ruteo con suscripciones y comodines (+, #).

== Casos de uso

// Messenger, Robótica, ver si hay otros relevantes.
// Qué problema resolvió el stack en cada caso y qué limitaciones tiene.
