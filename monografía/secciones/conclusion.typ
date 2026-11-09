= Conclusiones

El trabajo se propuso explicar por qué MQTT y Protocol Buffers resultan adecuados para sostener una comunicación continua sobre redes que el diseñador
no controla. La respuesta que surge del análisis y de las mediciones es que esa adecuación no proviene principalmente del tamaño de los encabezados ni
de la codificación binaria, sino de una decisión de arquitectura donde el dispositivo abre una única conexión hacia el broker y la mantiene abierta.
Esa conexión le permite atravesar NAT y firewalls sin aceptar conexiones entrantes, reparte el costo del handshake de TLS entre todos los mensajes y le
da al broker un canal para entregar datos sin que el dispositivo los pida. La misma decisión concentra también las debilidades del stack, que dependen
de que esa conexión y el broker sigan en pie. A continuación se retoma cada uno de los objetivos específicos.

El modelo pub/sub desacopla a las partes en el espacio, en el tiempo y en la sincronización, y MQTT lo implementa con un broker que distribuye los
mensajes según su tópico, con niveles de calidad de servicio y con sesiones que sobreviven a la desconexión del cliente.
Protocol Buffers lo complementa con una codificación binaria compacta, generada a partir de un esquema que comparten los participantes. La comparación
con las alternativas no dio un ganador absoluto, sino un ámbito de uso para cada tecnología. MQTT es preferible cuando se necesita una entrega
confiable en ambos sentidos con dispositivos detrás de NAT o firewalls; CoAP, para dispositivos muy restringidos que envían actualizaciones pequeñas
sin necesidad de entrega garantizada, y HTTP, para intercambios puntuales iniciados por el cliente o integrados con la Web. Del mismo modo, Protocol
Buffers conviene cuando el tamaño de los mensajes es crítico y es posible distribuir un esquema común, y JSON, cuando importan la legibilidad y la
interoperabilidad sin acuerdos previos. Los casos de uso analizados siguen ese mismo criterio.

En la capa de transporte, el análisis mostró que MQTT debe resolver por su cuenta algo que TCP no ofrece en la práctica y es saber si el otro extremo
sigue alcanzable. El keep-alive de MQTT cumple esa función, y la elección de su intervalo es un compromiso entre detectar rápido una caída y tolerar
los cortes breves de la red. Un valor de entre 30 y 60~s detecta una caída en menos de un minuto y medio y absorbe los cortes breves del ruteo,
mientras que uno muy corto vuelve frágil la conexión, como pudimos ver en el segundo experimento, con un intervalo de 5~s, un corte de 2~s alcanzó
para que el cliente la cerrara. El costo de TLS, por su parte, depende de cuántos mensajes viajan por cada conexión. En las conexiones persistentes
agregó entre 46 y 97~B por lectura y menos de 0,6~ms, mientras que con una conexión por lectura triplicó los bytes. TLS, además, protege
cada tramo por separado y no el recorrido completo, porque el broker ve el contenido en claro.

En cuanto a la confiabilidad, TCP y los niveles de calidad de servicio de MQTT cubren riesgos distintos. Mientras la conexión se
mantiene, TCP recupera los segmentos perdidos, en el primer experimento pudemos ver que con 5~% de pérdida, QoS 0 entregó el 100~% de las lecturas, y
QoS 1 solo agregó duplicados y bytes. Lo que aporta QoS 1 es una confirmación de la aplicación en cada tramo y el reenvío de los mensajes pendientes
cuando la conexión se corta y la sesión se retoma, es decir, justamente lo que TCP no puede dar, porque su confiabilidad termina con la conexión. La
elección del nivel depende, entonces, de qué significa que falte un mensaje. Para órdenes y eventos que no se repiten conviene QoS 1 con sesión
persistente y un receptor que tolere duplicados. Para datos que se reemplazan continuamente alcanza QoS 0, eventualmente con un número de secuencia, y
el segundo experimento mostró que, con pérdida, QoS 1 puede ser incluso contraproducente ya que los datos llegaron con una antigüedad mediana de 13,4~s
y el  grupo de nodos dejó de sincronizarse.

