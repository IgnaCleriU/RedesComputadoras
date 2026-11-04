#!/usr/bin/env bash
# Suma nodos QEMU de a escalones y mide la latencia con todos a la vez, hasta que la PC
# se queda sin RAM: menos de MIN_DISP_MB disponibles o más de MAX_SWAP_MB de swap usado.
#   ./escalar.sh [etiqueta]      (resultados en resultados/<etiqueta>/)
set -euo pipefail
cd "$(dirname "$0")"
label=${1:-escala}
MIN_DISP_MB=${MIN_DISP_MB:-800}
MAX_SWAP_MB=${MAX_SWAP_MB:-1024}
STEPS=${STEPS:-"1 2 4 8 12 16 20 24 28 32 36 40 44 48 52 56 60 64 72 80 96 112 128"}
out=resultados/$label
mkdir -p "$out"
rm -f "$out/multi.csv" "$out/escalones.csv"
./nodos.sh down
rm -f firmware/build-tap/nodos/*.log

mem() { awk -v k="$1:" '$1 == k {print int($2 / 1024)}' /proc/meminfo; }
swap_used() { echo $(($(mem SwapTotal) - $(mem SwapFree))); }

python3 monitor.py "$out/recursos.csv" &
mon=$!
trap 'kill $mon 2>/dev/null; ./nodos.sh down' EXIT

for n in $STEPS; do
    echo "== $n nodos (disponible $(mem MemAvailable) MiB, swap $(swap_used) MiB)"
    ./nodos.sh up "$n"
    # Esperar a que todos se conecten al broker (máx. 3 min).
    for _ in $(seq 180); do
        up=$(cat firmware/build-tap/nodos/*.log 2>/dev/null | grep -ac "eco: conectado" || true)
        if [ "$up" -ge "$n" ]; then break; fi
        sleep 1
    done
    echo "   conectados: $up"
    sleep 10 # que se asienten el arranque y la memoria
    echo "$(date +%s),$n,$up" >> "$out/escalones.csv"
    ./backend/eco -nodes "$n" -n 100 -interval 50ms -warmup 5 -label "$label" multi
    disp=$(mem MemAvailable) sw=$(swap_used)
    echo "   disponible $disp MiB, swap $sw MiB"
    if [ "$disp" -lt "$MIN_DISP_MB" ] || [ "$sw" -gt "$MAX_SWAP_MB" ] || [ "$up" -lt "$n" ]; then
        echo "== límite alcanzado con $n nodos"
        break
    fi
done
