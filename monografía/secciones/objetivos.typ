= Objetivos

Se desea realizar un análisis riguroso del stack de comunicación formado por MQTT y Protocol Buffers, como alternativa para el intercambio de datos en tiempo real, a alta frecuencia y con ancho de banda limitado, en aplicaciones de Internet de las Cosas, robótica y mensajería. El estudio sigue el recorrido de un mensaje desde el dispositivo que lo genera hasta el broker que lo distribuye, y evalúa cómo cada capa de la arquitectura contribuye a que ese recorrido sea eficiente y confiable.

Más que catalogar las prestaciones de ambas tecnologías, el trabajo busca explicar por qué resultan adecuadas para el problema planteado: sostener una comunicación continua sobre redes que el diseñador no controla, con enlaces inestables, firewalls de terceros y trayectos que atraviesan múltiples sistemas autónomos. Con ese fin, el análisis se articula en torno a dos ejes centrales de la materia: la capa de aplicación, donde operan MQTT y Protocol Buffers, y el ruteo, que determina el camino y la estabilidad con que los mensajes llegan a destino.

Para alcanzar este propósito se plantean los siguientes objetivos específicos:

- Describir la arquitectura publicador/suscriptor de MQTT (broker, tópicos, niveles de calidad de servicio, sesiones y seguridad) y el mecanismo de serialización de Protocol Buffers, comparándolos con alternativas como HTTP, CoAP y JSON.
- Relacionar el funcionamiento de MQTT con la capa de transporte (TCP, keep-alive y TLS), y contrastar sus niveles de calidad de servicio con la elección clásica entre TCP y UDP.
- Analizar el recorrido de los mensajes en la capa de red: direccionamiento, NAT y firewalls, y el papel de los protocolos de ruteo interno (OSPF, con RIP y EIGRP como comparación) y externo (BGP) en la latencia y la estabilidad de la comunicación.
- Contrastar el ruteo por destino IP de la capa de red con el ruteo por tópicos que realiza el broker en la capa de aplicación.
- Examinar casos de uso reales en robótica, mensajería e Internet de las Cosas, como los de InOrbit, para determinar las ventajas y limitaciones del stack en entornos de alta frecuencia y recursos acotados.
