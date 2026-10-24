= Anexos

// Material que cortaría la lectura del desarrollo. Los anexos se numeran con letras (A., B., ...).
#set heading(numbering: (..n) => if n.pos().len() > 1 { numbering("A.1.", ..n.pos().slice(1)) })

== Mensajes del experimento de sincronización

Archivo `.proto` compartido por el firmware de los nodos y por el backend del experimento de sincronización de luciérnagas. Los tópicos por los que viaja cada mensaje se describen en la sección de mensajes y tópicos de ese experimento.

```proto
syntax = "proto3";

message Flash {
  uint32 esp_id = 1;
  uint32 led_id = 2;
  uint32 seq    = 3;
  uint64 t_us   = 4;
}

message PhaseReport {
  uint32 esp_id = 1;
  uint32 led_id = 2;
  float  phase  = 3;
  bool   on     = 4;
  uint64 t_us   = 5;
}

message RxEvent {
  uint32 esp_id  = 1;
  uint32 src_esp = 2;
  uint32 src_led = 3;
  uint32 seq     = 4;
  uint64 t_us    = 5;
}

message ExperimentConfig {
  uint32 num_esp      = 1;
  uint32 leds_per_esp = 2;
  float  epsilon      = 3;
  uint32 loss_pct     = 4;
  uint32 latency_ms   = 5;
  uint32 qos          = 6;
  uint32 seed         = 7;
}
```
