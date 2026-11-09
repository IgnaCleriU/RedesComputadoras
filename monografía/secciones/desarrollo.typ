= Desarrollo

// Requisito de la cátedra: el desarrollo tiene que incluir contenido de ruteo (RIP, EIGRP, OSPF, BGP)
// y de capa de aplicación (protocolos), siempre relacionado con el tema. No hace falta cubrir todo.
//
// Estructura: `==` para cada sección numerada (1., 2., ...), `===` para las subsecciones (1.1., 1.2., ...) y `====` para
// apartados sin numerar en el índice (como cada caso dentro de un dominio en Casos de uso).
//
// El marco teórico explica qué es cada tecnología de la capa 7, mientras que el desarrollo analiza cómo se comporta el stack
// en las capas de transporte y de red. Luego en diseño experimental se mide.

== MQTT sobre TCP y TLS

=== Conexión persistente y keep-alive <sec-keepalive>

Como se planteó en el marco teórico (@sec-mqtt), el cliente MQTT abre una única conexión TCP hacia el broker y la mantiene abierta mientras dura la
sesión. A diferencia de HTTP, en el que cada solicitud puede abrir una conexión nueva o reutilizar una abierta hasta que el servidor la cierra por
inactividad @kurose2017, en MQTT el cierre anormal se interpreta como la caída del cliente y el broker publica
su mensaje de última voluntad. Esto plantea el problema de saber si el otro extremo sigue ahí. Un dispositivo que se apaga o sale del alcance de la
red no envía ningún segmento de cierre, y lo mismo ocurre cuando un NAT descarta la entrada de una conexión inactiva, situación que se analiza más
adelante, en la @sec-nat-firewalls. Un extremo que solo recibe, como un suscriptor, no se entera nunca, porque TCP no verifica de forma continua que
el otro extremo sea alcanzable @comer2014, y su keep-alive propio es opcional, viene desactivado por defecto y no debe tener un intervalo menor que
dos horas @rfc1122.

MQTT lo resuelve con un keep-alive propio. En el paquete CONNECT, el cliente declara un intervalo _K_ en segundos, y el valor 0 desactiva el mecanismo.
Mientras no sea cero, el cliente debe enviar algún paquete de control dentro de cada intervalo y, si no tiene nada que publicar, envía un PINGREQ, que
el broker contesta con un PINGRESP. Si el broker no recibe ningún paquete del cliente durante 1,5~_K_, debe cerrar la conexión como si la red hubiera
fallado @mqtt50. El tiempo que tarda en detectar una caída depende de cuándo ocurre, por ejemplo, si la falla sucede justo después de un paquete, el
broker la detecta 1,5~_K_ más tarde, y si sucede justo antes del siguiente envío, 0,5~_K_ más tarde. Con el intervalo de 60 s del Experimento 1, que se
describe en el diseño experimental (@sec-exp-mqtt-https), la detección demora entre 30 y 90 s. Hasta entonces el broker no publica la última voluntad
y, en Sparkplug, la aplicación de supervisión sigue considerando vigentes los datos de un nodo caído, porque su certificado de muerte es justamente ese
mensaje.

Elegir _K_ implica un compromiso, que resume la @tab-keepalive. Un intervalo corto detecta antes la caída y mantiene viva la entrada del NAT, pero
tiene dos costos. El primero es el tráfico, ya que en una conexión inactiva con TLS, cada intercambio de PINGREQ y PINGRESP ocupa unos 182 B, y con
10 s esto supera al volumen mensual de las lecturas que un nodo envía cada 10 s, de unos 36 MB, según el mapeo tecnológico (@sec-mapeo-tecnologico).
El segundo son las desconexiones innecesarias, ya que el umbral de 1,5~_K_ es el corte del camino que el stack soporta sin perder la conexión, y con
_K_ de 10 s es de 15 s, menor que los 40 s que OSPF tarda en detectar una falla por ausencia de Hellos @rfc2328. Ese corte cerraría la conexión y
obligaría al dispositivo a repetir los handshakes de TCP y de TLS (@sec-tls). En la práctica se usan intervalos de decenas de segundos, por ejemplo, 30
s en el  Gateway Bridge de ChirpStack @chirpstack-gwbridge-config, menos de un minuto recomendado por Digitransit @digitransit-mqtt y 60 s en el
Experimento 1. Un valor de entre 30 y 60 s detecta una caída en menos de un minuto y medio y absorbe los cortes breves del ruteo.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (left, left, left, left),
    table.header[Intervalo _K_][Umbral del broker (1,5~_K_)][Detección de una falla][Tráfico en una conexión inactiva],
    [10~s], [15~s], [5 a 15~s], [47,2~MB por mes],
    [30~s], [45~s], [15 a 45~s], [15,7~MB por mes],
    [60~s], [90~s], [30 a 90~s], [7,9~MB por mes],
    [300~s], [450~s], [150 a 450~s], [1,6~MB por mes],
  ),
  caption: [Efecto del intervalo de keep-alive _K_. El tráfico es una estimación con TLS, a razón de 182~B por intercambio de PINGREQ y PINGRESP (@tab-anatomia), durante 30 días. No se midió en el Experimento 1.],
) <tab-keepalive>

=== Cifrado con TLS <sec-tls>

MQTT no define un mecanismo de cifrado propio y delega la protección de los datos en el transporte. Sobre TCP se utiliza TLS, en el puerto 8883
registrado para ese fin @mqtt50. TLS ofrece confidencialidad, integridad de cada mensaje y autenticación del servidor mediante un certificado
@kurose2017 @stallings2004, y se apoya en TCP para obtener un servicio fiable extremo a extremo @stallings2004, la misma exigencia que MQTT plantea al
transporte @mqtt50. TLS se ubica entre TCP y MQTT, primero se establece la conexión TCP, luego se realiza el handshake de TLS y recién después el
cliente envía el CONNECT, que ya viaja cifrado, de modo que el usuario y la contraseña quedan protegidos.

El costo del cifrado tiene dos partes. La primera es el handshake, que se realiza una sola vez al conectar. En TLS 1.2, la versión empleada en el
Experimento 1, requiere dos idas y vueltas @rfc5246, de modo que, sumado al handshake de TCP, el cliente envía el CONNECT recién
después de unos tres RTT. Con 200 ms de RTT agregados, el tiempo de conexión aumentó entre 340 y 570 ms (@sec-exp-mqtt-https). TLS 1.3 reduce el
handshake completo a una sola ida y vuelta @rfc8446. La segunda parte es el recargo de cada mensaje, con TLS 1.2 y AES-GCM, cada registro agrega 29 B
(5 de cabecera, 8 de _nonce_ explícito y 16 de etiqueta de autenticación), lo que explica casi todo el aumento de 46,5 B por lectura de MQTT QoS 0,
cuya latencia crece menos de 0,6 ms.

Lo que determina cuánto pesa el handshake es cuántos mensajes se envían por cada conexión. En MQTT la conexión es persistente, por lo que el handshake
se paga una vez y se reparte entre todas las lecturas. HTTPS puede lograr lo mismo, por ejemplo: HTTP/1.1 mantiene las conexiones abiertas por defecto
@kurose2017, y con una conexión reutilizada el costo es comparable. Pero un dispositivo que duerme entre envíos, o un servidor que cierra las
conexiones inactivas, paga el handshake completo en cada lectura. En el Experimento 1 con una conexión por lectura, TLS
multiplicó por 3,1 los bytes por lectura y sumó 3,4 s de latencia, mientras que en las conexiones persistentes sumó entre 46 y 97 B y menos de 0,6 ms
(@tab-tls). Por eso la conexión persistente y el keep-alive de la @sec-keepalive son lo que hace barato el cifrado.

Por último, TLS protege el tramo entre el cliente y el broker, no el recorrido completo del mensaje. Como el broker termina la conexión TLS, ve el
contenido en claro, y un mensaje que va de un publicador a un suscriptor atraviesa dos conexiones TLS independientes, una por tramo. Proteger el
contenido frente al propio broker exige cifrar la carga útil en la aplicación, como hace Meshtastic con la clave de cada canal.

=== QoS MQTT sobre la confiabilidad de TCP <sec-qos-tcp>

Los niveles de calidad de servicio de MQTT, presentados en el marco teórico (@sec-mqtt), plantean una pregunta, ya que el protocolo opera sobre TCP,
que entrega los datos de forma fiable y ordenada. TCP construye sobre el servicio no confiable de IP un flujo de bytes sin errores, huecos ni
duplicados que llega en el orden en que se envió @kurose2017, mediante números de secuencia, confirmaciones y retransmisiones. Por eso un mensaje de
QoS 0 sobre TCP no equivale a un datagrama que puede perderse en el camino, en el Experimento 1 entregó el 100 % de las lecturas con 5 % de pérdida,
también con QoS 0, y lo que se degradó fue la latencia, con un percentil 99 de unos 3 s por el temporizador de retransmisión y el bloqueo de cabeza de
línea (@tab-perdida). La confiabilidad de TCP y la de MQTT se refieren, entonces, a cosas distintas, y los niveles de QoS cubren lo que TCP no
garantiza, que son tres cosas.

+ *Que el mensaje llegó a su destino final.* Un mensaje MQTT atraviesa dos conexiones TCP independientes, la del publicador con el broker y la del broker con cada suscriptor, y el nivel de QoS se aplica por separado en cada tramo.
+ *Que la aplicación lo recibió.* El ACK de TCP lo genera la pila del receptor cuando coloca los datos en el buffer de recepción, y el programa los lee después @kurose2017. Si el programa falla o la conexión se aborta entre ambos momentos, el emisor da por entregado un dato que no lo está.
+ *Que sobreviva a la conexión.* La confiabilidad de TCP existe mientras la conexión existe. Después de un corte mayor que 1,5~_K_, un reset del broker o un cambio de NAT, el emisor no sabe cuáles de los datos que envió llegaron.

QoS 0 no agrega nada a TCP @mqtt50, sin embargo QoS 1 agrega una confirmación de la aplicación, esta es que el emisor
conserva el mensaje hasta recibir el PUBACK, de modo que sabe que el broker lo aceptó y no solo que su pila TCP lo recibió, y si la conexión se rompe
lo reenvía al retomar la sesión @mqtt50. Su garantía es de al menos una vez, porque si el corte ocurre después de que el receptor procesó el mensaje y
antes del PUBACK, el receptor lo recibe dos veces. QoS 2 agrega un intercambio de cuatro paquetes con el que el receptor evita entregar el mensaje dos
veces, a costa de dos idas y vueltas por mensaje. La @tab-garantias-qos resume qué cubre cada nivel. Ninguno resuelve la primera carencia (cada tramo
se confirma por separado, y el publicador no sabe si el mensaje llegó a los suscriptores).

