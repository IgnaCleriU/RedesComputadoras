= Capítulo 1: Introducción

== Modelo de Comunicaciones

#image("/assets/image.png")

Elementos de un modelo de comunicaciones: 

- *Fuente*: Dispositivo que genera la información a transmitir.
- *Transmisor*: Dispositivo que transforma y codifica la información en señales adecuadas para el medio de transmisión.
- *Sistema de transmisión*: Medio físico por el que se propagan las señales.
- *Receptor*: Dispositivo que recibe las señales y las transforma en información para que sea manejada por el dispositivo de destino.
- *Destino*: Dispositivo que recibe la información transmitida.

== Comunicaciones de Datos

#image("/assets/image-1.png")

El modelo de comunicaciones de datos consiste en: 
+ La fuente genera los datos a transmitir y los guarda temporalmente en memoria como una secuencia de bits.
+ El transmisor toma los datos de la fuente y los codifica en señales adecuadas para el medio de transmisión. Los datos se transmiten como una secuencia de niveles de tensión $g(t)$, que representan los bits de información.
+ El sistema de transmisión recibe una señal $s(t)$ y la propaga a través del medio de transmisión. La señal puede sufrir distorsión, ruido y atenuación durante la propagación.
+ El receptor recibe la señal $r(t)$ y la decodifica para recuperar los datos transmitidos como secuencia de bits $g'(t)$.
+ La computadora de destino recibe los bits y los procesa, almacenándolos en la memoria como $g'$.
+ El destino intenta determinar si hubo un error en la transmisión de los datos. Si eso ocurre, el destino puede solicitar la retransmisión de los datos.
+ Los datos $m'$ finalmente se presentan al usuario a través del dispositivo de salida.

== Redes de Área Amplia

Surgen cuando no es práctico conectar dos dispositivos directamente entre sí; en cambio, cada uno se conecta a una red de comunicación.

Se considera una red de área amplia (_WAN_) a aquella que cubre un área geográfica extensa. Consiste en una serie de dispositivos de conmutación interconectados, llamados nodos de conmutación. Su función es dar el servicio de comunicación a los dispositivos conectados a la red.

Se utilizan cuatro tecnologías de transmisión: conmutación de circuitos, conmutación de paquetes, retransmisión de tramas (_frame relay_) y ATM (_Asynchronous Transfer Mode_).

=== Conmutación de Circuitos
Camino dedicado a través de los nodos de la red. Es una secuencia conectada de enlaces físicos. Se busca establecer el camino dedicado que otorgue la mayor velocidad de transmisión entre la fuente y el destino. 
=== Conmutación de Paquetes
Los datos se envían como una secuencia de unidades pequeñas llamadas paquetes. Cada paquete se pasa de nodo en nodo siguiendo algún camino. En cada nodo, el paquete se almacena temporalmente y luego se reenvía al siguiente nodo.
=== Retransmisión de Tramas (_Frame Relay_)
La conmutación de paquetes se diseñó para enlaces con muchos errores, así que tiene bastante sobrecarga por control de errores. Como los sistemas de transmisión actuales tienen una tasa de error baja, frame relay elimina gran parte de esa sobrecarga y logra velocidades mayores entre los nodos de la red.
=== ATM (_Asynchronous Transfer Mode_)
Generalización de _frame relay_ y conmutación de circuitos. Utiliza paquetes de longitud fija llamados celdas. ATM introduce poca información para el control de errores en dichas celdas. Al utilizar celdas de longitud fija, se reduce el procesamiento respecto al _frame relay_. Se ofrecen varios canales virtuales, cada uno con su propia velocidad definida al crear el canal.

== Redes de Área Local
Redes de cobertura pequeña. Una LAN suele ser propiedad de la misma organización dueña de los dispositivos conectados, que es quien la administra. Sus velocidades de transmisión son mucho mayores que en una WAN.

Existen las LAN conmutadas y las LAN inalámbricas.

== Redes Inalambricas
Proporcionan ventajas evidentes de movilidad y facilidad de instalación.

== Redes de Área Metropolitana
Redes de cobertura intermedia. Una MAN suele ser propiedad de una organización que la administra y proporciona servicio a los usuarios que necesitan alta capacidad en areas metropolitanas. Suelen ser más rápidas que las WAN, pero más lentas que las LAN. 

