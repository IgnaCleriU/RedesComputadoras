#!/usr/bin/env bash
# Todos-a-todos con ruido de red: N nodos publicando cada h ms, con cada perfil de netem aplicado
# en los dos sentidos del enlace de cada nodo. Se captura en cada tap (del lado del nodo), así
# que los tiempos incluyen el ruido de subida y de bajada.
#   ./ruido_medir.sh [etiqueta]      NODOS=40 H=1000 DUR_S=60 BYTES=16
set -euo pipefail
cd "$(dirname "$0")"
label=${1:-ruido}
NODOS=${NODOS:-40}
H=${H:-1000}
DUR_S=${DUR_S:-60}
BYTES=${BYTES:-16}
# nombre|parámetros de netem por sentido (vacío: sin ruido). La variación va con "slot" (ráfagas
# a intervalos aleatorios, sin reordenar): "delay X Y" reordena y TCP lo vive como pérdida.
PERFILES=(
    "sin-ruido|"
    "jitter|delay 3ms slot distribution normal 4ms 2ms"
    "wifi|delay 3ms slot distribution paretonormal 4ms 4ms"
    "wifi-perdida-1|delay 3ms slot distribution paretonormal 4ms 4ms loss 1%"
    "wifi-perdida-5|delay 3ms slot distribution paretonormal 4ms 4ms loss 5%"
)
out=resultados/$label
mkdir -p "$out"
res=$out/resumen.csv
echo "perfil;nodos;h_ms;emisores;mensajes;entregas_esperadas;entregas;perdida_pct;red_p50_ms;red_p99_ms;vuelta_p50_ms;tau_p50_ms;tau_p95_ms;tau_p99_ms;tau_max_ms;tau_p50_inicio_ms;tau_p50_final_ms;cpu_media_pct" > "$res"

./nodos.sh down
rm -f firmware/build-tap/nodos/*.log
python3 monitor.py "$out/recursos.csv" &
mon=$!
mt0=$(date +%s)
trap 'kill $mon 2>/dev/null; sudo pkill -x tcpdump || true; ./nodos.sh down' EXIT

./nodos.sh up "$NODOS"
for _ in $(seq 180); do
    up=$(cat firmware/build-tap/nodos/*.log 2>/dev/null | grep -ac "eco: conectado" || true)
    if [ "$up" -ge "$NODOS" ]; then break; fi
    sleep 1
done
echo "conectados: $up"
sleep 10

for p in "${PERFILES[@]}"; do
    name=${p%%|*} args=${p#*|}
    echo "== $name: ${args:-sin netem}"
    ./ruido.sh off
    if [ -n "$args" ]; then ./ruido.sh on "$args"; fi
    sleep 3
    caps=$out/caps_$name
    rm -rf "$caps"
    mkdir -p "$caps"
    for i in $(seq "$NODOS"); do
        sudo tcpdump -i "tapeco$i" -s 256 -B 4096 -Z "$USER" -w "$caps/$i.pcap" tcp port 53317 2>/dev/null &
    done
    sleep 3
    ws=$(($(date +%s) - mt0))
    for i in $(seq "$NODOS"); do
        mosquitto_pub -h 127.0.0.1 -t "eco/q$i/cmd" -m "bcast $((DUR_S * 1000 / H)) $H $BYTES $([ "$i" = 1 ] && echo 1 || echo 0)"
    done
    sleep $((DUR_S + 8))
    we=$(($(date +%s) - mt0))
    sudo pkill -INT -x tcpdump || true
    sleep 2
    mergecap -w "$out/ruido_$name.pcap" "$caps"/*.pcap
    rm -rf "$caps"
    cpu=$(awk -F, -v a="$ws" -v b="$we" 'NR > 1 && $1 >= a && $1 <= b {s += $7; n++} END {printf "%.1f", s / n}' "$out/recursos.csv")
    echo "$name;$(python3 analizar_todos.py "$out/ruido_$name.pcap" "$out/ruido_$name.csv" "$H");$cpu" | tee -a "$res"
done
./ruido.sh off
