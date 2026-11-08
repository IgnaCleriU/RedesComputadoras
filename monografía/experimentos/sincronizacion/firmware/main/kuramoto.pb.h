/* Equivalente a lo que genera nanopb-0.4.9.1 para proto/kuramoto.proto.
 *
 * Escrito a mano con el mismo formato que el generador (no está instalado en
 * esta máquina). Si cambia el .proto, regenerar con un clon de nanopb 0.4.9.1:
 *   python nanopb/generator/nanopb_generator.py -D firmware/main proto/kuramoto.proto
 */
#ifndef PB_KUR_KURAMOTO_PB_H_INCLUDED
#define PB_KUR_KURAMOTO_PB_H_INCLUDED
#include <pb.h>

#if PB_PROTO_HEADER_VERSION != 40
#error Regenerate this file with the current version of nanopb generator.
#endif

/* Struct definitions */
typedef struct _kur_PhaseReport {
    uint32_t id;
    float theta;
    float velocidad;
    uint32_t seq;
    uint64_t t_us;
} kur_PhaseReport;

#ifdef __cplusplus
extern "C" {
#endif

/* Initializer values for message structs */
#define kur_PhaseReport_init_default             {0, 0, 0, 0, 0}
#define kur_PhaseReport_init_zero                {0, 0, 0, 0, 0}

/* Field tags (for use in manual encoding/decoding) */
#define kur_PhaseReport_id_tag                   1
#define kur_PhaseReport_theta_tag                2
#define kur_PhaseReport_velocidad_tag            3
#define kur_PhaseReport_seq_tag                  4
#define kur_PhaseReport_t_us_tag                 5

/* Struct field encoding specification for nanopb */
#define kur_PhaseReport_FIELDLIST(X, a) \
X(a, STATIC,   SINGULAR, UINT32,   id,                1) \
X(a, STATIC,   SINGULAR, FLOAT,    theta,             2) \
X(a, STATIC,   SINGULAR, FLOAT,    velocidad,         3) \
X(a, STATIC,   SINGULAR, UINT32,   seq,               4) \
X(a, STATIC,   SINGULAR, FIXED64,  t_us,              5)
#define kur_PhaseReport_CALLBACK NULL
#define kur_PhaseReport_DEFAULT NULL

extern const pb_msgdesc_t kur_PhaseReport_msg;

/* Defines for backwards compatibility with code written before nanopb-0.4.0 */
#define kur_PhaseReport_fields &kur_PhaseReport_msg

/* Maximum encoded size of messages (where known) */
#define KURAMOTO_PB_H_MAX_SIZE                   kur_PhaseReport_size
#define kur_PhaseReport_size                     31

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif
