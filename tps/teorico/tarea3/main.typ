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
  trabajo: "Trabajo Práctico Nº 3",
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

  titulo: [Preguntas de repaso y Problemas --- Capítulo 4],
  resumen: none,

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

// Customización por sobre el template
#set par(
  spacing: 1.2em,
)

#set heading(numbering: none)

#v(1fr)
#align(center)[
  #text(size: 10pt)[
    *_Objetivo_ --- Resolver las preguntas de repaso y los problemas del Capítulo 4 de Stallings (2004)*
  ]
]

#pagebreak()

= Trabajo Práctico N°3

= b) PREGUNTAS DE REPASO

== 4.1. ¿Por qué hay dos cables en un par trenzado de cobre?

Cada par de cables trenzados constituye un único enlace de comunicación. La razón de que sean dos conductores, y no uno solo, es eléctrica: para que la corriente circule se necesita un circuito cerrado, es decir, un camino de ida y otro de retorno hacia la fuente; un solo cable no puede transportar una señal sin ese segundo conductor que complete el circuito.

Además, al ser dos conductores trenzados entre sí y muy próximos, ambos quedan expuestos de forma prácticamente idéntica a las interferencias electromagnéticas externas. Esto es lo que permite, en el receptor, tomar la señal como la diferencia entre ambos cables: el ruido captado por igual en los dos se cancela, mejorando la inmunidad al ruido frente a un único conductor.

== 4.2. ¿Cuáles son las limitaciones del par trenzado?

Comparado con otros medios guiados (cable coaxial y fibra óptica), el par trenzado presenta varias limitaciones:

- *Menor ancho de banda, distancia y velocidad de transmisión*: su rango de frecuencias útil (hasta 1 MHz para cables multipar) y la separación entre repetidores (apenas 2 km) son mucho menores que los del cable coaxial (hasta 500 MHz, repetidores cada 1-9 km) o la fibra óptica (de 180 a 370 THz, repetidores cada 40 km).
- *Atenuación fuertemente dependiente de la frecuencia*: a mayor frecuencia de la señal, mayor es la pérdida de energía por unidad de longitud.
- *Alta susceptibilidad a interferencias y ruido*: al acoplarse fácilmente con campos electromagnéticos externos, un par trenzado tendido en paralelo a una línea de alta tensión, por ejemplo, capta la energía de 50/60 Hz de esa línea. También es vulnerable al ruido impulsivo.
- *Necesidad frecuente de regeneración de la señal*: para transmisión analógica requiere amplificadores cada 5-6 km, y para transmisión digital, repetidores cada 2-3 km, un espaciado mucho más corto que el de otros medios guiados.

== 4.3. ¿Cuál es la diferencia entre el par trenzado no apantallado y el par trenzado apantallado?

La diferencia está en si el par de cables está protegido o no por una malla metálica adicional:

- *Par trenzado no apantallado (UTP, _Unshielded Twisted Pair_)*: es el más común, sobre todo en telefonía. Es el medio de transmisión más económico de todos, y también el más simple de instalar y manipular, pero al no tener protección adicional resulta más vulnerable a interferencias electromagnéticas externas, incluyendo las de pares cercanos o fuentes de ruido próximas.
- *Par trenzado apantallado (STP, _Shielded Twisted Pair_)*: el par de cables se recubre con una malla metálica que reduce las interferencias externas. Esto le permite ofrecer mejores prestaciones a velocidades de transmisión más altas, a cambio de ser más costoso y más difícil de manipular que el UTP.

#v(1em)


== 4.4. Describir los principales componentes del cable de fibra óptica.

La fibra óptica es un medio flexible y muy delgado (entre 2 y 125 μm), capaz de confinar un haz de luz en su interior. Se puede fabricar con distintos materiales, con una relación directa entre costo y pérdidas: las fibras de silicio ultrapuro fundido son las que menos pérdidas presentan, pero también las más difíciles de fabricar; las fibras de cristal multicomponente son más económicas a cambio de mayores pérdidas; y las fibras de plástico son las más baratas de todas, aptas para enlaces cortos donde son aceptables pérdidas más altas.

Un cable de fibra óptica tiene forma cilíndrica y está compuesto por tres secciones concéntricas:

- *Núcleo*: la sección más interna, formada por una o varias fibras de cristal o plástico, con un diámetro de entre 8 y 100 μm. Es por donde efectivamente viaja el haz de luz.
- *Revestimiento*: rodea a cada fibra individualmente. Es también cristal o plástico, pero con propiedades ópticas distintas a las del núcleo. La frontera entre núcleo y revestimiento actúa como un reflector que confina el haz de luz dentro del núcleo, sin el cual la luz escaparía.
- *Cubierta*: la capa más exterior, que envuelve a uno o varios revestimientos. Está hecha de plástico y otros materiales dispuestos en capas, con una función puramente de protección física: contra la humedad, la abrasión, aplastamientos y otros daños.

== 4.5. ¿Qué ventajas y desventajas tiene la transmisión de microondas?

*Ventajas:*

