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

### 4)

> Investigar y describir con el mayor detalle posible cómo funciona la técnica de corrección Hamming (7,4) y por qué es superior a la demostración didáctica que hicimos en este Laboratorio. Luego, aplicar la técnica sobre la carga útil obtenida en el desafío y elaborar un paquete de datos que podrían transmitir para que, en caso de corrupción, pueda ser recuperado.

#### Cómo funciona

El código de Hamming (7,4) transmite cada grupo de 4 bits de datos en un bloque de 7 bits, agregando 3 bits de paridad. Las posiciones del bloque se numeran del 1 al 7, y los bits de paridad ocupan las potencias de 2 (posiciones 1, 2 y 4), mientras que los de datos ocupan el resto (3, 5, 6 y 7). Cada bit de paridad cubre las posiciones que, escritas en binario, tienen encendido su bit:

| Posición     | 1 (`001`) | 2 (`010`) | 3 (`011`) | 4 (`100`) | 5 (`101`) | 6 (`110`) | 7 (`111`) |
| ------------ | :-------: | :-------: | :-------: | :-------: | :-------: | :-------: | :-------: |
| Contenido    | p1        | p2        | d1        | p4        | d2        | d3        | d4        |
| Cubierta por p1 | ✔      |           | ✔         |           | ✔         |           | ✔         |
| Cubierta por p2 |        | ✔         | ✔         |           |           | ✔         | ✔         |
| Cubierta por p4 |        |           |           | ✔         | ✔         | ✔         | ✔         |

Cada bit de paridad se elige, igual que con el método utilizado en el laboratorio, para que la cantidad de unos de su grupo sea par.

**Codificación.** Para los datos `1011` (d1 = 1, d2 = 0, d3 = 1, d4 = 1):

- p1 = d1 ⊕ d2 ⊕ d4 = 1 ⊕ 0 ⊕ 1 = 0
- p2 = d1 ⊕ d3 ⊕ d4 = 1 ⊕ 1 ⊕ 1 = 1
- p4 = d2 ⊕ d3 ⊕ d4 = 0 ⊕ 1 ⊕ 1 = 0

El bloque transmitido es `0110011` (p1 p2 d1 p4 d2 d3 d4).

**Decodificación.** El receptor vuelve a verificar los tres grupos. Supongamos que llega `0110111`, con el bit 5 invertido:

- Grupo de p1 (posiciones 1, 3, 5, 7): 0, 1, 1, 1 → impar → c1 = 1
- Grupo de p2 (posiciones 2, 3, 6, 7): 1, 1, 1, 1 → par → c2 = 0
- Grupo de p4 (posiciones 4, 5, 6, 7): 0, 1, 1, 1 → impar → c4 = 1

El síndrome c4 c2 c1 = `101` = 5 es directamente la posición del bit erróneo, que se corrige invirtiéndolo. Un síndrome `000` indica que no hubo error. Funciona porque cada posición está cubierta por una combinación distinta de grupos, que es justamente su número en binario.

#### Por qué es superior a la demostración del laboratorio

La comparación es a favor de Hamming(7,4) en todo, lo cual tiene sentido teniendo en cuenta que contiene mas redundacia qua la paridad bidimensional.
Aqui la comparacion con 50 bits de datos:

| | Paridad bidimensional | Hamming (7,4) |
| --- | --- | --- |
| Bits transmitidos | 65 (50 + 15 de control) | 91 (13 bloques de 4 bits de datos + 2 bits de relleno) |
| Bits de control por bit de datos | 0,30 | 0,75 (más el relleno) |
| Errores que corrige | 1 en todo el mensaje | 1 por bloque, hasta 13 si caen en bloques distintos |
| Ubicación del error | Cruzando fila y columna, con la matriz completa | El síndrome es la posición, bloque por bloque |
| Error en un bit de control | Caso aparte, deducido | Se ubica y se corrige como cualquier otro |
| Probabilidad de no recuperar el mensaje, con 1 bit de cada 1000 erróneo | 0,2 % | 0,03 % |
| Ídem, con 1 bit de cada 100 erróneo | 13,8 % | 2,6 % |

Las probabilidades suponen errores independientes. Para la paridad bidimensional, el mensaje no se recupera si hay 2 o más errores en los 65 bits; para Hamming, si algún bloque tiene 2 o más.

Hamming es superior en lo que importa para corregir:

