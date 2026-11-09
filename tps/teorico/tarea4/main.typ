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
  trabajo: "Trabajo Práctico Nº 4",
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

  titulo: [Preguntas de repaso --- Capítulo 15],
  resumen: [*_Objetivo_ --- Resolver las preguntas de repaso del Capítulo 15 de @stallings2004, sobre redes de área local: requisitos, topologías, la arquitectura del estándar IEEE 802 y los dispositivos de interconexión de capa 2.*],

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

// Numerar las preguntas como en el libro (15.1, 15.2, ...)
#counter(heading).update(14)

= Preguntas de repaso --- Capítulo 15

== ¿Qué diferencias hay entre los requisitos clave para las redes existentes en salas de computadores de aquellos necesarios para redes de área local de computadores personales?

El libro relaciona "redes en salas de computadores" con redes de respaldo o _backend_ comunicando centalizaciones de cómputo o almacenamiento de datos. Situándonos temporalmente en el año 2004 en el que se editó el libro, las redes "exitentes" eran redes de este tipo, y las redes LAN eran consideradas "recientes".

Teniendo esto en cuenta, podemos decir que las diferencias entre los requisitos de las redes _backend_ y las redes LAN de computadoras personales son:

- Coste de la conexión a la red: En redes de computadoras personales el coste de acceso a la red debe ser significativamente menor que el coste del propio equipo, en general limitando la velocidad de la red.
- Velocidad de la red: Como resultado del punto anterior las redes LAN de computadoras personales pueden estar limitadas en velocidad, mientras que para las redes de respaldo y almacenamiento la velocidad es un requisito clave.
- Cobertura y cantidad de dispositivos: Una red LAN de computadoras personales puede abarcar una o varias oficinas y múltiples estaciones u otros dispositivos como impresoras, mientras que en redes _backend_ la cobertura suele limitarse a unos pocos dispositivos de alto rendimiento ubicados en un mismo lugar.
- Fiabilidad: En redes de _backend_ se prioriza la fiabilidad para maximizar la productividad de los sistemas, mientras que en redes LAN la fiabilidad puede no ser crítica. Esto implica que para redes _backend_ suele implementarse un acceso al medio distribuido mas eficiente.

== ¿Qué diferencias hay entre una red LAN de respaldo, una red SAN y una red LAN troncal?

- Red LAN _backend_: conecta sistemas grandes como servidores, sistemas de cómputo y almacenamiento de datos priorizando velocidad y fiabilidad para la transferencia de datos entre pocos dispositivos.
- Red SAN (_Storage Area Network_): es una red independiente de uso exclusivo para gestión y almacenamiento de datos, ofreciendo un servicio de almacenamiento compartido. A diferencia de una LAN típica donde los servidores tienen su sistema de almacenamiento local, en una SAN no hay servidor entre los dispositivos de almacenamiento y la red sino que los servidores y los dispositivos de almacenamiento están directamente conectados a la red. La red prioriza la comunicación entre dispositivos de almacenamiento (para, por ejemplo, crear réplicas de datos) y la eficiencia de acceso de los clientes al almacenamiento.
- Red LAN troncal: su objetivo es interconectar distintas redes LAN de una misma organización, por lo que debe ser fiable y rápida, aunque por razones distintas que los otros tipos de redes LAN.

== ¿Qué es la topología de una red?

La topología de una red define la manera en que se conectan entre sí las estaciones de la red.

== Enumere cuatro topologías comunes para redes LAN y describa brevemente su principio de funcionamiento.

Las topologías mas comunes para redes LAN son cuatro:

- *Bus*: las estaciones se conectan mediante _taps_ _full-duplex_ a un medio lineal (generalmente un cable coaxial) con terminadores resistivos en ambos extremos para evitar las reflexiones de la señal. Las transisiones de cualquier estación se propagan a todas las demás estaciones, que identifican si el mensaje está dirigido a ellas. Requiere arbitraje del medio para evitar colisiones.

#figure(
  image("assets/topologia-bus.png", width: 60%),
  caption: [Topología bus],
)

- *Árbol*: es una generalización del bus, donde el medio lineal se ramifica mediante concentradores (_hubs_) en segmentos.

#figure(
  image("assets/topologia-arbol.png", width: 60%),
  caption: [Topología árbol],
)

- *Anillo*: las estaciones se conectan en un anillo cerrado mediante repetidores. Una trama viaja a través del anillo completo, siendo copiada al pasar por la estación destino, y es eliminada del anillo al volver al emisor. También requiere control de acceso al medio para evitar colisiones.

#figure(
  image("assets/topologia-anillo.png", width: 60%),
  caption: [Topología anillo],
)

- *Estrella*: las estaciones se conectan a un nodo central común mediante dos enlaces punto a punto (uno para transmisión y el otro para recepción). En el caso de que el nodo central sea un _hub_, la red actúa como un bus produciendo la difusión de tramas en toda la red. En el caso de que el nodo central sea un conmutador (_switch_), las tramas viajan (en lo posible) únicamente al destino. Conectando varios nodos centrales entre sí se logran topologías mas complejas que requieren la implementación de sistemas de encaminamiento.

#figure(
  image("assets/topologia-estrella.png", width: 60%),
  caption: [Topología estrella],
)

== ¿Cuál es el propósito del comité IEEE 802?