- Para una distancia dada, requiere menos repetidores o amplificadores que el cable coaxial.
- Su atenuación crece con el cuadrado de la distancia, no exponencialmente como en el par trenzado o el coaxial, por lo que los repetidores pueden espaciarse mucho más: entre 10 km y 100 km, frente a los pocos km de los medios guiados.
- A mayor frecuencia utilizada, mayor ancho de banda potencial y, por lo tanto, mayor velocidad de transmisión alcanzable.
- A frecuencias más altas, las antenas necesarias son más pequeñas y más económicas.

*Desventajas:*

- Exige que las antenas estén perfectamente alineadas entre sí, siguiendo la línea visual directa, y montadas de forma rígida.
- La atenuación aumenta con la lluvia, un efecto especialmente marcado por encima de los 10 GHz.
- Al ser un medio cada vez más popular, las áreas de cobertura tienden a solaparse, generando riesgo de interferencias, lo que exige una regulación estricta en la asignación de bandas.

== 4.6. ¿Qué es la difusión directa por satélite (DBS, Direct Broadcast Satellite)?

DBS es la aplicación más reciente de la tecnología satelital a la televisión, en la que la señal de video se transmite directamente desde el satélite a los domicilios de los usuarios, sin pasar por estaciones terrestres intermedias que redistribuyan la programación. Se volvió económicamente viable gracias a la reducción en costo y tamaño de las antenas receptoras domésticas, lo que a su vez permitió aumentar la cantidad de canales disponibles.

== 4.7. ¿Por qué un satélite debe usar frecuencias ascendentes y descendentes distintas?

Porque un satélite no puede transmitir y recibir simultáneamente en el mismo rango de frecuencias sin generar interferencia entre ambas señales: si usara la misma banda para el canal ascendente (estación terrestre → satélite) y el descendente (satélite → estación terrestre), la propia retransmisión del satélite se mezclaría con la señal entrante. Por eso, la señal recibida en una frecuencia dada debe reenviarse necesariamente en una frecuencia distinta.

== 4.8. Indique las diferencias más significativas entre la difusión de radio y las microondas.

- *Direccionalidad*: las ondas de radio son omnidireccionales, mientras que las microondas tienen un diagrama de radiación mucho más direccional. Por eso las ondas de radio no requieren antenas parabólicas ni montajes rígidos para mantener la alineación, a diferencia de las microondas.
- *Rango de frecuencias*: las ondas de radio (en el sentido informal usado aquí, VHF y parte de UHF) ocupan de 30 MHz a 1 GHz, un rango bastante más bajo que el de las microondas terrestres (1 a 40 GHz).
- *Sensibilidad a la lluvia*: las microondas se ven significativamente afectadas por la atenuación por lluvia, sobre todo por encima de los 10 GHz; las ondas de radio son mucho menos sensibles a este efecto.
- *Atenuación con la distancia*: ambas siguen la misma relación con la distancia, pero al tener una longitud de onda mayor, las ondas de radio sufren, en términos relativos, menor atenuación que las microondas.
- *Aplicación característica*: la naturaleza omnidireccional de las ondas de radio las hace ideales para difusión simultánea a múltiples destinos (por ejemplo, radio FM o TV VHF/UHF); las microondas, en cambio, se usan típicamente para enlaces punto a punto, ya que necesitan que ambas antenas estén alineadas entre sí.
- *Interferencia característica*: las ondas de radio son propensas a interferencias por multitrayectoria (reflexiones en el suelo, el mar u otros objetos, que pueden generar imágenes fantasma en receptores de TV); las microondas, en cambio, son más susceptibles a interferencias por solapamiento de áreas de cobertura entre enlaces cercanos.

== 4.9. ¿Qué dos funciones realiza una antena?

Una antena es un conductor eléctrico (o un conjunto de conductores) que sirve para radiar o captar energía electromagnética, y cumple dos funciones opuestas:

- *Transmitir*: convierte la energía eléctrica que le llega del transmisor en energía electromagnética, y la radia hacia el entorno cercano (la atmósfera, el espacio o el agua).
- *Recibir*: captura energía electromagnética del entorno y la convierte en energía eléctrica, que entrega al receptor.

En comunicaciones bidireccionales suele usarse la misma antena para ambas funciones, ya que sus características de transferencia de energía son idénticas en los dos sentidos, transmitiendo o recibiendo, siempre que se use la misma frecuencia.

== 4.10. ¿Qué es una antena isotrópica?

Es una antena ideal, sin equivalente físico real, definida como un punto en el espacio que radia potencia de igual forma en todas las direcciones. Su diagrama de radiación (la representación gráfica de cómo radia potencia según la dirección) es, por lo tanto, una esfera perfecta centrada en la posición de la antena. Al ser el caso más simple e igual en todas direcciones, se usa como referencia para medir la ganancia de otras antenas reales.

== 4.11 ¿Cuál es la ventaja de una antena parabólica por reflexión?

Su geometría consigue un haz paralelo sin dispersión. De igual forma, y en la recepción, si las ondas recibidas entran paralelas al eje de la parábola reflectante, la señal resultante se concentrará en el foco de la antena. Tambien cuanto mayor sea el diámetro de la antena parabólica, más direccional será el haz generado

== 4.12 ¿Qué factores determinan la ganancia de una antena?

