#!/usr/bin/env bash
# Red de los nodos del experimento de sincronización: puente br-kur y una tap por nodo.
# Se ejecuta como root (sudo). Las taps quedan a nombre del usuario que invoca con sudo,
# para que QEMU las abra sin privilegios.
#   sudo ./red.sh up N          puente br-kur (10.10.0.1/24) y taps tapk1..N
#   sudo ./red.sh netem "args"  mismos argumentos de netem en los dos sentidos de cada nodo
#   sudo ./red.sh clear         saca netem y borra los ifbk<i>
#   sudo ./red.sh down          clear, y borra las taps y el puente
# Basado en nodos.sh y ruido.sh de plataforma-comun/eco-mqtt.
set -euo pipefail

BR=br-kur
PREV=/run/kur-port-start-prev # valor anterior de ip_unprivileged_port_start

if [ "$(id -u)" != 0 ]; then
    echo "red.sh necesita root: sudo $0 $*" >&2
    exit 1
fi

taps() { ip -o link show | grep -o 'tapk[0-9]*' | sort -u || true; }

case "${1:-}" in
up)
    n=${2:?uso: $0 up N}
    dueno=${SUDO_USER:-${USER:-root}}
    if ! ip link show "$BR" &>/dev/null; then
        ip link add "$BR" type bridge
        ip addr add 10.10.0.1/24 dev "$BR"
        ip link set "$BR" up
    fi
    for i in $(seq "$n"); do
        ip link show "tapk$i" &>/dev/null || ip tuntap add "tapk$i" mode tap user "$dueno"
        ip link set "tapk$i" master "$BR" up
    done
    # El servidor SNTP escucha en el puerto 123 y corre sin privilegios: se baja el umbral de
    # puertos privilegiados. El valor anterior se guarda y `down` lo restaura.
    actual=$(sysctl -n net.ipv4.ip_unprivileged_port_start)
    if [ "$actual" -gt 123 ]; then
        [ -f "$PREV" ] || echo "$actual" >"$PREV"
        sysctl -qw net.ipv4.ip_unprivileged_port_start=123
    fi
    ;;
netem)
    args=${2:?uso: $0 netem \"<parámetros de netem>\"}
    modprobe ifb numifbs=0
    for t in $(taps); do
        ifb=ifb${t#tap} # tapk3 -> ifbk3
        ip link show "$ifb" &>/dev/null || ip link add "$ifb" type ifb
        ip link set "$ifb" up
        # Hacia el nodo: netem en la salida de la tap. Desde el nodo: la entrada de la tap se
        # redirige a ifbk<i>, que tiene el mismo netem en su salida.
        for dev in "$t" "$ifb"; do
            # shellcheck disable=SC2086 # $args son varios argumentos de netem
            tc qdisc replace dev "$dev" root netem $args
        done
        if ! tc qdisc show dev "$t" ingress | grep -q ingress; then
            tc qdisc add dev "$t" handle ffff: ingress
            tc filter add dev "$t" parent ffff: matchall action mirred egress redirect dev "$ifb"
        fi
    done
    ;;
clear)
    for t in $(taps); do
        tc qdisc del dev "$t" root 2>/dev/null || true
        tc qdisc del dev "$t" ingress 2>/dev/null || true
    done
    for i in $(ip -o link show | grep -o 'ifbk[0-9]*' | sort -u || true); do ip link del "$i"; done
    ;;
down)
    "$0" clear
    for t in $(taps); do ip link del "$t"; done
    if ip link show "$BR" &>/dev/null; then ip link del "$BR"; fi
    if [ -f "$PREV" ]; then
        sysctl -qw net.ipv4.ip_unprivileged_port_start="$(cat "$PREV")"
        rm -f "$PREV"
    fi
    ;;
*)
    echo "uso: $0 up N | netem \"<parámetros>\" | clear | down" >&2
    exit 2
    ;;
esac
