#!/usr/bin/env bash
# Difusión todos-a-todos: los N nodos publican en eco/todos cada h ms (q1 pide ack, el resto
# solo genera carga) y se mide el delay de q1 a todos con la captura en br-eco.
#   ./todos.sh [etiqueta]      NODOS=40 HS="1000 500 250 100" DUR_S=20 BYTES=16
set -euo pipefail
cd "$(dirname "$0")"
label=${1:-todos}
NODOS=${NODOS:-40}
HS=${HS:-"1000 500 250 100"}
DUR_S=${DUR_S:-20}
BYTES=${BYTES:-16}
out=resultados/$label
mkdir -p "$out"
res=$out/resumen.csv
echo "nodos;h_ms;emisores;mensajes;entregas_esperadas;entregas;perdida_pct;cable_p50_ms;cable_p99_ms;vuelta_p50_ms;tau_p50_ms;tau_p95_ms;tau_p99_ms;tau_max_ms;tau_p50_inicio_ms;tau_p50_final_ms;cpu_media_pct" > "$res"

./nodos.sh down
rm -f firmware/build-tap/nodos/*.log
python3 monitor.py "$out/recursos.csv" &
mon=$!
mt0=$(date +%s)
trap 'kill $mon 2>/dev/null; ./nodos.sh down' EXIT

./nodos.sh up "$NODOS"
for _ in $(seq 180); do
    up=$(cat firmware/build-tap/nodos/*.log 2>/dev/null | grep -ac "eco: conectado" || true)
    if [ "$up" -ge "$NODOS" ]; then break; fi
    sleep 1
done
echo "conectados: $up"
sleep 10

for h in $HS; do
    echo "== h = $h ms"
    sudo tcpdump -i br-eco -s 256 -B 65536 -Z "$USER" -w "$out/todos_h$h.pcap" tcp port 53317 2>/dev/null &
    td=$!
    sleep 2
    ws=$(($(date +%s) - mt0))
    for i in $(seq "$NODOS"); do
        mosquitto_pub -h 127.0.0.1 -t "eco/q$i/cmd" -m "bcast $((DUR_S * 1000 / h)) $h $BYTES $([ "$i" = 1 ] && echo 1 || echo 0)"
    done
    sleep $((DUR_S + 5))
    we=$(($(date +%s) - mt0))
    sudo kill -INT "$td"
    wait "$td" || true
    cpu=$(awk -F, -v a="$ws" -v b="$we" 'NR > 1 && $1 >= a && $1 <= b {s += $7; n++} END {printf "%.1f", s / n}' "$out/recursos.csv")
    echo "$(python3 analizar_todos.py "$out/todos_h$h.pcap" "$out/todos_h$h.csv" "$h");$cpu" | tee -a "$res"
    sleep 5
done