Los factores que determinan la ganancia de una antena pueden sacarse de la ecuacion para determinar la ganancia de una antena:

$ G = (4 pi A_e)/lambda^2 = (4 pi f^2 A_e)/c^2 $

- $G$: ganancia de la antena.

- $f$: frecuencia de la portadora.

- $c$: velocidad de la luz ($3 times 10^8 " m/s"$).

- $lambda$: longitud de onda de la portadora

- $A_e$: área efectiva.

el área efectiva de una antena isotrópica ideal es $lambda^2/(4 pi)$, siendo la ganancia en potencia igual a 1;

Y el área efectiva de una antena parabólica de área $A$ será $0.56 A$, siendo la ganancia en
potencia igual a $(7A)/lambda^2$

== 4.13 ¿Cuál es la principal causa de la pérdida de señal en comunicaciones vía satélite?

La principal causa es la pérdida en el espacio libre, la cual es la atenuacion dada por la distancia entre las antenas emisoras y receptoras. En comunicaciones vía satélite ésta es la principal causa de las pérdidas. Esta perdida se puede expresar en terminos de la potencia radiada $P_t$ y la recibidad $P_r$.

== 4.14 ¿Qué es la refracción?

La refracción es el fenómeno físico que ocurre cuando una onda electromagnética pasa de un medio con una densidad a otro con una densidad distinta, lo que provoca un cambio en su velocidad y una desviación en su dirección.

== 4.15 ¿Qué diferencia hay entre difracción y dispersión?

La difracción es fenómeno físicoo en el que una onda se desvía, dobla o esparce al encontrar un obstáculo o al atravesar una abertura pequeña. En cambio la dispersion es el fenomeno en el que una onda se separa en distintas componentes de distinta frecuencia o longitud de onda cuando atraviesan un medio material.

#pagebreak()

= c) PROBLEMAS

== 4.1
=== Pregunta

Supóngase que unos datos se almacenan en disquetes de $1.4 "Mb"$ que pesan $30 g$ cada
uno y que una compañía aérea transporta $10^4 "kg"$ de disquetes a una velocidad de $1.000 "km/h"$ sobre una distancia de $5.000 "km"$. ¿Cuál es la velocidad de transmisión en bits por segundo de este sistema?

=== Respuesta

Datos:
- Masa de cada disquete: $m = 30g = 0.03 "Kg"$
- Masa de la cantidad total del disquetes = $10^4 "Kg"$
-  Distancia: $d=5000 "Km"$
- Velocidad: $v = 1000 "Km"/h$
Primero tenemos que que ver cuantos disquetes se pueden tranportar en cada viaje:

$ N = "Masa total" / "Masa individual"= (10^4 "Kg")/(0.03 "Kg") = 333.333.33 $

Entonces por cada viaje viajan: \ 
$ "Total de bytes" =N times "Cantidad de bytes sobre disquetes" \ 
= 333.333.33 " disquetes" times (1.4 times 10^6 " bytes/disquete")\
 approx 4.66667 times 10^11 " bytes" $


En bits eso seria: $ "Total de bits" = 4.66667 times 10^11 " bytes" times 8 " bits/byte" approx 3.73333 times 10^12 " bits" $

Ahora el tiempo que le toma el avion para recorrer esa distancia es: $ "Tiempo" (t) = (5.000 " km")/(1.000 " km/h") = 5 " horas" $

La velocidad de transmision en $"bps"$ es:

$ "Velocidad" = (3.73333 times 10^12 " bits")/(5 h * 3600 "s/h") approx 207.407.407 " bps" $

Entonces la velocidad de transmision en Mbps seria: $207.41 "Mbps"$

== 4.2

=== Pregunta

Sea una línea telefónica caracterizada por una pérdida de $20 "dB"$. La potencia de la señal a
la entrada es de $0.5 W$ y el nivel del ruido a la salida es de $4.5 mu W$ Calcule la relación
señal ruido para la línea en $"dB"$.



=== Respuesta
- Atenuacion = $-20"dB"$
- Potencia de entrada: $p = 0.5W$
- Ruido: $X = 4.5 mu W$
\
La formula de amplitud es: \
$ A_"dB" = 10 times log_10 (p_e / p_s) $\
Luego:
$ A_"dB" / 10 = log_10(P_e/P_s) => 10^(A_"dB"/10) = P_e/P_s $
Despejando $P_S$ y remplazando \
$ P_"salida" = (0.5 " W")/100 = 0.005 " W" = 5 " mW" $
\
Entonces la relacion señal ruido va a ser:

$ "SNR"_"dB" = 10 log_10((0.005 " W")/(4.5 times 10^(-6) " W")) = 10 log_10(1.111.11) approx bold("30.46 dB") $

== 4.3

=== Pregunta

Dada una fuente de 100 W, determine la máxima longitud alcanzable en los siguientes medios de transmisión, si la potencia a recibir es 1 vatio:
- a) Un par trenzado de 0,5 mm (24 gauges) a 300 kHz.
- b) Un par trenzado de 0,5 mm (24 gauges) a 1 MHz.
- c) Un cable coaxial de 9,5 mm a 1 MHz.
- d) Un cable coaxial de 9,5 mm a 25 MHz.
- e) Una fibra óptica trabajando a su frecuencia óptima.