#figure(
  table(
    columns: (1.5fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, left, left, left, left),
    table.header[Situación][TCP][QoS 0][QoS 1][QoS 2],
    [Segmento perdido en la red, con la conexión viva],
    table.cell(colspan: 4)[TCP lo retransmite; los niveles de QoS no agregan nada],
    [El receptor MQTT confirma que aceptó el mensaje, en cada tramo],
    [No: el ACK confirma a la pila, no a la aplicación], [No], [Sí, con PUBACK], [Sí, con PUBREC y PUBCOMP],
    [Conexión cortada con el mensaje en tránsito],
    [Se pierde], [Se pierde], [Se reenvía si se retoma la sesión], [Se reenvía si se retoma la sesión],
    [Entregas de cada mensaje],
    [No aplica], [A lo sumo una], [Al menos una], [Exactamente una],
  ),
  caption: [Qué garantiza TCP y qué agrega cada nivel de QoS en cada tramo del recorrido de un mensaje @mqtt50.],
) <tab-garantias-qos>

Los reenvíos de QoS 1 y 2 solo funcionan si el estado sobrevive a la conexión, estos ocurren cuando el cliente se reconecta con Clean Start en 0 y el
broker conservó la sesión, que vence según el Session Expiry Interval @mqtt50. Si la sesión es nueva o expiró, después de un corte QoS 1 y 2 no aportan
nada frente a QoS 0. Además, dentro de una conexión viva los reintentos de la aplicación se superponen con los de TCP. En el Experimento 1, con pérdida
de paquetes pero sin cortes, QoS 1 no mejoró la entrega y generó duplicados, 9 por corrida con 1 % de pérdida y 52 con 5 %, porque el cliente reenvía el
PUBLISH mientras TCP todavía está recuperando el original. Su costo por lectura, sin contar el de abrir la conexión, fue de 202 B contra 140 B de QoS 0 (@tab-costo).

La elección del nivel depende de qué ocurre cuando falta un mensaje. Si el siguiente lo reemplaza, como en una lectura periódica, QoS 0 sobre TCP
alcanza, y su única exposición son los cortes de la conexión. Sparkplug, por otra parte, publica con QoS 0 y suple la confirmación con un número de
secuencia de 0 a 255, y si la aplicación advierte un salto le pide al nodo un nuevo certificado de nacimiento para reconstruir su estado
(@sec-caso-industria, en los casos de uso). Si el mensaje es una orden o un evento que no se repite, conviene QoS 1 con sesión persistente y un
receptor que tolere duplicados, y QoS 2 queda para los casos en que el duplicado es inaceptable. Los cortes de conexión, que el Experimento 1 no
cubrió, quedan para el ensayo de la @sec-exp-sincronizacion.

== Capa de red

=== NAT y firewalls <sec-nat-firewalls>

La mayoría de los dispositivos considerados en este trabajo no tiene una dirección IP pública propia. Un robot en un depósito, un sensor en
una planta industrial o un teléfono en una red celular se encuentran detrás de un traductor de direcciones (NAT), que reemplaza la dirección
y el puerto de origen de cada datagrama saliente por los de su interfaz pública y registra la correspondencia en una tabla, para poder traducir
en sentido inverso las respuestas que llegan @kurose2017. Ante el agotamiento de las direcciones IPv4, muchos proveedores de acceso agregan
además su propio NAT de gran escala, de modo que el tráfico del dispositivo puede atravesar dos traducciones antes de llegar a Internet @rfc6888.

La tabla de traducción solo incorpora una entrada cuando un host interno inicia una conexión. Un segmento que llega desde Internet sin una entrada
que le corresponda no tiene destinatario y se descarta, de manera que un dispositivo detrás de un NAT no puede actuar como servidor sin una
configuración explícita en el router, como el reenvío de puertos. Los firewalls con estado producen el mismo efecto, por diseño admiten el tráfico
de respuesta de las conexiones iniciadas desde la red interna y bloquean las conexiones entrantes no solicitadas @kurose2017. En ambos casos,
quien administra el broker no controla esos equipos, que pertenecen al cliente o a su proveedor de acceso.

El modelo de MQTT se ajusta a esta restricción, ya que, como se vio en la @sec-mqtt, todos los participantes son clientes y es el dispositivo quien
abre la conexión TCP hacia el broker. Esa conexión saliente crea la entrada en el NAT y en el firewall, y a partir de ella el broker puede entregarle
mensajes al dispositivo, incluidos los comandos que se originan en la nube, como segmentos de una conexión ya establecida. El único requisito sobre
la red del cliente es que permita las conexiones salientes hacia la dirección y el puerto del broker. IANA tiene registrados para MQTT los puertos
TCP 1883, sin cifrado, y 8883, sobre TLS, y, cuando una red restrictiva solo deja pasar el tráfico web, MQTT puede transportarse sobre WebSocket
@mqtt50, a cambio de la sobrecarga de ese protocolo adicional.

La contracara de este esquema es que las entradas de la tabla no son permanentes. El NAT no tiene forma de saber si una conexión inactiva sigue en
uso, por lo que la elimina tras un tiempo sin tráfico. Para las conexiones TCP establecidas, el IETF (Internet Engineering Task Force), una organización
internacional abierta de normalización que tiene como objetivos el contribuir a la ingeniería de internet, exige que ese tiempo no sea menor que dos
horas y cuatro minutos @rfc5382. En las mediciones sobre gateways domésticos que cita el RFC 8323, el promedio para TCP fue seis horas y veintiseis
minutos @rfc8323, pero se trata de un mínimo recomendado y no de una garantía, para un equipo que no lo cumple, o un firewall intermedio configurado
con un plazo menor, descarta la entrada mucho antes. Si la entrada desaparece mientras la conexión está inactiva, ninguno de los extremos se entera.
El siguiente segmento del broker hacia el dispositivo se descarta en el NAT, y el siguiente del dispositivo genera una entrada nueva, con otro puerto
público, que el broker no reconoce como parte de ninguna conexión. El resultado es una conexión que figura como abierta en ambos extremos pero que ya
no transporta datos, situación especialmente grave para un suscriptor que espera comandos y no transmite por iniciativa propia.

El keep-alive de MQTT, definido en la @sec-mqtt, resuelve también este problema. Al obligar al cliente a enviar algún paquete de control dentro de
cada intervalo, aunque sea un PINGREQ, garantiza que la conexión nunca permanezca inactiva más que ese intervalo, y con ello refresca la entrada en
cada NAT y firewall del trayecto, siempre que el intervalo sea menor que su tiempo de expiración. TCP ofrece un mecanismo análogo, pero es opcional y
su intervalo predeterminado no debe ser menor que dos horas @rfc1122, un valor demasiado largo frente a los plazos de muchos equipos intermedios.
Por eso el mantenimiento de la conexión se resuelve en la capa de aplicación, donde el intervalo es configurable por cada cliente. La especificación
de MQTT indica que su valor depende de la aplicación y que suele ser de algunos minutos @mqtt50, y en los nodos del Experimento 1 (@sec-exp-mqtt-https)
se usó un intervalo de 60 segundos. Elegirlo implica un compromiso, ya que un intervalo corto mantiene vivas las entradas y detecta antes una conexión
rota, pero cada PINGREQ y su respuesta consumen ancho de banda y, en los dispositivos móviles, obligan a activar la radio, con el consiguiente gasto de
energía.

=== Ruteo interno <sec-ruteo-interno>

Entre el dispositivo y el broker, cada datagrama atraviesa la red local del cliente, la de su proveedor de acceso, eventualmente las de uno o más
proveedores de tránsito y la del proveedor de nube que aloja el broker, es decir, redes administradas por organizaciones distintas. Internet organiza
esas redes en sistemas autónomos (AS), conjuntos de routers bajo una misma administración, y divide el problema del encaminamiento en dos niveles.
Dentro de cada AS, un protocolo de ruteo interno (IGP) calcula los caminos entre sus routers, mientras que entre AS es BGP el que intercambia la
información de alcanzabilidad @kurose2017. Para MQTT, ambos niveles son transparentes mientras funcionan. Su comportamiento importa cuando un enlace o
un router falla y la red debe encontrar un camino alternativo, porque durante ese lapso los segmentos de la conexión se pierden. Esta subsección y la
siguiente describen cómo y en cuánto tiempo se recupera cada protocolo.

OSPF es un protocolo de estado de enlace. Cada router descubre a sus vecinos mediante paquetes Hello y describe sus enlaces, con el costo de cada uno,
en anuncios de estado de enlace (LSA) que se inundan a todos los routers del área. Así, todos construyen la misma base de datos con la topología
completa, y cada uno calcula, con el algoritmo de Dijkstra, el árbol de caminos más cortos con raíz en sí mismo @rfc2328. Ante una falla, el router que
la detecta inunda un LSA actualizado y cada router recalcula sus rutas de forma independiente, sin esperar a que lo hagan sus vecinos, lo que le da a
OSPF una convergencia rápida. El factor que suele dominar es la detección. Si la falla deja la interfaz caída, el router la advierte de inmediato; si
no, como cuando el enlace pasa por un switch intermedio, recién la advierte cuando deja de recibir paquetes Hello durante el RouterDeadInterval, que
con los valores habituales de 10 segundos entre Hellos es de 40 segundos @rfc2328. Mecanismos como BFD reducen esa detección a fracciones de segundo
@rfc5880. OSPF admite además dividir el AS en áreas, de modo que la inundación y el recálculo se limitan al área afectada @kurose2017.

RIP, en cambio, es un protocolo de vector distancia basado en el algoritmo de Bellman-Ford. Cada router conoce solo las distancias, medidas en saltos,
que le anuncian sus vecinos, y les envía su tabla completa cada 30 segundos @rfc2453. La métrica admite como máximo 15 saltos, ya que el valor 16
representa un destino inalcanzable, lo que limita el tamaño de las redes en las que puede usarse. Su convergencia es lenta: una ruta se da por perdida
recién después de 180 segundos sin anuncios que la confirmen, y la noticia de la falla avanza de a un router por intercambio. Además, como los vecinos
pueden seguir anunciando caminos que pasaban por el enlace caído, la métrica de la ruta puede crecer de a poco hasta llegar a 16, el problema conocido
como conteo hasta el infinito @kurose2017. El horizonte dividido con reversa envenenada y las actualizaciones disparadas atenúan el problema, pero no
lo eliminan en los bucles de tres o más routers @rfc2453.

EIGRP, desarrollado por Cisco y publicado como RFC informativo, es un protocolo de vector distancia avanzado que evita estas limitaciones mediante el
algoritmo DUAL @rfc7868. Usa una métrica compuesta, que por defecto combina ancho de banda y retardo, y envía actualizaciones solo cuando hay cambios.
Para cada destino registra, además del sucesor (el vecino por el que pasa la mejor ruta), los sucesores factibles: vecinos cuya distancia anunciada es
menor que la mejor distancia que el router conoce hacia ese destino, condición que garantiza que el camino a través de ellos no forma un bucle. Si el
sucesor falla y existe un sucesor factible, el router conmuta a él de forma local e inmediata; solo si no lo hay pasa la ruta a estado activo y
consulta a sus vecinos, lo que demora la convergencia @rfc7868. Para detectar vecinos caídos, en los enlaces de alta velocidad envía Hellos cada 5
segundos con un tiempo de espera de 15 segundos @rfc7868. La @tab-convergencia-igp resume las diferencias entre los tres protocolos.

