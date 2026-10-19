// Carátula de la monografía.
// Compilar: `typst compile caratula.typ` (Typst 0.15.x, ver mise.toml en la raíz del repo).
// Estilo tomado de las tareas (plantilla barcala): New Computer Modern, A4, logos arriba.

#let titulo = "MQTT y Protocol Buffers"
#let subtitulo = "Un stack de comunicación en tiempo real para IoT, robótica y sistemas multiservicio"
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

#let meses = (
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
)
#let hoy = datetime.today()

#set document(title: "Monografía: carátula", author: integrantes.map(i => i.nombre))
#set page(paper: "a4", margin: (x: 2cm, top: 1.8cm, bottom: 2cm))
#set text(font: "New Computer Modern", size: 12pt, lang: "es", region: "AR")
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

// Lugar y fecha
#align(center)[
  Córdoba, #meses.at(hoy.month() - 1) de #hoy.year()
]