=== Respuesta



Potencia de Transmision:

$ P_"(dBW)" = 10 log_10(100) => 20 "dB" $

Potencia Recibida:

$ P_"(dBW)" = 10 log_10(1) => 0 "dB" $

Perdida total de Potencia:

$ L_"(máx (dB))" = 20 "dB" - 0 "dB" => 20 "dB" $

Entonces la distancia se calcula de esta manera para cada Alpha especifico.

$ d = L_"máx" / alpha $

- a) $d = (20 "dB")/(18 "dB/km") => d = 1.11 "Km"$
- b) $d = (20 "dB")/(29 "dB/km") => d = 0.69 "Km"$
- c) $d = (20 "dB")/(2.5 "dB/km") => d = 8 "Km"$
- d) $d = (20 "dB")/(11 "dB/km") => d = 1.82 "Km"$
- e) $alpha = 0.2 " a " 0.5 " dB/km"$ ,

  Distancia máxima: Para $alpha = 0.5 " dB/km"$: $d = (20 " dB")/(0.5 " dB/km") = bold("40 km")$

  Para $alpha = 0.2 " dB/km"$: $d = (20 " dB")/(0.2 " dB/km") = bold("100 km")$
  Entonces va de 40km a 100km


== 4.4

=== Pregunta

El cable coaxial es un sistema de transmisión con dos conductores. ¿Qué ventaja tiene co-
nectar la malla exterior a tierra?

=== Respuesta

Conectar la malla exterior a tierra en un cable coaxial hace que esta absorba las interferencias electromagnéticas del entorno y las deriva a tierra. Tambien evita que señales o cables vecinos acoplen ruido en la línea de transmisión.

== 4.5

=== Pregunta

Demuestre que duplicando la frecuencia de transmisión o duplicando la distancia entre las antenas de transmisión y recepción, la potencia recibida se atenúa en 6 dB

=== Respuesta

La formula para calcular la perdida en el espacio libre es:

$ L_"dB" = 20 log_10((4 pi dot f dot d)/c) => L_"dB" = 20 log_10(f) + 20 log_10(d) + 20 log_10((4 pi)/c) $

Entonces al duplicar la distancia:

$ L_"dB" = 20 log_10(f) + 20 log_10(2d) + 20 log_10((4 pi)/c) $


$ L_"dB" = 20 log_10(f) + 20 (log_10(d) + log_10(2)) + 20 log_10((4 pi)/c) $

Entonces podemos decir que para el caso de 2d tenemos
$ L_"dB"_2 = L_"dB" + 20 log_10(2) approx L_"dB" + 20 dot 0.30103 approx L_"dB" + bold("6.02 dB") $

De la misma manera se puede llegar a la expresion con la frecuencia:

$ L_"dB" = 20 log_10(2f) + 20 log_10(d) + 20 log_10((4 pi)/c) $

$ L_"dB" = 20 (log_10(f) + log_10(2)) + 20 log_10(d) + 20 log_10((4 pi)/c) $

Entonces:

$ L_"dB"_2 = L_"dB" + 20 log_10(2) approx L_"dB" + 20 dot 0.30103 approx L_"dB" + bold("6.02 dB") $

== 4.6

=== Pregunta

La profundidad en el océano a la que se detectan las señales electromagnéticas generadas desde aeronaves crece con la longitud de onda. Por tanto, los militares encontraron que usando longitudes de onda muy grandes, correspondientes a 30 Hz, podrían comunicarse con cualquier submarino alrededor del mundo. La longitud de las antenas es deseable que sea del orden de la mitad de la longitud de onda. ¿Cuál debería ser la longitud típica de las antenas para operar a esas frecuencias?

=== Respuesta

Para estas antenas la longitud de onda esta dada por:

$ lambda = c/f => lambda = (3 * 10^8 "m/s")/(30 "Hz") = 10.000.000 " m" = 10.000 "Km" $

Como la longitud tiene que ser de el orde de la mitad de la longitud de onda nos queda:

$ "Longitud de la antena" = lambda/2 = (10.000 " km")/2 = bold("5.000 km") $

== 4.7

=== Pregunta

La potencia de la señal de voz está concentrada en torno a los 300 Hz. Las antenas para transmitir esta frecuencia deberían tener un tamaño enormemente grande. Esto hace que, para transmitir voz por radio, la señal deba enviarse modulando una señal de frecuencia superior (portadora) para la que la antena correspondiente requiera un tamaño menor.

a) ¿Cuál debe ser la longitud de una antena, equivalente a la mitad de la longitud de onda, para enviar una señal de 300 Hz?

b) Una posible alternativa es emplear algún esquema de modulación, como los descritos en el Capítulo 5, de tal manera que la señal a transmitir tenga un ancho de banda estrecho, centrado en torno a la frecuencia portadora. Supóngase que quisiéramos una antena de 1 metro de longitud. ¿Qué frecuencia de portadora debería utilizarse?

=== Respuesta

==== a)

$ lambda = c/f => lambda = (3 * 10^8 "m/s")/(300 "Hz") = 1.000.000 " m" = 1.000 "Km" $