#figure(
  table(
    columns: 4,
    align: (left, left, left, left),
    table.header([], [*RIP*], [*OSPF*], [*EIGRP*]),
    [*Tipo*], [Vector distancia], [Estado de enlace], [Vector distancia avanzado],
    [*Algoritmo*], [Bellman-Ford], [Dijkstra], [DUAL],
    [*Métrica*], [Saltos (máximo 15)], [Costo por enlace], [Compuesta (ancho de banda y retardo)],
    [*Actualizaciones*], [Tabla completa cada 30~s], [LSA ante cambios y refresco cada 30~min], [Solo ante cambios],
    [*Detección de una falla no visible en la interfaz*], [180~s sin anuncios], [40~s sin Hellos], [15~s sin Hellos],
    [*Recuperación*],
    [Propagación de a un salto; posible conteo hasta el infinito],
    [Recálculo independiente en cada router del área],
    [Inmediata con sucesor factible; si no, consulta a los vecinos],
  ),
  caption: [Protocolos de ruteo interno, con los temporizadores predeterminados de sus especificaciones @rfc2453 @rfc2328 @rfc7868.],
) <tab-convergencia-igp>

Para una conexión MQTT, estas diferencias se traducen en el tiempo durante el cual sus segmentos se pierden: desde fracciones de segundo, cuando la
falla se detecta en la interfaz o con BFD, hasta decenas de segundos con los temporizadores predeterminados de OSPF y EIGRP, y varios minutos en RIP.
Qué ocurre con la conexión según la duración de ese lapso se analiza en la @sec-convergencia.

=== Ruteo externo <sec-ruteo-externo>

El broker no suele estar en el mismo AS que el dispositivo. Un robot conectado a la red de un cliente llega a Internet a través del AS de su proveedor
de acceso, el broker se aloja en el AS de un proveedor de nube y entre ambos puede haber uno o más proveedores de tránsito. El camino entre AS lo
determina BGP, el protocolo de ruteo externo de Internet @rfc4271.

BGP es un protocolo de vector de caminos. Los routers de borde de AS vecinos establecen sesiones eBGP sobre conexiones TCP y se anuncian prefijos
acompañados de atributos, entre ellos el AS-PATH, la lista de AS que atravesó el anuncio, que permite descartar las rutas que contienen al propio AS y
evitar así los bucles. Dentro de cada AS, las sesiones iBGP distribuyen esas rutas a los demás routers @rfc4271 @kurose2017. A diferencia de un IGP,
BGP no busca el camino más corto. Cada AS elige entre las rutas disponibles según sus políticas, que reflejan relaciones comerciales, como la de no
ofrecer tránsito gratuito a otro proveedor, y solo después considera la longitud del AS-PATH y otros criterios de desempate @kurose2017. En
consecuencia, el trayecto entre un dispositivo y el broker no es necesariamente el más corto ni el de menor latencia, y puede cambiar por decisiones
administrativas que no controlan ni el dispositivo ni el operador del broker.

La convergencia de BGP es mucho más lenta que la de un IGP. Un router detecta la caída de un vecino cuando expira el tiempo de espera de la sesión,
para el que la especificación sugiere 90 segundos, con mensajes KEEPALIVE cada 30 segundos. Además, para limitar la cantidad de actualizaciones, un
router espera un intervalo mínimo entre anuncios sucesivos hacia un mismo vecino, con un valor sugerido de 30 segundos entre vecinos externos @rfc4271.
Cuando un prefijo deja de ser alcanzable por un camino, los routers no descubren de inmediato cuál es la alternativa válida, sino que van probando
caminos más largos que todavía figuran en sus tablas, cada uno demorado por ese intervalo. En mediciones sobre Internet, Labovitz et al. observaron que
la conmutación a un camino alternativo entre dominios demoraba en promedio tres minutos, y que algunas recuperaciones provocaban oscilaciones de las
tablas de ruteo de hasta 15 minutos @labovitz2000.

Para el stack estudiado, esto tiene dos consecuencias. La primera es que una falla entre AS puede dejar al dispositivo sin camino hacia el broker
durante un tiempo comparable o mayor que el intervalo de keep-alive de MQTT, lo que fuerza el cierre de la conexión y la reconexión del cliente. La
segunda es que la mitigación está, en su mayor parte, fuera del alcance de quien diseña el sistema. El único factor que controla es la ubicación del
broker: alojarlo en una región del proveedor de nube cercana a los dispositivos reduce la cantidad de AS del trayecto y, con ella, la exposición a la
convergencia de BGP.

=== Convergencia y conexiones de larga duración <sec-convergencia>

Las subsecciones anteriores describieron cuánto tarda la red en encontrar un camino alternativo después de una falla. Mientras tanto, el trayecto entre
el dispositivo y el broker se comporta como un agujero negro: los routers que todavía apuntan al enlace caído descartan los segmentos, y durante la
reconvergencia pueden formarse bucles transitorios, en los que los segmentos circulan hasta que se agota su TTL @rfc5715. Ni TCP ni MQTT reciben aviso
de lo que ocurre, porque el ruteo opera en la capa de red y las direcciones de los extremos no cambian. Lo único que observa el emisor es que sus
segmentos dejan de ser confirmados. Lo que le pasa a la conexión depende, entonces, de cómo se compara la duración del corte con dos temporizadores de
los extremos: el de retransmisión de TCP y el keep-alive de MQTT.

TCP reacciona a la falta de confirmaciones con su temporizador de retransmisión (RTO). Cuando este vence, retransmite el segmento más antiguo sin
confirmar y duplica el RTO, de modo que los intentos sucesivos quedan cada vez más espaciados @rfc6298. Con un RTO inicial de 1 s, los reintentos
ocurren aproximadamente a 1, 3, 7, 15, 31 y 63 s del primer envío. Esto tiene una consecuencia poco intuitiva, ya que la conexión no se recupera en el
instante en que la red converge, sino en el reintento siguiente. Si el camino se restablece a los 20 s, por ejemplo, el próximo intento sale recién a
los 31 s, y la demora total resulta un 50 % mayor que el propio corte; en el peor caso, puede llegar casi al doble. Por otra parte, TCP tolera cortes
largos antes de abandonar la conexión: la especificación exige que siga reintentando durante al menos 100~s @rfc1122, y con los valores predeterminados
de Linux, el sistema operativo del servidor de los experimentos, el plazo es de unos 15 minutos @linux-ip-sysctl.

En la práctica, quien suele cerrar primero la conexión es el keep-alive de MQTT. Si el broker no recibe ningún paquete de control del cliente durante
una vez y media el intervalo de keep-alive, debe cerrar la conexión, y el cliente que no recibe respuesta a un PINGREQ en un tiempo razonable también
debería cerrarla @mqtt50. Con el intervalo de 60 s del Experimento 1, el broker da por caído a un cliente tras 90 s sin recibir nada de él. El umbral
efectivo es incluso menor, porque durante el corte el PINGREQ queda detrás de los segmentos pendientes y depende de los mismos reintentos. Si los
reintentos caen a los 63 y a los 127 s, un corte de algo más de un minuto ya alcanza para que el broker cierre la conexión, aunque la red haya
convergido antes de los 90 s. Así, según la duración del corte se distinguen tres regímenes, que resume la @tab-regimenes-corte.

#figure(
  table(
    columns: 4,
    align: (left, left, left, left),
    table.header([*Duración del corte*], [*Ejemplos*], [*Conexión*], [*Efecto sobre los mensajes*]),
    [Unos pocos segundos],
    [IGP con detección en la interfaz o con BFD; EIGRP con sucesor factible],
    [Se mantiene; TCP retransmite una o dos veces],
    [Llegan todos, con más latencia; QoS 1 puede duplicarlos],

    [Menor que 1,5 veces el keep-alive],
    [OSPF o EIGRP con detección por ausencia de Hellos],
    [Se mantiene, con reintentos cada vez más espaciados],
    [Llegan todos, juntos y con una demora del orden del corte],

    [Mayor que 1,5 veces el keep-alive],
    [RIP con detección por tiempo; BGP ante el retiro de una ruta],
    [El broker la cierra y publica la última voluntad; el cliente se reconecta],
    [Se pierden los de QoS 0 en tránsito; los de QoS 1 y 2 se reenvían si se retoma la sesión],
  ),
  caption: [Efecto de un corte del camino sobre una conexión MQTT según su duración. Con el keep-alive de 60~s del Experimento 1, el umbral es de 90~s, o algo menos por el espaciamiento de los reintentos de TCP.],
) <tab-regimenes-corte>

*Cortes de hasta unos pocos segundos.* Son los que produce un IGP cuando la falla se detecta en la interfaz o mediante BFD, o EIGRP cuando cuenta con
un sucesor factible. TCP los absorbe con uno o dos reintentos y la única consecuencia es una demora adicional del orden del RTO. Es el único régimen
que cubrió el Experimento 1, y de forma indirecta, ya que inyectó pérdidas aleatorias e independientes y no cortes. Con 5 % de pérdida, la entrega fue
del 100 % en todos los transportes y no hubo desconexiones de MQTT, pero el percentil 99 de la latencia de MQTT QoS 0 subió a unos 3 s, por pérdidas
repetidas del mismo segmento con el RTO duplicado en cada intento (@tab-perdida). En este régimen, QoS 1 no mejora la entrega y agrega duplicados,
porque el cliente reenvía el PUBLISH mientras TCP todavía está recuperando el original, como se discute en la @sec-qos-tcp.

*Cortes menores que una vez y media el keep-alive.* Corresponden, por ejemplo, a una falla que OSPF o EIGRP detectan por la ausencia de Hellos con sus
temporizadores predeterminados (@tab-convergencia-igp). La conexión sobrevive, pero las lecturas generadas durante el corte se acumulan sin confirmar
en el dispositivo y llegan juntas cuando el camino se restablece, con una demora del orden del corte más la espera hasta el reintento siguiente. Ningún
mensaje se pierde, cualquiera sea el nivel de QoS, pero su valor puede haber caducado: una lectura de telemetría que llega con decenas de segundos de
atraso, o un comando que el robot recibe tarde, pueden resultar tan inútiles como uno perdido. La memoria del dispositivo impone además un límite, ya
que un microcontrolador no puede acumular indefinidamente las lecturas pendientes.

*Cortes mayores que una vez y media el keep-alive.* Son los de RIP ante una falla que no se ve en la interfaz, o los de BGP cuando se retira una ruta,
que suelen durar minutos (@sec-ruteo-externo). El broker cierra la conexión y, como el cierre es anormal, publica el mensaje de última voluntad del
cliente, con lo que los demás participantes se enteran de la caída (@sec-mqtt). Cuando el camino se restablece, el siguiente segmento del dispositivo
llega a un broker que ya no reconoce la conexión y que responde con un _reset_, de modo que el cliente también la da por cerrada y se reconecta. La
reconexión tiene un costo: un nuevo handshake TCP y TLS, que en el Experimento 1 constituye el costo fijo por conexión (@tab-costo) y que al ESP32 le
insume unos 3 s de cómputo. Lo que se pierde depende del nivel de QoS y de la sesión. Los mensajes de QoS 0 que estaban en tránsito se pierden sin
aviso. Los de QoS 1 y 2 que no habían sido confirmados se reenvían al reconectarse, siempre que el cliente retome la sesión anterior y el broker la
haya conservado @mqtt50, y en ese caso el broker conserva también las suscripciones y los mensajes que llegaron para el cliente durante el corte. Es en
este régimen donde los niveles de QoS y las sesiones persistentes aportan lo que TCP no puede dar, porque la confiabilidad de TCP termina con la
conexión.

