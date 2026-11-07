# Trabajo Práctico N° 7 — Informe

**Grupo:** WireGuardians

**Integrantes del Grupo:**

| Name                            | DNI      | Mail UNC                          | Github                                                             |
| ------------------------------- | -------- | --------------------------------- | ------------------------------------------------------------------ |
| Viberti, Benjamin               | 46224179 | b.viberti@mi.unc.edu.ar           | [@benjaviberti](https://github.com/benjaviberti)                   |
| Espinoza Sutta, Aaron Alejandro | 96009173 | aaron.espinoza_4500@mi.unc.edu.ar | [@Aaron45000](https://github.com/Aaron45000)                       |
| Cleri, Juan Ignacio             | 46452662 | ignacio.cleri@mi.unc.edu.ar       | [@IgnaCleri](https://github.com/IgnaCleri)                         |
| Pineda, Juan Ignacio            | 45591343 | juan.ignacio.pineda@mi.unc.edu.ar | [@juanignaciopineda-dot](https://github.com/juanignaciopineda-dot) |
| Grafión, Atilio Leonel          | 43940195 | atilio.grafion@mi.unc.edu.ar      | [@Aollgn](https://github.com/Aollgn)                               |
| Badenes, Tomás                  | 44785038 | tomasbadenes@mi.unc.edu.ar        | [@b-Tomas](https://github.com/b-Tomas)                             |
| Oviedo, Ignacio Nicolas         | 43940195 | ignacio.oviedo.239@mi.unc.edu.ar  | [@GIX02](https://github.com/GIX02)                                 |
| Mendez, Jorge Nicolas           | 41301342 | jorge.mendez@mi.unc.edu.ar        | [@jorge088](https://github.com/jorge088)                           |

## Desafío

> Conéctense a la red del laboratorio, utilizando DHCP. La computadora transmisora envía el mensaje a todos los equipos de la red (difusión) aproximadamente cada 30 segundos. No sabemos de antemano qué protocolo de transporte, qué puerto ni qué IP de origen usa: descubrirlo es parte del TP. Si los podemos ayudar diciéndoles que la carga útil tiene un formato de tipo JSON:
>
> ```text
> {"SIZE": "10,5", ????????????????? }
> ```
>
> Dónde SIZE indica el tamaño de la matriz en formato FILAS, COLUMNAS

### 1) Configuración de red

> Averigüen su IP y su máscara (ipconfig / ip addr) y calculen la dirección de broadcast de la red. ¿Cuál es la dirección MAC de broadcast?

| Parámetro               | Valor |
| ----------------------- | ----- |
| Interfaz                |       |
| Dirección IPv4          |       |
| Máscara                 |       |
| Dirección de broadcast  |       |
| Dirección MAC broadcast |       |

### 2) Captura

> Abran Wireshark en la interfaz Wi-Fi y capturen al menos 2 minutos. Pueden llegar varios mensajes; no tienen porqué ser todos idénticos.

| Parámetro            | Valor |
| -------------------- | ----- |
| IP origen            |       |
| MAC origen           |       |
| IP destino           |       |
| Protocolo transporte |       |
| Puerto origen        |       |
| Puerto destino       |       |
| Mensajes distintos   |       |

### 3) Estructura del mensaje

> Analicen la estructura del mensaje. ¿Qué formato tiene? ¿Qué campos contiene y qué creen que representa cada uno? Con lo visto en la sección 1, propongan cómo hay que interpretar los datos.

### 4) Verificación de integridad

> Verifiquen la integridad del mensaje con el código de la sección 1: recalculen las paridades y compárenlas con las recibidas. Registren qué filas y qué columnas fallan (el síndrome).

### 5) Corrección de errores

> Si hay errores, ubíquenlos y corríjanlos. Para cada bit corregido indiquen fila, columna, valor recibido y valor corregido. Si recibieron más de un mensaje distinto, analicen cada uno por separado.

| Mensaje | Fila | Columna | Valor recibido | Valor corregido |
| ------- | ---- | ------- | -------------- | --------------- |
|         |      |         |                |                 |

### 6) Decodificación

> Construyan un archivo de texto en el formato de mensaje.txt con los datos ya corregidos y decodifíquenlo con decodificar_mensaje.py (o el cuaderno). Si todo salió bien, el mensaje les va a indicar cómo seguir. Ojo: un mensaje que "se lee bien" no es necesariamente un mensaje correcto.

### 7) (Opcional) Comparación de paridades

> paridad.py calcula las paridades, pero no las compara con las recibidas.

## Reflexiones e investigación

### 1)

> ¿Qué hubiera pasado si el mensaje tenía errores en dos bits de filas y columnas distintas? ¿Y si se dañaba un bit de los de control?

En el caso que el mesaje hubiese tenido errores en dos bits de filas y columnas distintas, habria cuatro posibles intersecciones en la matriz de tal 
forma que descubrir cuales de las cuatro son los dos bits erroneos no resulta simle. El receptor **detecta** que hubo errores, pero **no puede 
corregirlos**, porque no tiene forma de elegir. Si elige mal, invierte dos bits que estaban bien y el mensaje se acepta corrupto sin ningún aviso. Ante 
un síndrome con más de una fila o más de una columna, lo que corresponde es descartar el mensaje y esperar otra copia.

**Un bit de control dañado.** En el caso que se dañara el bit de control de una fila, falla esa fila y ninguna columna. Un error en un bit de datos, en 
cambio, siempre hace fallar una fila *y* una columna. Por eso, un síndrome de una sola fila, o de una sola columna, indica que el dañado es el bit de 
control y que los datos llegaron bien, de modo que no hay nada que corregir.

### 2)

> Si el mensaje es texto en castellano, muchas veces un error "se adivina" por contexto (Hola mondo). ¿Sirve eso para una contraseña, un número de cuenta o una dirección web? ¿Qué aporta el código frente a "leer y adivinar"?

No sirve. Adivinar por contexto funciona con texto en un idioma porque el lenguaje agrega redundancia, es decir, no cualquier secuencia de letras es una palabra ni cualquier secuencia de palabras es una frase, y esa redundancia permite notar que "mondo" no encaja y que podemos deducir que la palabra era "mundo". Pero para otros casos, decidir segun el contexto linguistico no tiene sentido:

- Para el caso de las contraseñas, estas se eligen justamente para que cualquier combinación sea igual de probable. `x7Kq9#` y `x7Kq8#` difieren en un bit y las dos son igual de creíbles, así que el error ni siquiera se nota.

-Para un numero de cuenta es incluaso peor, ya que todas las secuencias de dígitos se ven igual de válidas, y un dígito cambiado puede ser otra cuenta que existe, por lo que la transferencia le llegaría a un tercero.
- Una direccion web por otra parte, simplemente rsultaria en otro dominio, por ejemplo: la `o` (`1101111`) y la `g` (`1100111`) difieren en un bit, así que `google.com` puede llegar como `goggle.com`, que es otro dominio válido. Nada en el texto indica el error, y quien registre ese dominio recibe el tráfico.
 es agregar redundancia de forma explícita y controlada (los bits de control), en lugar de depender de la que tenga, o no, el contenido.

### 3)

> ¿Pudieron confirmar que su corrección es correcta? ¿Cómo?

### 4)

> Investigar y describir con el mayor detalle posible cómo funciona la técnica de corrección Hamming (7,4) y por qué es superior a la demostración didáctica que hicimos en este Laboratorio. Luego, aplicar la técnica sobre la carga útil obtenida en el desafío y elaborar un paquete de datos que podrían transmitir para que, en caso de corrupción, pueda ser recuperado.
