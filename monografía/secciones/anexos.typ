= Anexos

// Material que cortaría la lectura del desarrollo. Los anexos se numeran con letras (A., B., ...).
#set heading(numbering: (..n) => if n.pos().len() > 1 { numbering("A.1.", ..n.pos().slice(1)) })

== Mensajes del experimento de sincronización

// Archivo `.proto` completo compartido por el firmware de los nodos y por el backend.
