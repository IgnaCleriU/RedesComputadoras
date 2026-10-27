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

==== Planteo

*El modelo.* Cada oscilador tiene una frecuencia natural $omega_i$, que es fija, y una fase $theta_i$, que evoluciona según

$ dot(theta)_i = omega_i + K/N sum_(j=1)^N sin(theta_j - theta_i), quad i = 1, dots, N $ <ec-kuramoto>

donde $K$ es la intensidad del acoplamiento, en rad/s. El acoplamiento cambia la velocidad instantánea $dot(theta)_i$: si el oscilador $j$ va adelantado, $sin(theta_j - theta_i) > 0$ y el oscilador $i$ se acelera; si va atrasado, se frena.

*Parámetro de orden y campo medio.* El grado de sincronía se mide con el centroide de las fases sobre el círculo unitario:

$ r e^(i psi) = 1/N sum_(j=1)^N e^(i theta_j) $ <ec-orden>

$r$ vale 0 si las fases están dispersas y 1 si coinciden; $psi$ es la fase media. Con esta definición, la @ec-kuramoto se reescribe en forma de campo medio, que vale para cualquier $N$:

$ dot(theta)_i = omega_i + K r sin(psi - theta_i) $ <ec-campo-medio>

Cada oscilador es atraído hacia la fase media con una fuerza $K r$. Es la forma que se implementa en los nodos. El promedio de fases tiene que ser circular: se suman los vectores $(cos theta_j, sin theta_j)$ y se toman el módulo y el ángulo de la suma. Promediar los ángulos directamente falla en el corte entre $2 pi$ y 0.

*Frecuencia común.* Como el acoplamiento es simétrico, al sumar todas las ecuaciones los senos se cancelan de a pares:

$ d/(d t) sum_i theta_i = sum_i omega_i quad => quad Omega = overline(omega) = 1/N sum_i omega_i $

Si el grupo se engancha, gira a la frecuencia media $Omega$. Desde ahí se trabaja con las desintonías $Delta_i = omega_i - overline(omega)$. Con retardo en el acoplamiento, esta propiedad deja de valer.

*Límite de infinitos osciladores.* Con frecuencias tomadas de una distribución $g(omega)$ unimodal y simétrica, aparece una transición en el acoplamiento crítico

$ K_c = 2/(pi g(0)) $

Para una distribución de Lorentz de ancho $gamma$, $K_c = 2 gamma$ y, por encima del umbral, $r = sqrt(1 - K_c\/K)$. Con pocos nodos este resultado queda solo como contexto, y $K_c$ se calcula como se muestra a continuación.

*Umbral exacto con $N$ finito.* En el marco que gira a $overline(omega)$, un estado enganchado cumple

$ Delta_i = u sin(theta_i - psi), quad u = K r $

Cada oscilador necesita $|Delta_i| <= u$ y queda con un desfasaje $theta_i - psi = arcsin(Delta_i\/u)$. Reemplazando en la @ec-orden, con todos los cosenos positivos, se obtiene la condición de autoconsistencia:

$ r = u/K = f(u) = 1/N sum_(i=1)^N sqrt(1 - (Delta_i/u)^2), quad u >= max_i |Delta_i| $ <ec-autoconsistencia>

El estado enganchado existe si $K$ alcanza el mínimo de $u\/f(u)$:

$ K_c = min_(u >= max_i |Delta_i|) u/f(u) $ <ec-kc-finito>

Con esto se calculan, para las frecuencias concretas de cada corrida, el umbral de enganche total, el $r$ final y el desfasaje de cada nodo. Con $N = 2$ se obtiene $K_c = |Delta omega|$.

*$N = 3$ simétrico.* Con frecuencias $overline(omega) - Delta$, $overline(omega)$ y $overline(omega) + Delta$, por simetría el oscilador central queda alineado con $psi$ y los otros dos a $plus.minus alpha$. La condición de equilibrio del oscilador rápido es

$ Delta = K/3 (sin alpha + sin 2 alpha) $

El máximo de $sin alpha + sin 2 alpha$ es aproximadamente 1,760, en $alpha approx$ 53,6°, de modo que $K_c approx$ 1,704 $Delta$. El oscilador central hace de puente entre los extremos.

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
