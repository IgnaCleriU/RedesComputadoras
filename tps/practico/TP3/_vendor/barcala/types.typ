#import "@preview/valkyrie:0.2.2" as z

#let autor-schema = z.dictionary(
  (
    nombre: z.string(
      assertions: (
        z.assert.matches(
          regex("^[^,]+, [^,]+$"),
          message: (self, it) => "El nombre debe tener el formato \"Apellido, Nombre\"",
        ),
      ),
    ),
    email: z.string(
      optional: true,
      assertions: (
        z.assert.matches(
          regex("^[^@]+@[^@]+$"), // z.email() no acepta emails institucionales
          message: (self, it) => "Email inválido",
        ),
      ),
      // Parche local: el post-transform de barcala 0.3.0 no contempla el caso
      // en que `email` se omite (autor sin email) y explota con `it == none`.
      // Bug en valkyrie 0.2.2 (base-type.typ no guarda post-transform contra none).
      post-transform: (self, it) => if it == none {
        none
      } else {
        (
          user: it.split("@").at(0),
          domain: it.split("@").at(1),
        )
      },
    ),
    legajo: z.string(optional: true),
    notas: z.array(
      z.content(),
      default: (),
      pre-transform: z.coerce.array,
    ),
  ),
  pre-transform: z.coerce.dictionary(it => (nombre: it)),
  post-transform: (self, it) => (
    ..it,
    nombre: it.nombre.split(", ").at(1),
    apellido: it.nombre.split(", ").at(0),
  ),
)


#let formato-schema = z.dictionary((
  tipografia: z.string(default: "New Computer Modern"),
  margenes: z.choice(("simétricos", "anillado"), default: "simétricos"),
))

#let parse-options(options) = z.parse(
  options,
  z.dictionary((
    institucion: z.either(z.string(), z.content(), default: "unlp"),
    unidad-academica: z.either(z.string(), z.content()),
    asignatura: z.content(),
    trabajo: z.content(optional: true),
    equipo: z.content(optional: true),
    autores: z.array(
      autor-schema,
      pre-transform: z.coerce.array,
    ),
    titulo: z.content(),
    resumen: z.content(optional: true),
    fecha: z.date(pre-transform: z.coerce.date),
    formato: formato-schema,
  )),
)