Hay un caso en el que la duración del corte deja de importar: cuando el camino nuevo atraviesa un NAT distinto del original, como cuando un proveedor
conmuta a otro equipo de NAT de gran escala, o cuando el dispositivo cambia de red, por ejemplo de Wi-Fi a la red celular. La traducción de la conexión
no existe en el nuevo NAT (@sec-nat-firewalls), por lo que la conexión se pierde aunque la red converja de inmediato, con las mismas consecuencias que
en el tercer régimen.

El Experimento 1 no incluyó cortes de conexión, por lo que los dos últimos regímenes no se midieron allí (@sec-exp-mqtt-https). Se ensayan en el experimento de la @sec-exp-sincronizacion, sobre la misma plataforma, aplicando con `tc netem` una pérdida del 100 % sobre la interfaz de un nodo durante un intervalo fijo, con duraciones por debajo y por encima del umbral del keep-alive. Esas mediciones muestran además que un corte breve puede cerrar la conexión por el lado del cliente, antes del umbral de una vez y media el keep-alive que aplica el broker.

== Ruteo por tópicos y ruteo IP <sec-ruteo-topicos>

// El router decide por dirección IP de destino. el broker decide por tópico.
// Comparar tablas de ruteo con suscripciones y comodines (+, #).
// TODO(casos de uso) Ejemplo real: Digitransit codifica un hash en los niveles del tópico y permite suscribirse por zona
// geográfica con comodines, análogo a un prefijo en una tabla de ruteo.
// Fuente: https://www.digitransit.fi/en/developers/apis/5-realtime-api/vehicle-positions/digitransit-mqtt (GTFS-Realtime en Protobuf sobre MQTT).
// TODO(prometido en Casos de uso, @sec-caso-industria) Retomar la limitación de Sparkplug. Como las métricas viajan dentro de la
// carga útil, el broker solo rutea por nodo o dispositivo y no se puede suscribir a una métrica individual.
// TODO(prometido en Casos de uso, @sec-caso-lora) Comparar con Meshtastic. La malla difunde cada paquete, y el broker, que rutea
// por tópico sin interpretar la carga útil, entrega todas las copias publicadas por varios puentes (la deduplicación queda en los suscriptores).
//

Las secciones anteriores describieron cómo la red lleva cada segmento desde el dispositivo hasta el broker. Entre el publicador y los
suscriptores hay, sin embargo, una segunda decisión de encaminamiento, que se toma en la capa de aplicación. Un router que recibe un
datagrama examina la dirección IP de destino de su cabecera y decide, a partir de su tabla, si lo entrega directamente, a qué otro router
lo reenvía o si debe descartarlo e informar el error al origen @stallings2004[pp.~602--603]. El broker, al recibir un paquete PUBLISH,
examina el nombre de tópico y decide, a partir de las suscripciones registradas, a qué clientes debe entregarlo. Ambos son mecanismos de
encaminamiento basados en una tabla y en una clave que viaja en el encabezado, y compararlos permite ver qué ideas del ruteo IP reaparecen
en MQTT y en qué puntos se aparta de ellas.

=== Dirección IP y nombre de tópico

La clave del router es la dirección IP de destino, un número de longitud fija (32 bits en IPv4) dividido en una parte de red y una parte
de computador. La frontera entre ambas la indica la máscara: el router realiza una operación AND bit a bit entre la dirección y la máscara
y obtiene así el número de red sobre el que decide @stallings2004[pp.~612--613]. Con el direccionamiento sin clases (CIDR), la parte de
red puede tener cualquier longitud y se escribe como un prefijo de la forma `a.b.c.d/x`, donde `x` es la cantidad de bits que la componen
@kurose2017[sec.~4.3.3] @rfc4632.

La clave del broker es el nombre de tópico, una cadena de texto UTF-8 de hasta 65 535 bytes, organizada en niveles separados por `/`,
sin cantidad fija de niveles y en la que se distinguen mayúsculas de minúsculas @mqtt50. Al igual que una dirección IP, se lee de izquierda
a derecha, de lo general a lo particular: en el tópico `flota/robot1/bateria` de la @sec-mqtt, cada nivel restringe el anterior, como
cada bit adicional del prefijo restringe el bloque de direcciones. La diferencia está en quién define la jerarquía. En IP la fijan la
asignación de bloques a proveedores y organizaciones, y la máscara se expresa en bits; en MQTT la define quien diseña el sistema, y cada
nivel tiene el significado que la aplicación le asigne.

Hay, además, una diferencia de fondo en lo que identifica cada clave. Una dirección IP de unidifusión identifica una interfaz, es decir, un
receptor, y es el emisor quien elige a quién se dirige. Un tópico identifica el contenido del mensaje y no a sus receptores: el publicador
no sabe quién lo recibirá, y son los suscriptores quienes eligen qué reciben. Es el desacoplamiento en el espacio del modelo
publicador/suscriptor descrito en la @sec-pubsub.

=== Tablas de ruteo y tablas de suscripciones

Cada entrada de una tabla de ruteo asocia un destino con el siguiente nodo por el que debe salir el paquete, de modo que cada router solo
necesita conocer el próximo salto hacia cada destino @stallings2004[p.~386]. Esas entradas las instala el administrador o las calculan los
protocolos de ruteo, como OSPF, RIP, EIGRP y BGP, a partir del conocimiento que cada router tiene de la topología
@stallings2004[p.~642], tal como se analizó en la @sec-ruteo-interno y la @sec-ruteo-externo. Los hosts de destino no participan en su
construcción.

La tabla del broker asocia, en cambio, filtros de tópico con sesiones de clientes, junto con las opciones de cada suscripción, como el
nivel máximo de QoS. Sus entradas no las calcula ningún algoritmo a partir de una topología, sino que las crean los propios receptores con
un paquete SUBSCRIBE y las eliminan con UNSUBSCRIBE o al terminar la sesión @mqtt50. En un broker único no hay ningún protocolo que
sincronice tablas entre nodos, y la topología se reduce al conjunto de conexiones abiertas.

Por eso, el análogo más cercano en IP no es el ruteo de unidifusión, sino la multidifusión. Allí, las estaciones usan IGMP para
suscribirse a un grupo de multidifusión y para abandonarlo, y los routers consultan periódicamente qué grupos interesan a las estaciones
de cada red @stallings2004[p.~638]. El router no necesita saber qué estaciones pertenecen a cada grupo, sino solo si queda al menos un
miembro activo en la red @stallings2004[p.~641], y debe traducir cada dirección de grupo a la lista de redes que contienen miembros
@stallings2004[p.~636]. El paquete SUBSCRIBE de MQTT cumple la función del informe de pertenencia de IGMP y el tópico, la de la dirección
de grupo. Como en la multidifusión, las fuentes no necesitan suscribirse para enviar @stallings2004[p.~638]. La diferencia es que las
direcciones de grupo IP son identificadores planos, mientras que los tópicos son jerárquicos y admiten comodines.

La @tab-tabla-ruteo-suscripciones muestra una tabla de cada tipo y la decisión que produce cada una ante un mismo caso: un datagrama
dirigido a una dirección que coincide con varias entradas, y un mensaje cuyo tópico coincide con varias suscripciones.

#figure(
  kind: table,
  grid(
    columns: 2,
    gutter: 1.5em,
    table(
      columns: 2,
      align: (left, left),
      table.header([*Prefijo*], [*Interfaz de salida*]),
      [`10.1.0.0/16`], [`eth1`],
      [`10.1.2.0/24`], [`eth2`],
      [`0.0.0.0/0`], [`eth0`],
      table.cell(colspan: 2)[Destino `10.1.2.7`: coinciden las tres entradas y se reenvía solo por `eth2`.],
    ),
    table(
      columns: 2,
      align: (left, left),
      table.header([*Filtro*], [*Cliente*]),
      [`flota/robot1/#`], [`panel`],
      [`flota/+/bateria`], [`monitor-energia`],
      [`#`], [`registro`],
      table.cell(
        colspan: 2,
      )[Tópico `flota/robot1/bateria`: coinciden los tres filtros y se entrega a los tres clientes.],
    ),
  ),
  caption: [Tabla de reenvío de un router (izquierda) y tabla de suscripciones de un broker (derecha). Ante varias coincidencias, el router elige una sola entrada, la de prefijo más largo, mientras que el broker entrega el mensaje a todas.],
) <tab-tabla-ruteo-suscripciones>

=== Comodines y prefijos

El comodín `#` cumple en una suscripción el papel de un prefijo en una tabla de ruteo. El filtro `flota/robot1/#` abarca todos los
tópicos que comienzan con esos dos niveles, incluido el propio `flota/robot1`, del mismo modo que `200.23.16.0/20` abarca todas las
direcciones cuyos primeros 20 bits coinciden con los del bloque, y el filtro `#` por sí solo, que coincide con cualquier tópico, se asemeja
a la ruta por defecto `0.0.0.0/0`. Por eso, la especificación exige que `#` sea el último carácter del filtro y ocupe un nivel completo
@mqtt50: como un prefijo, solo puede dejar libre el final de la clave.

La semejanza se rompe en la regla que se aplica cuando hay varias coincidencias. Una dirección de destino puede coincidir con más de una
entrada de la tabla, y en ese caso el router aplica la regla del prefijo más largo: elige la entrada más específica y reenvía el datagrama
solo por la interfaz asociada a ella @kurose2017[sec.~4.2.1]. Esa regla es la que permite que un bloque más específico «perfore» un bloque
agregado más general sin que se pierda la agregación @kurose2017[sec.~4.3.3]. El broker, en cambio, no elige: entrega el mensaje a todos
los clientes cuyos filtros coinciden. En la @tab-tabla-ruteo-suscripciones, la ruta por defecto solo recibe el tráfico que ninguna otra
entrada captura, mientras que el cliente suscrito a `#` recibe todos los mensajes, además de los que reciben los otros dos. Cuando las
coincidencias corresponden a un mismo cliente, como `flota/robot1/#` y `flota/+/bateria` suscritos por la misma sesión, la especificación
de la versión 5.0 exige que el broker respete el mayor de los niveles de QoS de las suscripciones coincidentes y le permite enviar una sola
copia o una por cada suscripción @mqtt50, de modo que el resultado depende de la implementación. Mosquitto, por ejemplo, ofrece una opción
de configuración para elegir entre ambos comportamientos @mosquitto-conf. En la versión 5.0, el cliente puede además asociar un
identificador a cada suscripción, que el broker incluye en los mensajes entregados para indicar qué suscripciones los originaron @mqtt50.

