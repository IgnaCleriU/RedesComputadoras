== Mapeo tecnológico <sec-mapeo-tecnologico>

Los experimentos se realizaron sobre placas emuladas, una red simulada y un broker corriendo en la misma computadora que el emulador. Llevar el sistema a un despliegue real requiere reemplazar cada una de esas piezas por un equipo o un servicio que se pueda comprar o contratar. A continuación se analizan los costos que este paso implica para el escenario del Experimento 1 (@sec-exp-mqtt-https), con ocho nodos que envían una lectura cada 10 s, la misma frecuencia que se usó para proyectar el tráfico en la @tab-proyeccion. El criterio no es buscar la alternativa de mayor prestación, sino una solución viable que equilibre la calidad técnica, el plazo de implementación y el presupuesto. Los precios, a fin de generalizar, se expresan en dólares estadounidenses, son aproximados y corresponden a noviembre de 2026, sin impuestos ni costos de importación.

=== Nodos

Cada nodo se construye sobre el mismo microcontrolador que se emuló en los experimentos, el ESP32 de Espressif. Al tratarse del mismo chip, el firmware se compila sin cambios, salvo por la interfaz de red. La emulación conectaba cada nodo por Ethernet, mientras que el chip físico trae integrada un módulo Wi-Fi. El ESP32 se comercializa montado en placas de distintos fabricantes, y una placa de referencia como la ESP32-DevKitC, del propio Espressif, cuesta alrededor de USD 10 @espressif-devkitc.

Cuando el lugar de instalación no cuenta con una red Wi-Fi, el nodo necesita conectarse a la red celular. Para ese caso se considera la placa LilyGO T-A7670SA, que combina el mismo microcontrolador con un módem celular y cuesta alrededor de USD 28 @lilygo-a7670sa. El módem opera en LTE, el estándar de telefonía celular de cuarta generación, en su categoría 1, una variante de LTE pensada para dispositivos que transmiten a baja velocidad y que funciona sobre la red 4G común de los operadores. Existen variantes más eficientes en consumo, como LTE-M, pero su disponibilidad en Argentina no está confirmada para todos los operadores, por lo que la categoría 1 resulta la opción de menor riesgo.

=== Conectividad

Con Wi-Fi, el nodo aprovecha la red ya existente en el lugar y no agrega costo de conectividad. Como es el dispositivo el que abre la conexión hacia el broker, no necesita aceptar conexiones entrantes y funciona detrás del NAT y del firewall de esa red (@sec-nat-firewalls).

Con conectividad celular, en cambio, cada nodo requiere un plan de datos. Para aplicaciones industriales o de Internet de las Cosas no corresponden los planes de telefonía personal, sino los planes M2M (_machine to machine_), pensados para dispositivos. Los operadores locales no publican las tarifas de estos planes, pero los proveedores globales de tarjetas SIM para IoT sí lo hacen. Su precio depende principalmente del volumen de datos transferido, al que algunos suman un cargo fijo mensual por tarjeta.

En este punto, las mediciones del Experimento 1 se traducen directamente en dinero. El operador factura los bytes IP que atraviesan su red, con los encabezados de TCP y TLS incluidos, que son los que se midieron. Con MQTT sobre TLS, una lectura ocupa unos 140 B (@tab-costo), lo que equivale a unos 36 MB por mes en cada nodo. Con la tarifa de Hologram, por ejemplo, ese volumen cuesta alrededor de USD 2 por nodo y por mes @hologram-precios. Las decisiones analizadas en el experimento se reflejan entonces en la factura. Enviar el mismo contenido en JSON aumentaría ese volumen en alrededor de un 40 %, y usar HTTP con conexión reutilizada lo multiplicaría casi por cuatro. Este volumen es, de todos modos, un piso, porque en una red celular real se suman las reconexiones, cada una con un costo fijo de unos 3 KB entre los handshakes de TCP y TLS, el CONNECT y el cierre (@tab-costo), las consultas DNS y los mensajes de keep-alive.

Las redes LoRa, presentadas entre los casos de uso (@sec-caso-lora), son otra alternativa para zonas sin cobertura celular, pero cambian la arquitectura del nodo y quedan fuera de este relevamiento.

=== Broker

Para el broker se comparan dos alternativas. La primera es un servidor propio que ejecute Mosquitto, el mismo broker usado en los experimentos. Un servidor virtual privado (VPS), es decir, una máquina virtual alquilada a un proveedor de nube, de la menor capacidad disponible alcanza holgadamente para ocho nodos y cuesta alrededor de USD 5 por mes @aws-lightsail-precios, mientras que Mosquitto es software libre y no tiene costo de licencia. Conviene alojarlo en la región del proveedor más cercana a los dispositivos, que en este caso es São Paulo, porque así el trayecto atraviesa menos sistemas autónomos y queda menos expuesto a la convergencia de BGP (@sec-ruteo-externo).

La segunda alternativa es un servicio administrado, en el que el proveedor opera el broker y cobra según el uso. AWS IoT Core, por ejemplo, costaría alrededor de USD 2 por mes en este escenario, pero su forma de facturar contrasta con la del plan de datos. El servicio cobra por mensaje y mide cada uno en bloques de 5 KB @aws-iot-core-precios, de modo que una lectura de 18 B en Protocol Buffers cuesta lo mismo que una de 72 B en JSON. Con este tipo de tarifa, achicar el mensaje no reduce el costo, y lo único que lo reduce es enviar menos mensajes.

