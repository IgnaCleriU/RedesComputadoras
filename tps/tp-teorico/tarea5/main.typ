// Template https://github.com/juanm04/barcala
#import "@preview/barcala:0.3.0": apendice, informe, nomenclatura
#import "@preview/lilaq:0.5.0" as lq // Paquete para gráficos, puede ser omitido
#import "@preview/physica:0.9.7": * // Paquete para matemática y física, puede ser omitido
#import "@preview/zero:0.5.0" // Paquete para números lindos y unidades de medida, puede ser omitido

// Cambiar a false cuando el informe esté listo para presentar
#let drafting = false
#set page(
  foreground: if drafting {
    rotate(-0.955317rad, text(
      weight: "bold",
      size: 80pt,
      fill: rgb("#00000040"),
      "BORRADOR",
    ))
  },
)

// Los emails de la carátula se renderizan como `raw` inline, que no corta en las
// comas y se desborda del margen. Agregamos un espacio de ancho cero tras cada
// coma para habilitar el salto de línea.
#show raw.where(block: false): it => {
  show ",": ",\u{200B}"
  it
}

#show: informe.with(
  unidad-academica: image("assets/FCEFyN.png"),
  institucion: image("assets/UNC.jpg"),
  asignatura: "Redes de Computadoras",
  trabajo: "Trabajo Práctico Nº 5",
  equipo: "WireGuardians",
  autores: (
    (
      nombre: "Viberti, Benjamin",
      email: "b.viberti@mi.unc.edu.ar",
    ),
    (
      nombre: "Espinoza Sutta, Aaron Alejandro",
      email: "aaron.espinoza_4500@mi.unc.edu.ar",
    ),
    (
      nombre: "Cleri, Juan Ignacio",
      email: "ignacio.cleri@mi.unc.edu.ar",
    ),
    (
      nombre: "Pineda, Juan Ignacio",
      email: "juan.ignacio.pineda@mi.unc.edu.ar",
    ),
    (
      nombre: "Grafión, Atilio Leonel",
      email: "atilio.grafion@mi.unc.edu.ar",
    ),
    (
      nombre: "Badenes, Tomás",
      email: "tomasbadenes@mi.unc.edu.ar",
    ),
    (
      nombre: "Oviedo, Ignacio Nicolas",
      email: "ignacio.oviedo.239@mi.unc.edu.ar",
    ),
    (
      nombre: "Mendez, Jorge Nicolas",
      email: "jorge.mendez@mi.unc.edu.ar",
    ),
  ),
  
  titulo: [Preguntas de repaso --- Capítulo 20],
  resumen: [*_Objetivo_ --- Resolver las preguntas de repaso del Capítulo 20 de @stallings2004, sobre protocolos de transporte: direccionamiento, multiplexación, control de flujo por créditos, establecimiento de conexión y los protocolos TCP y UDP.*],
  
  fecha: datetime.today().display("[year]-[month]-[day]"),
)

// Enlaces de colores
#show cite: set text(blue)
#show link: set text(blue)
#show ref: set text(blue)

// Bloques de matemática con números para citar
#set math.equation(numbering: "(1)")
#show ref: it => {
  if it.element != none and it.element.func() == math.equation {
    // Sobreescribir las referencias a ecuaciones
    link(it.element.location(), numbering(
      it.element.numbering,
      ..counter(math.equation).at(it.element.location()),
    ))
  } else {
    // Otras referencias quedan igual
    it
  }
}

// Configuración de `zero`
#import zero: num, zi
#zero.set-num(
  decimal-separator: ",",
)
#zero.set-group(
  size: 3,
  separator: ".",
  threshold: (integer: 5, fractional: calc.inf),
)
#zero.set-unit(
  fraction: "inline",
)

// #nomenclatura(
//   ($f$, [Frecuencia [#zi.hertz()]]),
//   ($C$, [Capacidad del canal [#zi.bit-per-second()]]),
// )

// Customización por sobre el template
#set par(
  spacing: 1.2em,
)

// Numerar las preguntas como en el libro (20.1, 20.2, ...)
#counter(heading).update(19)

= Preguntas de repaso --- Capítulo 20

== ¿Qué elementos de direccionamiento son necesarios para especificar un usuario de servicio de transporte (TS) destino?

Para identificar al usuario destino se necesita la siguiente información:

- Identificación del usuario.
- Identificación de la entidad de transporte.
- Dirección de la estación.
- Número de la red.