El comodín `+`, que reemplaza exactamente un nivel en cualquier posición del filtro, no tiene equivalente en el ruteo con prefijos. Un
prefijo CIDR solo puede fijar los bits del comienzo de la dirección y dejar libres los del final, mientras que `flota/+/bateria` fija el
primer y el tercer nivel y deja libre el del medio. Para expresar lo mismo con prefijos haría falta una entrada por robot. El análogo más
cercano en la capa de red es el reenvío generalizado de las redes definidas por software, en el que cada entrada de la tabla de flujos
compara varios campos de la cabecera a la vez y cada campo puede contener comodines, como una dirección `128.119.*.*`
@kurose2017[sec.~4.4.1]. Cada nivel de un tópico se comporta, en ese sentido, como un campo independiente de la cabecera. Aun así, la regla
de decisión vuelve a ser distinta, porque cuando un paquete coincide con varias entradas de la tabla de flujos se aplica solo la de mayor
prioridad @kurose2017[sec.~4.4.1].

La especificación agrega una excepción que no tiene análogo en IP. Los filtros que comienzan con un comodín no coinciden con los tópicos
que comienzan con `$`, como los de `$SYS`, que muchos brokers usan para publicar sus propias estadísticas @mqtt50. Un cliente suscrito a `#`
no recibe, por lo tanto, los mensajes internos del broker, salvo que se suscriba a ellos explícitamente.

El costo de la búsqueda también se resuelve de manera diferente. Un router de alta velocidad debe encontrar el prefijo más largo en
nanosegundos, por lo que la búsqueda se implementa en hardware y con algoritmos más eficientes que un recorrido lineal de la tabla
@kurose2017[sec.~4.2.1]. Un broker hace la búsqueda en software. EMQX, por ejemplo, organiza los filtros en un árbol de tópicos, una estructura jerárquica
en la que compara cada tópico publicado con los filtros suscritos, incluidos los que tienen comodines @emqx-cluster, y su documentación advierte que el uso de comodines en un gran número de clientes puede afectar el desempeño
@emqx-wildcard. Cuando EMQX funciona como un conjunto de nodos, la analogía con el ruteo IP se vuelve literal. Además del árbol, cada nodo
mantiene una tabla, que la propia documentación llama tabla de ruteo, que asocia cada filtro con los nodos que tienen suscriptores, y una
tabla de suscripciones local, que asocia cada filtro con los clientes conectados a ese nodo. El nodo que recibe un PUBLISH consulta el
árbol y la tabla de ruteo, reenvía el mensaje a los nodos correspondientes, y cada uno de ellos lo entrega a sus clientes según su tabla
local @emqx-cluster. Es una estructura en dos niveles, como la del ruteo entre sistemas autónomos: un nodo no necesita saber qué cliente se
suscribió en otro nodo, sino solo a qué nodo debe enviarle el mensaje.

=== Agregación y diseño del espacio de tópicos

La utilidad de un prefijo depende de cómo se asignaron las direcciones. Si los bloques se reparten de manera jerárquica, primero a los
proveedores y luego a sus clientes, un único prefijo puede anunciar muchas redes, lo que se conoce como agregación de rutas y mantiene
pequeñas las tablas @kurose2017[sec.~4.3.3] @rfc4632. Stallings señala, a propósito de IPv6, que las direcciones pueden agruparse por
jerarquías de red, por proveedores de acceso, por proximidad geográfica o por institución, y que esas agrupaciones conducen a tablas más
pequeñas y a consultas más rápidas @stallings2004[p.~624]. Si las direcciones no siguen esa jerarquía, la agregación deja de ser posible.

Con los tópicos ocurre lo mismo. Un filtro con comodines solo puede seleccionar conjuntos de mensajes que la jerarquía de tópicos agrupa,
y lo que no se codifica en el tópico no puede seleccionarse con ninguna suscripción. El orden y el contenido de los niveles equivalen, por
lo tanto, al plan de direccionamiento de una red, y se fijan al diseñar el sistema. En el Experimento 1, cada nodo publica en
`exp/tel/{ID del nodo}` y el backend recibe las lecturas de todos con una única suscripción a `exp/tel/+` (@sec-exp-mqtt-https), una
entrada que cumple la función de una ruta agregada.

La API de posiciones de vehículos de Digitransit, el servicio de información de transporte público de Finlandia, lleva esta idea a la
ubicación geográfica, de manera análoga al agrupamiento por proximidad que menciona Stallings. Su broker publica la posición de cada
vehículo codificada como GTFS-Realtime en Protocol Buffers, y el tópico incluye, después de niveles como la ciudad, la línea, el viaje y
el identificador del vehículo, una forma simplificada de _geohash_: un nivel con las partes enteras de la latitud y la longitud, en la
forma `60;24`, seguido de tres niveles que intercalan el primer, el segundo y el tercer decimal de ambas coordenadas. Así, la posición
(60,123; 24,789) se codifica como `60;24/17/28/39` @digitransit-mqtt. Cada nivel adicional reduce diez veces el lado de la celda en cada
coordenada, del mismo modo que cada bit adicional de un prefijo reduce a la mitad el bloque de direcciones, y la documentación destaca que
este formato permite suscribirse con facilidad a zonas geográficas y recomienda especificar los niveles del tópico para limitar lo que se
recibe @digitransit-mqtt. A partir de la estructura documentada, por ejemplo, el filtro
`/gtfsrt/vp/tampere/+/+/+/+/+/+/+/+/+/+/61;23/47/#` recibe los vehículos de Tampere ubicados en una celda de una décima de grado de lado,
cualquiera sea su línea o su viaje.

El ejemplo muestra también los límites de la analogía. Una zona que no coincide con las celdas exige varias suscripciones, del mismo modo
que un rango de direcciones que no está alineado con una potencia de dos exige varios prefijos. Y, a diferencia de una dirección IP, el
tópico de un vehículo cambia a medida que se mueve, de modo que un suscriptor que sigue una zona ve aparecer y desaparecer vehículos sin
que nadie modifique su suscripción. El costo de esa expresividad es el tamaño del encabezado: un tópico de unos veinte niveles se repite en
cada PUBLISH, un costo que el alias de tópico de la versión 5.0, descrito en la @sec-stack, permite reducir.

=== Entrega a uno, a todos y a uno de un grupo

IP distingue tres tipos de direcciones: las de unidifusión, que identifican una única interfaz; las de multidifusión, cuyo paquete se
entrega a todas las interfaces de un conjunto; y las de monodifusión (_anycast_), cuyo paquete se entrega a una sola interfaz de un
conjunto, la más cercana según la métrica de los protocolos de ruteo @stallings2004[p.~624]. Una suscripción ordinaria de MQTT se comporta
como la multidifusión, ya que el mensaje llega a todas las sesiones con un filtro coincidente. La versión 5.0 agrega las suscripciones
compartidas, que usan filtros de la forma `$share/{nombre del grupo}/{filtro}` y entregan cada mensaje a una sola de las sesiones del
grupo @mqtt50, lo que las asemeja a la monodifusión. La diferencia es el criterio de elección, ya que en IP decide la métrica de ruteo,
mientras que la especificación de MQTT no establece cómo elige el broker y en la práctica suele usarse para repartir la carga entre varias
copias de un mismo servicio, como el servidor de red de ChirpStack (@sec-caso-lora). Las suscripciones ordinarias que coinciden con el
mismo tópico siguen recibiendo cada una su copia.

MQTT no tiene, en cambio, una forma de dirigir un mensaje a un cliente concreto. Para enviar una orden a `robot1` se publica en un tópico
al que, por convención, solo ese robot se suscribe, como `flota/robot1/comandos`. La unidifusión surge así de la convención de nombres,
y solo queda garantizada si el broker controla quién puede suscribirse a cada tópico. Mosquitto lo permite con listas de control de acceso
cuyos patrones sustituyen el identificador o el usuario de cada cliente, de modo que una regla como `pattern read flota/%c/comandos` deja
leer ese tópico solo al cliente cuyo identificador coincide con el nivel correspondiente @mosquitto-conf. Es el esquema que aplica
OpenRobOps para que un robot no pueda leer los datos de otro (@sec-caso-inorbit), y cumple en el broker la función que en la red cumplen
las listas de acceso de un router o un firewall, aunque filtra por tópico y no por dirección.

=== Límites del ruteo por tópicos

El ruteo por tópicos se apoya en el ruteo IP y no lo reemplaza. Con un único broker, la decisión por tópico se toma una sola vez, en un
solo salto de la capa de aplicación, y no requiere mecanismos contra bucles como el tiempo de vida de IP. Pero el publicador y cada
suscriptor tienen su propia conexión TCP con el broker, y cada una se encamina por IP de manera independiente, de modo que una falla de
ruteo como las analizadas en la @sec-convergencia puede cortar la entrega a un suscriptor sin afectar a los demás. Como el broker es el
punto por el que pasan todos los mensajes, el ruteo por tópicos funciona como una red superpuesta a Internet, cuyo único nodo intermedio
es el broker.

Además, el broker, como el router, decide únicamente a partir del encabezado. El router no examina el segmento que transporta el datagrama,
y el broker no interpreta la carga útil (@sec-stack), lo que corresponde a la menor expresividad del esquema basado en tópicos frente al
basado en contenido @eugster2003pubsub. Sparkplug muestra la consecuencia. Como las métricas viajan dentro de la carga útil de Protocol
Buffers, el tópico solo identifica el nodo o el dispositivo que las publica, y una aplicación interesada en una única métrica debe recibir
y decodificar todos los mensajes de ese nodo (@sec-caso-industria) @sparkplug3. Es el equivalente a pedirle a un router que encamine
según el contenido de un segmento, algo que su tabla no puede expresar.

Por último, el broker no reconoce mensajes duplicados. Stallings describe la técnica de inundación, en la que cada nodo reenvía el paquete
por todos sus enlaces salvo aquel por el que llegó, de modo que el destino recibe varias copias, y por eso el paquete debe llevar un
identificador único, como el nodo de origen y un número de secuencia, para que el destino conserve una sola y descarte el resto
@stallings2004[p.~387]. La malla de Meshtastic funciona de este modo, y cuando varios puentes reciben el mismo paquete de la malla y lo
publican, el broker trata cada copia como un mensaje independiente y las entrega todas, ya que no interpreta el identificador que viaja en
la carga útil. Son los suscriptores los que deben descartar las copias, a partir del número que la radio de origen asigna a cada paquete
(@sec-caso-lora) @meshtastic-mqtt. La multidifusión IP evita ese problema en los propios routers, que encaminan cada paquete según un árbol
de expansión con raíz en la fuente, de modo que cada red reciba una sola copia @stallings2004[p.~637]. El broker no tiene un mecanismo
equivalente porque no tiene forma de saber que dos PUBLISH son copias del mismo mensaje.

La @tab-ruteo-topicos-ip resume la comparación.

