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

En el caso que el mesaje hubiese tenido errores en dos bits de filas y columnas distintas, habria cuatro posibles intersecciones en la matriz de tal forma que descubrir cuales de las cuatro son los dos bits erroneos no resulta simle. El receptor **detecta** que hubo errores, pero **no puede corregirlos**, porque no tiene forma de elegir. Si elige mal, invierte dos bits que estaban bien y el mensaje se acepta corrupto sin ningún aviso. Ante un síndrome con más de una fila o más de una columna, lo que corresponde es descartar el mensaje y esperar otra copia.

**Un bit de control dañado.** En el caso que se dañara el bit de control de una fila, falla esa fila y ninguna columna. Un error en un bit de datos, en cambio, siempre hace fallar una fila *y* una columna. Por eso, un síndrome de una sola fila, o de una sola columna, indica que el dañado es el bit de control y que los datos llegaron bien, de modo que no hay nada que corregir.

### 2)

> Si el mensaje es texto en castellano, muchas veces un error "se adivina" por contexto (Hola mondo). ¿Sirve eso para una contraseña, un número de cuenta o una dirección web? ¿Qué aporta el código frente a "leer y adivinar"?

No sirve. Adivinar por contexto funciona con texto en un idioma porque el lenguaje agrega redundancia, es decir, no cualquier secuencia de letras es una palabra ni cualquier secuencia de palabras es una frase, y esa redundancia permite notar que "mondo" no encaja y que podemos deducir que la palabra era "mundo".

Los tres ejemplos de la consigna no tienen esa redundancia:

- **Contraseña.** Se elige justamente para que cualquier combinación sea igual de probable. `x7Kq9#` y `x7Kq8#` difieren en un bit (`9` es `0111001` y `8` es `0111000`) y las dos son igual de creíbles, así que el error ni siquiera se nota: la autenticación falla y nada indica por qué.
- **Número de cuenta.** Todas las secuencias de dígitos se ven igual de válidas, y un dígito cambiado puede ser otra cuenta que existe, por lo que la transferencia le llegaría a un tercero. Por eso el CBU incluye dos dígitos verificadores, uno en cada bloque: es un código de detección agregado a propósito. Aun así, solo detecta: indica que el número es inválido, pero no cuál dígito está mal.
- **Dirección web.** La `o` (`1101111`) y la `g` (`1100111`) difieren en un bit, así que `google.com` puede llegar como `goggle.com`, que es otro dominio válido. Nada en el texto indica el error, y quien registre ese dominio recibe el tráfico. Ese ataque se conoce como _bitsquatting_ [3].

Lo que aporta el código es independizar la detección y la corrección del significado:

- **Funciona con cualquier dato.** Le da lo mismo si los bits son texto, una contraseña, un número o datos cifrados, que por diseño parecen aleatorios y no tienen ningún contexto.
- **Es automático.** Una placa de red o un router no pueden "leer y adivinar", pero sí aplicar una regla fija sobre los bits.
- **Tiene garantías.** La paridad bidimensional corrige cualquier error simple y detecta cualquier par de errores. Adivinar no garantiza nada.
- **No toca datos correctos.** El código ubica el bit que está mal, en lugar de modificar lo que "parece raro".

El costo es agregar redundancia de forma explícita y controlada (los bits de control), en lugar de depender de la que tenga, o no, el contenido.

### 3)

> ¿Pudieron confirmar que su corrección es correcta? ¿Cómo?

_Pendiente: completar con lo que pasó en el Desafío, que todavía no tiene la captura ni la carga útil. Abajo están los métodos para confirmar la corrección._

Hay varias comprobaciones posibles, de menor a mayor confianza:

