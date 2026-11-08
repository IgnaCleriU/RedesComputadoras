"""tau en el tiempo y carga contra h: python3 graficar_todos.py resultados/todos"""
import csv, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = sys.argv[1]
res = list(csv.DictReader(open(os.path.join(d, "resumen.csv")), delimiter=";"))
fig, (a, b) = plt.subplots(1, 2, figsize=(14, 4.5))
for r in res:
    rows = list(csv.DictReader(open(os.path.join(d, f"todos_h{r['h_ms']}.csv"))))
    if rows:
        a.plot([float(x["t_s"]) for x in rows], [float(x["tau_ms"]) for x in rows], ".-", ms=3,
               label=f"h = {r['h_ms']} ms")
a.set_yscale("log"); a.set_xlabel("tiempo desde el primer mensaje de q1 [s]")
a.set_ylabel("tau de q1 a los 39 restantes [ms]"); a.set_title(f"{res[0]['nodos']} nodos publicando a la vez")
a.legend(); a.grid(alpha=0.3, which="both")
hs = [r["h_ms"] for r in res]
b.bar([x - 0.2 for x in range(len(hs))], [float(r["cpu_media_pct"]) for r in res], 0.4, label="CPU de la PC [%]")
b.bar([x + 0.2 for x in range(len(hs))], [100 - float(r["perdida_pct"]) for r in res], 0.4,
      label="entregas a tiempo [%]")
b.set_xticks(range(len(hs)), hs); b.set_xlabel("h [ms]"); b.set_ylim(0, 105)
b.set_title("Carga y entregas"); b.legend(loc="lower left"); b.grid(alpha=0.3, axis="y")
fig.tight_layout()
fig.savefig(os.path.join(d, "todos.png"), dpi=120)