#figure(
  table(
    columns: 3,
    align: (left, left, left),
    table.header([], [*Router IP*], [*Broker MQTT*]),
    [*Clave de la decisión*],
    [Dirección IP de destino, de longitud fija],
    [Nombre de tópico, cadena UTF-8 de niveles separados por `/`],

    [*Qué identifica la clave*], [El receptor (una interfaz)], [El contenido del mensaje],
    [*Quién crea las entradas*], [El administrador o los protocolos de ruteo], [Los suscriptores, con SUBSCRIBE],
    [*Agrupamiento de claves*],
    [Prefijos CIDR: solo fijan el comienzo de la dirección],
    [`#` al final del filtro; `+` en cualquier nivel],

    [*Varias coincidencias*],
    [Se usa solo la de prefijo más largo],
    [Se entrega a todas las suscripciones coincidentes],

    [*Destinos por mensaje*],
    [Uno en unidifusión; todos los miembros en multidifusión; uno del conjunto en monodifusión],
    [Todos los suscriptores; uno por grupo en suscripciones compartidas],

    [*Alcance de la decisión*], [Salto a salto, en cada router del camino], [Una vez, en el broker],
    [*Lo que no examina*], [El segmento de transporte y los datos], [La carga útil],
    [*Duplicados*],
    [La multidifusión los evita con árboles de expansión],
    [No los detecta; quedan a cargo de los suscriptores],
  ),
  caption: [Comparación entre el ruteo IP y el ruteo por tópicos de MQTT @stallings2004 @kurose2017 @mqtt50.],
) <tab-ruteo-topicos-ip>

== Casos de uso <sec-casos-de-uso>

// Organización por dominio y, dentro de cada uno, según el stack. Todos los casos se analizan en los ejes problema,
// stack (versión de MQTT y formato), mecanismos de MQTT usados, aspectos de red y limitaciones. El énfasis está en MQTT y
// Protocol Buffers, no en los detalles de cada dominio. Cada actor y cada término se presentan la primera vez que aparecen,
// y se evita usar con otro sentido el vocabulario del marco teórico (cliente, publicación, suscripción, canal, flujo, orden).

Las secciones anteriores analizaron la combinación de MQTT y Protocol Buffers a partir de las capas y protocolos que atraviesa un mensaje. Esta sección examina cómo la emplean sistemas reales de distintos dominios, con el fin de identificar qué propiedades de cada tecnología aprovechan y qué ventajas y limitaciones aparecen en la práctica. En cada caso se consideran, en la medida en que las fuentes lo permiten, el problema de comunicación que enfrenta, la combinación de protocolo y formato que adopta, los mecanismos de MQTT que utiliza, los aspectos de red involucrados y sus limitaciones. Los mecanismos analizados, como los niveles de QoS o el mensaje de última voluntad, existen tanto en la versión 3.1.1 de MQTT como en la 5.0, por lo que la versión solo se aclara cuando un caso depende de una función que agregó la 5.0.

No todos los casos combinan MQTT y Protocol Buffers. Algunos emplean MQTT con otro formato, y su inclusión permite distinguir el aporte de cada pieza, ya que, como se planteó en la @sec-alternativas, el protocolo de aplicación y el mecanismo de serialización constituyen decisiones independientes. Esa independencia se observa también en sistemas que no se analizan aquí. Zigbee2MQTT, por ejemplo, un programa que conecta a MQTT lámparas, sensores y otros dispositivos domésticos inalámbricos, utiliza MQTT con JSON @zigbee2mqtt, mientras que la aplicación de mensajería Signal utiliza Protocol Buffers sobre WebSocket, sin MQTT @signal-websocket.

=== Mensajería instantánea <sec-caso-mensajeria>

La mensajería en teléfonos móviles ofrece uno de los ejemplos más conocidos de uso masivo de MQTT. Al desarrollar su aplicación de mensajería Messenger, Facebook (hoy Meta) necesitaba entregar los mensajes a los teléfonos con baja latencia y sin agotar su batería, y recurrió a MQTT por tratarse de un protocolo diseñado para hacer un uso moderado del ancho de banda y de la energía. Sobre él construyó un mecanismo que mantiene una conexión persistente entre cada teléfono y los servidores de la empresa, con el que logró entregar en muchos casos los mensajes de un teléfono a otro en cientos de milisegundos en lugar de varios segundos @zhang2011messenger. Se trata del esquema planteado en la @sec-pubsub, en el que el teléfono abre la conexión hacia el servidor y recibe por ella los datos, sin aceptar conexiones entrantes ni consultar periódicamente. La documentación pública no detalla la estructura de tópicos ni los niveles de QoS empleados, por lo que el análisis de este caso se limita al modelo de conexión, al formato de los mensajes y a los límites que la propia empresa encontró en el protocolo.

La evolución posterior de Messenger muestra cuánto influye el formato de los mensajes sobre esa conexión persistente. En su diseño original, la aplicación recibía primero un aviso breve de que había datos nuevos, y luego debía pedirlos mediante una consulta HTTPS, es decir, HTTP protegido con TLS, cuya respuesta en JSON era de gran tamaño. Cada mensaje nuevo exigía así un intercambio adicional y una transferencia voluminosa. Una reforma de 2014 cambió ese esquema. La aplicación pasó a obtener el estado completo de las conversaciones una sola vez, al iniciarse, y a recibir después por MQTT solo los cambios, a medida que se producían. Esa misma reforma reemplazó JSON por Thrift, una herramienta desarrollada originalmente en Facebook que, de forma análoga a Protocol Buffers, define los mensajes mediante un esquema y los codifica por lo general en formato binario @thrift. El cambio de formato redujo aproximadamente a la mitad el tamaño de los mensajes @fein2014messenger. Aunque el formato no es Protocol Buffers, la reducción es coherente con la ventaja de un formato con esquema frente a JSON descrita en la @sec-protobuf-json.

Un artículo que la empresa presentó en 2021 muestra, en cambio, un límite de MQTT a gran escala. Allí se describe el sistema que mantiene actualizada la información que el usuario tiene en pantalla, como los comentarios nuevos en una entrada, los contactos que están en línea o el aviso de que alguien está escribiendo. Cada uno de esos elementos constituye un flujo de datos, es decir, una secuencia de actualizaciones que el teléfono recibe mientras esa información está a la vista, y un mismo teléfono puede tener muchos flujos abiertos a la vez. En MQTT, todos ellos pertenecerían a una única sesión, atendida por un único servidor. Si ese servidor se sobrecarga o falla, no es posible trasladar solo algunos flujos a otro servidor, sino que debe trasladarse la sesión completa. Por eso la empresa diseñó un protocolo propio que viaja por la misma conexión del teléfono, pero permite que cada flujo sea atendido por un servidor distinto y se recupere por separado @barber2021bladerunner.

=== Robótica <sec-caso-robotica>

En la mensajería, la mayor parte del tráfico va del servidor al teléfono. En la robótica móvil, en cambio, el tráfico es intenso en ambos sentidos. Los robots móviles autónomos (AMR) y guiados (AGV) que se emplean en la industria y la logística, pero también en otras tareas como la limpieza, trabajan en flotas, es decir, en conjuntos de robots que comparten una misma instalación, y deben enviar de forma continua su posición y su estado, y al mismo tiempo recibir órdenes. Además, operan en depósitos o fábricas cuya red administra la empresa que los utiliza, y no siempre quien provee el software que los supervisa, por lo que suelen quedar detrás de NAT y firewalls que no aceptan conexiones entrantes. En este dominio se analizan tanto un servicio comercial que combina MQTT con Protocol Buffers como estándares que adoptan MQTT con JSON para que robots y sistemas de distintos fabricantes puedan comunicarse entre sí.

==== InOrbit y OpenRobOps <sec-caso-inorbit>

InOrbit es una empresa que ofrece una plataforma primariamente basada en la nube para supervisar y operar flotas heterogéneas de robots móvils y dispositivos de distintos fabricantes. La empresa publica como código abierto un kit de desarrollo o SDK que desarrolladores pueden utilizar para incorporar dispositivos con la plataforma.

Con el SDK, cada robot abre su propia conexión MQTT 3.1.1 hacia el broker de la plataforma, cifrada con TLS. Antes de conectarse, obtiene la dirección del broker y el usuario y la contraseña con los que debe identificarse mediante una consulta HTTPS, de modo que HTTP se usa una sola vez, al iniciar, y MQTT para la conexión que permanece abierta. Cada tópico indica el robot y el tipo de dato que transporta, y por la misma conexión viajan en un sentido los datos del robot y en el otro las órdenes de la plataforma. La mayor parte de los datos se codifica con Protocol Buffers, con un tipo de mensaje para cada clase de dato, como la posición, el mapa del lugar o las imágenes de una cámara. A la reducción de tamaño que aporta la codificación se suman decisiones del propio SDK, como limitar la frecuencia con que se publican ciertos datos o eliminar puntos intermedios de los recorridos antes de enviarlos @inorbit-edge-sdk.

Los mecanismos de MQTT se eligen según la naturaleza de cada dato. La posición y los demás datos que cambian continuamente se publican con QoS 0, ya que si una muestra se pierde, la siguiente la reemplaza. El mapa, por el contrario, cambia rara vez, y como su pérdida dejaría a la plataforma sin él durante mucho tiempo, se publica con QoS 1 y como mensaje retenido, de modo que quien empieza a recibir datos del robot lo obtiene de inmediato. Algo similar ocurre con el estado de conexión. Al conectarse, el robot publica que está en línea mediante un mensaje retenido y registra en el mismo tópico un mensaje de última voluntad, también retenido. Si la conexión se interrumpe, el broker publica la última voluntad, que reemplaza al mensaje anterior, y quien se suscribe después recibe así el estado vigente.

InOrbit publicó además, bajo el nombre OpenRobOps, una versión de código abierto de la plataforma, que permite examinar también el lado del servidor, incluida la definición de los mensajes en archivos `.proto`. Como broker utiliza Mosquitto, un broker MQTT de código abierto, configurado para que cada robot tenga sus propias credenciales y solo pueda acceder a sus tópicos, de modo que un robot comprometido no pueda leer los datos de otros ni hacerse pasar por ellos. Su esquema ilustra la evolución descrita en la @sec-protobuf-compat, ya que los campos que dejan de usarse permanecen con una marca que indica que no deben emplearse, y la información nueva se agrega con números de campo no utilizados, de modo que los programas antiguos siguen siendo comprendidos @openrobops-repo.

Tanto el SDK de InOrbit como OpenRobOps utilizan MQTT 3.1.1, y esa elección explica parte de sus limitaciones. Esta versión no permite indicar en el mensaje qué formato tiene su contenido, por lo que el receptor deduce el tipo de cada mensaje a partir del tópico en el que llega. Esa dependencia es frágil, porque junto con los mensajes de Protocol Buffers conviven formatos más antiguos, como texto plano o documentos JSON guardados dentro de un campo de texto de un mensaje de Protocol Buffers, y como ningún mensaje declara su formato, cada programa que los recibe debe saber de antemano qué formato corresponde a cada tópico. La versión 3.1.1 tampoco ofrece una forma de asociar una respuesta con la solicitud que la originó. Para confirmar que una orden llegó, el robot devuelve una copia de cada mensaje que recibe, y la plataforma identifica a qué orden corresponde mediante un número que la propia orden incluía. La versión 5.0 resuelve ambas necesidades con propiedades del protocolo. Una indica el tipo de contenido del mensaje, y otras dos permiten que quien solicita indique en qué tópico espera la respuesta y agregue un identificador que quien responde devuelve sin cambios, de modo que el solicitante puede asociar cada respuesta con su solicitud @mqtt50.

