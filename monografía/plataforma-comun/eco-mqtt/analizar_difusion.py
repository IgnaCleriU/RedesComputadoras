"""Fan-out de una difusión MQTT a partir de la captura en br-eco (un solo reloj: el de la PC).

    python3 analizar_difusion.py captura.pcap salida.csv  -> imprime una fila de resumen

Para cada mensaje k que publica el emisor en eco/todos:
  T0      llega a la PC el PUBLISH del emisor
  Ti      mosquitto le manda el PUBLISH al receptor i
  Ai      llega a la PC el ack del receptor i (eco/q<i>/ack)
fan-out al receptor i = Ti - T0; a todos = max_i Ti - T0; vuelta en el ESP32 = Ai - Ti.
"""
import subprocess, sys

PC = "10.10.0.1"


def node(ip):
    o = list(map(int, ip.split(".")))
    return o[2] * 256 + o[3] - 10


def pct(v, p):
    v = sorted(v)
    return v[max(0, -(-len(v) * p // 100) - 1)] if v else float("nan")


def publishes(pcap):
    """(t, ip origen, ip destino, tópico, payload) de cada PUBLISH de la captura.

    Los flujos TCP se arman a mano por número de secuencia en lugar de usar el disector MQTT de
    tshark, que con una retransmisión o un hueco pierde la alineación y deja de ver mensajes. El
    tiempo de cada mensaje es la primera vez que se capturó su último byte.
    """
    rows = subprocess.run(
        ["tshark", "-r", pcap, "-Y", "tcp.len > 0", "-T", "fields", "-E", "separator=;",
         "-e", "frame.time_epoch", "-e", "ip.src", "-e", "ip.dst", "-e", "tcp.srcport",
         "-e", "tcp.dstport", "-e", "tcp.seq_raw", "-e", "tcp.payload"],
        capture_output=True, text=True, check=True).stdout.splitlines()
    flows = {}  # (src, sport, dst, dport) -> {seq: (t, datos)}, la primera captura de cada seq
    for line in rows:
        t, src, dst, sp, dp, seq, data = line.split(";")
        flows.setdefault((src, sp, dst, dp), {}).setdefault(int(seq), (float(t), bytes.fromhex(data)))
    out = []
    for (src, _, dst, _), segs in flows.items():
        buf, ends, times, pos, i = bytearray(), [], [], None, 0
        for seq in sorted(segs):
            t, b = segs[seq]
            if pos is not None and seq > pos:  # hueco nunca capturado: se retoma en este segmento
                buf, ends, times, pos, i = bytearray(), [], [], None, 0
            if pos is None:
                pos = seq
            if seq + len(b) <= pos:  # retransmisión de algo que ya está
                continue
            buf += b[pos - seq:]
            pos = seq + len(b)
            ends.append(len(buf))
            times.append(t)
            while i < len(buf):  # mensajes MQTT completos: cabecera, longitud restante (varint)
                j, rl, mult = i + 1, 0, 1
                while j < len(buf) and buf[j] & 0x80:
                    rl, mult, j = rl + (buf[j] & 0x7F) * mult, mult * 128, j + 1
                if j >= len(buf):
                    break
                rl += buf[j] * mult
                fin = j + 1 + rl
                if fin > len(buf):
                    break
                if buf[i] >> 4 == 3:  # PUBLISH
                    tl = int.from_bytes(buf[j + 1:j + 3], "big")
                    k = j + 3 + tl + (2 if (buf[i] >> 1) & 3 else 0)
                    tm = times[next(n for n, e in enumerate(ends) if e >= fin)]
                    out.append((tm, src, dst, buf[j + 3:j + 3 + tl].decode(errors="replace"), bytes(buf[k:fin])))
                i = fin
    return out


def leer(pcap):
    """T0 por (emisor, seq), entregas y acks por (emisor, seq) -> {receptor: t}, y los nodos vistos."""
    t0, deliv, ack, nodes = {}, {}, {}, set()
    for t, src, dst, topic, b in publishes(pcap):
        nodes |= {node(ip) for ip in (src, dst) if ip != PC}
        if len(b) < 8:
            continue
        key = (int.from_bytes(b[4:8], "little"), int.from_bytes(b[:4], "little"))
        if topic == "eco/todos" and src != PC:
            t0[key] = min(t, t0.get(key, t))
        elif topic == "eco/todos" and dst != PC and node(dst) != key[0]:
            d = deliv.setdefault(key, {})
            d[node(dst)] = min(t, d.get(node(dst), t))
        elif topic.endswith("/ack") and src != PC:
            a = ack.setdefault(key, {})
            a[node(src)] = min(t, a.get(node(src), t))
    return t0, deliv, ack, nodes


if __name__ == "__main__":
    t0, deliv, ack, _ = leer(sys.argv[1])
    receivers = {r for d in deliv.values() for r in d}
    fan, last, turn = [], [], []
    with open(sys.argv[2], "w") as out:
        out.write("emisor,seq,receptor,fanout_us,vuelta_us\n")
        for key, ts in sorted(t0.items()):
            d = deliv.get(key, {})
            for r, ti in d.items():
                f = (ti - ts) * 1e3
                fan.append(f)
                a = ack.get(key, {}).get(r)
                if a is not None:
                    turn.append((a - ti) * 1e3)
                out.write(f"{key[0]},{key[1]},{r},{f * 1e3:.0f},{'' if a is None else round((a - ti) * 1e6)}\n")
            if len(d) == len(receivers):
                last.append((max(d.values()) - ts) * 1e3)

    exp = len(t0) * len(receivers)
    print(";".join(map(str, [
        len(receivers) + 1, len(t0), exp, len(fan), f"{100 * (exp - len(fan)) / max(exp, 1):.2f}",
        *(f"{pct(fan, p):.3f}" for p in (50, 99)),
        *(f"{pct(last, p):.3f}" for p in (50, 95, 99, 100)),
        f"{pct(turn, 50):.3f}", f"{pct(last, 50) + pct(turn, 50):.3f}",
    ])))
