== Diseño experimental

// Presentación de los dos experimentos y de la estructura común (planteo, implementación, resultados y análisis).

=== Plataforma común

// Placas ESP32 emuladas con QEMU, broker Mosquitto y backend; restricciones de la emulación.

=== Experimento 1: MQTT contra HTTPS para telemetría

// Caso base. Mide el costo del transporte y de la serialización por separado,
// El experimento 2 se apoya en esos números.

==== Planteo

==== Implementación

==== Resultados

==== Análisis de resultados

=== Experimento 2: sincronización de osciladores acoplados

La sincronización colectiva aparece cuando un conjunto de osciladores, cada uno con su propio ritmo, termina funcionando a una frecuencia común sin que nadie la imponga. Las diferencias entre las frecuencias naturales no desaparecen, pero la interacción alcanza para compensarlas. En biología se observa en las células marcapasos del corazón, en las células del núcleo supraquiasmático que regulan los ritmos circadianos, en suspensiones de levaduras, en las luciérnagas que destellan al unísono y en los grillos que cantan a la vez. En física e ingeniería aparece en arreglos de láseres, en osciladores de microondas y en uniones de Josephson @strogatz2000.

La idea del experimento es reproducir ese fenómeno con una red de nodos que se comportan como luciérnagas. Cada ESP32 ejecuta un único oscilador, con una frecuencia natural distinta a la de los demás: su fase avanza a su propio ritmo y cada vuelta completa equivale a un destello. Si los nodos no se comunican, cada uno destella a su frecuencia. Si cada uno conoce la fase de los otros y corrige la propia, a partir de cierto acoplamiento el grupo se engancha en un ritmo común, sin ningún nodo que actúe de coordinador.

Esa sincronía existe solo a través de los mensajes que intercambian los nodos, y por eso sirve para evaluar el stack. El modelo matemático predice cómo debería comportarse el grupo si la comunicación fuera ideal, de modo que la sincronización funciona como una carga de referencia con un comportamiento teórico conocido. Comparar esa predicción con lo que se mide en los nodos permite observar qué tan bien cumple el transporte con lo que la aplicación necesita.

La prueba se implementa sobre la plataforma común, con un oscilador por cada ESP32 emulada. Cada nodo integra periódicamente su fase, la serializa con Protocol Buffers junto con su identificador y una marca de tiempo, y la publica por MQTT en un tópico propio, por ejemplo `kuramoto/phase/7`. Además, se suscribe con un comodín a `kuramoto/phase/+`, de modo que recibe las fases de todos los demás a través del broker. Con esas fases calcula la corrección que aplica a su propia evolución, y el ciclo se repite.

Este esquema aprovecha las características del stack presentadas en el marco teórico. Es un intercambio de muchos a muchos: ningún nodo necesita conocer la dirección de los otros, y sumar uno nuevo no requiere modificar a los que ya están, porque el modelo publicador/suscriptor desacopla a quienes envían de quienes reciben. También exige mucho del broker, que entrega cada publicación a los otros $N - 1$ nodos, lo que da $N(N - 1)$ entregas por cada ronda de publicaciones. Como los mensajes son cortos y muy frecuentes, el tamaño reducido de la codificación binaria de Protocol Buffers y el encabezado pequeño de MQTT tienen un efecto directo sobre el tráfico total.

// TODO(rebase sobre master) Reemplazar las menciones al marco teórico por referencias: @sec-pubsub, @sec-mqtt, @sec-protobuf y @sec-ruteo-topicos (comodines).

==== Planteo

*El modelo.* El experimento se basa en el modelo de osciladores acoplados que propuso Kuramoto @kuramoto1975. Para presentarlo se sigue la revisión de Strogatz @strogatz2000, y para el caso de una cantidad finita de osciladores, el trabajo de Verwoerd y Mason @verwoerd2008. Cada oscilador se describe solo por su fase y está acoplado a todos los demás con el mismo peso. Tiene una frecuencia natural $omega_i$, que es fija, y una fase $theta_i$, que evoluciona según