Otras limitaciones provienen de la arquitectura y no de la versión del protocolo. Abrir una conexión por robot, incluso cuando un mismo programa representa a varios, permite que el broker limite cada conexión a los tópicos de su robot y que el mensaje de última voluntad, que se registra una vez por conexión, anuncie la desconexión de un robot concreto. A cambio, cada robot exige su propia negociación TLS y sus propios paquetes de keep-alive, un costo que se multiplica cuando un solo equipo representa a muchos robots. Además, OpenRobOps ejecuta un único broker, ya que Mosquitto no permite que varias copias del broker funcionen como un solo sistema, repartiéndose los robots o reemplazando a una copia que falla, porque cada una guarda por separado sus mensajes retenidos y sus sesiones. Si ese broker se detiene, todos los robots quedan incomunicados, que es el punto de falla que la @sec-pubsub atribuye a la arquitectura centralizada.

==== VDA 5050 e ISO 21423

Sin un estándar común, cada fabricante de robots ofrece su propio sistema de control de flota, es decir, el software que asigna tareas a los robots y coordina sus movimientos. Para operar en conjunto robots de distintas marcas, una planta depende entonces de una plataforma como las de la @sec-caso-inorbit, que debe adaptarse a la interfaz particular de cada fabricante. VDA 5050 es una especificación, desarrollada por las asociaciones alemanas de la industria automotriz (VDA) y de fabricantes de maquinaria (VDMA), que define cómo se comunican los robots con un sistema de control de flota de cualquier fabricante. A diferencia del protocolo de la @sec-caso-inorbit, que una sola empresa define para su propia plataforma, se trata de un estándar abierto, que adopta MQTT con JSON y que InOrbit también admite @inorbit-interop.

La especificación exige como mínimo la versión 3.1.1 de MQTT y elige JSON porque permite agregar parámetros nuevos sin afectar a los equipos existentes y porque cada mensaje puede verificarse contra un esquema JSON, un documento aparte que describe los campos y los tipos que debe contener. A diferencia de lo que ocurre con Protocol Buffers, ese esquema no hace falta para leer el mensaje, sino solo para comprobar que es válido, de modo que cualquier fabricante puede interpretar los mensajes sin disponer de él. Los tópicos indican el nombre del protocolo, su versión, el fabricante, el número de serie del robot y el tipo de mensaje @vda5050. Como la versión forma parte del tópico, robots que usan versiones incompatibles pueden convivir en un mismo broker, ya que un sistema suscrito a los tópicos de una versión nunca recibe los mensajes de otra. Es una estrategia de evolución distinta de la de Protocol Buffers, que mantiene la compatibilidad dentro de un mismo esquema mediante los números de campo, como se describió en la @sec-protobuf-compat.

Con el objetivo declarado de reducir la sobrecarga de comunicación, la especificación establece QoS 0 para todos los mensajes, salvo los del tópico que informa si el robot está conectado, que usan QoS 1 y se publican como retenidos. En ese tópico, el robot registra además un mensaje de última voluntad que avisa la pérdida de la conexión. Sin embargo, la reducción de sobrecarga que se busca con el nivel de QoS no se extiende al contenido de los mensajes. La confirmación de QoS 1 agrega apenas unos pocos bytes, mientras que el mensaje con el que el robot informa periódicamente su posición, su batería y la tarea en curso repite en JSON, en cada envío, los nombres de todos sus campos, que es precisamente el costo que Protocol Buffers elimina, como se mostró en la @sec-protobuf-json.

La norma ISO 21423, publicada en 2026, sigue un enfoque análogo. Especifica la comunicación entre robots móviles industriales, sistemas de control de flota y otros equipos del edificio que los robots necesitan accionar para desplazarse, como puertas automáticas o ascensores @iso21423, y adopta también MQTT y JSON @iso21423. OpenRobOps la admite @openrobops-repo, lo que muestra que una misma plataforma puede ofrecer los dos formatos sobre MQTT, con Protocol Buffers en su protocolo propio y JSON en los estándares que comparte con otros fabricantes.

=== Internet de las Cosas industrial <sec-caso-industria>

En una planta industrial, donde máquinas y sensores conectados a la red envían datos de forma continua, un sistema de supervisión debe conocer en todo momento el estado de numerosos equipos que a menudo provienen de distintos fabricantes. Al igual que VDA 5050 e ISO 21423 para los robots móviles, este ámbito cuenta con un estándar abierto de interoperabilidad sobre MQTT, que cumple una función similar para los equipos de planta. A diferencia de aquellos, sin embargo, este estándar adopta Protocol Buffers en lugar de JSON. Eclipse Sparkplug, desarrollada por la Fundación Eclipse, una organización sin fines de lucro que mantiene proyectos de software abierto, define cómo se comunican sobre MQTT tres tipos de participantes. Los dispositivos son los equipos que generan los datos, como sensores, motores o las computadoras industriales que comandan las máquinas. Los nodos del _edge_ o de borde, llamados así porque se ubican en el límite de la red, junto a las máquinas, reúnen los datos de esos dispositivos, que a menudo no pueden comunicarse por MQTT, y los publican en el broker. Las aplicaciones de supervisión, por último, se suscriben a esos datos para mostrarlos, almacenarlos o enviar órdenes. La especificación completa lo que MQTT deja abierto de manera deliberada, como la estructura de los tópicos, el formato de los mensajes y la forma de conocer qué equipos están en línea @sparkplug3. Su versión 3.0 fue adoptada como norma ISO/IEC 20237:2023 @sparkplug-iso.

Cada tópico indica la versión de la especificación, un grupo de nodos, el tipo de mensaje, el nodo y el dispositivo. El tipo distingue los datos, las órdenes y los mensajes que anuncian la conexión y la desconexión. El contenido de los mensajes se codifica con Protocol Buffers, mediante un esquema común que representa los datos como una lista de mediciones, llamadas métricas, cada una con su tipo y su momento de registro. Como ese esquema es genérico y sirve para cualquier equipo, el nombre de cada métrica viaja como texto, lo que reintroduce dentro del mensaje binario el costo que Protocol Buffers evita al identificar los campos por número. Para reducirlo, la especificación permite identificar cada métrica con un número corto, llamado alias. El nodo informa la correspondencia entre nombres y alias una sola vez, en el mensaje que publica al conectarse y que se describe a continuación, y los mensajes de datos posteriores llevan solo el número. Con el mismo propósito, recomienda publicar un valor solo cuando cambia, y no de forma periódica.

El aspecto más elaborado de Sparkplug es la forma en que la aplicación de supervisión sabe qué nodos están en línea. Para ello se apoya en el mensaje de última voluntad y el keep-alive descritos en la @sec-mqtt. Al conectarse, cada nodo publica un mensaje que anuncia su presencia y enumera todas las métricas que reportará, que la especificación llama certificado de nacimiento y que no tiene relación con los certificados digitales de TLS. Antes de publicarlo, registra como mensaje de última voluntad un certificado de muerte, que el broker publica si la conexión se interrumpe sin aviso. Al recibirlo, la aplicación de supervisión marca como desactualizados los datos de ese nodo, para que nadie tome los últimos valores recibidos como vigentes. La rapidez con que se detecta la caída depende, por lo tanto, del intervalo de keep-alive analizado en la @sec-keepalive.

Este esquema presenta, sin embargo, un problema con el orden de llegada de los certificados. Como el broker solo detecta la caída de una conexión cuando vence el keep-alive, el nodo puede volver a conectarse antes de que eso ocurra. En ese caso, el certificado de muerte de la conexión anterior puede publicarse después del nuevo certificado de nacimiento, y la aplicación daría por desconectado a un nodo que está en línea. Para evitarlo, ambos certificados llevan un número que cambia en cada conexión, y la aplicación solo considera caído al nodo cuando el certificado de muerte corresponde al último nacimiento recibido.

Un problema distinto es la pérdida de datos. Como se publican con QoS 0, los mensajes que están en tránsito cuando se corta una conexión se pierden, aunque TCP sea confiable mientras la conexión existe. Para detectarlo, cada mensaje lleva un número de secuencia, y cuando la aplicación advierte que falta uno, le pide al nodo un nuevo certificado de nacimiento para reconstruir su estado completo. Se trata de un mecanismo de la aplicación que suple la confirmación que QoS 0 no ofrece, en línea con lo analizado en la @sec-qos-tcp.

Las aplicaciones de supervisión anuncian también su propio estado, con un mensaje retenido y un mensaje de última voluntad. Así, los nodos saben si hay alguien recibiendo sus datos y pueden esperar a que la aplicación designada como principal, encargada de registrarlos, esté en línea antes de publicar, para no enviar datos que nadie almacenaría. La especificación exige además que cada conexión comience sin sesión persistente, de modo que el broker no acumula mensajes viejos para los clientes desconectados. Quien se desconecta pierde los datos publicados mientras tanto, pero recupera el estado actual, porque cada nodo vuelve a publicar su estado completo al reconectarse. Cuando se emplea la versión 5.0, este comportamiento se fija con propiedades exclusivas de esa versión, como la duración de la sesión una vez cerrada la conexión.

Estas decisiones tienen también costos. La especificación prohíbe publicar el certificado de nacimiento como mensaje retenido, por lo que una aplicación que se suscribe más tarde debe pedirle al nodo uno nuevo antes de poder interpretar los mensajes que usan alias, salvo que el broker implemente una extensión opcional que lo conserve. Además, como las métricas viajan dentro del contenido de los mensajes, el broker solo puede distribuirlos según el nodo o el dispositivo que los origina. Una aplicación interesada en una única métrica debe recibir y decodificar todos los mensajes del nodo, una limitación del ruteo por tópicos ya señalada en la @sec-ruteo-topicos.

=== Internet de las Cosas sobre redes LoRa <sec-caso-lora>

Los casos anteriores suponen dispositivos conectados directamente a una red IP. LoRa es, en cambio, una tecnología de radio que permite comunicar dispositivos a varios kilómetros de distancia con muy bajo consumo de energía, a costa de una velocidad de transmisión muy reducida, y cuyos enlaces no transportan IP. Por eso, en las redes LoRa no puede emplearse MQTT directamente. Su interés para este trabajo radica en dos aspectos. Por un lado, muestran a Protocol Buffers en el enlace más restringido de todos los casos analizados. Por otro, muestran el papel de MQTT en el punto en que los datos de la radio ingresan a una red IP, donde un equipo intermediario debe hacerlos llegar a un servidor. Los dos proyectos que se describen a continuación, Meshtastic y ChirpStack, ilustran respectivamente el primer y el segundo aspecto.

==== Meshtastic

