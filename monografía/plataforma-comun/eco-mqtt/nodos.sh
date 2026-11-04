#!/usr/bin/env bash
# Varios ESP32 emulados sobre tap + puente (necesita sudo para el puente y las taps).
#   ./nodos.sh up N     levanta los nodos 1..N que no estén corriendo
#   ./nodos.sh down     apaga todos y borra taps y puente
# Firmware: idf.py -B build-tap -D SDKCONFIG=build-tap/sdkconfig \
#           -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.tap" build
# La PC es 10.10.0.1 en br-eco; el nodo i es q<i>, con IP 10.10.0.0 + 10 + i.
set -euo pipefail
cd "$(dirname "$0")"
b=firmware/build-tap
d=$b/nodos
idx_addr=$((0x3FF000)) # NODE_IDX_ADDR en main.c

case "${1:-}" in
up)
    if ! ip link show br-eco &>/dev/null; then
        sudo ip link add br-eco type bridge
        sudo ip addr add 10.10.0.1/16 dev br-eco
        sudo ip link set br-eco up
    fi
    mkdir -p "$d"
    [ -f "$b/flash.bin" ] || (cd "$b" && esptool.py --chip esp32 merge_bin --fill-flash-size 4MB -o flash.bin @flash_args >/dev/null)
    for i in $(seq "$2"); do
        if [ -f "$d/$i.pid" ] && kill -0 "$(cat "$d/$i.pid")" 2>/dev/null; then continue; fi
        ip link show "tapeco$i" &>/dev/null || {
            sudo ip tuntap add "tapeco$i" mode tap user "$USER"
            sudo ip link set "tapeco$i" master br-eco up
        }
        cp "$b/flash.bin" "$d/$i.bin"
        python3 -c "import struct,sys; sys.stdout.buffer.write(struct.pack('<I', $i))" |
            dd of="$d/$i.bin" bs=1 seek=$idx_addr conv=notrunc status=none
        qemu-system-xtensa -machine esp32 -display none -monitor none -serial "file:$d/$i.log" \
            -drive file="$d/$i.bin",if=mtd,format=raw \
            -nic tap,ifname="tapeco$i",script=no,downscript=no,model=open_eth &
        echo $! > "$d/$i.pid"
    done
    ;;
down)
    for p in "$d"/*.pid; do
        if [ -f "$p" ]; then
            kill "$(cat "$p")" 2>/dev/null || true
            rm -f "$p"
        fi
    done
    ./ruido.sh off
    for t in $(ip -o link show | grep -o 'tapeco[0-9]*' | sort -u); do sudo ip link del "$t"; done
    if ip link show br-eco &>/dev/null; then sudo ip link del br-eco; fi
    ;;
*)
    echo "uso: $0 up N | down" >&2
    exit 2
    ;;
esac