Como la longitud tiene que ser de el orde de la mitad de la longitud de onda nos queda:

$ "Longitud de la antena" = lambda/2 = (1.000 " km")/2 = bold("500 km") $

==== b)

$ "Longitud de la antena" = lambda/2 => 2 * "Longitud de la antena" = lambda $

Entonces $"Longitud de la antena" = 1 "m"$:

$ 2 * 1 = lambda => lambda = 2 $

Ahora despejamos la frencuencia de:

$ lambda = c/f => 2 "m" = (3 * 10^8 "m/s")/f => f = (3 * 10^8 "m/s")/(2 "m") = 150 "Mhz" $

== 4.8

=== Pregunta
Hay leyendas sobre gente que es capaz de recibir la señal de radio a través de los empastes de los dientes. Supóngase que tiene un empaste de 2,5 mm (0,0025 m) de largo que actuara a modo de antena, siendo igual su longitud a la mitad de la longitud de onda. ¿Qué frecuencia recibiría?

=== Respuesta
Datos:
- Longitud de la antena = 0.0025m
- Velocidad de propagacion = $3 * 10^8 "m/s"$

$ L = lambda/2 => lambda = 2 * 0.0025 "m" = 0.005 "m" $

Luego, sabiendo que:
$ c = lambda * f => f = c/lambda = (3 * 10^8 "m/s")/(0.005 "m") = 6 * 10^10 "Hz" $

#v(1em)

La frecuencia que recibiría a través del empaste es de $6 * 10^10 "Hz"$

== 4.9

=== Pregunta
Suponga una comunicación entre dos satélites que cumple la ley del espacio libre. Suponga que la señal es muy débil. Se disponen de dos alternativas de diseño. Una consiste en utilizar una frecuencia igual al doble de la frecuencia actual y la otra consiste en duplicar el área efectiva de las dos antenas. Manteniendo todos los demás parámetros inalterados, ¿se conseguirá la misma potencia recibida? o, en caso contrario, ¿cuál de las dos alternativas proporcionaría una potencia recibida superior? ¿Cuál sería el incremento de potencia recibida en el mejor de los casos?
=== Respuesta
La potencia recibida ($P_r$) en una comunicación en espacio libre expresada en función de las áreas efectivas de las antenas transmisora y receptora
($A_"et"$ y $A_"er"$) es:

$ P_r = (P_t * A_"et" * A_"er")/(d^2 * lambda^2) $

Luego: $lambda = c/f$, sustituyendo:

$ P_r = (P_t * A_"et" * A_"er" * f^2)/(d^2 * c^2) $


- Opcion 1 \
Para
$ f_1 = 2f => P_r = (P_t * A_"et" * A_"er" * (2f)^2)/(d^2 * c^2) $
$ P_r = (P_t * A_"et" * A_"er" * 4 f^2)/(d^2 * c^2) $
$ P_r = 4 * (P_t * A_"et" * A_"er" * f^2)/(d^2 * c^2) $

- Opcion 2
$ A_"et"' = 2 A_"et" \ "y" \ A_"er"' = 2 A_"er" $
Luego
$ P_r = (P_t * 2 A_"et" * 2 A_"er" * f^2)/(d^2 * c^2) $
$ P_r = 4 * (P_t * A_"et" * A_"er" * f^2)/(d^2 * c^2) $


¿Se conseguirá la misma potencia recibida?
Sí, las dos ecuaciones son equivalentes y por tanto se obtiene lo mismo.

#pagebreak()

== 4.10
=== Pregunta
En la transmisión de radio en el espacio libre, la potencia de la señal se reduce proporcio nalmente al cuadrado de la distancia recorrida desde la fuente, mientras que en una transmisión en un cable, la atenuación es una cantidad fija en dB por kilómetro. En la siguiente tabla se muestra, en dB, la reducción relativa a una referencia dada para la transmisión en el espacio libre y en un cable uniforme. Rellene las celdas que faltan para completar la tabla.



#align(center, table(
  columns: 3,
  align: center,
  table.header([Longitud], [Radio (dB)], [Cable (dB)]),
  [1], [-6], [-3],
  [2], [], [],
  [4], [], [],
  [8], [], [],
  [16], [], [],
))

=== Respuesta

*Cable*: la atenuación es una cantidad fija en dB por unidad de longitud (modelo lineal). Con la referencia $"Cable"(1) = -3 " dB"$, la fórmula general es:

$ "Cable"(L) = -3 times L "dB" $

*Radio (espacio libre)*: la potencia decae con el cuadrado de la distancia, por lo que cada vez que se duplica la distancia se pierden $20 log_10(2) approx 6 " dB"$ adicionales. Con la referencia $"Radio"(1) = -6 " dB"$, la fórmula general es:

$ "Radio"(L) = -6 - 20 log_10(L) "dB" $

Aplicando ambas fórmulas para cada longitud:

#align(center, table(
  columns: 3,
  align: center,
  table.header([Longitud], [Radio (dB)], [Cable (dB)]),
  [1], [-6], [-3],
  [2], [-12], [-6],
  [4], [-18], [-12],
  [8], [-24], [-24],
  [16], [-30], [-48],
))

== 4.11