$ dot(theta)_i = omega_i + K/N sum_(j=1)^N sin(theta_j - theta_i), quad i = 1, dots, N $ <ec-kuramoto>

donde $K$ es la intensidad del acoplamiento, en rad/s. El acoplamiento cambia la velocidad instantánea $dot(theta)_i$: si el oscilador $j$ va adelantado, $sin(theta_j - theta_i) > 0$ y el oscilador $i$ se acelera; si va atrasado, se frena.

*Parámetro de orden y campo medio.* El grado de sincronía se mide con el centroide de las fases sobre el círculo unitario:

$ r e^(i psi) = 1/N sum_(j=1)^N e^(i theta_j) $ <ec-orden>

$r$ vale 0 si las fases están dispersas y 1 si coinciden; $psi$ es la fase media @strogatz2000. La @fig-orden muestra ambas situaciones.

// Dibuja N fases (en grados) sobre el círculo unitario con su centroide, calculado a partir de esas mismas fases.
#import "@preview/cetz:0.4.2"
#let circulo-orden(fases, detalle: false) = cetz.canvas(length: 1.5cm, {
  import cetz.draw: *
  let n = fases.len()
  let cx = fases.map(t => calc.cos(t * 1deg)).sum() / n
  let cy = fases.map(t => calc.sin(t * 1deg)).sum() / n
  let r = calc.sqrt(cx * cx + cy * cy)
  let media = calc.atan2(cx, cy)
  let eje = 0.4pt + gray
  line((-1.25, 0), (1.25, 0), stroke: eje)
  line((0, -1.25), (0, 1.25), stroke: eje)
  circle((0, 0), radius: 1, stroke: 0.7pt)
  for t in fases {
    circle((calc.cos(t * 1deg), calc.sin(t * 1deg)), radius: 0.06, fill: white, stroke: 0.7pt)
  }
  line((0, 0), (cx, cy), stroke: 1pt, mark: (end: ">", fill: black, scale: 0.6))
  circle((cx, cy), radius: 0.04, fill: black, stroke: none)
  if detalle {
    arc((0, 0), start: 0deg, stop: media, radius: 0.3, anchor: "origin", stroke: 0.6pt)
    content((0.47 * calc.cos(media / 2), 0.47 * calc.sin(media / 2)), $psi$)
    content((cx / 2 - 0.14 * calc.sin(media), cy / 2 + 0.14 * calc.cos(media)), $r$)
    let t = fases.last()
    content((1.26 * calc.cos(t * 1deg), 1.26 * calc.sin(t * 1deg)), $theta_j$)
  }
  content((0, -1.5), [$r approx$ #str(calc.round(r, digits: 2)).replace(".", ",")])
})

#figure(
  grid(
    columns: 2,
    column-gutter: 2.5em,
    circulo-orden((12, 68, 128, 172, 233, 262, 308, 349)),
    circulo-orden((22, 34, 47, 60, 71, 84, 97, 116), detalle: true),
  ),
  caption: [Fases de ocho osciladores sobre el círculo unitario (círculos vacíos) y su centroide $r e^(i psi)$ (punto negro). A la izquierda, fases dispersas; a la derecha, fases agrupadas.],
) <fig-orden>

Si se multiplica la @ec-orden por $e^(-i theta_i)$ y se toma la parte imaginaria, resulta

$ r sin(psi - theta_i) = 1/N sum_(j=1)^N sin(theta_j - theta_i) $

Al reemplazar esa suma en la @ec-kuramoto se obtiene la forma de campo medio @strogatz2000, que vale para cualquier $N$:

$ dot(theta)_i = omega_i + K r sin(psi - theta_i) $ <ec-campo-medio>