En la capa de red, el modelo de MQTT se ajusta a las restricciones de las redes que el diseñador no controla. Como todos los participantes son clientes
y es el dispositivo quien abre la conexión, el único requisito sobre la red del cliente es que permita las conexiones salientes hacia el broker. La
contracara es que el NAT descarta las entradas inactivas, y el keep-alive, al impedir que la conexión quede inactiva, las mantiene vigentes. Respecto
del ruteo, la convergencia de OSPF, RIP, EIGRP y BGP es invisible para TCP y para MQTT, y lo que le ocurre a la conexión depende de cómo se compara la
duración del corte con el temporizador de retransmisión de TCP y con el umbral de una vez y media el keep-alive. Los cortes de pocos segundos, como los
de un IGP con detección rápida o los de EIGRP con un sucesor factible, solo agregan demora. Los menores que ese umbral, como los de OSPF con sus
temporizadores predeterminados, no cierran la conexión, pero entregan datos atrasados que pueden haber perdido su valor. Los mayores, como los de RIP o
los de BGP al retirar una ruta, cierran la conexión, hacen que el broker publique la última voluntad y obligan a repetir los handshakes, y es en ese
régimen donde los niveles de calidad de servicio y las sesiones persistentes cobran sentido. Un cambio de NAT, por último, corta la conexión aunque la
red converja de inmediato. El segundo experimento confirmó este comportamiento con cortes de duración controlada, se observo que ante un corte de 15~s,
la última  voluntad se publicó a los 6,9~s, cerca de los 7,5~s previstos.

El contraste entre el ruteo IP y el ruteo por tópicos mostró que el broker es, en la capa de aplicación, un mecanismo de
encaminamiento análogo a un router. Ambos deciden a partir de una tabla y de una clave que viaja en el encabezado, y el comodín `#` cumple en una
suscripción el papel de un prefijo en una tabla de ruteo. Las diferencias marcan los límites del broker. Como no interpreta la carga útil, no puede
encaminar según el contenido, y por eso en Sparkplug no es posible suscribirse a una métrica individual. Tampoco reconoce las copias de un mismo
mensaje, como las que publican varios puentes de Meshtastic, de modo que descartarlas queda a cargo de los suscriptores. Además, el ruteo por tópicos
no reemplaza al ruteo IP, sino que se apoya en él, este funciona como una red superpuesta cuyo único nodo intermedio es el broker, y cada conexión con
él se encamina por IP de manera independiente. El nombre del tópico tiene, por último, un costo concreto, en el segundo experimento ocupó 17 de los
99~bytes de cada entrega, casi tanto como el dato, y el alias de tópico redujo el tráfico total un 9,7~%.

Los casos de uso analizados, pese a pertenecer a dominios distintos, comparten el mismo patrón ya que el dispositivo, o el equipo que lo
representa, abre una conexión persistente hacia el broker y recibe por ella también las órdenes. Usan Protocol Buffers en los tramos que concentran el
volumen de mensajes y en los enlaces de radio más restringidos, y JSON en los datos que se comparten entre empresas y en los estándares entre
fabricantes, como VDA 5050 o ISO 21423. Publican con QoS 0 los datos de alta frecuencia y reservan QoS 1 y los mensajes retenidos para el estado de
conexión y los datos que cambian poco. Las limitaciones que exponen se concentran en el broker, que conserva estado y, cuando la implementación no
permite replicarlo, como ocurre con Mosquitto, se convierte en el punto único de falla del sistema.

Las mediciones confirmaron lo anterior y le pusieron números. En el primer experimento, una lectura por MQTT QoS 0 con TLS ocupó
165~B, 3,4 veces menos que por HTTP con conexión reutilizada y entre 14 y 16 veces menos que con una conexión por lectura, con una mediana de latencia
de unos 3~ms, frente a 45~ms y 3,4~s. Estos datos concluyen en que con TLS, mantener la conexión abierta explica el 82~% del ahorro, y el protocolo de
aplicación, el 18~% restante. Protocol Buffers redujo la carga útil un 75~% respecto de JSON, unos 54~B por lectura en todos los caminos, pero cambiar de
HTTP con conexión reutilizada a MQTT QoS 0 ahorró más de siete veces eso.
El experimento mostró también los límites de esa ventaja. MQTT tiene el costo fijo por conexión más alto, por lo que deja de convenir si la conexión
dura menos de tres o cuatro lecturas, como en un dispositivo que duerme y se reconecta en cada envío. Además, parte de la diferencia de latencia con
HTTP no se debe al protocolo, sino a cómo el cliente usa TCP, que con el algoritmo de Nagle desactivado, HTTP con conexión reutilizada bajó de 44 a
5~ms, aunque siguió enviando tres veces más bytes que MQTT.