=== Pregunta

En la Sección 4.2 se ha establecido que si una fuente de energía electromagnética se sitúa en el foco de un paraboloide, y que si el paraboloide tiene una superficie reflectante, entonces, la onda se reflejará en líneas paralelas al eje del paraboloide. Para demostrar esto considérese, por ejemplo, la parábola mostrada en la Figura 4.12. Sea $P(x_1, y_1)$ un punto de la parábola y sea $P F$ la línea que une $P$ con el foco. Construya la línea $L$ que pasa por $P$ paralela al eje $x$ y la recta $M$ tangente a la parábola en $P$. El ángulo entre $L$ y $M$ es $beta$ y el ángulo entre $P F$ y $M$ es $alpha$. El ángulo $alpha$ es el ángulo con el que el rayo que pasa por $F$ incide en la parábola en $P$. Debido a que el ángulo de incidencia es igual al ángulo de reflexión, el rayo reflejado por $P$ debe ser igual al ángulo $alpha$. Por tanto, si se demuestra que $alpha = beta$, se habrá demostrado que los rayos que se emitan desde $F$ y sean reflejados por la parábola serán paralelos al eje $x$.

#figure(
  image("assets/4_12-parabola_de_reflexion.png", width: 224pt),
  caption: [Parábola de reflexión],
  numbering: none,
)

a) Demuestre primero que $tan beta = (p \/ y_1)$. _Sugerencia_: recuérdese de trigonometría que la pendiente de una recta es igual a la tangente del ángulo que forma esa recta con el eje $x$ positivo. Igualmente, recuérdese que la pendiente de una recta tangente a una curva en un punto dado es igual a la derivada de la curva en ese punto.

b) Ahora demuéstrese que $tan alpha = (p \/ y_1)$, lo que demostraría que $alpha = beta$. _Sugerencia_: recuérdese de trigonometría que la fórmula de la tangente de la diferencia entre dos ángulos $alpha_1$ y $alpha_2$, es

$ tan(alpha_2 - alpha_1) = (tan alpha_2 - tan alpha_1)/(1 + tan alpha_2 dot tan alpha_1) $

=== Respuesta

a)

Se busca probar que $tan beta = (p \/ y_1)$. Siguiendo la sugerencia, $tan beta$ será igual a la pendiente de la recta $M$.

Dado el foco de la parábola, esta se puede modelar como $y^2 = 2 p x$. Luego para obtener la recta tangente a la parábola para una abscisa arbitraria se deriva la ecuación en función de $x$:

$
     (d y)/(d x) y^2 & = (d y)/(d x) 2 p x \
  2 y (d y)/(d x)(x) & = 2 p \
      (d y)/(d x)(x) & = p/y
$

La pendiente de la recta $M$ será la pendinte de la recta tangente a la parábola de reflexión en el punto $(x_1, y_1)$, y se obtiene evaluando la ecuación anterior en $x_1$:

$ (d y)/(d x)(x_1) = p/y_1 $

luego

$ tan beta = (d y)/(d x)(x_1) = p/y_1 $

b) Se busca demostrar que $tan alpha = tan beta = (p \/ y_1)$.

Definiendo al ángulo $alpha_1$ como el ángulo entre el eje $x$ y la recta $P F$ (o la inclinación de $P F$) y recordando que $beta$ es la inclinación de $M$, se tiene que el ángulo comprendido entre $P F$ y $M$ es $alpha = alpha_1 - beta$.

La pendiente de $P F$ es $m_"PF" = y_1/(x_1-p/2)$. Despejando $x_1$ en la ecuación de la parábola tenemos que:

$
  x_1 = (y_1^2)/(2p) => m_"PF" = y_1/((y_1^2)/(2p) - p/2) = (2p y_1)/(y_1^2 - p^2) \
  tan(alpha_1) = m_"PF" = (2p y_1)/(y_1^2 - p^2)
$

Luego, aplicando la propiedad sugerida:

$
  tan(alpha) & = tan(alpha_1 - beta) \
             & = (tan(alpha_1) - tan(beta))/(1 + tan(alpha_1) dot tan(beta)) \
             & = ((2p y_1)/(y_1^2 - p^2) - p/y_1)/(1 + (2p y_1)/(y_1^2 - p^2) dot p/y_1) \
             & = ((2p y_1^2 - p (y_1^2 - p^2))/(y_1 (y_1^2 - p^2)))/(1 + (2p^2)/(y_1^2 - p^2)) \
             & = ((p y_1^2 + p^3)/(y_1 (y_1^2 - p^2)))/(((y_1^2 - p^2) + 2p^2)/(y_1^2 - p^2)) \
             & = ((p (y_1^2 + p^2))/(y_1 (y_1^2 - p^2)))/((y_1^2 + p^2)/(y_1^2 - p^2)) \
             & = (p (y_1^2 + p^2))/(y_1 (y_1^2 - p^2)) dot (y_1^2 - p^2)/(y_1^2 + p^2) \
  tan(alpha) & = tan(beta) = p/y_1
$

Concluyendo en que el ángulo de incidencia es igual al ángulo de reflexión: $alpha = beta$.

== 4.12

=== Pregunta