Meshtastic es un software de código abierto que se instala en pequeñas radios LoRa de bajo costo y que, junto con una aplicación para teléfonos, permite intercambiar mensajes de texto y datos de posición sin depender de redes celulares ni de Internet. Las radios forman una red mallada, en la que cada una retransmite los mensajes que recibe para que lleguen a radios fuera del alcance del emisor. Por radio, cada mensaje viaja con un encabezado binario fijo y un contenido codificado con Protocol Buffers, que no puede superar los 239 bytes @meshtastic-mesh-algo, un margen en el que un formato textual como JSON resultaría difícil de sostener.

Una radio que además dispone de conexión a Internet puede actuar como puente entre la malla y un broker MQTT. Publica en el broker los mensajes que recibe de la malla y se suscribe a él para retransmitir en su malla los mensajes que otros puentes publican desde mallas lejanas, de modo que el broker une mallas que no tienen alcance de radio entre sí. Los usuarios de Meshtastic pueden organizar sus conversaciones en grupos, que el proyecto llama canales, y cada mensaje se publica encapsulado en otro mensaje de Protocol Buffers que agrega su canal y el identificador del puente @meshtastic-protobufs. Como los mensajes de la malla ya están codificados con Protocol Buffers, el puente los reenvía sin traducirlos @meshtastic-mqtt.

Los mensajes de cada canal se cifran con una clave que comparten las radios de ese canal, de modo que solo ellas pueden leerlos. Al publicarlos en el broker, el puente puede conservar ese cifrado o enviarlos descifrados, y la configuración por defecto opta por lo segundo @meshtastic-mqtt-config. La diferencia es relevante porque el broker, como intermediario del modelo publicador/suscriptor, recibe el contenido de todos los mensajes. TLS, que también es opcional en la conexión con el broker, protege solo el tramo entre el puente y el broker, por lo que el broker y sus suscriptores siguen pudiendo leer los mensajes. Si el mensaje conserva el cifrado del canal, en cambio, solo pueden leerlo quienes tienen la clave.

La presencia de varios puentes en una misma malla muestra la diferencia entre dos formas de hacer llegar los mensajes, que se vinculan con la comparación entre ruteo por tópicos y ruteo IP de la @sec-ruteo-topicos. La malla difunde cada mensaje a todas sus radios, de modo que varios puentes pueden recibirlo y publicarlo. El broker, que entrega cada mensaje según su tópico sin interpretar su contenido, reenvía cada copia a todos los suscriptores, y son estos quienes deben descartar los duplicados a partir del número que la radio de origen asigna a cada mensaje. En el sentido inverso aparece otro problema. Los desarrolladores de Meshtastic mantienen un broker público, al que las radios se conectan por defecto y en el que confluye el tráfico de muchas mallas. Si ese tráfico se retransmitiera por cada malla, saturaría enlaces de radio de muy baja capacidad, por lo que los mensajes que llegan desde ese broker se entregan solo a las radios al alcance directo del puente.

==== ChirpStack

LoRaWAN es un protocolo que organiza las redes LoRa de manera distinta a Meshtastic. En lugar de una malla, los dispositivos transmiten por radio a uno o más equipos fijos, llamados _gateways_, que reenvían por Internet lo que reciben a un servidor central, llamado servidor de red, que verifica cada mensaje, descarta las copias repetidas y lo entrega al programa del usuario que utiliza esos datos @lorawan. ChirpStack es una implementación de código abierto de ese servidor, y permite seguir un dato desde la radio hasta ese programa a través de tramos con protocolos y formatos distintos.

Los _gateways_ suelen reenviar los datos mediante un protocolo sobre UDP, definido por Semtech, el fabricante de los circuitos de radio LoRa, que representa la información en JSON. Según su propia especificación, se trata de un protocolo deliberadamente básico, que no verifica la identidad de los extremos ni retransmite los datagramas perdidos y que, por eso, está pensado para demostraciones o para redes privadas y confiables. El protocolo contempla además que el _gateway_ se encuentre detrás de un NAT, por lo que el _gateway_ envía periódicamente un mensaje para que el NAT mantenga abierta la asociación por la que le llegan los datos que el servidor envía hacia los dispositivos @semtech-pf. El mantenimiento de esas asociaciones se analizó en la @sec-nat-firewalls.

ChirpStack incluye un componente, llamado Gateway Bridge, que traduce ese protocolo a MQTT, con Protocol Buffers como codificación recomendada y JSON reservado para la depuración @chirpstack-gwbridge-events. La documentación recomienda ejecutarlo en el propio _gateway_, de modo que el tramo que atraviesa Internet aproveche la autenticación y el cifrado TLS de la conexión MQTT @chirpstack-semtech-udp. Se reemplaza así un protocolo sin confiabilidad ni seguridad por una conexión TCP persistente lo más cerca posible del origen de los datos. Los mensajes que el _gateway_ publica incluyen, como campos de Protocol Buffers, información sobre cómo se recibió cada transmisión, como la frecuencia y la intensidad y la calidad de la señal @chirpstack-gwproto, valores que en JSON repetirían sus nombres en cada mensaje.

En cuanto a los mecanismos de MQTT, el Gateway Bridge publica el estado de conexión del _gateway_ como mensaje retenido y, cuando se ejecuta en el propio _gateway_, registra además un mensaje de última voluntad que avisa su desconexión @chirpstack-gwbridge-mqtt. Si se ejecutara en un servidor, su conexión MQTT seguiría abierta aunque el _gateway_ dejara de funcionar, y la última voluntad no reflejaría esa caída. El servidor de red, por su parte, emplea la versión 5.0 y, si el broker lo admite, se suscribe a los mensajes de todos los _gateways_ mediante una suscripción compartida, que reparte los mensajes entre varias copias del servidor de red que se ejecutan en paralelo @chirpstack-repo.

Como en Meshtastic, una misma transmisión de radio puede ser recibida por varios _gateways_, pero en LoRaWAN es el servidor de red el que elimina los duplicados, para lo cual espera un breve intervalo a que lleguen todas las copias. Esa espera, sumada a la latencia del tramo MQTT, demora la respuesta que el servidor envía al dispositivo. Como el dispositivo, para ahorrar energía, solo enciende su receptor durante un breve lapso después de cada transmisión, una respuesta que llega tarde se pierde.

Hacia el programa del usuario, ChirpStack publica los datos en JSON por defecto, con Protocol Buffers como opción @chirpstack-config. El formato se elige así según el tramo, con la codificación binaria donde se concentra el volumen de mensajes y JSON donde prima la facilidad de integración con otros sistemas.

// TODO(casos de uso) Referenciar @sec-mapeo-tecnologico si la opción de conectividad LoRaWAN queda incluida en el mapeo.

=== Ventajas y limitaciones observadas <sec-casos-sintesis>

Los casos analizados, pese a pertenecer a dominios distintos, comparten un mismo patrón de red. En todos ellos el dispositivo, o el equipo intermediario que lo representa, abre una conexión persistente hacia un broker cuya dirección conoce u obtiene al iniciar, y recibe por ella los mensajes que le están destinados, entre ellos las órdenes. No necesita, por lo tanto, aceptar conexiones entrantes, lo que le permite operar detrás de NAT y firewalls, como se analizó en la @sec-nat-firewalls. La mayoría informa además si está en línea mediante los mecanismos de MQTT, aunque con variantes. InOrbit, VDA 5050 y ChirpStack combinan un mensaje retenido con el mensaje de última voluntad, de modo que cualquier suscriptor conoce el estado vigente. Sparkplug aplica ese patrón solo a las aplicaciones de supervisión, mientras que los nodos vuelven a anunciar su estado con un nuevo certificado de nacimiento al reconectarse.

La elección del formato sigue también un criterio común. Protocol Buffers aparece en los tramos que concentran el volumen de mensajes, como los datos de los robots, los mensajes de los _gateways_ LoRaWAN o las mediciones de los equipos industriales, y en los enlaces de radio más restringidos. JSON, por el contrario, aparece en los datos que se entregan a programas de otras empresas y en estándares compartidos entre fabricantes, como VDA 5050 o ISO 21423, en los que importa que cualquiera pueda leer los mensajes sin disponer de un esquema, aunque Sparkplug muestra que un estándar abierto también puede adoptar Protocol Buffers cuando el volumen de datos lo justifica.

En los datos que se publican con alta frecuencia predomina QoS 0, ya que cada muestra queda reemplazada por la siguiente. Los casos se apoyan en la entrega fiable de TCP y, cuando la necesitan, agregan mecanismos propios, como los números de secuencia de Sparkplug. QoS 1 y los mensajes retenidos quedan reservados para el estado de conexión y para los datos que cambian con poca frecuencia, como el mapa de un robot. La reducción del volumen tampoco depende solo de la codificación, ya que Protocol Buffers se combina con decisiones de la aplicación, como limitar la frecuencia de publicación o publicar solo los cambios. Esas optimizaciones pueden tener, sin embargo, un costo, como muestra Sparkplug, donde una aplicación que se suscribe tarde debe pedir un nuevo certificado de nacimiento antes de poder interpretar los datos que usan alias. En cuanto a la magnitud del beneficio, la única medición realizada sobre un sistema en funcionamiento real proviene de Messenger, que redujo a la mitad el tamaño de los mensajes al reemplazar JSON por Thrift, un formato con esquema análogo a Protocol Buffers.

Los casos también exponen los límites del stack. Del lado de MQTT, el broker conserva estado, y cuando la implementación no permite repartirlo entre múltiples réplicas, como ocurre con Mosquitto, se convierte en el punto de falla de todo el sistema. A gran escala, la sesión resulta una unidad demasiado grande para repartir la carga entre servidores y recuperarse ante fallas, y cuando cada dispositivo mantiene su propia conexión, cada uno asume el costo de su negociación TLS y de su keep-alive. El ruteo por tópicos, por su parte, no permite filtrar según el contenido de los mensajes. Del lado de Protocol Buffers, todo programa que recibe los datos debe disponer del esquema, y la convivencia con formatos más antiguos debilita el acuerdo que establece el esquema.

Por último, varias implementaciones permanecen en MQTT 3.1.1 y resuelven en la aplicación o mediante el tópico funciones que la versión 5.0 incorpora, como indicar el formato de los mensajes o asociar cada respuesta con su solicitud, según se vio en la @sec-caso-robotica. Entre los casos analizados, el servidor de red de ChirpStack es el que más aprovecha las funciones exclusivas de esa versión, mientras que Sparkplug solo las emplea para fijar el comportamiento de la sesión. Ninguno de los casos cuya implementación pudo examinarse utiliza las propiedades que indican el formato o asocian respuestas con solicitudes, lo que sugiere que, al menos en la muestra analizada, las ventajas de la versión 5.0 todavía no se reflejan plenamente en la práctica. En conjunto, los casos indican que el stack aporta sus mayores ventajas en los tramos de alta frecuencia y en los dispositivos que operan detrás de redes ajenas, mientras que sus limitaciones se concentran en el broker y en la distribución del esquema.

// El mapeo tecnológico tiene su propia sección (@sec-mapeo-tecnologico, en secciones/mapeo-tecnologico.typ).