Cada oscilador es atraído hacia la fase media con una fuerza $K r$. Es la forma que se implementa en los nodos. El promedio de fases tiene que ser circular: se suman los vectores $(cos theta_j, sin theta_j)$ y se toman el módulo y el ángulo de la suma. Promediar los ángulos directamente falla en el corte entre $2 pi$ y 0.

*Frecuencia común.* Para saber a qué frecuencia gira el grupo cuando se engancha, se suma la @ec-kuramoto sobre todos los osciladores:

$ sum_(i=1)^N dot(theta)_i = sum_(i=1)^N omega_i + K/N sum_(i=1)^N sum_(j=1)^N sin(theta_j - theta_i) $

La suma doble vale cero. Como el seno es impar, $sin(theta_j - theta_i) = -sin(theta_i - theta_j)$, de modo que el término del par $(i, j)$ se cancela con el del par $(j, i)$, y los términos con $i = j$ ya son nulos. Queda entonces

$ d/(d t) sum_(i=1)^N theta_i = sum_(i=1)^N omega_i $ <ec-suma-fases>

Esta relación vale siempre, haya o no enganche: el acoplamiento redistribuye las velocidades entre los osciladores, pero no cambia su suma. Si además todos están enganchados, $dot(theta)_i = Omega$ para todo $i$, y la @ec-suma-fases da $N Omega = sum_i omega_i$, es decir

$ Omega = overline(omega) = 1/N sum_(i=1)^N omega_i $ <ec-frecuencia-comun>

Verwoerd y Mason llegan al mismo resultado: en un estado enganchado, cada oscilador avanza a una velocidad constante igual a la media de las frecuencias naturales @verwoerd2008. Desde ahí se trabaja con las desintonías $Delta_i = omega_i - overline(omega)$. Con retardo en el acoplamiento, la frecuencia común deja de ser igual a la media.

*Límite de infinitos osciladores.* El primer resultado sobre el umbral de sincronización es el análisis de Kuramoto para $N -> infinity$, que se resume siguiendo a Strogatz @strogatz2000. Las desintonías se toman de una densidad $g(Delta)$ unimodal y simétrica, y se buscan soluciones estacionarias, con $r$ constante y $psi$ girando a velocidad uniforme. Si las fases se miden desde $psi$, la @ec-campo-medio se reduce a

$ dot(theta)_i = Delta_i - K r sin theta_i $

Según el valor de $Delta_i$, los osciladores se separan en dos grupos. Los que cumplen $|Delta_i| <= K r$ tienden a un punto fijo con $Delta_i = K r sin theta_i$ y $|theta_i| <= pi\/2$, y quedan enganchados. Los que tienen $|Delta_i| > K r$ no alcanzan ningún punto fijo y derivan alrededor del círculo.

El valor de $r$ tiene que ser coherente con estas dos poblaciones. La simetría de $g$ anula la contribución de los osciladores a la deriva al centroide, y también la parte imaginaria de la contribución de los enganchados. Solo queda el promedio de $cos theta$ sobre los enganchados, y con el cambio de variable $Delta = K r sin theta$ resulta

$ r = integral_(-K r)^(K r) cos theta(Delta) thin g(Delta) dif Delta = K r integral_(-pi\/2)^(pi\/2) cos^2 theta thin g(K r sin theta) dif theta $

Esta ecuación siempre admite la solución $r = 0$, que corresponde al estado incoherente. Las demás soluciones, con sincronización parcial, se obtienen dividiendo por $r$:

$ 1 = K integral_(-pi\/2)^(pi\/2) cos^2 theta thin g(K r sin theta) dif theta $ <ec-rama-parcial>

El acoplamiento crítico es el valor en el que esta rama nace desde $r = 0$. Al tomar $r -> 0^+$ en la @ec-rama-parcial, $g$ se evalúa en 0 y la integral de $cos^2 theta$ vale $pi\/2$, de modo que $1 = K_c g(0) pi\/2$, es decir

$ K_c = 2/(pi g(0)) $ <ec-kc-infinito>

