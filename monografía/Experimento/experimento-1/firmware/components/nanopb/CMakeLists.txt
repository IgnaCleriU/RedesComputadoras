# Runtime de nanopb 0.4.9.1 (https://github.com/nanopb/nanopb), solo los .c/.h necesarios.
idf_component_register(SRCS "pb_common.c" "pb_encode.c" "pb_decode.c"
                       INCLUDE_DIRS ".")
