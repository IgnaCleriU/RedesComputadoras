/* Equivalente a lo que genera nanopb-0.4.9.1 para proto/telemetry.proto.
 *
 * nanopb es la implementación de Protocol Buffers para microcontroladores. Para
 * codificar un struct necesita una descripción de sus campos: la macro
 * exp_Telemetry_FIELDLIST lista cada campo con su asignación (STATIC: sin memoria
 * dinámica), su tipo y su número de etiqueta. telemetry.pb.c la expande con
 * PB_BIND en la tabla exp_Telemetry_msg que usa pb_encode (encode.c).
 *
 * Se escribió a mano con el mismo formato que genera el generador, porque no se
 * pudo ejecutar nanopb_generator en esta máquina. Si se cambia el .proto,
 * regenerar con un clon de nanopb 0.4.9.1 (necesita el paquete protobuf de Python):
 *   git clone --branch 0.4.9.1 https://github.com/nanopb/nanopb.git /tmp/nanopb
 *   python /tmp/nanopb/generator/nanopb_generator.py -D firmware/main proto/telemetry.proto
 */
#ifndef PB_EXP_TELEMETRY_PB_H_INCLUDED
#define PB_EXP_TELEMETRY_PB_H_INCLUDED
#include <pb.h>

#if PB_PROTO_HEADER_VERSION != 40
#error Regenerate this file with the current version of nanopb generator.
#endif

/* Struct definitions */
typedef struct _exp_Telemetry {
    uint32_t esp_id;
    uint32_t seq;
    uint64_t t_us;
    float value;
    uint32_t status;
} exp_Telemetry;

#ifdef __cplusplus
extern "C" {
#endif

/* Initializer values for message structs */
#define exp_Telemetry_init_default               {0, 0, 0, 0, 0}
#define exp_Telemetry_init_zero                  {0, 0, 0, 0, 0}

/* Field tags (for use in manual encoding/decoding) */
#define exp_Telemetry_esp_id_tag                 1
#define exp_Telemetry_seq_tag                    2
#define exp_Telemetry_t_us_tag                   3
#define exp_Telemetry_value_tag                  4
#define exp_Telemetry_status_tag                 5

/* Struct field encoding specification for nanopb */
#define exp_Telemetry_FIELDLIST(X, a) \
X(a, STATIC,   SINGULAR, UINT32,   esp_id,            1) \
X(a, STATIC,   SINGULAR, UINT32,   seq,               2) \
X(a, STATIC,   SINGULAR, UINT64,   t_us,              3) \
X(a, STATIC,   SINGULAR, FLOAT,    value,             4) \
X(a, STATIC,   SINGULAR, UINT32,   status,            5)
#define exp_Telemetry_CALLBACK NULL
#define exp_Telemetry_DEFAULT NULL

extern const pb_msgdesc_t exp_Telemetry_msg;

/* Defines for backwards compatibility with code written before nanopb-0.4.0 */
#define exp_Telemetry_fields &exp_Telemetry_msg

/* Maximum encoded size of messages (where known) */
#define EXP_TELEMETRY_PB_H_MAX_SIZE              exp_Telemetry_size
#define exp_Telemetry_size                       34

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif
