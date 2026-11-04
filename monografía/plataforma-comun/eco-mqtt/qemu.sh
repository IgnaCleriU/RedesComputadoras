#!/usr/bin/env bash
# Arranca el nodo de eco en el ESP32 emulado. Requiere `. ~/esp/esp-idf/export.sh`
# y el firmware compilado con:
#   idf.py -B build-qemu -D SDKCONFIG=build-qemu/sdkconfig \
#          -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.qemu" build
set -euo pipefail
b="$(dirname "$0")/firmware/build-qemu"
(cd "$b" && esptool.py --chip esp32 merge_bin --fill-flash-size 4MB -o flash.bin @flash_args >/dev/null)
exec qemu-system-xtensa -nographic -machine esp32 \
    -drive file="$b/flash.bin",if=mtd,format=raw \
    -nic user,model=open_eth