En la práctica la dirección se expresa como el par (estación, puerto), llamado _socket_ en TCP, donde el puerto identifica a un usuario TS particular dentro de la estación.

Normalmente hay una única entidad de transporte por estación, por lo que no hace falta identificarla. Si hubiera más de una (por ejemplo TCP y UDP), la dirección debe indicar además el tipo de protocolo de transporte.

== Describa cuatro estrategias por las que un usuario TS emisor pueda averiguar la dirección de un usuario TS receptor.

Hay dos estrategias estáticas y dos dinámicas:

Estáticas:
+ *El usuario conoce previamente la dirección que desea utilizar*: es una configuración del sistema. Sirve para procesos que interesan sólo a unos pocos usuarios y que no deben ser conocidos por todos.
+ *Direcciones conocidas*: a algunos servicios de uso común se les asignan direcciones fijas conocidas por todos, por ejemplo un servidor FTP o SMTP.

Dinámicas:
+ *Servidor de nombres*: el usuario solicita mediante un nombre genérico o global la dirección de un usuario. El servidor de nombres devuelve la dirección, y luego la entidad de transporte establece la conexión. Es útil para servicios que cambian de localización de vez en cuando, por ejemplo para balancear la carga.
+ *Creación del proceso en el momento de la solicitud*: el emisor envía una petición a una dirección bien conocida, donde un proceso del sistema crea el proceso destino y devuelve su dirección. Por ejemplo, una cliente puede pedirle a un gestor de trabajos remoto que lance un programa de simulación en un servidor.

== Explique el uso de la multiplexación en el contexto de un protocolo de transporte.

El protocolo de transporte utiliza multiplexación en dos sentidos respecto de los protocolos de capas superiores y respecto de los servicios de red que usa.

Respecto de las capas superiores, el protocolo de transporte multiplexa y demultiplexa múltiples usuarios sobre el mismo protocolo de transporte, distinguiéndose mediante números de puerto o puntos de acceso al servicio. En TCP, como una conexión queda determinada por los _sockets_ origen y destino, un mismo puerto puede admitir múltiples conexiones, cada una con un puerto diferente. UDP incorpora a IP esta capacidad de direccionamiento de puerto.

Respecto de los servicios de red, la entidad de transporte puede usar multiplexación hacia arriba, que consiste en multiplexar múltiples conexiones sobre una única conexión de la capa inferior, o multiplexación hacia abajo, que consiste en dividir una única conexión entre múltiples conexiones de la capa inferior. Por ejemplo, en el caso de redes X.25, si un solo circuito tiene el rendimiento suficiente para varios usuarios conviene multiplexarlos sobre él. Por otra parte, cada circuito X.25 está restringido en números de secuencia, y en redes de alta velocidad y gran retardo podría requerirse un rango mayor, por lo que dividir la conexión entre varios circuitos puede mejorar el rendimiento.

== Describa brevemente el esquema de créditos utilizado por TCP para el control de flujo.

Es un control de flujo extremo a extremo donde el receptor le indica explícitamente al emisor cuántos datos puede enviar. Cada octeto tiene un número de secuencia y los segmentos llevan tres campos: número de secuencia (SN, el del primer octeto de datos del segmento), número de confirmación (AN) y ventana (W). Un segmento con (AN = i, W = j) significa:

- Se confirman todos los octetos hasta i − 1; el siguiente esperado es el i.
- Se concede crédito para enviar j octetos más, del i al i + j − 1.

El emisor avanza el borde final de su ventana a medida que transmite y el borde inicial solo cuando recibe crédito nuevo (la ventana se achica al transmitir y se amplía con cada crédito). El receptor no está obligado a confirmar cada segmento: puede enviar una confirmación acumulada.

#figure(
  image("assets/credito-tcp.png", width: 70%),
  caption: [Ejemplo del mecanismo de asignación de crédito de TCP.],
)

El receptor puede ser _conservador_ (conceder solo el espacio libre real en su memoria temporal) u _optimista_ (conceder espacio que espera liberar, mejorando el rendimiento con retardos grandes; pero si el emisor es más rápido que el receptor se descartan segmentos y hay que retransmitir, lo que complica el protocolo).

== ¿Cuál es la diferencia principal entre el esquema de créditos de TCP y el esquema de control de flujo de ventana deslizante utilizada por muchos otros protocolos, como por ejemplo HDLC?

