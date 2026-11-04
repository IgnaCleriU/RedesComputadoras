"""CDF de tau por perfil de ruido: python3 graficar_ruido.py resultados/ruido"""
import csv, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1]
res = list(csv.DictReader(open(os.path.join(d, "resumen.csv")), delimiter=";"))
fig, ax = plt.subplots(figsize=(9, 4.5))
for r in res:
    v = sorted(float(x["tau_ms"]) for x in csv.DictReader(open(os.path.join(d, f"ruido_{r['perfil']}.csv"))))
    ax.step(v, [(i + 1) / len(v) for i in range(len(v))], where="post",
            label=f"{r['perfil']} (p50 {float(r['tau_p50_ms']):.0f} ms)")
ax.set_xscale("log")
ax.set_xlabel("tau de q1 a los demás nodos [ms]")
ax.set_ylabel("fracción de mensajes")
ax.set_title(f"{res[0]['nodos']} nodos publicando cada {res[0]['h_ms']} ms, ruido en cada enlace")
ax.legend(loc="lower right")
ax.grid(alpha=0.3, which="both")
fig.tight_layout()
fig.savefig(os.path.join(d, "ruido.png"), dpi=120)
