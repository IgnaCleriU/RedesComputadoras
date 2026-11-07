#!/usr/bin/env bash
# Aplica las condiciones de red del experimento a cada tap, en ambos sentidos.
#   pérdida: LOSS % en cada sentido
#   latencia: RTT_MS de ida y vuelta extra (RTT_MS/2 por sentido)
# Uso: sudo ./infra/net/netem.sh <loss%> <rtt_ms> [N=8]
#      sudo ./infra/net/netem.sh clear [N=8]
# Lo llama el runner antes de cada corrida (y clear al terminar).
#
# Semántica:
#  - "RTT de X ms" es X ms más de ida y vuelta: X/2 en el tap y X/2 en su ifb.
#  - La pérdida se aplica en cada sentido por separado (5 % = 5 % de lo que sube
#    y 5 % de lo que baja), aleatoria e independiente por paquete, sin ráfagas.
#  - El retardo es fijo, sin jitter.
#  - netem actúa antes del bridge para lo que sube (el paquete perdido no aparece
#    en la captura) y después para lo que baja (aparece pero no llega al nodo).
set -euo pipefail
if [[ "${1:-}" == "clear" ]]; then
  N="${2:-8}"
  for ((i = 0; i < N; i++)); do
    tc qdisc del dev "tap$i" root 2>/dev/null || true
    tc qdisc del dev "ifb$i" root 2>/dev/null || true
  done
  exit 0
fi
LOSS="${1:?loss%}"; RTT="${2:?rtt_ms}"; N="${3:-8}"
HALF=$(awk -v r="$RTT" 'BEGIN { printf "%.1f", r / 2 }')

for ((i = 0; i < N; i++)); do
  for dev in "tap$i" "ifb$i"; do   # tap: red -> nodo ; ifb: nodo -> red
    tc qdisc del dev "$dev" root 2>/dev/null || true
    if [[ "$LOSS" != "0" || "$RTT" != "0" ]]; then
      # limit alto para que netem no descarte por cola llena con 200 ms
      tc qdisc add dev "$dev" root netem delay "${HALF}ms" loss "${LOSS}%" limit 10000
    fi
  done
done
echo "netem: loss=${LOSS}% rtt=+${RTT}ms en tap0..tap$((N - 1))"