1. **Recalcular las paridades después de corregir.** Si el síndrome queda vacío, la matriz es consistente. Es una condición necesaria, pero no suficiente: como se vio en la reflexión 1, con tres errores en tres esquinas de un rectángulo el receptor "corrige" la cuarta y todas las paridades cierran igual.
2. **Comprobar que el tamaño coincide con `SIZE`.** La carga útil tiene que tener filas × columnas bits de datos más filas + columnas bits de control. Esto descarta errores de interpretación del formato, no de transmisión.
3. **Comparar varias copias.** El transmisor reenvía el mensaje cada 30 segundos, y los errores no tienen por qué caer en los mismos bits. Si dos copias corregidas por separado coinciden bit a bit, es muy poco probable que las dos estén mal de la misma forma. Con tres copias se puede votar bit a bit por mayoría, incluso sin usar las paridades.
4. **Decodificar y seguir la instrucción.** Si el texto tiene sentido y la instrucción que contiene funciona, hay una confirmación de punta a punta. Pero, como advierte la consigna 6 y muestra la reflexión 2, un mensaje que se lee bien no es necesariamente correcto, así que esto complementa las comprobaciones anteriores y no las reemplaza.

### 4)

> Investigar y describir con el mayor detalle posible cómo funciona la técnica de corrección Hamming (7,4) y por qué es superior a la demostración didáctica que hicimos en este Laboratorio. Luego, aplicar la técnica sobre la carga útil obtenida en el desafío y elaborar un paquete de datos que podrían transmitir para que, en caso de corrupción, pueda ser recuperado.

#### Cómo funciona

El código de Hamming (7,4) [1] [4] transmite cada grupo de 4 bits de datos en un bloque de 7 bits, agregando 3 bits de paridad. Las posiciones del bloque se numeran del 1 al 7, y los bits de paridad ocupan las potencias de 2 (posiciones 1, 2 y 4), mientras que los de datos ocupan el resto (3, 5, 6 y 7). Cada bit de paridad cubre las posiciones que, escritas en binario, tienen encendido su bit:

| Posición     | 1 (`001`) | 2 (`010`) | 3 (`011`) | 4 (`100`) | 5 (`101`) | 6 (`110`) | 7 (`111`) |
| ------------ | :-------: | :-------: | :-------: | :-------: | :-------: | :-------: | :-------: |
| Contenido    | p1        | p2        | d1        | p4        | d2        | d3        | d4        |
| Cubierta por p1 | ✔      |           | ✔         |           | ✔         |           | ✔         |
| Cubierta por p2 |        | ✔         | ✔         |           |           | ✔         | ✔         |
| Cubierta por p4 |        |           |           | ✔         | ✔         | ✔         | ✔         |

Cada bit de paridad se elige, igual que en el laboratorio, para que la cantidad de unos de su grupo sea par.

**Codificación.** Para los datos `1011` (d1 = 1, d2 = 0, d3 = 1, d4 = 1):

- p1 = d1 ⊕ d2 ⊕ d4 = 1 ⊕ 0 ⊕ 1 = 0
- p2 = d1 ⊕ d3 ⊕ d4 = 1 ⊕ 1 ⊕ 1 = 1
- p4 = d2 ⊕ d3 ⊕ d4 = 0 ⊕ 1 ⊕ 1 = 0

El bloque transmitido es `0110011` (p1 p2 d1 p4 d2 d3 d4).

**Decodificación.** El receptor vuelve a verificar los tres grupos. Supongamos que llega `0110111`, con el bit 5 invertido:

- Grupo de p1 (posiciones 1, 3, 5, 7): 0, 1, 1, 1 → impar → c1 = 1
- Grupo de p2 (posiciones 2, 3, 6, 7): 1, 1, 1, 1 → par → c2 = 0
- Grupo de p4 (posiciones 4, 5, 6, 7): 0, 1, 1, 1 → impar → c4 = 1

