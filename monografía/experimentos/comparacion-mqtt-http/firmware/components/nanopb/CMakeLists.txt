# nanopb 0.4.9.1 (https://github.com/nanopb/nanopb), descargado al configurar.
# Solo se compila el runtime: los pb_*.c/.h de la raíz del repo.
#
# ESP-IDF lee este archivo dos veces. La primera (CMAKE_BUILD_EARLY_EXPANSION)
# solo junta dependencias entre componentes, así que no hace falta descargar nada.
if(CMAKE_BUILD_EARLY_EXPANSION)
    idf_component_register()
    return()
endif()

include(FetchContent)
FetchContent_Declare(nanopb_src
    URL      https://github.com/nanopb/nanopb/archive/refs/tags/0.4.9.1.tar.gz
    URL_HASH SHA256=4575944a468718ef25f05eb01d994364650b581563089a9841986bb1e460eac3
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    # El CMakeLists.txt de nanopb no es un componente de ESP-IDF (pide protoc).
    # Apuntar a una carpeta que no existe hace que solo se descargue.
    SOURCE_SUBDIR no-usar-cmake-de-nanopb)
FetchContent_MakeAvailable(nanopb_src)

idf_component_register(
    SRCS "${nanopb_src_SOURCE_DIR}/pb_common.c"
         "${nanopb_src_SOURCE_DIR}/pb_encode.c"
         "${nanopb_src_SOURCE_DIR}/pb_decode.c"
    INCLUDE_DIRS "${nanopb_src_SOURCE_DIR}")