En la ventana deslizante fija (como en X.25) confirmar y dar permiso de envío son lo mismo: cada confirmación avanza automáticamente una ventana de tamaño fijo, y para frenar al emisor el receptor retiene las confirmaciones. En el esquema de créditos de TCP la *confirmación y el control de flujo están desacoplados*: se puede confirmar un segmento sin conceder crédito nuevo (W = 0) y conceder crédito sin confirmar datos nuevos. Además, la ventana es variable y se mide en octetos, no en tramas.

Esto pesa en redes no fiables: con ventana fija, si el receptor frena reteniendo confirmaciones, el emisor no puede distinguir si la falta de confirmaciones se debe al control de flujo o a una pérdida. Con créditos el receptor confirma aunque no conceda crédito, y la pérdida de un segmento de confirmación/crédito se corrige con las confirmaciones posteriores. El único riesgo es un bloqueo mutuo si se pierde el (AN = i, W = j) que reabre una ventana cerrada con W = 0; se evita con un temporizador de ventana que obliga a reenviar un segmento al expirar.

== Explique los mecanismos de diálogo en dos y tres pasos.

*Diálogo en dos pasos:* A envía un SYN (solicitud de conexión); si B está en LISTEN, responde con un SYN que funciona como confirmación y pasa a ESTAB, y A pasa a ESTAB al recibirlo. La pérdida de un SYN se cubre con un temporizador de retransmisión, y los SYN duplicados se ignoran una vez establecida la conexión. Basta con un servicio de red fiable, pero sobre una red no fiable falla:

- Un segmento de datos obsoleto de una conexión anterior puede llegar durante una nueva y aceptarse en lugar del válido, que se descarta como duplicado. Para evitarlo, cada conexión empieza con un número de secuencia distinto, que se anuncia en el SYN (SYN i).
- Eso no resuelve un SYN i obsoleto: B lo toma como una solicitud nueva y responde, descarta el SYN real de A como duplicado, y ambos creen tener una conexión válida con números de secuencia distintos, por lo que B rechaza los datos de A.

#figure(
  image("assets/dos-pasos-datos-obsoleto.png", width: 70%),
  caption: [Diálogo en dos pasos: un segmento de datos obsoleto se acepta en una conexión nueva.],
)

#figure(
  image("assets/dos-pasos-syn-obsoleto.png", width: 70%),
  caption: [Diálogo en dos pasos: un SYN obsoleto desincroniza los números de secuencia.],
)

*Diálogo en tres pasos (usado por TCP):* cada extremo confirma explícitamente el SYN y el número de secuencia inicial (ISN) del otro. El SYN ocupa el número i, por lo que el primer octeto de datos es el i + 1:

+ A → B: SYN, SN = i
+ B → A: SYN, SN = j, AN = i + 1
+ A → B: SN = i + 1, AN = j + 1 (es el primer segmento de datos de A)

Se agrega el estado SYN RECEIVED, para no declarar la conexión establecida hasta que ambos SYN estén confirmados, y el segmento RST. La regla es enviar RST si la conexión todavía no está en ESTAB y llega un ACK inválido (que no referencia nada enviado):

- Si un SYN i obsoleto llega a B, este responde SYN j, AN = i + 1; A no pidió esa conexión y responde RST, AN = j. El AN en el RST evita que un RST obsoleto cancele una apertura legítima.
- Si un SYN/ACK obsoleto (SYN k, AN = p) llega a A mientras abre una conexión, A responde RST, AN = k y la apertura real sigue sin problemas, porque las confirmaciones llevan números de secuencia.

#figure(
  image("assets/tres-pasos.png", width: 70%),
  caption: [Diálogo en tres pasos: (a) funcionamiento normal, (b) SYN retrasado, (c) SYN/ACK obsoleto durante una apertura.],
)

== ¿Cuál es el beneficio del mecanismo de diálogo en tres pasos?

Su beneficio es que evita que los segmentos SYN duplicados u obsoletos, que llegan con retraso desde conexiones anteriores, generen conexiones falsas o confundan una conexión nueva. Para lograrlo, cada extremo confirma explícitamente el SYN y el número de secuencia inicial del otro antes de dar la conexión por establecida.


== Defina las características de urgencia y forzado de TCP.

TCP ofrece dos servicios para marcar los datos:

- *Forzado (PSH):* normalmente TCP decide cuándo juntó suficientes datos para armar un segmento. Con el forzado, el usuario puede pedir que se envíen enseguida todos los datos pendientes, y el receptor también los entrega al usuario sin esperar.
- *Urgencia (URG):* sirve para avisarle al usuario destino que en el flujo de datos hay datos importantes o urgentes. TCP marca el final de esos datos con el puntero urgente y los manda en el flujo normal. Después, el usuario destino decide qué hacer con ellos.