A menudo es más conveniente expresar las distancias en km en lugar de en m y las frecuencias en MHz en lugar de Hz. Rescriba la Ecuación (4.1) usando estas unidades.

=== Respuesta

La ecuación 4.1 (página 111) describe la relación entre la ganancia de una antena y su area efectiva:

$
  G = (4 pi A_e)/lambda^2 = (4 pi f^2 A_e)/c^2
$

Esta ecuación no es particularmente interesante para la consigna dada. Indagando un poco más, resulta que el problema 4.12 del libro tiene un error de traducción. En la versión en inglés de la 7ma edición del libro, el problema 4.12 hace referencia a la ecuación 4.2 (página 112), que describe la pérdida en el espacio libre:

$
  L = 10 log_10((4 pi d)/lambda)^2 "dB" = 10 log_10((4 pi d f)/c)^2 "dB"
$

Donde:
- $L ["dB"]$: pérdida en el espacio libre.
- $d [m]$: distancia.
- $lambda [m]$: longitud de onda.
- $f ["Hz"]$: frecuencia de la onda.
- $c ["m/s"]$: velocidad de la luz ($approx 3 times 10^8 "m/s"$).

La ecuación equivalente expresando la distancia en $"km"$ y la frecuencia en $"MHz"$ es:

$
  L_"dB" & = 10 log_10((4 pi d f)/c)^2 \
         & = 20 log_10((4 pi (d_"km" times 10^3) (f_"MHz" times 10^6))/(3 times 10^8)) \
         & = 20 log_10((4 pi d_"km" f_"MHz" times 10^9)/(3 times 10^8)) \
         & = 20 log_10((40 pi)/3) + 20 log_10(d_"km") + 20 log_10(f_"MHz") \
         & = 32.442 + 20 log_10(d_"km") + 20 log_10(f_"MHz")
$

== 4.13

=== Pregunta

Suponga que un transmisor emite 50 W de potencia.

a) Exprese la potencia transmitida en dBm y dBW.

b) Si la potencia del transmisor se aplica a una antena con ganancia unidad, usando una frecuencia de portadora de 900 MHz, ¿cuál es la potencia recibida, en dBm, en el espacio libre a una distancia de 100 m?

c) Repita el Apartado (b) para una distancia de 10 km.

d) Repita (c) pero suponiendo una ganancia para la antena de recepción de 2.

=== Respuesta
==== a)

Referencias: *dBW* toma como referencia 1 W, y *dBm* toma como referencia 1 mW ($P = 50 "W" = 50000 "mW"$):

$ P("dBW") = 10 times log_10(50) = bold("16.98 dBW") $
$ P("dBm") = 10 times log_10(50000) = bold("46.98 dBm") $

==== b)

Primero se calcula la pérdida en el espacio libre ($L_p$) para $f = 900 "MHz"$ y $d = 100 "m"$:

$
  L_p("dB") = 20 times log_10((4 pi times d times f)/c) = 20 times log_10((4 pi times 100 times (900 times 10^6))/(3 times 10^8)) = 71.52 "dB"
$

Como las ganancias de ambas antenas son unitarias (0 dB), la potencia recibida es directamente la transmitida menos esa pérdida:

$ P_r("dBm") = p_t("dBm") - L_p("dB") = 46.98 - 71.52 = bold("-24.54 dBm") $

==== c)

Se repite el cálculo anterior para $d = 10 "Km"$ (100 veces más lejos):

$
  L_p("dB") = 20 times log_10((4 pi times d times f)/c) = 20 times log_10((4 pi times (10 times 10^3) times (900 times 10^6))/(3 times 10^8)) = 111.52 "dB"
$

$ P_r("dBm") = p_t("dBm") - L_p("dB") = 46.98 - 111.52 = bold("-64.54 dBm") $
==== d)

Se repite el apartado (c), pero ahora la antena receptora no es unitaria: tiene una ganancia de *2* (valor lineal, no en dB). Para sumarla a la cuenta anterior primero hay que pasarla a dB:

$ G_r("dB") = 10 times log_10(2) = 3.01 "dB" $

A diferencia de la pérdida (que se resta), la ganancia de antena se *suma*, ya que una antena con ganancia concentra más energía en la dirección de interés que una antena isotrópica de referencia:

$ P_r("dBm") = P_t("dBm") - L_p("dB") + G_r("dB") = 46.98 - 111.52 + 3.01 = bold("-61.53 dBm") $

== 4.14

=== Pregunta
Un transmisor de microondas tiene una salida de 0,1 W a 2 GHz. Suponga que este trans-
misor se utiliza en un sistema de comunicación de microondas en el que las antenas trans-
misora y receptora son parábolas, cada una con un diámetro igual a 1,2 m.

a) ¿Cuál es la ganancia de cada antena en decibelios?

b) Teniendo en cuenta la ganancia de la antena para la señal transmitida, ¿cuál es la potencia efectiva radiada?

c) Si la antena receptora se sitúa a 24 km de la antena transmisora en el espacio libre, determine la potencia de la señal a la salida de la antena receptora en dBm.

=== Respuesta

==== a)

$ P = 0.1 "W", \ f = 2 "GHz" \ "y" \ "diametro:" D = 1.2 "m" $