El comité IEEE 802 normaliza la capa física y de enlace de datos para redes LAN y MAN. Para eso dividió la capa de enlace en dos subcapas, LLC (Control de Enlace Lógico) y MAC (Control de Acceso al Medio), lo que permite que un mismo protocolo LLC funcione sobre distintos esquemas de acceso al medio, como los que definen 802.3 (Ethernet) o 802.11 (WiFi). Así, distintas tecnologías de nivel físico y MAC pueden competir y evolucionar por separado sin afectar a la capa superior. Dentro del mismo comité, el subgrupo 802.1 se ocupa de la interconexión, incluyendo puentes y árbol de expansión.

== ¿Por qué existen diferentes normativas para redes LAN?

Existen varias normativas porque cada medio físico (cable coaxial, par trenzado, fibra óptica, medio inalámbrico) impone requisitos de acceso al medio distintos: Ethernet usa contención tipo CSMA/CD, las redes en anillo usan paso de testigo y las redes inalámbricas usan variantes de contención adaptadas a ese medio. También pesa que cada entorno de uso prioriza cosas distintas, como bajo costo, máximo rendimiento o tiempo real, algo que una sola normativa difícilmente podría cubrir bien en todos los casos. Por último, varias de estas tecnologías se desarrollaron de forma independiente y compitiendo entre sí, así que terminaron normalizándose por separado en vez de unificarse en un solo estándar.

== Enumere y describa brevemente los servicios proporcionados por LLC.

Los servicios proporcionados por el Control de Enlace Logico son lo siguientes:

- *Servicio no orientado a conexión sin confirmación:* este servicio es de tipo datagrama. Es muy sencillo, puesto que no incluye mecanismos de control de flujo ni de errores, por lo que no está garantizada la recepción de los datos.

- *Servicio en modo conexión:* En este servicion se establece una conexión lógica entre dos usuarios que intercambian datos, existiendo control de flujo y de errores.

- *Servicio no orientado a conexión con confirmación:* es una mezcla de los dos anteriores. Los datagramas son confirmados, pero no se establece conexión lógica previa.

== Enumere y describa brevemente los modos de operación proporcionados por el protocolo LLC.

=== Operacion de Tipo 1:

Transmite las tramas de datos sin establecer una sesión o conexión previa y sin requerir acuses de recibo. Tampoco implementa control de flujo ni control de errores en la subcapa LLC, aunque existe detección de errores y rechazo a nivel MAC.

=== Operacion de Tipo 2:

En este modo se requiere el establecimiento previo de un enlace lógico entre los puntos de acceso al servicio (SAP) del emisor y del receptor antes de iniciar la transferencia de datos.

=== Operacion de Tipo 3:

En este modo los datos se envían en sucesivas PDU de orden AC, y deben ser confirmadas usando una PDU de respuesta AC.

== Enumere algunas funciones básicas que se realicen en la capa MAC.

+ *Control de acceso al medio:* Regula y gestiona el uso del canal físico compartido entre múltiples dispositivos para evitar o gestionar conflictos de transmisión.

+ *Encapsulado de datos y delimitación de tramas:* Ensambla los datos en tramas en la emisión y su desarmado en la recepción, incluyendo la identificación clara del inicio y fin de la trama.

+ *Detección de errores:* Genera y comprueba la Secuencia de Comprobación de Trama (FCS / CRC) para detectar tramas alteradas durante la transmisión y proceder a su descarte.

+ *Direccionamiento físico:* Incluye las direcciones MAC de origen y destino en la cabecera para la identificación unívoca de los dispositivos en la red local.

== ¿Qué funciones lleva a cabo un puente?

- *Filtrado y reenvío:* Lee la dirección MAC de destino para decidir si transmite la trama a otro segmento o la descarta.
- *Aprendizaje automático:* Inspecciona las direcciones de origen para construir dinámicamente una tabla de direcciones MAC asignadas a sus puertos.
- *Segmentación de red:* Divide una red grande en dominios de colisión independientes para reducir el tráfico innecesario.

== ¿Qué es un árbol de expansión?

Es un mecanismo en el que los puentes desarrollan automáticamente una tabla de encaminamiento y la actualizan en respuesta a cambios en la topología. El algoritmo consta de tres mecanismos: retransmisión de tramas, aprendizaje de direcciones y mecanismo para evitar bucles

== ¿Qué diferencias existen entre un concentrador y un conmutador de capa 2?

*Concentrador/Hub (Capa 1):* Es un repetidor pasivo que retransmite las señales a todos sus puertos por igual. Todos los equipos comparten un único dominio de colisión y el mismo ancho de banda.

*Switch L2 (Capa 2):* Examina la trama y la reenvía únicamente al puerto de destino correspondiente. Otorga un dominio de colisión independiente por puerto y permite transmisiones simultáneas.

== ¿Cuál es la diferencia entre un conmutador de almacenamiento y envío y uno rápido?

*Almacenamiento y envío:* Recibe la trama completa en su memoria intermedia, verifica que no tenga errores mediante el código CRC/FCS y luego la reenvía. Mayor latencia, pero no propaga tramas corruptas.

*Conmutación rápida:* Lee solo los primeros bytes para obtener la dirección MAC de destino y comienza a reenviar la trama de inmediato. Menor latencia, pero puede reenviar tramas dañadas.


// Bibliografía. Si hay referencias bibliográficas se renderiza.
// Si no, solamente con full: true se renderiza la bibliografía completa, aunque no haya referencias en el texto
#bibliography("bibliografia.bib", full: true)
