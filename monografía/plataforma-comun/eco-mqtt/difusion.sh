#!/usr/bin/env bash
# Delay de difusión: q1 publica en eco/todos y se mide cuándo le llega a cada uno de los demás,
# capturando en br-eco (reloj de la PC). Necesita sudo para tcpdump.
#   ./difusion.sh [etiqueta]      NODOS="2 20 40 60" MSGS=200 PERIODO_MS=100 BYTES=16
set -euo pipefail
cd "$(dirname "$0")"
label=${1:-difusion}
NODOS=${NODOS:-"2 20 40 60"}
MSGS=${MSGS:-200}
PERIODO_MS=${PERIODO_MS:-100}
BYTES=${BYTES:-16}
out=resultados/$label
mkdir -p "$out"
res=$out/resumen.csv
echo "nodos;mensajes;entregas_esperadas;entregas;perdida_pct;uno_p50_ms;uno_p99_ms;todos_p50_ms;todos_p95_ms;todos_p99_ms;todos_max_ms;vuelta_esp32_p50_ms;app_a_todos_p50_ms" > "$res"

./nodos.sh down
rm -f firmware/build-tap/nodos/*.log
python3 monitor.py "$out/recursos.csv" &
mon=$!
trap 'kill $mon 2>/dev/null; ./nodos.sh down' EXIT

for n in $NODOS; do
    echo "== $n nodos"
    ./nodos.sh up "$n"
    for _ in $(seq 180); do
        up=$(cat firmware/build-tap/nodos/*.log 2>/dev/null | grep -ac "eco: conectado" || true)
        if [ "$up" -ge "$n" ]; then break; fi
        sleep 1
    done
    echo "   conectados: $up"
    sleep 10
    sudo tcpdump -i br-eco -s 256 -B 16384 -Z "$USER" -w "$out/difusion_$n.pcap" tcp port 53317 2>/dev/null &
    td=$!
    sleep 2
    mosquitto_pub -h 127.0.0.1 -t eco/q1/cmd -m "bcast $MSGS $PERIODO_MS $BYTES"
    sleep $((MSGS * PERIODO_MS / 1000 + 3))
    sudo kill -INT "$td"
    wait "$td" || true
    python3 analizar_difusion.py "$out/difusion_$n.pcap" "$out/difusion_$n.csv" | tee -a "$res"
done
