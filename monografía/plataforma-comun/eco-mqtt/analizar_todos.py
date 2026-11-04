"""Difusión todos-a-todos: todos los nodos publican en eco/todos y solo q1 pide ack.

    python3 analizar_todos.py captura.pcap salida.csv h_ms  -> imprime una fila de resumen

- Fan-out del broker (cable), de todos los emisores: hasta el último receptor, max_i Ti - T0.
- Delay de aplicación a aplicación (tau), de los mensajes de q1 hasta el último receptor:
      tau = vuelta_p50 / 2 + max_i (Ti - T0 + vuelta_i / 2)
  con vuelta_i = Ai - Ti medida en esta misma corrida: acá el emisor también compite por la CPU.
"""
import sys
from analizar_difusion import leer, pct

PROBE = 1
t0, deliv, ack, nodes = leer(sys.argv[1])
h = sys.argv[3]

expected = got = 0
cable = []
for key, ts in t0.items():
    exp = nodes - {key[0]}
    d = deliv.get(key, {})
    expected += len(exp)
    got += len(d)
    if exp <= d.keys():
        cable.append((max(d.values()) - ts) * 1e3)

probe = sorted((ts, key) for key, ts in t0.items() if key[0] == PROBE)
turn = [(ack[k][r] - deliv[k][r]) * 1e3 for _, k in probe for r in ack.get(k, {}) if r in deliv.get(k, {})]
s = pct(turn, 50) / 2
tau = []  # (t, tau) de los mensajes de q1 que llegaron y volvieron de todos
with open(sys.argv[2], "w") as out:
    out.write("seq,t_s,tau_ms,cable_ms\n")
    for ts, k in probe:
        d, a = deliv.get(k, {}), ack.get(k, {})
        if not (nodes - {PROBE}) <= (d.keys() & a.keys()):
            continue
        v = s + max((d[r] - ts) * 1e3 + (a[r] - d[r]) * 1e3 / 2 for r in d)
        tau.append((ts, v))
        out.write(f"{k[1]},{ts - probe[0][0]:.3f},{v:.3f},{(max(d.values()) - ts) * 1e3:.3f}\n")

vals = [v for _, v in tau]
q = max(1, len(tau) // 4)  # primer y último cuarto: si la PC no da abasto, tau crece con el tiempo
print(";".join(map(str, [
    len(nodes), h, len({k[0] for k in t0}), len(t0), expected, got,
    f"{100 * (expected - got) / max(expected, 1):.2f}",
    f"{pct(cable, 50):.3f}", f"{pct(cable, 99):.3f}", f"{pct(turn, 50):.3f}",
    *(f"{pct(vals, p):.3f}" for p in (50, 95, 99, 100)),
    f"{pct(vals[:q], 50):.3f}", f"{pct(vals[-q:], 50):.3f}",
])))
