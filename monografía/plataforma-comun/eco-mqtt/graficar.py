"""CDF del RTT de cada corrida: python3 graficar.py resultados/real resultados/qemu"""
import csv, sys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

dirs = sys.argv[1:]
fig, axes = plt.subplots(2, 4, figsize=(16, 7), sharey=True)
for row, qos in enumerate((0, 1)):
    for col, size in enumerate((16, 256, 1024, 4096)):
        ax = axes[row][col]
        for d in dirs:
            with open(os.path.join(d, f"lat_{size}B_qos{qos}.csv")) as f:
                v = sorted(int(r["rtt_us"]) / 1000 for r in csv.DictReader(f))
            ax.step(v, [(i + 1) / len(v) for i in range(len(v))], where="post", label=os.path.basename(d))
        ax.set_xscale("log")
        ax.set_title(f"{size} B, QoS {qos}")
        ax.grid(True, which="both", alpha=0.3)
        if row == 1:
            ax.set_xlabel("RTT [ms]")
    axes[row][0].set_ylabel("fracción de pings")
axes[0][0].legend()
fig.tight_layout()
fig.savefig("resultados/cdf_rtt.png", dpi=120)