El síndrome c4 c2 c1 = `101` = 5 es directamente la posición del bit erróneo, que se corrige invirtiéndolo. Un síndrome `000` indica que no hubo error. Funciona porque cada posición está cubierta por una combinación distinta de grupos, que es justamente su número en binario: un error en la posición *i* hace fallar exactamente los grupos de los bits encendidos en *i*. En forma matricial, el síndrome es s = H · rᵀ (mod 2), donde las columnas de H son los números del 1 al 7 en binario:

```text
     1 2 3 4 5 6 7
H = [0 0 0 1 1 1 1]   ← p4
    [0 1 1 0 0 1 1]   ← p2
    [1 0 1 0 1 0 1]   ← p1
```

Un error en la posición *i* da como síndrome la columna *i* de H. Una forma equivalente de calcularlo, que es la que usa `hamming.py`, es hacer el XOR de las posiciones que tienen un 1: para `0110111`, 2 ⊕ 3 ⊕ 5 ⊕ 6 ⊕ 7 = 5.

**Capacidad.** Dos bloques válidos cualesquiera difieren en al menos 3 bits (distancia mínima 3, que verificamos con los 16 bloques posibles). Por eso el código corrige un error por bloque, o bien detecta dos, pero no las dos cosas a la vez. Con dos errores el síndrome no es cero, pero apunta a una tercera posición, y si el receptor corrige, deja tres bits mal. Además, es un código *perfecto*: los 16 bloques válidos, cada uno con sus 7 vecinos a un bit de distancia, cubren exactamente las 2⁷ = 128 combinaciones de 7 bits (16 × 8 = 128). Todo bloque recibido está a lo sumo a un bit de un único bloque válido, así que no se desperdicia ningún síndrome. Si se agrega un octavo bit con la paridad de todo el bloque, se obtiene el Hamming extendido (8,4), que corrige un error y detecta dos al mismo tiempo (SECDED). Es la base de la memoria ECC, que protege cada palabra de 64 bits con 8 bits de control.

#### Por qué es superior a la demostración del laboratorio

La comparación no es a favor de Hamming en todo. Para la matriz de 10 × 5 del enunciado (50 bits de datos), la paridad bidimensional agrega menos bits:

| | Paridad bidimensional (10 × 5) | Hamming (7,4) |
| --- | --- | --- |
| Bits transmitidos | 65 (50 + 15 de control) | 91 (13 bloques; 2 bits de relleno) |
| Bits de control por bit de datos | 0,30 | 0,75 (más el relleno) |
| Errores que corrige | 1 en todo el mensaje | 1 por bloque, hasta 13 si caen en bloques distintos |
| Ubicación del error | Cruzando fila y columna, con la matriz completa | El síndrome es la posición, bloque por bloque |
| Error en un bit de control | Caso aparte, deducido | Se ubica y se corrige como cualquier otro |
| Probabilidad de no recuperar el mensaje, con 1 bit de cada 1000 erróneo | 0,2 % | 0,03 % |
| Ídem, con 1 bit de cada 100 erróneo | 13,8 % | 2,6 % |

Las probabilidades suponen errores independientes. Para la paridad bidimensional, el mensaje no se recupera si hay 2 o más errores en los 65 bits; para Hamming, si algún bloque tiene 2 o más.

Hamming es superior en lo que importa para corregir:

1. **Capacidad de corrección.** La paridad bidimensional corrige un solo error en todo el mensaje, y con dos ya falla (reflexión 1). Hamming corrige uno por cada bloque de 7 bits, así que su capacidad crece con el largo del mensaje. Con 1 bit erróneo cada 100, la probabilidad de no recuperar el mensaje baja de 13,8 % a 2,6 %.
2. **Ubicación directa.** No hay que armar la matriz ni cruzar filas con columnas: el síndrome de 3 bits *es* la posición del error. Además, cada bloque se decodifica apenas llega, sin esperar al resto del mensaje.
3. **Trato uniforme.** Un error en un bit de paridad se ubica y se corrige igual que uno de datos. No hay casos especiales como el de la reflexión 1, donde un error de control combinado con uno de datos se acepta sin aviso.
4. **Es óptimo y escalable.** Por ser perfecto, ningún código con 3 bits de control protege más de 4 bits de datos contra un error. La misma construcción da Hamming (15,11) o (31,26), con mucha menos sobrecarga, y su versión extendida se usa en la práctica.