1. **Capacidad de corrección.** La paridad bidimensional corrige un solo error en todo el mensaje, y con dos ya falla (reflexión 1). Hamming corrige uno por cada bloque de 7 bits, así que su capacidad crece con el largo del mensaje. Con 1 bit erróneo cada 100, la probabilidad de no recuperar el mensaje baja de 13,8 % a 2,6 %.
2. **Ubicación directa.** No hay que armar la matriz ni cruzar filas con columnas ya que el síndrome de 3 bits *es* la posición del error. Además, cada bloque se decodifica apenas llega, sin esperar al resto del mensaje.
3. **Trato uniforme.** Un error en un bit de paridad se ubica y se corrige igual que uno de datos. No hay casos especiales como el de la reflexión 1, donde un error de control combinado con uno de datos se acepta sin aviso.
4. **Es óptimo y escalable.** Por ser perfecto, ningún código con 3 bits de control protege más de 4 bits de datos contra un error. La misma construcción da Hamming (15,11) o (31,26), con mucha menos sobrecarga, y su versión extendida se usa en la práctica.

Su límite son las ráfagas: dos errores seguidos en el mismo bloque lo engañan. Si eso preocupa, se puede entrelazar: transmitir primero el bit 1 de todos los bloques, después el bit 2, y así sucesivamente, de modo que una ráfaga se reparta entre bloques distintos y quede un solo error en cada uno.

#### Aplicación y paquete de datos

Tenemos una captura del desafio, esta no contiene el link ganador pero va a fucionar lo mismo:

```json
{"SIZE": "99,9", "PL": "https://www.youtube.com/watch?v=msX4oAXpvUE", "CHECK": "https://www.youtube.com/shorts/nw7pN6XW9e4"}
```

**Como carga útil vamos a usar solo el primer enlace**, el del campo `PL`:

```text
https://www.youtube.com/watch?v=msX4oAXpvUE
```

Para proteger la carga útil, cada byte se divide en dos mitades de 4 bits y cada mitad se codifica en un bloque de Hamming (7,4). Se usan los 8 bits de cada byte, tal como viajan en el datagrama, y no los 7 del laboratorio, para que el método sirva con cualquier contenido y no solo con texto ASCII. Como cada byte da exactamente dos bloques, no hace falta relleno: los 43 bytes del enlace (344 bits) se convierten en 86 bloques (602 bits).

El paquete completo, resulta:

```json
{"SIZE": "43", "CODE": "HAMMING(7,4)", "PL": "11001101110000000111110011000001111100110000011110000000000111110000111000011101101001010101111111010101011111110001111000111100011110001111000111100011110101010001011000011110011001110011011111110001111010010100011111001100000111101001011100110010101011001100100101010101000101101100110100001111001101111111110011010101010101010111111100011110001111110011011010010001111100110011001101000011110011011100001000011111111100011111100110100001110101011100110101010100011111000011010010111100001000011100110011001101111111100110011010010100101111000000011110000000000111111001100100101010010110011000100101"}
```

El siguiente script arma el paquete y lo pone a prueba. Para correrlo, hay que guardarlo como `hamming.py` y ejecutar `python hamming.py`.