== ¿Qué es una opción en los criterios de implementación de TCP?

El estándar TCP proporciona una especificación precisa del protocolo que se va a utilizar entre entidades TCP. Sin embargo, ciertos aspectos del protocolo admiten varias opciones de implementación posibles. Aunque dos implementaciones que escojan opciones alternativas pueden interoperar, puede haber consecuencias en el rendimiento. Las áreas de diseño para las que se especifican opciones son las siguientes:

- *Política de envío:* TCP puede construir un segmento por cada lote de datos del usuario, o esperar a acumular una cierta cantidad antes de enviar.
- *Política de entrega:* el receptor puede entregar los datos al usuario a medida que llegan los segmentos en orden, o almacenar varios antes de entregarlos.
- *Política de aceptación:* ante segmentos fuera de secuencia, el receptor puede usar aceptación ordenada o aceptación en ventana (acepta todo lo que caiga dentro de la ventana de recepción).
- *Política de retransmisión:* hay tres estrategias: sólo el primero, por lotes o individual.
- *Política de confirmación:* la confirmación puede ser inmediata, con un segmento vacío, o acumulada, incorporando el ACK en un segmento de datos de salida.

== ¿Cómo puede utilizarse TCP para tratar la congestión de red o de interconexión de red?

TCP usa su mecanismo de control de flujo por créditos para detectar la congestión, que se manifiesta como un aumento de los retardos y la pérdida de segmentos. Ante estas señales, reduce el envío de datos. Para esto se utilizan dos tipos de técnicas:

+ *Gestión de temporizadores de retransmisión:* se estima el RTT para ajustar el temporizador.
+ *Gestión de ventana:* con el arranque lento, la ventana crece gradualmente a medida que llegan las confirmaciones. Ante una pérdida, la ventana se reduce y vuelve a crecer de forma más lenta.

== ¿Qué proporciona UDP que no ofrezca IP?

UDP añade a IP dos cosas esenciales:

Puertos: IP lleva el paquete hasta la computadora destino. En cambio UDP usa números de puerto para entregarlo a la aplicación exacta de destino.

Detección de errores: IP solo revisa que su propia cabecera esté bien. UDP calcula un Checksum que verifica que el contenido de los datos no se haya corrompido en el camino.


// TODO Actividad 2: responder al menos 11 ejercicios (pág. 719) del Capítulo 20

#show heading: set heading(numbering: none)

#pagebreak()

== Actividad 2: Ejercicios (pág. 719) — mínimo 11


=== Ejercicio 20.1

==== Consigna

Es una práctica común en la mayoría de los protocolos de transporte (en realidad, en la mayoría de los protocolos de todas las capas) que los datos y la señalización de control se multiplexen sobre el mismo canal lógico en cada conexión por usuario. Una alternativa consiste en establecer una única conexión de control de transporte entre cada par de entidades de transporte que se comuniquen. Esta conexión se usaría para transmitir las señales de control de todas las conexiones de los usuarios de transporte entre las dos entidades. Discuta las implicaciones de esta estrategia.

==== Respuesta

*1) Caso: Cada conexion multiplexada sobre la misma conexion logica.*

Ventajas:

- Es mas eficiente ya que las confirmaciones (ACK) y los ajustes de ventana de crédito se incluyen en los segmentos de datos de retorno, reduciendo la sobrecarga de las cabeceras y la cantidad de paquetes en la red.

- Esta mantiene un orden estricto entre datos y control, los comandos (como FIN) se procesan en el punto exacto del flujo en el que fueron transmitidos.

- Un problema en el canal de control de una conexión afecta únicamente a esa sesión de usuario, no a todas sesiones.

Desventajas:

- Es mas propenso a bloqueado debido a la saturacion del canal o control del flujo.

*2) Caso establecimiento de una única conexión de control para llevar todas las señales de control para todas las conexiones de usuario*

Ventajas:

- Los mensajes de control no comparten colas con los datos, órdenes prioritarias (como reinicios RST) se transmiten inmediatamente sin ser retenidas por bloqueos en el canal de datos.

Desventajas:

- Hay un mayor trafico en la red al no poder hacer _piggybacking_

- Se pueden crear *condiciones de carrera* si existen redes con retardos variables, ya que estos retardos puedes "desfasar" las señales del canal de control con respecto a los datos.

