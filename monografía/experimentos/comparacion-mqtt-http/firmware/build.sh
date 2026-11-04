#!/usr/bin/env bash
# Compila el firmware y arma la imagen de flash única (4 MB) que usa el runner.
#   ./firmware/build.sh            (desde experimento/)
# Requiere ESP-IDF v5.5.x en ~/esp/esp-idf (IDF_PATH lo puede cambiar).
#
# Entorno de esta máquina:
#  - ESP-IDF v5.5.6 en ~/esp/esp-idf, toolchain Xtensa de `install.sh esp32`.
#  - Python: el del sistema (3.15) es demasiado nuevo para ESP-IDF 5.5.
#    ~/esp/pyshim/ tiene enlaces python3/python a un Python 3.12 de uv, y este
#    script lo pone primero en el PATH.
#  - QEMU de Espressif 9.2.2 en ~/esp/qemu/qemu/bin. `idf_tools.py install
#    qemu-xtensa` lo borraba por falta de libslirp.so.0: se extrajo a mano el
#    mismo .tar.xz de ~/.espressif/dist y se instaló `pacman -S libslirp`.
#
# Pasos: cargar el entorno, copiar la CA actual (el firmware la embebe), compilar
# (bootloader + tabla de particiones + programa) y juntar todo con merge_bin en
# una imagen de 4 MB rellena con 0xFF, que es lo que necesita QEMU.
set -euo pipefail
cd "$(dirname "$0")"
IDF_PATH="${IDF_PATH:-$HOME/esp/esp-idf}"
[[ -d "$HOME/esp/pyshim" ]] && export PATH="$HOME/esp/pyshim:$PATH"
# shellcheck disable=SC1091
. "$IDF_PATH/export.sh" > /dev/null
cp ../infra/certs/ca.crt main/ca.crt
idf.py build
cd build
python -m esptool --chip esp32 merge_bin --fill-flash-size 4MB -o flash.bin.tmp @flash_args
# Reemplazo atómico: el runner puede estar leyendo la imagen en este momento.
mv flash.bin.tmp flash.bin
echo "Imagen lista: $(pwd)/flash.bin"
