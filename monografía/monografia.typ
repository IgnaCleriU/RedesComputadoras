// Monografía (WireGuardians). Tema: MQTT + Protocol Buffers.
// Compilar: `typst compile monografia.typ "WireGuardians-MONOGRAFÍA.pdf"` (Typst 0.15.x, ver mise.toml en la raíz del repo).
// Orden del documento: carátula, índice (automático), secciones (una por archivo en `secciones/`),
// bibliografía y anexos.
// Detalles de uso en README.md.

// ---------------------------------------------------------------------------
// Datos de la carátula
// ---------------------------------------------------------------------------
#let titulo = "MQTT y Protocol Buffers"
#let subtitulo = "Un stack de comunicación en tiempo real para IoT, robótica y mensajería con servicios en la nube"
#let docente = "Oliva Cuneo, Facundo Nicolas"

// DNI y mail: planilla de la cátedra (nombres tal como figuran ahí).
#let integrantes = (
  (nombre: "Viberti, Benjamin", dni: "46224179", mail: "b.viberti"),
  (nombre: "Espinoza Sutta, Aaron Alejandro", dni: "96009173", mail: "aaron.espinoza_4500"),
  (nombre: "Cleri, Juan Ignacio", dni: "46452662", mail: "ignacio.cleri"),
  (nombre: "Pineda, Juan Ignacio", dni: "45591343", mail: "juan.ignacio.pineda"),
  (nombre: "Grafión, Atilio Leonel", dni: "43940195", mail: "atilio.grafion"),
  (nombre: "Badenes, Tomás", dni: "44785038", mail: "tomasbadenes"),
  (nombre: "Oviedo, Ignacio Nicolás", dni: "44169239", mail: "ignacio.oviedo.239"),
  (nombre: "Mendez, Jorge Nicolas", dni: "41301342", mail: "jorge.mendez"),
)

#let dominio-mail = "mi.unc.edu.ar"

// Borrador: agrega una marca de agua en todas las páginas. Pasar a `false` para la entrega.
#let borrador = true

#let hoy = datetime.today()
// `datetime.display` no traduce los meses, así que la fecha se arma a mano.
#let meses = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")
#let fecha = [#hoy.day() de #meses.at(hoy.month() - 1) de #hoy.year()]

// ---------------------------------------------------------------------------
// Configuración general (la carátula usa estos márgenes; el cuerpo los cambia más abajo)
// ---------------------------------------------------------------------------
#set document(title: "Monografía: " + titulo, author: integrantes.map(i => i.nombre))
#set page(paper: "a4", margin: (x: 2cm, top: 1.8cm, bottom: 2cm))
#set page(background: if borrador {
  rotate(-45deg, text(size: 80pt, weight: "bold", fill: luma(225), tracking: 0.1em)[BORRADOR])
})
#set text(font: "New Computer Modern", lang: "es", region: "AR")

// ---------------------------------------------------------------------------
// Carátula
// ---------------------------------------------------------------------------
#let caratula() = [
  #set text(size: 12pt)
  #set par(justify: false, spacing: 0pt, leading: 0.65em)

  // El pie con los mails se renderiza como `raw` inline, que no corta en las comas y se
  // desborda del margen. Se agrega un espacio de ancho cero tras cada coma (igual que en las tareas).
  #show raw.where(block: false): it => {
    show ",": ",\u{200B}"
    it
  }

  // Logos
  #grid(
    columns: (1fr, 1fr),
    align: (left + horizon, right + horizon),
    image("assets/FCEFyN.png", height: 1.9cm),
    image("assets/UNC.jpg", height: 1.9cm),
  )
  #v(0.6cm)
  #line(length: 100%, stroke: 0.5pt)

  // Institución y asignatura
  #v(1.2cm)
  #align(center)[
    #text(size: 11pt, smallcaps[Universidad Nacional de Córdoba]) \
    #text(size: 11pt, smallcaps[Facultad de Ciencias Exactas, Físicas y Naturales]) \
    #v(0.5em)
    #text(size: 12pt)[Ingeniería en Computación] \
    #v(1.2em)
    #text(size: 17pt, smallcaps[Redes de Computadoras])
  ]

  #v(1fr)

  // Título
  #align(center)[
    #text(size: 12pt, tracking: 0.25em, upper[Monografía])
    #v(0.9em)
    #line(length: 35%, stroke: 0.5pt)
    #v(1.1em)
    #text(size: 26pt, weight: "bold", titulo)
    #v(0.7em)
    #block(width: 70%, text(size: 14pt, style: "italic", subtitulo))
    #v(1.1em)
    #line(length: 35%, stroke: 0.5pt)
  ]

  #v(1fr)

  // Equipo, integrantes (con DNI) y docente
  #align(center)[
    #text(size: 12pt, smallcaps[Equipo]) \
    #v(0.5em)
    #text(size: 14pt, underline[WireGuardians])
    #v(1em)
    #grid(
      columns: (auto, auto),
      column-gutter: 1.4em,
      row-gutter: 0.6em,
      align: left,
      ..integrantes
        .map(i => ([#i.nombre#super[1]], text(size: 0.9em)[DNI #i.dni]))
        .flatten(),
    )
    #v(1.4em)
    #text(size: 12pt, smallcaps[Docente]) \
    #v(0.5em)
    #docente
  ]

  #v(1fr)

  // Pie: mails de los integrantes, con el mismo formato que las tareas
  #align(center)[
    #set text(size: 10pt)
    #super[1]#raw("{" + integrantes.map(i => i.mail).join(",") + "}@" + dominio-mail)
  ]
  #v(0.5cm)
  #line(length: 100%, stroke: 0.5pt)
  #v(0.5cm)

  // Fecha
  #align(center)[
    #fecha
  ]
]