Su límite son las ráfagas: dos errores seguidos en el mismo bloque lo engañan. Si eso preocupa, se puede entrelazar: transmitir primero el bit 1 de todos los bloques, después el bit 2, y así sucesivamente, de modo que una ráfaga se reparta entre bloques distintos y quede un solo error en cada uno.

#### Aplicación y paquete de datos

_Pendiente: el Desafío todavía no tiene la carga útil. Mientras tanto, aplicamos la técnica sobre `mensaje.txt`, el archivo de ejemplo de la cátedra ("Hola mundo!"). Cuando esté la carga útil corregida, basta con guardarla en el mismo formato y repetir los comandos._

El script [`hamming.py`](hamming.py) toma los bits de datos ya corregidos, sin los bits de control de la paridad bidimensional, los separa en grupos de 4 (con relleno de ceros al final si hace falta) y codifica cada grupo en un bloque de 7 bits. Con eso arma un paquete con el mismo estilo JSON que el del Desafío:

```bash
python hamming.py codificar mensaje.txt > paquete.json
```

```json
{"SIZE": "4,28", "CODE": "HAMMING(7,4)", "DATA": "0011001110100101100111111111110011011001101101001100110011010010110011000111110110100010110001011001111000011001011001110101010000000101101000000001001100000000011100001101001000000001010100000000"}
```

- `SIZE`: filas y columnas de los datos originales, para reconstruir las filas y descartar el relleno.
- `CODE`: el código usado, para que el receptor sepa cómo interpretar `DATA`.
- `DATA`: los bloques de 7 bits, uno detrás de otro. Son 112 bits de datos convertidos en 28 bloques (196 bits).

El receptor corrige y reconstruye el mensaje. Si se invierte el bit 5 del bloque 6:

```text
$ python hamming.py decodificar paquete_dañado.json > recuperado.txt
bloque 6: error en la posición 5, corregido
```

`recuperado.txt` es idéntico a `mensaje.txt`, y `decodificar_mensaje.py` vuelve a mostrar "Hola mundo!". El modo `demo` daña el paquete de forma controlada:

```text
$ python hamming.py demo mensaje.txt
Datos: 112 bits -> 28 bloques, 196 bits transmitidos

1 error por bloque (28 errores): 28 corregidos, recuperado OK
2 errores en el bloque 1 (posiciones 1 y 3): síndrome 2, recuperado MAL: corrige el bit equivocado
```

Con un error en cada uno de los 28 bloques (28 errores en total), el mensaje se recupera completo, algo imposible con la paridad bidimensional, que no corrige más de uno. El segundo caso muestra el límite: con dos errores en el mismo bloque, el síndrome (1 ⊕ 3 = 2) apunta a una posición sana.

Como en el laboratorio, `DATA` usa caracteres `0` y `1`, por lo que cada bit ocupa un byte. En una implementación real los bloques se empaquetarían bit a bit, y los 196 bits ocuparían 25 bytes.

## Referencias

1. R. W. Hamming, "Error detecting and error correcting codes", _Bell System Technical Journal_, vol. 29, n.º 2, pp. 147–160, 1950.
2. C. E. Shannon, "A Mathematical Theory of Communication", _Bell System Technical Journal_, vol. 27, pp. 379–423 y 623–656, 1948.
3. A. Dinaburg, "Bitsquatting: DNS Hijacking without Exploitation", Black Hat USA, 2011.
4. A. S. Tanenbaum y D. J. Wetherall, _Computer Networks_, 5.ª ed., Pearson, 2011, sec. 3.2.1, pp. 204–210.
