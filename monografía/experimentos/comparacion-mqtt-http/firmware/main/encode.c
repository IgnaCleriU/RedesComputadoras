// Serializa una lectura en protobuf (nanopb) o JSON, con los mismos campos.
// Devuelve los bytes escritos en buf, o 0 si hubo error.
//
// JSON (snprintf con formato fijo, value con 4 decimales), ~72 B:
//   {"esp_id":3,"seq":42,"t_us":1793041765379595,"value":27.1234,"status":0}
//
// Protobuf (nanopb, sin memoria dinámica: todo va al buffer), campo por campo:
//   esp_id = 3        etiqueta 0x08 (campo 1, varint) + 0x03               2 B
//   seq = 42          etiqueta 0x10 + varint (1 B hasta 127, 2 desde 128)   2-3 B
//   t_us ≈ 1,79e15    etiqueta 0x18 + varint de 51 bits (7 bits por byte)   9 B
//   value             etiqueta 0x25 (campo 4, 32 bits fijos) + float        5 B
//   status = 0        en proto3 el valor por defecto no se escribe          0 B
//   total: 18 B (16 si seq = 0, 19 si seq >= 128). JSON es ~4 veces más grande.
#include <stdio.h>

#include "node.h"
#include "pb_encode.h"
#include "telemetry.pb.h"

size_t encode_reading(const node_config_t *cfg, const reading_t *r, uint8_t *buf, size_t cap)
{
    if (cfg->json) {
        int n = snprintf((char *)buf, cap,
                         "{\"esp_id\":%lu,\"seq\":%lu,\"t_us\":%llu,\"value\":%.4f,\"status\":%lu}",
                         (unsigned long)cfg->esp_id, (unsigned long)r->seq,
                         (unsigned long long)r->t_us, (double)r->value, (unsigned long)r->status);
        return (n > 0 && (size_t)n < cap) ? (size_t)n : 0;
    }
    exp_Telemetry msg = exp_Telemetry_init_zero;
    msg.esp_id = cfg->esp_id;
    msg.seq = r->seq;
    msg.t_us = r->t_us;
    msg.value = r->value;
    msg.status = r->status;
    pb_ostream_t s = pb_ostream_from_buffer(buf, cap);
    if (!pb_encode(&s, exp_Telemetry_fields, &msg)) {
        return 0;
    }
    return s.bytes_written;
}
