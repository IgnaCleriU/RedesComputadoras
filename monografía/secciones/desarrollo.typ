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

=== QoS MQTT sobre la confiabilidad de TCP <sec-qos-tcp>

// TODO(prometido en Marco teórico, @sec-mqtt) Analizar la relación entre los niveles de QoS y la confiabilidad que ya ofrece TCP.

// TCP garantiza entrega ordenada dentro de una conexión, no que la aplicación procesó el mensaje. Si la conexión se cae, lo que estaba en tránsito se pierde.
// Publisher -> broker -> siscriber son dos conexiones TCP distintas

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
uso, por lo que la elimina tras un tiempo sin tráfico. Para las conexiones TCP establecidas, el IETF (Internet Engineering Task Force) una organización 
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

El Experimento 1 no incluyó cortes de conexión, por lo que los dos últimos regímenes no se midieron (@sec-exp-mqtt-https). Un ensayo que los cubra
podría reutilizar la misma plataforma: aplicar con `tc netem` una pérdida del 100 % sobre la interfaz de un nodo durante un intervalo fijo, con
duraciones por debajo y por encima del umbral del keep-alive, y medir para cada nivel de QoS, con sesión persistente y sin ella, las lecturas perdidas,
duplicadas y demoradas, y el tiempo hasta que el nodo vuelve a publicar.

== Ruteo por tópicos y ruteo IP

// El router decide por dirección IP de destino. el broker decide por tópico.
// Comparar tablas de ruteo con suscripciones y comodines (+, #).

== Casos de uso

// Messenger, Robótica, ver si hay otros relevantes.
// Qué problema resolvió el stack en cada caso y qué limitaciones tiene.

// TODO(mapeo tecnológico) Pedido del profesor (mail del 27/10). Aplica a todo el trabajo.
// - Hacer el "mapeo tecnológico", es decir, ponerle marca y modelo a los equipos reales con los que se implementaría
//   el sistema, dónde se comprarían y cuánto cuestan. Es lo primero que se pregunta en un caso real (¿cuánto sale hacer esto?).
// - Probablemente convenga una sección propia, acá después de Casos de uso. Cosas a relevar según el caso:
//   - Dispositivos de borde (placas y módulos, por ejemplo la familia ESP32 de los experimentos, o gateways industriales).
//   - Broker (servidor propio en la nube contra servicio MQTT administrado, con su costo mensual).
//   - Conectividad (routers, módems celulares, planes de datos).
// - Para cada equipo, indicar modelo, proveedor (local o importación), precio con fecha y moneda, y la fuente.
// - Justificar las elecciones con los tres factores que acotan un proyecto (calidad técnica, plazo y presupuesto).
//   La idea es proponer una solución viable, no necesariamente la de máxima calidad técnica.
