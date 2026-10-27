#!/usr/bin/env bash
# Crea el bridge br-exp (10.10.0.1/24) con tap0..tapN-1 para las instancias QEMU,
# más un ifbK por tap para aplicar netem también al tráfico que sube del nodo.
# Uso: sudo ./infra/net/setup.sh [N=8] [usuario dueño de los taps=$SUDO_USER]
# Se corre una vez por arranque de la máquina; infra/net/teardown.sh lo deshace.
#
#   br-exp 10.10.0.1/24       ← dumpcap captura acá; la IP es la del servidor
#     ├── tap0 ── QEMU nodo 1 (10.10.0.11)    netem en tap0 (host → nodo)
#     │            └─ ifb0 ◄── ingreso de tap0             ifb0 (nodo → host)
#     └── ...
#
# Por qué TAP y no la red "user" de QEMU (slirp): slirp termina el TCP del guest
# dentro de QEMU y abre otra conexión desde el host, así que la captura vería los
# segmentos del kernel de Linux y no los de lwIP del ESP32. Con TAP + bridge las
# tramas del ESP32 llegan al host tal cual.
#
# Por qué ifb: tc solo puede aplicar netem a lo que SALE de una interfaz. Para el
# tap, salir es ir hacia el nodo. Lo que manda el nodo ENTRA al tap: se lo redirige
# a un ifb, donde ese tráfico "sale" y se le puede poner netem (infra/net/netem.sh).
#
# Si ufw está activo descarta lo que entra por br-exp (los nodos no reciben la
# respuesta SNTP). Hace falta: sudo ufw allow in on br-exp
set -euo pipefail
N="${1:-8}"
OWNER="${2:-${SUDO_USER:-$USER}}"

modprobe tun
modprobe bridge
modprobe sch_netem
modprobe ifb numifbs=0 || true   # numifbs=0: que no cree ifb sueltos por su cuenta

if ! ip link show br-exp &>/dev/null; then
  ip link add br-exp type bridge
  ip addr add 10.10.0.1/24 dev br-exp
fi
# Sin STP ni retardo de forwarding: los taps reenvían apenas se levantan
ip link set br-exp type bridge stp_state 0 forward_delay 0
ip link set br-exp up

# Que el firewall del host no filtre el tráfico de puenteo
sysctl -qw net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
sysctl -qw net.bridge.bridge-nf-call-ip6tables=0 2>/dev/null || true
sysctl -qw net.ipv6.conf.br-exp.disable_ipv6=1 || true

for ((i = 0; i < N; i++)); do
  tap="tap$i"; ifb="ifb$i"
  if ! ip link show "$tap" &>/dev/null; then
    # Dueño el usuario: QEMU abre el tap sin root
    ip tuntap add dev "$tap" mode tap user "$OWNER"
  fi
  sysctl -qw "net.ipv6.conf.$tap.disable_ipv6=1" || true
  ip link set "$tap" master br-exp
  ip link set "$tap" up

  if ! ip link show "$ifb" &>/dev/null; then
    ip link add "$ifb" type ifb
  fi
  ip link set "$ifb" up
  # Lo que entra al tap (nodo -> red) se redirige a ifb, donde se aplica netem
  tc qdisc del dev "$tap" ingress 2>/dev/null || true
  tc qdisc add dev "$tap" handle ffff: ingress
  tc filter add dev "$tap" parent ffff: matchall action mirred egress redirect dev "$ifb"
done

# dumpcap corre como usuario (grupo wireshark); el resto no necesita root.
echo "Red lista: br-exp 10.10.0.1/24, tap0..tap$((N - 1)) (dueño: $OWNER)"
ip -br link show master br-exp
