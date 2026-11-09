// 1. Copiar la plantilla al directorio del TP:
//    cp -r tps/template tps/teorico/tareaN   (o `tps/template/*` si ya existe)
// 2. Actualizar "trabajo" en L38 (número de trabajo práctico) y "titulo" en L75
// 3. Actualizar el "resumen" u objetivo en L76
// 4. Al entregar, poner `drafting` en false para sacar la marca de BORRADOR

// Template https://github.com/juanm04/barcala
#import "@preview/barcala:0.3.0": apendice, informe, nomenclatura
#import "@preview/lilaq:0.5.0" as lq // Paquete para gráficos, puede ser omitido
#import "@preview/physica:0.9.7": * // Paquete para matemática y física, puede ser omitido
#import "@preview/zero:0.5.0" // Paquete para números lindos y unidades de medida, puede ser omitido

// Cambiar a false cuando el informe esté listo para presentar
#let drafting = true
#set page(
  foreground: if drafting {
      rotate(-0.955317rad, text(
      weight: "bold",
      size: 80pt,
      fill: rgb("#00000040"),
      "BORRADOR"
    ))
  }
)

// Los emails de la carátula se renderizan como `raw` inline, que no corta en las
// comas y se desborda del margen. Agregamos un espacio de ancho cero tras cada
// coma para habilitar el salto de línea.
#show raw.where(block: false): it => {
  show ",": ",\u{200B}"
  it
}

#show: informe.with(
  unidad-academica: image("assets/FCEFyN.png"),
  institucion: image("assets/UNC.jpg"),
  asignatura: "09807 - Redes de Computadoras",
  trabajo: "Trabajo Práctico Nº X",
  equipo: "WireGuardians",
  autores: (
    (
      nombre: "Viberti, Benjamin",
      email: "b.viberti@mi.unc.edu.ar",
    ),
    (
      nombre: "Espinoza Sutta, Aaron Alejandro",
      email: "aaron.espinoza_4500@mi.unc.edu.ar",
    ),
    (
      nombre: "Cleri, Juan Ignacio",
      email: "ignacio.cleri@mi.unc.edu.ar",
    ),
    (
      nombre: "Pineda, Juan Ignacio",
      email: "juan.ignacio.pineda@mi.unc.edu.ar",
    ),
    (
      nombre: "Grafión, Atilio Leonel",
      email: "atilio.grafion@mi.unc.edu.ar",
    ),
    (
      nombre: "Badenes, Tomás",
      email: "tomasbadenes@mi.unc.edu.ar",
    ),
    (
      nombre: "Oviedo, Ignacio Nicolas",
      email: "ignacio.oviedo.239@mi.unc.edu.ar",
    ),
    (
      nombre: "Mendez, Jorge Nicolas",
      email: "jorge.mendez@mi.unc.edu.ar",
    ),
  ),
  
  titulo: [Preguntas de Repaso y Problemas],
  resumen: [*_Objetivo_ --- Resolver las preguntas de repaso y los problemas del Capítulo Y de @stallings2004.*],
  
  fecha: datetime.today().display("[year]-[month]-[day]"),
)

// Enlaces de colores
#show cite: set text(blue)
#show link: set text(blue)
#show ref: set text(blue)

// Bloques de matemática con números para citar
#set math.equation(numbering: "(1)")
#show ref: it => {
  if it.element != none and it.element.func() == math.equation {
    // Sobreescribir las referencias a ecuaciones
    link(it.element.location(), numbering(
      it.element.numbering,
      ..counter(math.equation).at(it.element.location()),
    ))
  } else {
    // Otras referencias quedan igual
    it
  }
}

// Configuración de `zero`
#import zero: num, zi
#zero.set-num(
  decimal-separator: ",",
)
#zero.set-group(
  size: 3,
  separator: ".",
  threshold: (integer: 5, fractional: calc.inf),
)
#zero.set-unit(
  fraction: "inline",
)

// #nomenclatura(
//   ($f$, [Frecuencia [#zi.hertz()]]),
//   ($C$, [Capacidad del canal [#zi.bit-per-second()]]),
// )

// Customización por sobre el template
#set par(
  spacing: 1.2em
)

= Una Sección

_(contenido)_


// Sección de apéndices. Si no se usa, se puede comentar o borrar
#show: apendice

= Un apéndice

// Bibliografía. Si hay referencias bibliográficas se renderiza.
// Si no, solamente con full: true se renderiza la bibliografía completa, aunque no haya referencias en el texto
#bibliography("bibliografia.bib", full: true)
