"""Delay de difusión contra cantidad de nodos: python3 graficar_difusion.py resultados/difusion

Delay de aplicación a aplicación de cada mensaje, hasta el último receptor:
    D = s + max_i (fan-out_i + vuelta_i / 2)
con s = mitad de la vuelta mediana con 2 nodos (el emisor publica sin competencia de CPU) y la
vuelta de cada receptor repartida por mitades entre subida y bajada por su pila.
"""
import csv, glob, os, re, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1]


def pct(v, p):
    v = sorted(v)
    return v[max(0, -(-len(v) * p // 100) - 1)]


runs = {}
for f in glob.glob(os.path.join(d, "difusion_*.csv")):
    n = int(re.search(r"_(\d+)\.csv", f).group(1))
    msgs = defaultdict(list)
    for r in csv.DictReader(open(f)):
        if r["vuelta_us"]:
            msgs[r["seq"]].append((int(r["fanout_us"]) / 1e3, int(r["vuelta_us"]) / 1e3))
    runs[n] = msgs
ns = sorted(runs)
s = pct([v for m in runs[ns[0]].values() for _, v in m], 50) / 2

wire = {n: [max(f for f, _ in m) for m in runs[n].values()] for n in ns}
turn = {n: [v for m in runs[n].values() for _, v in m] for n in ns}
delay = {n: [s + max(f + v / 2 for f, v in m) for m in runs[n].values()] for n in ns}

print(f"s (emisor) = {s:.2f} ms")
print("| nodos | fan-out del broker a todos p50 / p99 [ms] | vuelta en el ESP32 p50 [ms] | delay a todos p50 / p95 / p99 / máx [ms] |")
print("|---|---|---|---|")
for n in ns:
    print(f"| {n} | {pct(wire[n], 50):.2f} / {pct(wire[n], 99):.2f} | {pct(turn[n], 50):.2f} | "
          + " / ".join(f"{pct(delay[n], p):.1f}" for p in (50, 95, 99, 100)) + " |")

fig, ax = plt.subplots(figsize=(8, 4.5))
pos = range(len(ns))
for vals, color, lab, off in ((wire, "C0", "fan-out del broker (cable)", -0.2),
                              (delay, "C1", "delay de aplicación a aplicación", 0.2)):
    bp = ax.boxplot([vals[n] for n in ns], positions=[p + off for p in pos], widths=0.35,
                    whis=(1, 99), showfliers=False, patch_artist=True)
    for b in bp["boxes"]:
        b.set_facecolor(color)
        b.set_alpha(0.6)
    ax.plot([], [], color=color, lw=8, alpha=0.6, label=lab)
ax.set_xticks(list(pos), [str(n) for n in ns])
ax.set_xlabel("nodos (1 emisor, N-1 receptores)")
ax.set_ylabel("tiempo hasta el último receptor [ms]")
ax.set_title("Difusión MQTT entre ESP32 emulados (cajas: p25-p75, bigotes: p1-p99)")
ax.legend(loc="upper left")
ax.grid(alpha=0.3, axis="y")
fig.tight_layout()
fig.savefig(os.path.join(d, "difusion.png"), dpi=120)