- Si el canal de control colapsa, se pierde las señales de control de todas las conexiones.

=== Ejercicio 20.2

La discusión sobre control de flujo con un servicio de red fiable, referido como mecanismo de contrapresión, utiliza un protocolo de control de flujo de una capa inferior. Discuta las desventajas de esta estrategia.

==== Respuesta

El mecanismo de contrapresion en pocas palabras es esquema de control de flujo que cuando un nodo intermedio excede su capacidad le exige al anterior que detenga su transmision, este se propaga sucesivamente hasta la fuente original.

#pagebreak()

Esta estrategia tiene desventajas como:

- Bloqueo de linea lo cual puede afectar a trafico que no tenia nada que ver en primer lugar.

- La Detencion de el flujo en la capa inferior paraliza todas las comunicaciones entre los dos nodos, impidiendo que aplicaciones ligeras o prioritarias sigan operando.

- En redes donde la propagacion del mecanismo es lenta puede agravarse la congestion ya que durante el tiempo en el que mecanismo tarde en llegar a la fuente original este va a seguir transfiriendo paquetes.

=== Ejercicio 20.3

Dos entidades de transporte se comunican a través de una red fiable. Supongamos que el tiempo normalizado para transmitir un segmento es igual a 1. Supongamos que el retardo de propagación extremo a extremo vale 3 y que la entrega de un segmento recibido al usuario de transporte requiere un tiempo de 2. El emisor tiene inicialmente concedido un crédito de siete segmentos. El receptor utiliza un criterio de control de flujo conservador y actualiza su asignación de créditos en cuanto puede. ¿Cuál es el máximo rendimiento alcanzable?

==== Respuesta

- $t_"tx" = 1$ Tiempo de transmision
- $t_"prop" = 3$ Tiempo de propagacion
- $t_"proc" = 2$ Tiempo de procesamiento
- Credito inicial de 7 segmentos

$ T_"ciclo" = t_"tx" + t_"prop" + t_"proc" + t_"prop" = 1 + 3 + 2 + 3 = 9 "unidades de tiempo" $

El rendimiento maximo es la relación entre el tiempo en que el emisor transmite activamente y la duración total del ciclo:

$ U = frac("Crédito disponible", "Tiempo total de ciclo") = W / T_"ciclo" = 7 / 9 ≈ "0,7778" ≈ "77,78%" $

=== Ejercicio 20.4

Dibuje un diagrama similar al de la Figura 20.4 para los siguientes casos (suponga un ser
vicio de red fiable ordenado):
#set enum(numbering: "a.")
+ Cierre de la conexión: activo/pasivo.
+ Cierre de la conexión: activo/activo.
+ Rechazo de la conexión.
+ Cancelación de la conexión: un usuario emite un Open a un usuario que está preparado y entonces emite un Close antes de que se intercambie ningún dato.

==== Respuesta

*a. Cierre de la conexión: activo/pasivo.*

#figure(
  image("assets/20.4_a.jpg", width: 50%),
  caption: [Escenario cierre de la conexión activo/pasivo.],
)

*b. Cierre de la conexión: activo/activo.*

#figure(
  image("assets/20.4_b.jpg", width: 50%),
  caption: [Escenario cierre de la conexión activo/activo.],
)

*c. Rechazo de la conexión.*

#figure(
  image("assets/20.4_c.jpg", width: 50%),
  caption: [Escenario rechazo de la conexión.],
)

*d. Cancelación de la conexión: un usuario emite un Open a un usuario que está preparado y entonces emite un Close antes de que se intercambie ningún dato.*

#figure(
  image("assets/20.4_d.jpg", width: 50%),
  caption: [Escenario cancelación de la conexión.],
)



=== Ejercicio 20.5

Con un servicio de red fiable y ordenado, ¿son estrictamente necesarios los números de
secuencia de los segmentos? ¿Qué capacidad se pierde sin ellos?

==== Respuesta

Los números de secuencia no son estrictamente necesarios, como se nos dice que el servicio de red es fiable y ordenado nos garantiza que se han enviado todos los segmentos, sin duplicados y en el mismo orden en que se enviaron.
Sin números de secuencia se pierde la capacidad de desacoplar el reconocimiento de la asignación de crédito, porque los mensajes ACK/Crédito no podrían referirse de forma inequívoca a segmentos concretos.


=== Ejercicio 20.6

Considere un servicio de red orientado a conexión que sufre un reinicio. ¿Cómo podría ser
tratado por un protocolo de transporte que suponga que el servicio de red es fiable excepto
en el caso de un reinicio?