$ bold("Area:") A = pi times (D/2)^2 = pi times (1.2/2)^2 = 1.13 "m"^2 $

$ bold("Longitud de onda:") lambda = c/f = (3 times 10^8)/(2 times 10^9) = 0.15 "m" $

Ganancia de una antena parabólica:

$ G_p("dB") = 10 times log_10(7 times A/lambda^2) = 10 times log_10(7 times 1.13/0.15^2) = bold("25.45 dB") $

Como ambas antenass son identicas, tienen la misma ganacia:

$ G_t = G_r = bold("25.45 dB") $
La ganancia de cada antena es de 25,45dB.

==== b)

$ P_t("dBW") = 10 times log_10(0.1) = -10 "dBW" $
$ P_t("dBm") = -10 + 30 = 20 "dBm" $

*Potencia efectiva radiada* = EIRP(dBm) = P_t(dBm) + G_t(dB) = *45,45dBm*

=== c)

$ bold("distancia:") d = 24 "Km" $

$
  L_p("dB") = 20 times log_10((4 pi times d times f)/c) = 20 times log_10((4 pi times (24 times 10^3) times (2 times 10^9))/(3 times 10^8)) = 126.06 "dB"
$

$ P_r("dBm") = P_t("dBm") - L_p("dB") + G_t("dB") + G_r("dB") = 20 - 126.06 + 25.45 + 25.45 = bold("-55.16 dBm") $

== 4.15

=== Pregunta

En la Sección 4.3 se afirma que si no hay obstáculos intermedios, la trayectoria visual óptica se puede expresar como d 3,75 h, donde d es la distancia entre la antena y el horizonte, en kilómetros, y h es la altura de la antena, en metros. Teniendo en cuenta que el radio de la Tierra es 6.370 km, obtenga la expresión anterior. Sugerencia: supóngase que la antena es perpendicular a la superficie terrestre y nótese que la recta que une el punto más alto de la antena y el horizonte es la tangente a la superficie terrestre en el horizonte. Para visualizar más claramente el problema, dibuje un gráfico con la antena, la trayectoria visual y el radio de la Tierra.

=== Respuesta

Suponiendo que la antena es perpendicular a la superficie terrestre, se puede formar un triángulo rectángulo entre el centro de la Tierra, la base de la antena y el horizonte, ya que la línea de visión es tangente a la superficie y por lo tanto perpendicular al radio en ese punto.

#figure(
  image("assets/Geometría de la línea de visión.jpg", width: 171pt),
  caption: [Geometría de la línea de visión],
  numbering: none,
)

Aplicando el teorema de Pitágoras:

$ (R + h)^2 = R^2 + d^2 $

$ d^2 = 2 R h + h^2 $

Como h es despreciable frente a R = 6.370 km, queda:

$ d approx sqrt(2 R h) $

Ajustando unidades (h en metros → km, dividiendo por 1000):

$ d = sqrt(2 dot 6.370 dot h/1000) = sqrt(12.74) sqrt(h) approx 3.57 sqrt(h) $

Por eso se llega a la expresión *d = 3,57√h*, que después se usa para resolver los ejercicios de línea de visión óptica y de radio.

#pagebreak()

== 4.16

=== Pregunta

Calcule la altura de una antena de una emisora de TV que sea capaz de alcanzar clientes alejados a 80 km.

=== Respuesta

Usando la fórmula de la línea de visión de radio con factor K = 4/3.

$ d = 3.57 sqrt(K h) $

Despejando h:

$ h = (d \/ 3.57)^2 / K = (80 \/ 3.57)^2 / (4 \/ 3) = 22.41^2 / 1.333 = 502.2 / 1.333 approx 376.6 "m" $

La altura de una antena de una emisora de TV debe ser de aproximadamente 376,6 metros.

== 4.17

=== Pregunta

Suponga que un rayo de luz visible pasa desde la atmósfera hasta el agua formando un ángulo con el horizonte de 30. ¿Cuál es el ángulo del rayo en el agua? Nota: en condiciones atmosféricas normales en la superficie terrestre, un valor razonable del índice de refracción es 1,0003. El valor típico del índice de refracción en el agua es 4/3.

=== Respuesta

Usando la Ley de Snell

$ n_1 sin theta_i = n_2 sin theta_r $

Como el ángulo dado (30°) es respecto al horizonte, el ángulo de incidencia respecto a la normal es:

$ theta_i = 90° - 30° = 60° $

Con n₁ = 1,0003 (aire) y n₂ = 4/3 (agua):

$ 1.0003 dot sin(60°) = 4/3 sin theta_r $

$ 1.0003 dot 0.8660 = 0.8663 = 4/3 sin theta_r $

$ sin theta_r = 0.8663/(4 \/ 3) = 0.6497 $

$ theta_r = arcsin(0.6497) approx 40.5° $

Convirtiendo ese resultado a ángulo respecto al horizonte:

$ 90° - 40.5° approx 49.5° $

El ángulo del rayo en el agua es de aproximadamente 40,5° respecto a la normal o 49,5° respecto al horizonte.

= Bibliografía

Stallings, W. _Comunicaciones y Redes de Computadoras_.