#caratula()

// ---------------------------------------------------------------------------
// Formato del cuerpo (desde la página 2; la carátula cuenta como página 1 y no lleva número)
// ---------------------------------------------------------------------------
#set page(margin: (x: 2.5cm, y: 2.5cm), numbering: "1")
#set text(size: 11pt)
#set par(justify: true, leading: 0.65em, spacing: 1.2em)

// Títulos: los capítulos (nivel 1) van sin número y cada uno arranca en página nueva.
// Desde el nivel 2 se numera: `==` -> 1., 2., ...; `===` -> 1.1., 1.2., ...
#set heading(numbering: (..n) => if n.pos().len() > 1 { numbering("1.1.", ..n.pos().slice(1)) })

// Referencias a secciones: "Sección 1.3" en lugar de "Sección 1.3.", ya que la numeración de los
// títulos termina en punto. Las referencias a figuras, tablas y ecuaciones no cambian.
#show ref: it => {
  let el = it.element
  if el != none and el.func() == heading and el.numbering != none {
    let nums = counter(heading).at(el.location()).slice(1)
    link(el.location(), [#el.supplement~#numbering("1.1", ..nums)])
  } else {
    it
  }
}
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  it
}
#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 3): set text(size: 12pt)
#show heading.where(level: 4): set text(size: 11pt)
#show heading: set block(above: 1.4em, below: 1em)

// Figuras y tablas: epígrafe en cursiva ("Figura 1: ..."); en las tablas va arriba.
#show figure.caption: set text(size: 10pt, style: "italic")
#show figure.where(kind: table): set figure.caption(position: top)
#set math.equation(numbering: "(1)")

// Tablas: texto un poco más chico, alineado a la izquierda y encabezado en negrita.
#set table(stroke: 0.5pt + luma(170), inset: 5pt, align: left)
#show table: set text(size: 9.5pt)
#show table: set par(justify: false)
#show table.cell.where(y: 0): set text(weight: "bold")

// Bloques de código (mensajes .proto, JSON): fondo gris claro y letra un poco más chica.
#show raw.where(block: true): set text(size: 9pt)
#show raw.where(block: true): block.with(fill: luma(245), inset: 8pt, radius: 3pt, width: 100%, breakable: false)

// Índice: se arma solo a partir de los títulos.
#show outline.entry.where(level: 1): set text(weight: "bold")
#outline(title: [Índice], depth: 3)

// ---------------------------------------------------------------------------
// Secciones (una por archivo: así cada integrante edita lo suyo sin pisarse)
// ---------------------------------------------------------------------------
#include "secciones/introduccion.typ"
#include "secciones/objetivos.typ"
#include "secciones/alcance.typ"
#include "secciones/marco-teorico.typ"
#include "secciones/desarrollo.typ"
#include "secciones/experimentos.typ"
#include "secciones/conclusion.typ"

// ---------------------------------------------------------------------------
// Bibliografía (estilo IEEE; muestra todas las entradas de bibliografia.bib)
// ---------------------------------------------------------------------------
= Bibliografía
#bibliography("bibliografia.bib", title: none, style: "ieee", full: true)

// ---------------------------------------------------------------------------
// Anexos
// ---------------------------------------------------------------------------
#include "secciones/anexos.typ"