==== Respuesta

Si se supone que la red es fiable excepto cuando hay un reinicio, en ese momento pueden perderse los segmentos que estén en tránsito. Para manejarlo, el protocolo de transporte debería hacer que el emisor guarde los datos enviados hasta que sean reconocidos. Cuando se notifica un reinicio, las entidades de transporte se resincronizan, informandose mutuamente cuál fue el número de secuencia del último segmento recibido y se retransmite lo que falte. 

=== Ejercicio 20.7

==== Consigna

La discusión de la política de retransmisión hizo referencia a tres problemas asociados con
el cálculo dinámico del valor del temporizador. ¿Qué modificaciones sobre la política ayu
darían a aliviar estos problemas?

==== Respuesta

Los problemas asociados con el cálculo dinámico (tomando la media convencional) del temporizador son: 

1. El cálculo se realiza entre el tiempo de salida y de llegada, sin embargo no se tiene en cuenta el retraso que tiene el receptor al enviar la respuesta.
2. El calculo que se realiza sobre los ACK no contempla si es de la llamada principal o de la retransmisión por lo tanto no garantiza que el tiempo medido sea fiel.
3. Tomar la media simple no representa los cambios en el tráfico de la red, es decir: Si la red estaba cargada al momento de hacer el cálculo, la estimación es fiel para una red cargada. En el caso de que la red se alivie esta estimación resulta ser muy grande y genera pérdidas de rendimiento. Para el caso de una red aliviada a la hora de hacer el cálculo, el problema es análogo.


Modificaciones: 

- Para solucionar el problema 1, hay que estimar con el algoritmo de Jacobson la desviación media del RTT y no solo su media.
  De esta manera el temporizador se amplía cuando las mediciones son muy dispersas y se ajusta cuando se estabilizan.

- Mediante el algoritmo de Karn se puede solucionar el problema número 2. Este algoritmo resuelve el problema utilizando las
las siguientes reglas:
1. No utilizar el RTT medido para un segmento retransmitido para actualizar SRTT y SDEV.
2. Calcular el RTO de decaimiento utilizando la ecuación: $RTO= q*RTO$ cuando se produzca una re transmisión. 
3. Utilizar el valor del RTO de decaimiento para segmentos sucesivos hasta que llegue una confirmación para un segmento que no se haya retransmitido. 
   
Cuando se recibe una confirmación para un segmento que no se ha retransmitido, se activa de nuevo el algoritmo de Jacobson para calcular valores futuros de RTO.

- Para solucionar el problema número 3, se utiliza:
  - Promediado exponencial: se le da más peso a las observaciones recientes, por lo que sigue los cambios más rápido que la media simple.
  - Decaimiento exponencial del RTO: ante cada retransmisión se multiplica el RTO por una constante ($RTO = q·RTO$, normalmente $q = 2$). Si el vencimiento del temporizador se debe a congestión, esperar más tiempo antes de reintentar evita que todas las fuentes retransmitan a la vez y agraven la congestión.

=== Ejercicio 20.8

==== Consigna

Considere un protocolo de transporte que usa un servicio de red orientado a conexión. Su
ponga que ese protocolo de transporte utiliza un esquema de asignación de créditos para el
control de flujo y que el protocolo de red usa un esquema de ventana deslizante. ¿Qué
relación, si existe, debería haber entre la ventana dinámica del protocolo de transporte y la
ventana fija del protocolo de red?

==== Respuesta

La ventana de red actúa como mecanismo de contrapresión sobre el transporte: si la entidad receptora llena 
su memoria temporal y rechaza datos del servicio de red, la ventana deslizante no avanza, el nivel de red del
emisor agota su ventana y deja de aceptar segmentos del transporte emisor. Por lo tanto, la cantidad que puede 
enviarse está acotada por la menor de ambas ventanas. Sin embargo, este mecanismo es tosco: si hay varias 
conexiones de transporte multiplexadas sobre una conexión de red, el control se aplica sobre el agregado. 
El crédito de transporte, ajustado dinámicamente al espacio libre del receptor, permite controlar cada conexión 
individualmente y evita tener que recurrir al rechazo en el nivel de red, que debería quedar como último recurso.

// Bibliografía. Si hay referencias bibliográficas se renderiza.
// Si no, solamente con full: true se renderiza la bibliografía completa, aunque no haya referencias en el texto
#bibliography("bibliografia.bib", full: true)