Para una distribución de Lorentz de ancho $gamma$, $g(0) = 1\/(pi gamma)$, por lo que $K_c = 2 gamma$ y, por encima del umbral, $r = sqrt(1 - K_c\/K)$ @strogatz2000. Estas expresiones valen en el límite de infinitos osciladores. Con $N$ finito, $r$ fluctúa con una amplitud del orden de $N^(-1\/2)$ @strogatz2000. Por eso, en este trabajo la @ec-kc-infinito queda solo como contexto, y $K_c$ se calcula como se muestra a continuación.

*Umbral exacto con $N$ finito.* Verwoerd y Mason estudian el mismo modelo para una cantidad finita de osciladores @verwoerd2008, y definen el acoplamiento crítico como el menor $K$ para el que existe un estado enganchado. No es el mismo umbral que el de la @ec-kc-infinito: aquel marca el comienzo de la sincronización parcial, y este, el enganche de todos los osciladores.

En un estado enganchado, $dot(theta)_i = overline(omega)$ para todo $i$. Reemplazando en la @ec-campo-medio se obtiene

$ Delta_i = u sin(theta_i - psi), quad u = K r $

Por lo tanto, cada oscilador necesita $|Delta_i| <= u$. De la parte real de la @ec-orden, multiplicada por $e^(-i psi)$, sale $r = 1\/N sum_i cos(theta_i - psi)$, y cada coseno vale $plus.minus sqrt(1 - (Delta_i\/u)^2)$. Verwoerd y Mason demuestran que existe un estado enganchado si y solo si la ecuación resultante tiene solución con todos los signos positivos @verwoerd2008, lo que da la condición de autoconsistencia:

$ r = u/K = f(u) = 1/N sum_(i=1)^N sqrt(1 - (Delta_i/u)^2), quad u >= max_i |Delta_i| $ <ec-autoconsistencia>

Despejando, $K = u\/f(u)$, y el menor acoplamiento para el que hay solución es

$ K_c = min_(u >= max_i |Delta_i|) u/f(u) $ <ec-kc-finito>

Al derivar $u\/f(u)$ e igualar a cero, el mínimo queda en el valor $u^*$ que cumple

$ 2 dot 1/N sum_(i=1)^N sqrt(1 - (Delta_i/u^*)^2) = 1/N sum_(i=1)^N 1/sqrt(1 - (Delta_i/u^*)^2) $

Esa ecuación tiene una única solución @verwoerd2008, y entonces $K_c = u^* \/ f(u^*)$. El resultado garantiza que el estado enganchado existe, pero no que el sistema lo alcance desde cualquier condición inicial, porque el trabajo no aborda la estabilidad. Ese punto se comprueba con la simulación.

Con esto se calculan, para las frecuencias concretas de cada corrida, el umbral de enganche total, el $r$ final y el desfasaje de cada nodo. Con $N = 2$ se obtiene $K_c = |Delta omega|$.

*Enganche parcial y normalización.* Con $N >= 3$ y frecuencias asimétricas, puede engancharse un subgrupo mientras otro nodo deriva. Este caso no tiene fórmula simple y se estudia por simulación, comparando las frecuencias efectivas de cada nodo. Como el acoplamiento se divide por $N$, al agregar nodos con el mismo $K$ cada interacción individual se debilita. Si cada nodo dividiera por la cantidad de fases recibidas en lugar de un $N$ fijo, el modelo cambiaría cuando se pierden mensajes; por eso conviene usar $N$ fijo.

*Efecto de la red: retardo.* En la red, cada nodo conoce las fases de los demás con un retardo $tau$:

$ dot(theta)_i = omega_i + K/N sum_(j != i) sin(theta_j (t - tau) - theta_i (t)) $ <ec-retardo>

La suma excluye $j = i$ porque cada nodo conoce su propia fase sin demora. Para osciladores idénticos, si se incluyera ese término propio, la frecuencia común cumpliría $Omega = omega - K sin(Omega tau)$, y el estado en fase sería estable si $K cos(Omega tau) > 0$. En la implementación ese término no existe.

