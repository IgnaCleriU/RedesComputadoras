# WireGuardians

**Redes de Computadoras — Ingeniería en Computación — FCEFyN — UNC— 2026**

## Trabajos Prácticos

| Informe                                               | Enunciado                                           |
| ----------------------------------------------------- | --------------------------------------------------- |
| [TP1 — Práctico](tps/practico/TP1/informe-tp-1.md)    | [RC - TP N1.pdf](<tps/practico/TP1/RC - TP N1.pdf>) |
| [TP2 — Práctico](tps/practico/TP2/InformeTP2.md)      | [RC - TP N2.pdf](<tps/practico/TP2/RC - TP N2.pdf>) |
| [TP3 — Práctico](tps/practico/TP3/InformeTP3.pdf)     | [RC - TP N3.pdf](<tps/practico/TP3/RC - TP N3.pdf>) |
| [TP4 — Práctico](tps/practico/TP4/InformeTP4.md)      | [RC - TP N4.pdf](<tps/practico/TP4/RC - TP N4.pdf>) |
| [TP5 — Práctico](tps/practico/TP5/InformeTP5.md)      | [RC - TP N5.pdf](<tps/practico/TP5/RC - TP N5.pdf>) |
| [TP6 — Práctico](tps/practico/TP6/main.pdf)           | [RC - TP N6.pdf](<tps/practico/TP6/Consigna/RC - TP N6.pdf>) |
| [TP7 — Práctico](tps/practico/TP7/InformeTP7.md)      | [RC - TP N7.pdf](<tps/practico/TP7/RC - TP N7.pdf>) |
| [Tarea 2 — Teórico](tps/tp-teorico/tarea2/tarea2.pdf) | [Tarea02.pdf](tps/tp-teorico/tarea2/Tarea02.pdf)    |
| [Tarea 3 — Teórico](tps/tp-teorico/tarea3/main.pdf)   | —                                                   |
| [Tarea 4 — Teórico](tps/tp-teorico/tarea4/main.pdf)   | —                                                   |

### Esquema de archivos

```
tps/
├── practico/TP{N}/       # un TP del práctico
├── tp-teorico/tarea{N}/  # una tarea del teórico
└── template/             # plantilla Typst para informes
    ├── main.typ
    ├── bibliografia.bib
    └── assets/
```

## Informes en Typst

Los informes se escriben en [Typst](https://typst.app/docs/) partiendo de `tps/template/`:

```
cp -r tps/template tps/{practico|tp-teorico}/{tareaN|TPN}     # crea la carpeta del TP con la plantilla adentro
cp -r tps/template/* tps/{practico|tp-teorico}/{tareaN|TPN}/  # si la carpeta ya existe
```

y se completan `trabajo`, `titulo` y `resumen` al principio de `main.typ` (los pasos están comentados arriba de todo en el archivo).

### Con VSCode (recomendado)

1. Abrir el repo en VSCode: aparece el aviso de extensiones recomendadas → **Install**. Es [Tinymist](https://marketplace.visualstudio.com/items?itemName=myriad-dreamin.tinymist) (`myriad-dreamin.tinymist`), que trae su propio compilador de Typst: no hace falta instalar nada más.
2. Usar la versión **0.15.x** de la extensión (probada: 0.15.6). Tinymist alinea su versión *minor* con la de Typst, así que una 0.14.x o 0.16.x compilaría con otro compilador y el informe puede romperse. Para fijarla: engranaje de la extensión → *Install Specific Version...*.
3. Con un `.typ` abierto: botón de lupa/preview arriba a la derecha para ver el render en vivo. Al guardar se genera el PDF al lado del `.typ` (configurado en `.vscode/settings.json`).

### Por consola

La versión de Typst está fijada en `mise.toml` (hoy `0.15.1`), así que todos compilamos con la misma:

```
curl https://mise.run | sh     # una sola vez, ver https://mise.jdx.dev
mise install                   # instala el typst de mise.toml
mise run pdf tps/template/main.typ     # compila una vez
mise run watch tps/template/main.typ   # recompila al guardar
```

Sin `mise` también funciona instalando Typst a mano (`cargo install typst-cli --locked` o el paquete del sistema) **siempre que sea 0.15.x**, y compilando con `typst compile main.typ` / `typst watch main.typ`. Verificar con `typst --version`.

> Typst todavía no tiene un archivo de versión propio ([RFC abierto](https://github.com/typst/typst/issues/5995)), por eso el pin vive en `mise.toml`. Si en el futuro subimos de versión, cambiar `mise.toml` y la versión de la extensión juntas.

## Horario de cursada

| Día   | Tipo      | Inicio | Finaliza | Sede      |
| ------ | --------- | ------ | -------- | --------- |
| Lunes  | Teórico  | 18:30  | 21:00    | CU107 Lab |
| Jueves | Práctica | 18:30  | 21:00    | CU301     |

## Modalidad de trabajo

Cada punto de un trabajo práctico es un issue del repo, y se asigna a quien lo toma.


## Cómo contribuir

Este repositorio guarda el material de estudio de la materia: trabajos prácticos (del práctico y del teórico), apuntes de clase y bibliografía. Esta sección explica cómo agregar contenido nuevo sin romper la organización existente.

### Estructura de carpetas

| Tipo de contenido                | Carpeta destino                      |
| -------------------------------- | ------------------------------------ |
| TP del práctico                 | `tps/practico/TPN/`                |
| TP del teórico                  | `tps/tp-teorico/tareaN/`           |
| Apuntes de clase                 | `Material/clases/teorico/claseN/` o `.../practico/claseN/` |
| Bibliografía (libros, programa) | `Material/Bibliografia/`           |

Si un archivo no encaja en ninguna categoría existente, creá la carpeta que corresponda siguiendo el mismo criterio (tipo de contenido, no persona ni fecha) y documentala acá (ver [Mantener esto actualizado](#mantener-esto-actualizado)).

### Conventional Commits

Los mensajes de commit siguen el formato `tipo: descripción breve`. Tipos usados en este repo:

- `docs:` — agregar o modificar material de estudio (TPs, bibliografía).
- `class:` — agregar o modificar apuntes de una clase puntual.
- `feat:` — cambios estructurales del repo (nuevas carpetas, reorganización).
- `fix:` — corregir un error en un archivo ya subido (typo, archivo corrupto, etc.).

Ejemplos:

```
docs: agregar TP2 de práctico
docs: agregar TP1 de teórico
class: agregar apuntes clase 2
fix: corregir enlace roto en apuntes clase 1
```

### Ramas

Cada colaborador trabaja en su propia rama. Lo único que importa es no trabajar sobre `master`.

```
git checkout <tu-rama>
git merge master
```

Hacé tus commits en esa rama.

### Pull Requests

`master` está protegida: no se puede pushear directo a esa rama, todo cambio tiene que entrar por Pull Request.

Cuando quieras subir contenido a `master`:

1. Pushear la rama propia.
2. Abrir un Pull Request contra `master`.
3. El PR necesita **1 aprobación** y que **todos los comentarios de review estén resueltos** antes de poder mergearse.

### Mantener esto actualizado

Si agregás una categoría nueva de material, reorganizás carpetas, o cambiás el flujo de ramas/PRs, actualizá esta sección en el mismo cambio para que no quede desactualizada respecto a la estructura real del repo.