Se elige el servidor propio. A esta escala la diferencia de precio es mínima, y la decisión la definen el plazo y la continuidad con lo ya probado, ya que se trata del mismo broker y la misma configuración del experimento, sin necesidad de adaptar el sistema a un servicio distinto.

=== Costo del sistema

La @tab-mapeo resume los componentes relevados.

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header[Componente][Equipo o servicio][Precio aproximado],
    [Nodo con Wi-Fi], [Placa con ESP32 (por ejemplo, ESP32-DevKitC)], [USD 10],
    [Nodo celular], [Placa LilyGO T-A7670SA (ESP32 y módem LTE)], [USD 28],
    [Datos celulares], [Plan IoT de un proveedor global de SIM], [USD 2 por mes por nodo, más unos USD 3 por SIM],
    [Broker], [VPS en São Paulo con Mosquitto], [USD 5 por mes],
  ),
  caption: [Componentes del sistema y precios aproximados en dólares estadounidenses (noviembre de 2026, sin impuestos).],
) <tab-mapeo>

Con conectividad Wi-Fi, poner en marcha los ocho nodos requiere unos USD 80 en placas y USD 5 por mes para el broker. Con conectividad celular, la inversión inicial sube a unos USD 250 entre placas y tarjetas SIM, y el costo mensual a unos USD 21, de los cuales 16 corresponden a los datos. En ambos casos, el sistema estudiado puede implementarse con equipos de bajo costo y de amplia disponibilidad. La principal incertidumbre no es el precio sino la cobertura. Ninguno de los proveedores globales con tarifas públicas declara operar sobre la red de Personal, por lo que antes de un despliegue habría que verificar qué operador tiene señal en el lugar de instalación.

=== Escalabilidad

El escenario de ocho nodos es solo un caso de uso entre muchos posibles, y cada componente de la @tab-mapeo crece con una variable distinta.

- Las placas y las tarjetas SIM crecen con la cantidad de nodos y se pagan una sola vez.
- El cargo fijo mensual de las tarjetas crece con la cantidad de nodos.
- Los datos celulares crecen con la cantidad de nodos, la frecuencia de envío y el tamaño de cada lectura.
- El broker contratado crece con la cantidad de mensajes, sin importar su tamaño.
- El broker propio crece de a escalones, según el tamaño de servidor que exige la carga, y por transferencia solo cuando el tráfico supera el volumen incluido en el plan.

Según el caso de uso, el costo total queda dominado por uno u otro de estos componentes.

Cuando se supervisan variables que cambian lentamente, como una temperatura o el nivel de un tanque, basta con enviar una lectura por minuto o incluso menos. Un nodo celular con esa frecuencia transfiere unos 6 MB por mes y, con las tarifas relevadas, paga alrededor de USD 1,2, de los cuales USD 1 corresponde al cargo fijo de la tarjeta @hologram-precios. En este caso, reducir el tamaño de los mensajes casi no modifica la factura, y el costo lo definen el hardware y la cantidad de nodos.

La situación se invierte en una flota grande conectada por celular que envía datos con frecuencia, como la de mil nodos con una lectura cada 10 s considerada en la @tab-proyeccion. Los datos pasan a ser el componente principal, del orden de USD 2000 por mes para toda la flota, y cada decisión del stack se multiplica por la cantidad de nodos. Enviar JSON en lugar de Protocol Buffers aumentaría el volumen de datos de toda la flota en alrededor de un 40 %, y usar HTTP en lugar de MQTT lo multiplicaría casi por cuatro, con el consiguiente aumento de la parte del costo que depende del volumen. También cambia la elección del broker. Con esa carga, un servicio que cobra por mensaje costaría alrededor de USD 260 por mes. Un servidor propio también tiene costos que crecen con el uso, por el cómputo y la transferencia de datos, pero lo hacen de a escalones. El tráfico de toda la flota, de algunas decenas de gigabytes por mes, queda muy por debajo del volumen que incluyen incluso los planes más chicos, y aun un servidor varias veces más grande que el de la @tab-mapeo cuesta una fracción del servicio contratado. El servidor propio pasa a ser así la alternativa más económica, a pesar del trabajo que implica operarlo. A esta escala, de todos modos, los precios de lista pierden representatividad, porque los operadores negocian los planes M2M con descuentos por volumen, y las cifras deben leerse como órdenes de magnitud.

En un depósito con robots móviles (@sec-caso-robotica), el tráfico también es intenso, porque cada robot publica su posición y su estado de forma continua, pero viaja por la red Wi-Fi de la instalación, que no cobra por byte. El costo de comunicación se reduce al broker y resulta despreciable frente al valor de los robots. En este caso, la ventaja del stack no se mide en dinero, sino en la latencia y en el uso de la red.

La mensajería (@sec-caso-mensajeria) se ubica en el extremo opuesto. Los datos viajan por el plan de telefonía de cada usuario, que es quien paga el tramo celular, y el costo de la empresa se concentra en mantener conexiones persistentes con millones de dispositivos móviles. A esa escala, el broker deja de ser un producto que se contrata y pasa a desarrollarse a medida, como muestra la evolución de Messenger.

Estos casos muestran que el ahorro de bytes del stack se convierte en dinero solo cuando la conexión se cobra por volumen y la frecuencia de envío es alta. En los demás, la elección de MQTT y Protocol Buffers se justifica por la latencia y el uso de la red más que por el costo.