*$N = 2$ con retardo.* Con $phi = theta_2 - theta_1$ y $Delta omega = omega_2 - omega_1$, el estado enganchado de la @ec-retardo cumple

$ Delta omega = K sin phi cos(Omega tau), quad Omega = overline(omega) - K/2 cos phi sin(Omega tau) $

La primera condición solo tiene solución si $K |cos(Omega tau)| >= |Delta omega|$. Aproximando $Omega approx overline(omega)$:

$ K_c (tau) approx (|Delta omega|)/(|cos(overline(omega) tau)|) $ <ec-kc-retardo>

Una simulación con $overline(omega) = 2 pi$ rad/s y $Delta omega =$ 0,2 rad/s dio el primer $K$ con enganche en 0,200 sin retardo, 0,247 con $tau =$ 100 ms y 0,647 con $tau =$ 200 ms, y la frecuencia común bajó de 6,283 a 6,178 rad/s. La @ec-kc-retardo da así una predicción de $K_c$ y de $Omega$ en función de la latencia.

El retardo entra multiplicado por la frecuencia absoluta de parpadeo $overline(omega)$, no por la desintonía. A 1 Hz, con 250 ms de latencia ya no hay enganche con un $K$ moderado; a 0,5 Hz el límite pasa a 500 ms. La frecuencia de parpadeo define cuánta latencia tolera el sistema.

*Pérdida de paquetes.* MQTT viaja sobre TCP: si se descarta un paquete, TCP lo retransmite y el mensaje llega igual, más tarde, aun con QoS 0. La pérdida de paquetes se traduce en retardo adicional y jitter, no en mensajes perdidos. Los mensajes se pierden de verdad solo si se descartan en la aplicación o si se corta la conexión. En ese caso, el efecto depende de la política del nodo:
- si mantiene la última fase recibida, la pérdida aumenta la edad de la información y actúa como retardo adicional;
- si usa solo lo recibido en cada paso, con $N$ fijo, el acoplamiento efectivo baja a aproximadamente $K(1 - p)$.

*Actualización discreta.* Cada nodo integra su fase con un paso propio y publica con un período $h$. Son dos parámetros distintos. Con integración de Euler, el lazo es estable si $0 < K h < 2$, pero con valores reales $K h approx$ 0,05, así que ese límite no influye. El período de publicación determina cada cuánto llega información nueva, y actúa como un retardo adicional de alrededor de $h\/2$.

*Jitter y caída del broker.* La variación del retardo actúa como ruido en la fase: baja $r$ en régimen y sube el $K_c$ medido. Si cae el broker, el acoplamiento se anula y cada nodo vuelve a su frecuencia natural.

*Acoplamiento efectivo.* $K$ es una ganancia del software de cada nodo: se fija al comienzo de cada corrida y no cambia durante ella. No depende de la red y no cambia el tráfico, que lo determinan $h$ y el tamaño de los mensajes. La red no modifica $K$, pero sí el acoplamiento efectivo (@tab-acople-efectivo). Por eso hace falta un $K$ mayor que el teórico para lograr el enganche, y la diferencia entre el $K_c$ teórico y el medido es lo que el stack le quita a la sincronización.

#figure(
  table(
    columns: (auto, 1fr),
    table.header[Efecto de la red][Acoplamiento efectivo],
    [Latencia $tau$], [Con $N = 2$, el enganche exige $K |cos(overline(omega) tau)| >= |Delta omega|$],
    [Pérdida de mensajes (solo lo recibido, $N$ fijo)], [Aproximadamente $K(1 - p)$],
    [Período de publicación $h$], [Información vieja: retardo adicional de alrededor de $h\/2$],
    [Caída del broker], [Nulo],
  ),
  caption: [Efecto de la red sobre el acoplamiento efectivo.],
) <tab-acople-efectivo>

==== Implementación

==== Resultados

==== Análisis de resultados
