"""RAM, CPU y RTT contra cantidad de nodos: python3 graficar_escala.py resultados/escala"""
import csv, os, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1]
lat = list(csv.DictReader(open(os.path.join(d, "multi.csv"))))
por_n = defaultdict(list)
for r in csv.DictReader(open(os.path.join(d, "recursos.csv"))):
    por_n[int(r["qemus"])].append(r)
ns = [int(r["nodos"]) for r in lat]
# Por escalón: el peor momento de memoria y la CPU mediana.
rss = [max(int(x["qemu_rss_mb"]) for x in por_n[n]) / 1024 for n in ns]
disp = [min(int(x["mem_disp_mb"]) for x in por_n[n]) / 1024 for n in ns]
swap = [max(int(x["swap_usado_mb"]) for x in por_n[n]) / 1024 for n in ns]
cpu = [sorted(float(x["cpu_pct"]) for x in por_n[n])[len(por_n[n]) // 2] for n in ns]

fig, (a, b, c) = plt.subplots(1, 3, figsize=(16, 4.5))
a.plot(ns, rss, "o-", label="RSS de los QEMU")
a.plot(ns, disp, "o-", label="RAM disponible")
a.plot(ns, swap, "o-", label="swap usado")
a.set_xlabel("nodos"); a.set_ylabel("GiB"); a.set_title("Memoria"); a.legend(); a.grid(alpha=0.3)
b.plot(ns, cpu, "o-")
b.set_xlabel("nodos"); b.set_ylabel("% de los 12 hilos"); b.set_title("CPU de la PC (mediana)")
b.set_ylim(0, 100); b.grid(alpha=0.3)
for k, lab in (("p50_ms", "p50"), ("p99_ms", "p99"), ("max_ms", "máx")):
    c.plot(ns, [float(r[k]) for r in lat], "o-", label=lab)
c.set_yscale("log"); c.set_xlabel("nodos"); c.set_ylabel("RTT [ms]")
c.set_title("Latencia con todos los nodos a la vez"); c.legend(); c.grid(alpha=0.3, which="both")
fig.tight_layout()
fig.savefig(os.path.join(d, "escala.png"), dpi=120)
