= Resumen Stallings - Redes de Computadoras

= Capítulo 1: Introducción

== Modelo de Comunicaciones

#image("/assets/image.png")

Elementos de un modelo de comunicaciones: 

- *Fuente*: Dispositivo que genera la información a transmitir.
- *Transmisor*: Dispositivo que transforma y codifica la información en señales adecuadas para el medio de transmisión.
- *Sistema de tranmisión*: Medio físico por el que se propagan las señales.
- *Receptor*: Dispositivo que recibe las señales y las transforma en información para que sea manejada por el dispositivo de destino.
- *Destino*: Dispositivo que recibe la información transmitida.

== Comunicaciones de Datos

#image("/assets/image-1.png")

El modelo de comunicaciones de datos consiste en: 
+ La fuente de información, genera los datos a transmitir, y los guarda temporalmente en la memoria como una secuencia de bits. 
+ El transmisor, que toma los datos de la fuente y los codifica en señales adecuadas para el medio de transmisión. Los datos se transmiten como una secuencia de niveles de tensión _[g(t)]_, que representan los bits de información.
+ El sistema de transmisión recibe una señal _[s(t)]_ y la propaga a través del medio de transmisión. La señal puede sufrir distorsión, ruido y atenuación durante la propagación.
+ El receptor recibe la señal _[r(t)]_ y la decodifica para recuperar los datos transmitidos como secuencia de bits g'(t).
+ La computadora de destino recibe los bits y los procesa, almacenándolos en la memoria como _g'_.
+ El destino intenta determinar si hubo un error en la transmisión de los datos. Si eso ocurre, el destino puede solicitar la retransmisión de los datos.
+ Los datos _m'_ finalmente se presentan al usuario a traves del dispositivo de salida.

== Redes de Área Amplia

Aparecen como solución al caso donde no es necesario/posible conectar entre sí dos dispositivos de comunicación. Se conecta cada dispositivo a una red de comunicación.

Se considera una red de área amplia (_WAN_) a aquella que cubre un área geográfica extensa. Consiste en una serie de dispositivos de conmutación interconectados, estos dispositivos llamados nodos de conmutación, tienen como función proporcionar el servicio de comunicación entre los dispositivos de comunicación conectados a la red.

Se utilizan cuatro tecnologias de transmisión: conmutacion de circuitos, conmutación de paquetes, retransmisión de tramas (_frame relay_) y ATM (_Asynchronous Transfer Mode_).

=== Conmutación de Circuitos
Camino dedicado a través de los nodos de la red. Es una secuencia conectada de enlaces físicos. Se busca establecer el camino dedicado que otrogue la mayor velocidad de trnasmicion entre la fuente y el destino. 
=== Conmutación de Paquetes
Los datos se dividen en paquetes: secuencias de pequeñas unidades de información. Cada paquete se pasa de nodo en nodo siguiendo algún camino. En cada nodo, el paquete se almacena temporalmente y luego se reenvía al siguiente nodo.
=== Retransmisión de Tramas (_Frame Relay_)
Aprovechando la mejora los sistemas de transmisión y su baja tasa de error, eliminan las etapas de verificación de errores y su procesamiento asociado, en la Conmutación de Paquetes. Se utiliza para transmitir datos a alta velocidad entre nodos de la red.
=== ATM (_Asynchronous Transfer Mode_)
Generalización de _frame relay_ y conmutación de circuitos. Utiliza paquetes de longitud fija llamados celdas. ATM introduce poca información para el control de errores en dichas celdas. Al utilizar celdas de longitud fija, se reduce el procesamiento respeto al _frame relay_. Se ofrecen varios canales virtuales, cada uno con su propia velocidad definida al crear el canal.

== Redes de Área Local
Redes de cobertura pequeña. Habitualmente es propiedad de la misma entidad propietaria de los dispositivos de comunicación conectados a la red. Otorga la gestión de la red al usuario. Sus velocidades de transmisión son mucho mayores que en una WAN.

Existen las LAN conmutadas y las LAN inalambricas.