El segundo experimento mostró que el stack puede sostener una aplicación en la que cada nodo necesita el dato de todos los demás, con un comportamiento
que coincide con el modelo teórico cuando este incluye la antigüedad de los datos. En ese régimen, el período de publicación, que es una decisión de la
aplicación, pesó mucho más que el retardo de la red, con unos 250~ms frente a 5~ms. Las virtudes atribuidas al stack se observaron en la práctica, un
nodo nuevo se integró al grupo sin que los demás cambiaran su configuración, un campo desconocido no afectó a la sincronía y el grupo se recuperó solo
después de cada interrupción. También quedaron a la vista sus límites. La caída del broker desordenó a todo el grupo, y la reconexión del cliente
prolongó la interrupción unos 10~s más. Cruzar dos campos del esquema, a su vez, produjo mensajes que se decodifican sin error y un grupo que no se
sincroniza, sin ninguna señal en la red: el esquema es un acuerdo que el protocolo no puede verificar.

El mapeo tecnológico permite cerrar con la viabilidad económica del sistema. El escenario del primer experimento, con ocho nodos que envían una lectura
cada 10~s, puede implementarse con equipos de bajo costo y de amplia disponibilidad. Con conectividad Wi-Fi requiere unos USD~80 en placas con ESP32 y
USD~5 por mes para un servidor propio con Mosquitto, y con conectividad celular, unos USD~250 de inversión inicial y USD~21 por mes, de los cuales 16
corresponden a los datos. La principal incertidumbre no es el precio, sino la cobertura del operador en el lugar de instalación. El análisis de escala
muestra, además, que el ahorro de bytes del stack se traduce en dinero solo cuando la conexión se cobra por volumen y la frecuencia de envío es alta.
En una flota de mil nodos celulares con una lectura cada 10~s, los datos rondan los USD~2000 por mes, y usar JSON en lugar de Protocol Buffers los
aumentaría alrededor de un 40~%, mientras que usar HTTP en lugar de MQTT los multiplicaría casi por cuatro. En cambio, con un broker que cobra por
mensaje, achicar los mensajes no reduce el costo, y en una red Wi-Fi propia, como la de un depósito con robots, la ventaja del stack se mide en
latencia y en uso de la red más que en dinero.

Estas conclusiones tienen el alcance de las condiciones en que se obtuvieron. Los experimentos se realizaron sobre placas emuladas, con tiempos de
criptografía y de procesamiento que no son los de un microcontrolador físico, sin radio real ni medición del consumo, y con pérdidas aleatorias e
independientes en lugar de las ráfagas de un enlace real. La convergencia del ruteo se analizó en el desarrollo y se representó con cortes de duración
controlada, pero no se reprodujo. Tampoco se evaluaron un broker en clúster ni la escala de miles de clientes, y el segundo experimento se apoya, salvo
en el ensayo de QoS con pérdida, en una corrida por condición. Quedan como continuación natural repetir las mediciones con placas físicas sobre una red
celular, evaluar la reanudación de sesión TLS y TLS 1.3 para los dispositivos que se reconectan en cada envío, y medir el comportamiento de un broker
replicado.

En síntesis, MQTT y Protocol Buffers son una opción adecuada para el intercambio frecuente de datos sobre redes que no se controlan, siempre que el
diseño respete tres condiciones. La primera es mantener la conexión abierta, con un keep-alive elegido en función de la red, la segunda, es elegir el nivel de calidad de servicio según lo que significa que falte un mensaje, y por ultimo, tratar al esquema y al broker como partes críticas del sistema,
porque las fallas del primero no se detectan solas y las del segundo afectan a todos los participantes a la vez.
