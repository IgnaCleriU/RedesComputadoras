### Transmisión en Banda Base vs Banda Ancha

**Banda Base (Baseband)**

En banda base, la señal digital se transmite directamente sobre el medio (cable) sin modulación, usando **toda la capacidad del canal** para una sola señal a la vez.

- **Cómo funciona**: los datos digitales (1s y 0s) se representan directamente como pulsos eléctricos u ópticos (por ejemplo, voltaje alto = 1, voltaje bajo = 0). No hay conversión a una señal analógica modulada.
- **Un solo canal**: solo se puede transmitir una señal por vez en todo el ancho de banda disponible.
- **Bidireccional**: la comunicación puede ser en ambos sentidos usando el mismo canal (generalmente half-duplex o requiere separación temporal).
- **Alcance**: señales limitadas en distancia, ya que se degradan (atenúan) más rápido; suelen necesitar repetidores.
- **Ejemplos**: Ethernet (10BASE-T, 100BASE-TX, etc.), USB, la mayoría de las LAN.

**Banda Ancha (Broadband)**

En banda ancha, la señal digital se **modula** sobre una o varias ondas portadoras analógicas, permitiendo que múltiples señales viajen simultáneamente por el mismo medio usando distintas frecuencias.

- **Cómo funciona**: se usa una técnica como FDM (multiplexación por división de frecuencia) para dividir el ancho de banda del canal en múltiples subcanales, cada uno con su propia frecuencia portadora. Los datos se modulan (AM, FM, QAM, etc.) antes de enviarse.
- **Múltiples canales**: varias señales (datos, voz, video) pueden coexistir en el mismo cable simultáneamente.
- **Unidireccional por canal**: cada canal transmite en una sola dirección, pero al haber múltiples canales, se logra comunicación bidireccional simultánea.
- **Alcance**: mayor distancia sin degradación significativa, gracias a amplificadores analógicos.
- **Ejemplos**: televisión por cable, DSL, redes de cable módem (DOCSIS), sistemas de telecomunicaciones tradicionales.


Básicamente cada frecuencia portadora es un canal y a esta se la modula para enviar 1 y 0 (tiene mas amplitud cuando es 1, y menos cuando es 0).


### Código Manchester 
El código Manchester es un método de codificación digital donde cada bit de datos tiene una transición de voltaje en su mitad. Un bit '0' se representa por una subida (bajo a alto) y un bit '1' por una bajada (alto a bajo), permitiendo que la señal se sincronice sola.

Cómo funciona el código Manchester

- Cada bit dura un tiempo fijo.

- Hay un cambio seguro de voltaje justo en medio de cada bit.

- El reloj de la máquina viaja junto con los datos.

- No pasa corriente continua por la línea.

Reglas de los bits

- **Cero (0):** Sube de voltaje de bajo a alto en el centro.

- **Uno (1):** Baja de voltaje de alto a bajo en el centro.



### **Perturbaciones en la transmisión**

- **Atenuación**: la señal pierde energía con la distancia, por lo que debe llegar con suficiente potencia para ser detectada. Como la atenuación afecta más a las frecuencias altas, las señales analógicas se distorsionan y se necesitan amplificadores/repetidores para compensarlo.
- **Distorsión de retardo**: como la velocidad de propagación varía según la frecuencia, distintas componentes de la señal llegan en momentos diferentes, deformándola. Se corrige con **ecualización**.
- **Ruido**: cualquier señal no deseada que se mezcla con la señal original. Tipos principales:
    - **Térmico**: por agitación de electrones en el conductor.
    - **Intermodulación**: cuando varias frecuencias comparten el medio.
    - **Diafonía**: por acoplamiento entre líneas cercanas.
    - **Impulsivo**: pulsos breves y de gran amplitud.