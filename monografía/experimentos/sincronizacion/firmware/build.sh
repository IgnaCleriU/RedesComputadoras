#!/usr/bin/env bash
# Compila el firmware y arma la imagen de flash única (4 MB) para QEMU.
#   ./firmware/build.sh
# Requiere ESP-IDF v5.5.x en ~/esp/esp-idf (IDF_PATH lo puede cambiar).
#
# Python: el del sistema puede ser demasiado nuevo para ESP-IDF 5.5. Si existe
# ~/esp/pyshim/ (enlaces python3/python a un Python 3.12 de uv) se pone primero
# en el PATH; si no existe se usa el Python del entorno de ESP-IDF.
#
# Pasos: cargar el entorno, compilar (bootloader + tabla de particiones +
# programa) y juntar todo con merge_bin en una imagen de 4 MB rellena con 0xFF.
set -euo pipefail
cd "$(dirname "$0")"
IDF_PATH="${IDF_PATH:-$HOME/esp/esp-idf}"
export IDF_PATH
[[ -d "$HOME/esp/pyshim" ]] && export PATH="$HOME/esp/pyshim:$PATH"
# shellcheck disable=SC1091
. "$IDF_PATH/export.sh" > /dev/null
idf.py build
cd build
python -m esptool --chip esp32 merge_bin --fill-flash-size 4MB -o flash.bin.tmp @flash_args
# Reemplazo atómico: otro proceso puede estar leyendo la imagen en este momento.
mv flash.bin.tmp flash.bin
echo "Imagen lista: $(pwd)/flash.bin"
