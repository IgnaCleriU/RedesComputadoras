#!/usr/bin/env bash
# Borra todo lo que creó setup.sh.  Uso: sudo ./infra/net/teardown.sh [N=8]
set -uo pipefail
N="${1:-8}"
for ((i = 0; i < N; i++)); do
  ip link del "tap$i" 2>/dev/null
  ip link del "ifb$i" 2>/dev/null
done
ip link del br-exp 2>/dev/null
echo "Red del experimento eliminada"
