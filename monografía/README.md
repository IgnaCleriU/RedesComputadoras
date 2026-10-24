# Monografía: MQTT y Protocol Buffers

El documento está en [Typst](https://typst.app/docs/) (0.15.x, ver `mise.toml` en la raíz del repo). Para commits y Pull Requests, ver el README de la raíz.

## Archivos

| Archivo | Qué es |
| --- | --- |
| `monografia.typ` | Documento principal: carátula, formato general, índice y orden de las secciones. |
| `secciones/*.typ` | Una sección por archivo (ver "Orden del documento"). |
| `bibliografia.bib` | Referencias en formato BibTeX (se muestran en estilo IEEE). |
| `assets/` | Logos e imágenes. |
| `WireGuardians-MONOGRAFÍA.pdf` | PDF compilado. |

## Orden del documento

Sigue la estructura habitual de una monografía (portada, índice, introducción, marco teórico, desarrollo, conclusiones, bibliografía y anexos). Entre paréntesis, el archivo de `secciones/` de cada parte:

1. Carátula (en `monografia.typ`): título, integrantes, docente, institución y fecha.
2. Índice (automático).
3. Introducción (`introduccion`, `objetivos`, `alcance`): contexto y problema, objetivos y alcance.
4. Marco teórico (`marco-teorico`): modelo pub/sub, MQTT, Protocol Buffers y alternativas.
5. Desarrollo (`desarrollo`, `experimentos`): análisis y diseño experimental.
6. Conclusiones (`conclusion`): responden a los objetivos; no agregan información nueva.
7. Bibliografía (automática, desde `bibliografia.bib`).
8. Anexos (`anexos`): material extenso que cortaría la lectura, como los `.proto` completos. Se numeran con letras.

## Compilar

Desde esta carpeta:

```bash
typst compile monografia.typ "WireGuardians-MONOGRAFÍA.pdf"
```

Para recompilar al guardar, usar `typst watch` con los mismos argumentos.

## Cómo escribir

Cada persona edita **su** archivo de `secciones/`, así se evitan conflictos al mergear. Las rutas dentro de un archivo de `secciones/` son relativas a ese archivo: una imagen de `assets/` se escribe `../assets/figura.png`.

- **Títulos:** `==` es una sección numerada (1., 2., ...) y `===` una subsección (1.1., 1.2., ...). Los capítulos (`=`) ya están creados y no se numeran. El índice se arma solo.
- **Figuras:** el epígrafe sale como "Figura 1: ...".

  ```typ
  #figure(
    image("../assets/figura.png", width: 70%),
    caption: [Descripción de la figura.],
  ) <fig-nombre>
  ```

  En el texto se cita con `@fig-nombre`.
- **Tablas:** `#figure(table(...), caption: [...]) <tab-nombre>`; se cita con `@tab-nombre`.
- **Ecuaciones:** `$ E = m c^2 $ <ec-nombre>`; se cita con `@ec-nombre`.
- **Citas:** agregar la entrada a `bibliografia.bib` (modelo en `tps/tp-teorico/tarea5/bibliografia.bib`) y citar con `@clave`; en el texto sale como "[1]" (estilo IEEE). La bibliografía lista todas las entradas del `.bib`.
- **Sección nueva:** crear el archivo en `secciones/` y agregarlo con `#include` en `monografia.typ`, en el lugar que corresponda.

## Requisito de la cátedra

El desarrollo tiene que incluir contenido de **ruteo** (Capítulo 5: Capa de Interred, direccionamiento y encaminamiento; RIP, EIGRP, OSPF, BGP) y de **capa de aplicación** (Capítulo 7: protocolos de capa de aplicación), siempre relacionado con el tema de la monografía. No hace falta cubrir todos los protocolos, pero sí desarrollar ambos temas.
