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

### 2)

> Si el mensaje es texto en castellano, muchas veces un error "se adivina" por contexto (Hola mondo). ¿Sirve eso para una contraseña, un número de cuenta o una dirección web? ¿Qué aporta el código frente a "leer y adivinar"?

### 3)

> ¿Pudieron confirmar que su corrección es correcta? ¿Cómo?

Sí. Lo confirmamos en dos pasos:

- Primero, que la matriz corregida fuera consistente con los bits de control.
- Después, que el mensaje decodificado funcionara. La prueba definitiva fue que el enlace del mensaje llevaba al video del premio.

**Detección y corrección con un script.** Para la detección y la corrección usamos un script de Python que recalcula la paridad de cada fila y de cada columna y la compara con los bits de control recibidos. Las filas y columnas que no coinciden forman el síndrome, y el bit erróneo está en el cruce de la fila y la columna que fallan, así que el script lo invierte. Así se evitan los errores de contar unos y ceros a mano en una matriz con tantos bits, y el resultado es reproducible.

Después de corregir, que todas las paridades coincidan es una condición necesaria, pero no suficiente. Como vimos en la reflexión 1, si el receptor elige mal ante dos errores, invierte bits que estaban bien y aun así todas las paridades cierran. El código, por sí solo, no puede distinguir ese caso de una corrección correcta.

Por eso no nos quedamos con la salida del script de Python como mensaje final: verificamos que la instrucción funcionara. El mensaje decodificado tenía un enlace y, al abrirlo, llegamos al video del premio. Es una prueba mucho más fuerte de lo que parece, por lo que vimos en la reflexión 2. Si un solo bit del enlace hubiera quedado mal, apuntaría a otro video, a otro dominio o a ningún lado. En un enlace de YouTube, como los del mensaje, el identificador del video tiene 11 caracteres de 64 posibles cada uno, es decir 64¹¹ ≈ 7,4 × 10¹⁹ combinaciones. Que una corrección equivocada diera por casualidad justo el identificador del video del premio es, en la práctica, imposible.

Las dos comprobaciones son independientes, ya que una mira los bits y la otra el significado del mensaje, y las dos dieron bien. Si el enlace no hubiera funcionado, el paso siguiente habría sido comparar varias copias del mensaje, que el transmisor reenvía cada 30 segundos.

### 4)

> Investigar y describir con el mayor detalle posible cómo funciona la técnica de corrección Hamming (7,4) y por qué es superior a la demostración didáctica que hicimos en este Laboratorio. Luego, aplicar la técnica sobre la carga útil obtenida en el desafío y elaborar un paquete de datos que podrían transmitir para que, en caso de corrupción, pueda ser recuperado.