```python
#!/usr/bin/env python3
import json
import random

CARGA_UTIL = "https://www.youtube.com/watch?v=msX4oAXpvUE"

POS_DATOS = (3, 5, 6, 7)  # posiciones (de 1 a 7) de d1, d2, d3 y d4
POS_PARIDAD = (1, 2, 4)   # posiciones de p1, p2 y p4


def invertir(bits, i):
    """Invierte el bit de índice i (desde 0) de una cadena de "0" y "1"."""
    return bits[:i] + ("1" if bits[i] == "0" else "0") + bits[i + 1:]


def codificar_bloque(datos):
    """4 bits de datos -> bloque de 7 bits (p1 p2 d1 p4 d2 d3 d4)."""
    bloque = [0] * 8  # el índice 0 no se usa, para trabajar con posiciones 1 a 7
    for pos, bit in zip(POS_DATOS, datos):
        bloque[pos] = int(bit)
    for p in POS_PARIDAD:
        # p cubre las posiciones que tienen encendido el bit p en su número
        bloque[p] = sum(bloque[i] for i in range(1, 8) if i & p and i != p) % 2
    return "".join(str(b) for b in bloque[1:])


def sindrome(bloque):
    """XOR de las posiciones que tienen un 1: 0 si no hay error, o la posición errónea."""
    s = 0
    for pos, bit in enumerate(bloque, start=1):
        if bit == "1":
            s ^= pos
    return s


def decodificar_bloque(bloque):
    """Bloque de 7 bits -> (4 bits de datos, posición corregida o 0)."""
    s = sindrome(bloque)
    if s:
        bloque = invertir(bloque, s - 1)
    return "".join(bloque[p - 1] for p in POS_DATOS), s


def codificar(texto):
    """Texto -> paquete. Cada byte da dos bloques, uno por cada mitad de 4 bits."""
    datos = texto.encode("utf-8")
    bits = "".join(f"{b:08b}" for b in datos)
    pl = "".join(codificar_bloque(bits[k:k + 4]) for k in range(0, len(bits), 4))
    return {"SIZE": str(len(datos)), "CODE": "HAMMING(7,4)", "PL": pl}


def decodificar(paquete):
    """Paquete -> (texto, lista de (bloque, posición) corregidos)."""
    pl = paquete["PL"]
    if len(pl) != 14 * int(paquete["SIZE"]):
        raise ValueError("el largo de PL no coincide con SIZE: se perdieron o sobran bits")
    bits, correcciones = "", []
    for k in range(0, len(pl), 7):
        datos, pos = decodificar_bloque(pl[k:k + 7])
        bits += datos
        if pos:
            correcciones.append((k // 7 + 1, pos))
    datos = bytes(int(bits[k:k + 8], 2) for k in range(0, len(bits), 8))
    return datos.decode("utf-8", errors="replace"), correcciones


if __name__ == "__main__":
    paquete = codificar(CARGA_UTIL)
    n = len(paquete["PL"]) // 7
    print(f"Carga útil: {paquete['SIZE']} bytes -> {n} bloques, {len(paquete['PL'])} bits")
    print(json.dumps(paquete))

    # Prueba 1: un error en cada bloque, en una posición al azar (semilla fija).
    rng = random.Random(7)
    pl = paquete["PL"]
    for b in range(n):
        pl = invertir(pl, 7 * b + rng.randrange(7))
    texto, corr = decodificar({**paquete, "PL": pl})
    print(f"\n1 error en cada bloque ({n} errores): {len(corr)} corregidos,",
          "recuperado OK" if texto == CARGA_UTIL else "recuperado MAL")

    # Prueba 2: dos errores en un mismo bloque, en las posiciones 1 y 2 del
    # bloque que lleva la segunda mitad de la "m" de "v=msX4oAXpvUE".
    b = 2 * CARGA_UTIL.index("v=m") + 5  # índice (desde 0) de ese bloque
    pl = invertir(invertir(paquete["PL"], 7 * b), 7 * b + 1)
    texto, corr = decodificar({**paquete, "PL": pl})
    print(f"2 errores en el bloque {b + 1} (posiciones 1 y 2): síndrome {corr[0][1]},",
          "recuperado OK" if texto == CARGA_UTIL else "recuperado MAL")
    print("Recuperado:", texto)
```

- `codificar_bloque` ubica los 4 bits de datos en las posiciones 3, 5, 6 y 7 y calcula cada paridad sobre las posiciones que cubre, igual que en la tabla de arriba.
- `sindrome` hace el XOR de las posiciones que tienen un 1. En un bloque correcto da 0, y con un bit invertido da su posición, que `decodificar_bloque` vuelve a invertir.
- `codificar` y `decodificar` pasan de la carga útil al paquete y del paquete a la carga útil, bloque por bloque.

La salida, con el paquete recortado:

```text
$ python hamming.py
Carga útil: 43 bytes -> 86 bloques, 602 bits
{"SIZE": "43", "CODE": "HAMMING(7,4)", "PL": "11001101110000…"}

1 error en cada bloque (86 errores): 86 corregidos, recuperado OK
2 errores en el bloque 66 (posiciones 1 y 2): síndrome 3, recuperado MAL
Recuperado: https://www.youtube.com/watch?v=esX4oAXpvUE
```

- **Prueba 1.** Con un error en cada uno de los 86 bloques (86 bits invertidos, uno de cada 7), el enlace se recupera completo.

- **Prueba 2.** Con dos errores en el mismo bloque, en las posiciones 1 y 2, dan síndrome 1 ⊕ 2 = 3, y el receptor invierte el bit 3, que no era un bit erroneo.
