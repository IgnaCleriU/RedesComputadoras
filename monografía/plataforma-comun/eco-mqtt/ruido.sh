#!/usr/bin/env bash
# Ruido de red con netem en el enlace de cada nodo, en los dos sentidos (necesita sudo):
#   ./ruido.sh on "delay 5ms 5ms loss 1%"   hacia el nodo: netem en la salida de tapeco<i>;
#                                            desde el nodo: la entrada de la tap se redirige a
#                                            ifbeco<i>, que tiene el mismo netem en su salida
#   ./ruido.sh off
set -euo pipefail
taps=$(ip -o link show | grep -o 'tapeco[0-9]*' | sort -u || true)

case "${1:-}" in
on)
    sudo modprobe ifb numifbs=0
    for t in $taps; do
        ifb=ifb${t#tap}
        ip link show "$ifb" &>/dev/null || sudo ip link add "$ifb" type ifb
        sudo ip link set "$ifb" up
        # Ojo: "delay X Y" (jitter) reordena paquetes, aun con una pfifo hija; para variar el
        # retardo sin reordenar, usar "slot" (libera en ráfagas, en orden, como el 802.11).
        for dev in "$t" "$ifb"; do
            # shellcheck disable=SC2086 # $2 son varios argumentos de netem
            sudo tc qdisc replace dev "$dev" root netem $2
        done
        if ! tc qdisc show dev "$t" ingress | grep -q ingress; then
            sudo tc qdisc add dev "$t" handle ffff: ingress
            sudo tc filter add dev "$t" parent ffff: matchall action mirred egress redirect dev "$ifb"
        fi
    done
    ;;
off)
    for t in $taps; do
        sudo tc qdisc del dev "$t" root 2>/dev/null || true
        sudo tc qdisc del dev "$t" ingress 2>/dev/null || true
    done
    for i in $(ip -o link show | grep -o 'ifbeco[0-9]*' | sort -u); do sudo ip link del "$i"; done
    ;;
*)
    echo "uso: $0 on \"<parámetros de netem>\" | off" >&2
    exit 2
    ;;
esac
