"""Gráficos y tablas del experimento principal.

Uso (desde experimento/):
    uv run --with pandas --with matplotlib --with scipy analysis/figuras.py [datos/principal] [docs/resultados/figs]

Lee summary.csv, metrics.csv y los readings.csv de cada corrida, y deja
PNG y tablas (tablas.md) en la carpeta de salida (por defecto docs/resultados/figs/).

Selección de datos: BASE es la configuración de referencia (8 nodos, TLS, sin
pérdida ni RTT, protobuf, sin nodelay; período 10 s para http_req y 1 s para el
resto). sel(df, t, **cambios) filtra el transporte t con la base y los cambios
pedidos; val() devuelve (media, desvío) de una métrica de summary.csv.

Salidas:
  01_bytes_por_lectura_tls     bytes por lectura de los 4 transportes, con y sin TLS
  02_composicion_bytes (+csv)  payload / handshake amortizado / resto (encabezados, TLS, ACKs)
  03_comparacion_10s           los 4 transportes con período de 10 s
  04..08                       una línea por transporte para cada nivel de un factor
  09..12                       CDF de la latencia de cada lectura (base, 10 s, 5 % pérdida, 200 ms RTT)
  13_modelo_costo (+csv)       ajuste bytes por lectura = v + C / n
  tablas.md                    tabla por configuración, IC 95 % y tests de Welch

Corrección del reloj: el SNTP de lwIP deja al nodo atrasado RTT/2 (ver
firmware/main/timesync.c), así que con RTT agregado las latencias se corrigen
restando RTT/2 (fig 07 con adjust, fig 12 con shift_ms).
"""
import glob
import json
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

RUNS = sys.argv[1] if len(sys.argv) > 1 else "datos/principal"
OUT = sys.argv[2] if len(sys.argv) > 2 else "docs/resultados/figs"
os.makedirs(OUT, exist_ok=True)

# Paleta categórica validada (orden fijo; color = transporte en todos los gráficos)
TR = ["mqtt0", "mqtt1", "http_reuse", "http_req"]
COL = {"mqtt0": "#2a78d6", "mqtt1": "#eb6834", "http_reuse": "#1baf7a", "http_req": "#eda100"}
MRK = {"mqtt0": "o", "mqtt1": "s", "http_reuse": "^", "http_req": "D"}
NAME = {
    "mqtt0": "MQTT QoS 0",
    "mqtt1": "MQTT QoS 1",
    "http_reuse": "HTTP reutilizado",
    "http_req": "HTTP por request",
}
SURF, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"

plt.rcParams.update({
    "figure.facecolor": SURF, "axes.facecolor": SURF, "savefig.facecolor": SURF,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "axes.axisbelow": True,
    "font.size": 10, "axes.titlesize": 11, "axes.titleweight": "bold", "legend.frameon": False,
    "lines.linewidth": 2, "lines.markersize": 7,
})

S = pd.read_csv(os.path.join(RUNS, "summary.csv"))
M = pd.read_csv(os.path.join(RUNS, "metrics.csv"))
for df in (S, M):
    for c in ("tls", "nodelay"):
        df[c] = df[c].astype(str).str.lower() == "true"
M = M[M["valid"].astype(str).str.lower() == "true"]

BASE = dict(nodes=8, tls=True, loss_pct=0, rtt_ms=0, serialization="pb", nodelay=False)


def base_period(t):
    return 10000 if t == "http_req" else 1000


def sel(df, t, **over):
    q = dict(BASE, period_ms=base_period(t))
    q.update(over)
    m = df["transport"] == t
    for k, v in q.items():
        m &= df[k] == v
    return df[m]


def row(t, **over):
    r = sel(S, t, **over)
    return r.iloc[0] if len(r) else None


def val(t, col, **over):
    r = row(t, **over)
    if r is None:
        return np.nan, np.nan
    return r[col + "_mean"], r[col + "_std"]


def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, name), dpi=160)
    plt.close(fig)
    print("fig", name)


def bar_labels(ax, bars, vals, fmt):
    for b, v in zip(bars, vals):
        if np.isfinite(v):
            ax.annotate(fmt.format(v), (b.get_x() + b.get_width() / 2, b.get_height()),
                        xytext=(0, 3), textcoords="offset points", ha="center", va="bottom",
                        fontsize=8, color=INK2)


# ---------------------------------------------------------------- 1. bytes por lectura, TLS sí/no
def fig_bytes_tls():
    fig, ax = plt.subplots(figsize=(7.5, 4))
    x = np.arange(len(TR))
    w = 0.36
    for i, tls in enumerate([False, True]):
        v = [val(t, "ip_bytes_per_reading", tls=tls) for t in TR]
        bars = ax.bar(x + (i - 0.5) * w, [a for a, _ in v], w * 0.92, yerr=[b for _, b in v],
                      color=[COL[t] for t in TR], alpha=1.0 if tls else 0.45,
                      hatch=None if tls else "///", edgecolor=SURF, linewidth=0, capsize=2,
                      error_kw=dict(ecolor=INK2, lw=0.8))
        bar_labels(ax, bars, [a for a, _ in v], "{:.0f}")
    ax.set_xticks(x, [NAME[t] + ("\n(período 10 s)" if t == "http_req" else "\n(período 1 s)") for t in TR])
    ax.set_ylabel("bytes IP por lectura entregada")
    ax.set_title("Bytes en la red por lectura (8 nodos, protobuf)")
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(facecolor="#888", alpha=0.45, hatch="///", label="sin TLS"),
                       Patch(facecolor="#888", label="con TLS")], loc="upper left")
    save(fig, "01_bytes_por_lectura_tls.png")


# ---------------------------------------------------------------- 2. composición de los bytes
def fig_composicion():
    rows = []
    for t in TR:
        for tls in (False, True):
            r = row(t, tls=tls)
            if r is None:
                continue
            deliv = r["delivered_unique_mean"]
            total = r["ip_bytes_per_reading_mean"]
            hs = r["handshake_bytes_per_conn_mean"] * r["connections_mean"] / deliv if deliv else np.nan
            pay = r["payload_bytes_mean_mean"]
            rows.append(dict(t=t, tls=tls, payload=pay, handshake=hs, resto=total - pay - hs, total=total))
    d = pd.DataFrame(rows)
    d.to_csv(os.path.join(OUT, "composicion_bytes.csv"), index=False)
    fig, ax = plt.subplots(figsize=(8, 5.2))
    labels = [f"{NAME[r.t]}\n{'TLS' if r.tls else 'sin TLS'}" for r in d.itertuples()]
    y = np.arange(len(d))[::-1]
    left = np.zeros(len(d))
    parts = [("payload", "#2a78d6", "payload de la aplicación"),
             ("resto", "#9ec5f4", "encabezados MQTT/HTTP, TCP/IP, TLS y ACK"),
             ("handshake", "#eb6834", "handshake TCP+TLS amortizado")]
    for col, c, lab in parts:
        ax.barh(y, d[col], 0.6, left=left, color=c, edgecolor=SURF, linewidth=2, label=lab)
        left += d[col].fillna(0).values
    for yi, tot in zip(y, d["total"]):
        ax.annotate(f"{tot:.0f} B", (tot, yi), xytext=(4, 0), textcoords="offset points",
                    va="center", fontsize=8, color=INK2)
    ax.set_yticks(y, labels, fontsize=8)
    ax.set_xlabel("bytes IP por lectura")
    ax.set_title("De qué están hechos los bytes de cada lectura")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=3, fontsize=8)
    ax.grid(axis="y", visible=False)
    ax.set_xlim(right=d["total"].max() * 1.12)
    save(fig, "02_composicion_bytes.png")


# ---------------------------------------------------------------- 3. comparación justa a 10 s
def fig_10s():
    fig, axs = plt.subplots(1, 3, figsize=(10, 3.6))
    x = np.arange(len(TR))
    for ax, (col, lab, fmt) in zip(axs, [("ip_bytes_per_reading", "bytes IP por lectura", "{:.0f}"),
                                          ("packets_per_reading", "paquetes por lectura", "{:.1f}"),
                                          ("latency_ms_p50", "latencia p50 (ms)", "{:.0f}")]):
        v = [val(t, col, period_ms=10000) for t in TR]
        bars = ax.bar(x, [a for a, _ in v], 0.6, yerr=[b for _, b in v], color=[COL[t] for t in TR],
                      capsize=2, error_kw=dict(ecolor=INK2, lw=0.8))
        bar_labels(ax, bars, [a for a, _ in v], fmt)
        ax.set_xticks(x, [NAME[t].replace(" ", "\n", 1) for t in TR], fontsize=8)
        ax.set_title(lab)
        if col == "latency_ms_p50":
            ax.set_yscale("log")
    fig.suptitle("Los cuatro transportes con el mismo período (10 s, 8 nodos, TLS)", fontweight="bold")
    save(fig, "03_comparacion_10s.png")


# ---------------------------------------------------------------- líneas por factor
def fig_factor(factor, levels, metrics, name, title, logx=False, xlab=None, adjust=None):
    fig, axs = plt.subplots(1, len(metrics), figsize=(4.2 * len(metrics), 3.6))
    axs = np.atleast_1d(axs)
    for ax, (col, lab, logy) in zip(axs, metrics):
        for t in TR:
            xs, ys, es = [], [], []
            for lv in levels:
                m, s = val(t, col, **{factor: lv})
                if adjust and col.startswith("latency"):
                    m = adjust(lv, m)
                if np.isfinite(m):
                    xs.append(lv); ys.append(m); es.append(s)
            if xs:
                ax.errorbar(xs, ys, yerr=es, color=COL[t], marker=MRK[t], label=NAME[t], capsize=2,
                            markeredgecolor=SURF, markeredgewidth=1.5, elinewidth=0.8)
        ax.set_title(lab)
        ax.set_xlabel(xlab or factor)
        if logx:
            ax.set_xscale("log")
        if logy:
            ax.set_yscale("log")
        ax.set_xticks(levels, [str(l) for l in levels])
    axs[0].legend(fontsize=8)
    fig.suptitle(title, fontweight="bold")
    save(fig, name)


# ---------------------------------------------------------------- CDF de latencia por lectura
# Junta los readings.csv de las corridas que coinciden con la configuración y se
# queda con la primera llegada de cada (esp_id, seq), igual que cmd/analyze.
def readings_for(t, **over):
    q = dict(BASE, period_ms=base_period(t))
    q.update(over)
    out = []
    for cj in glob.glob(os.path.join(RUNS, "*", "rep*", "config.json")):
        c = json.load(open(cj))
        if c.get("status") != "ok" or c["transport"] != t:
            continue
        if any(c.get(k, False if k == "nodelay" else None) != v for k, v in q.items()):
            continue
        r = pd.read_csv(os.path.join(os.path.dirname(cj), "readings.csv"))
        r = r.sort_values("t_recv_us").drop_duplicates(["esp_id", "seq"])
        out.append(r["latency_us"].values / 1000.0)
    return np.concatenate(out) if out else np.array([])


def fig_cdf(name, title, over_by_t, xmax=None, shift_ms=0.0):
    fig, ax = plt.subplots(figsize=(7.5, 4))
    for t in TR:
        lat = readings_for(t, **over_by_t(t))
        if not len(lat):
            continue
        lat = np.sort(np.clip(lat - shift_ms, 0.1, None))
        ax.plot(lat, np.arange(1, len(lat) + 1) / len(lat), color=COL[t], label=f"{NAME[t]} (n={len(lat)})")
    ax.set_xscale("log")
    ax.set_xlabel("latencia extremo a extremo (ms, escala log)")
    ax.set_ylabel("fracción de lecturas")
    ax.set_title(title)
    ax.legend(fontsize=8, loc="lower right")
    if xmax:
        ax.set_xlim(right=xmax)
    save(fig, name)


# ---------------------------------------------------------------- modelo costo fijo + marginal
# Toma las 15 corridas de cada transporte persistente que solo difieren en el
# período. n = lecturas entregadas / conexiones (lecturas por conexión), y ajusta
# por mínimos cuadrados y = v + C·(1/n): v es el costo por lectura y C el costo
# fijo de cada conexión (handshake, CONNECT, cierre). http_req siempre tiene n = 1.
def fig_modelo():
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    rows = []
    for t in ["mqtt0", "mqtt1", "http_reuse"]:
        d = M[(M["transport"] == t) & (M["nodes"] == 8) & M["tls"] & (M["loss_pct"] == 0)
              & (M["rtt_ms"] == 0) & (M["serialization"] == "pb") & ~M["nodelay"]]
        n = d["delivered_unique"] / d["connections"]          # lecturas por conexión
        A = np.vstack([np.ones(len(n)), 1 / n]).T
        (v, C), *_ = np.linalg.lstsq(A, d["ip_bytes_per_reading"], rcond=None)
        pred = A @ [v, C]
        y = d["ip_bytes_per_reading"]
        r2 = 1 - ((y - pred) ** 2).sum() / ((y - y.mean()) ** 2).sum()
        rows.append(dict(transporte=t, v=v, C=C, r2=r2))
        ax.scatter(n, y, color=COL[t], marker=MRK[t], s=40, edgecolor=SURF, linewidth=1.5, zorder=3)
        xs = np.logspace(0, 4.5, 100)
        ax.plot(xs, v + C / xs, color=COL[t], label=f"{NAME[t]}: {v:.0f} B + {C:.0f} B / n  (R²={r2:.3f})")
    r = sel(M, "http_req", period_ms=10000)
    ax.axhline(r["ip_bytes_per_reading"].mean(), color=COL["http_req"], label="HTTP por request (n = 1 siempre)")
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlabel("lecturas por conexión (n)"); ax.set_ylabel("bytes IP por lectura")
    ax.set_title("Costo fijo por conexión + costo por lectura (TLS)")
    ax.legend(fontsize=8, loc="upper center", bbox_to_anchor=(0.5, -0.16), ncol=2)
    fig.set_size_inches(7.5, 5)
    pd.DataFrame(rows).to_csv(os.path.join(OUT, "modelo_costo.csv"), index=False)
    save(fig, "13_modelo_costo.png")


# ---------------------------------------------------------------- tests estadísticos
# Test t de Welch (no supone varianzas iguales) sobre los valores por corrida.
def welch(a_t, b_t, col, a_over=None, b_over=None):
    a = sel(M, a_t, **(a_over or {}))[col].values
    b = sel(M, b_t, **(b_over or {}))[col].values
    if len(a) < 2 or len(b) < 2:
        return None
    res = stats.ttest_ind(a, b, equal_var=False)
    return a.mean(), a.std(ddof=1), b.mean(), b.std(ddof=1), res.pvalue


# Intervalo de confianza del 95 %: media ± t(0,975; n−1)·s/√n (t de Student, n = 5).
def ci95(t, col, **over):
    v = sel(M, t, **over)[col].values
    if len(v) < 2:
        return np.nan, np.nan
    h = stats.t.ppf(0.975, len(v) - 1) * v.std(ddof=1) / np.sqrt(len(v))
    return v.mean(), h


def tablas():
    L = []
    cols = [("delivery_rate", "entrega", "{:.3f}"), ("ip_bytes_per_reading", "B/lectura", "{:.1f}"),
            ("packets_per_reading", "paq/lectura", "{:.2f}"), ("latency_ms_p50", "p50 ms", "{:.1f}"),
            ("latency_ms_p95", "p95 ms", "{:.1f}"), ("latency_ms_p99", "p99 ms", "{:.1f}"),
            ("connections", "conexiones", "{:.0f}"), ("handshake_bytes_per_conn", "B handshake/conn", "{:.0f}"),
            ("connect_ms_p50", "conexión p50 ms", "{:.1f}"), ("retransmissions", "retrans.", "{:.1f}"),
            ("duplicates", "duplicados", "{:.1f}"), ("pending_unsent", "pendientes", "{:.1f}"),
            ("overruns", "overruns", "{:.1f}"), ("rtf_min", "RTF min", "{:.3f}")]
    S2 = S.sort_values(["transport", "factor", "config_id"])
    L.append("| config | n | " + " | ".join(c[1] for c in cols) + " |")
    L.append("|---|---|" + "---|" * len(cols))
    for r in S2.itertuples():
        cells = []
        for c, _, f in cols:
            m, s = getattr(r, c + "_mean"), getattr(r, c + "_std")
            cells.append(f.format(m) + (" ± " + f.format(s) if s and np.isfinite(s) and s > 0 else ""))
        L.append(f"| `{r.config_id}` | {r.n_runs} | " + " | ".join(cells) + " |")
    L.append("")
    L.append("## Intervalos de confianza 95 % (t de Student, base)")
    L.append("| transporte | B/lectura | p50 ms | p95 ms |")
    L.append("|---|---|---|---|")
    for t in TR:
        cells = []
        for c in ("ip_bytes_per_reading", "latency_ms_p50", "latency_ms_p95"):
            m, h = ci95(t, c)
            cells.append(f"{m:.1f} ± {h:.1f}")
        L.append(f"| {t} | " + " | ".join(cells) + " |")
    L.append("")
    L.append("## Tests de Welch")
    L.append("| comparación | métrica | A media ± sd | B media ± sd | p |")
    L.append("|---|---|---|---|---|")
    comps = [
        ("mqtt0", "mqtt1", {}, {}, "ip_bytes_per_reading"),
        ("mqtt0", "mqtt1", {}, {}, "latency_ms_p50"),
        ("mqtt1", "http_reuse", {}, {}, "ip_bytes_per_reading"),
        ("mqtt1", "http_reuse", {}, {}, "latency_ms_p50"),
        ("mqtt1", "http_req", {"period_ms": 10000}, {}, "ip_bytes_per_reading"),
        ("http_reuse", "http_req", {"period_ms": 10000}, {}, "ip_bytes_per_reading"),
        ("mqtt0", "mqtt0", {"loss_pct": 5}, {}, "delivery_rate"),
        ("mqtt1", "mqtt1", {"loss_pct": 5}, {}, "delivery_rate"),
        ("mqtt0", "mqtt1", {"loss_pct": 5}, {"loss_pct": 5}, "delivery_rate"),
        ("mqtt0", "mqtt1", {"loss_pct": 5}, {"loss_pct": 5}, "latency_ms_p95"),
    ]
    for t in TR:
        comps.append((t, t, {"serialization": "json"}, {}, "ip_bytes_per_reading"))
        comps.append((t, t, {"tls": False}, {}, "ip_bytes_per_reading"))
        comps.append((t, t, {"tls": False}, {}, "latency_ms_p50"))
    for a, b, ao, bo, col in comps:
        r = welch(a, b, col, ao, bo)
        if r is None:
            continue
        L.append(f"| {a} {ao or 'base'} vs {b} {bo or 'base'} | {col} | {r[0]:.3f} ± {r[1]:.3f} | "
                 f"{r[2]:.3f} ± {r[3]:.3f} | {r[4]:.2g} |")
    open(os.path.join(OUT, "tablas.md"), "w").write("\n".join(L) + "\n")
    print("tablas.md")


if __name__ == "__main__":
    fig_bytes_tls()
    fig_composicion()
    fig_10s()
    fig_factor("nodes", [2, 4, 8],
               [("ip_bytes_per_reading", "bytes IP por lectura", False),
                ("latency_ms_p50", "latencia p50 (ms)", True),
                ("latency_ms_p95", "latencia p95 (ms)", True)],
               "04_nodos.png", "Escala: cantidad de nodos (TLS, período base)", xlab="nodos")
    fig_factor("period_ms", [100, 1000, 10000],
               [("ip_bytes_per_reading", "bytes IP por lectura", True),
                ("packets_per_reading", "paquetes por lectura", True),
                ("latency_ms_p50", "latencia p50 (ms)", True)],
               "05_periodo.png", "Período de envío (8 nodos, TLS)", logx=True, xlab="período (ms)")
    fig_factor("loss_pct", [0, 1, 5],
               [("duplicates", "lecturas duplicadas por corrida", False),
                ("latency_ms_p95", "latencia p95 (ms)", True),
                ("retransmissions", "retransmisiones TCP por corrida", False),
                ("ip_bytes_per_reading", "bytes IP por lectura", False)],
               "06_perdida.png", "Pérdida de paquetes en ambos sentidos (8 nodos, TLS) — la entrega fue 100 % en todos los casos", xlab="pérdida (%)")
    fig_factor("rtt_ms", [0, 50, 200],
               [("latency_ms_p50", "latencia p50 (ms)", True),
                ("connect_ms_p50", "tiempo de conexión p50 (ms)", False),
                ("ip_bytes_per_reading", "bytes IP por lectura", False)],
               "07_latencia_red.png", "RTT agregado con netem (8 nodos, TLS; latencia corregida −RTT/2)",
               xlab="RTT agregado (ms)", adjust=lambda rtt, m: m - rtt / 2)
    fig_factor("serialization", ["pb", "json"],
               [("payload_bytes_mean", "bytes de payload", False),
                ("ip_bytes_per_reading", "bytes IP por lectura", False)],
               "08_serializacion.png", "Protocol Buffers vs JSON (8 nodos, TLS)", xlab="serialización")
    fig_cdf("09_cdf_latencia_base.png", "Latencia por lectura, configuración base (TLS, 8 nodos)",
            lambda t: {})
    fig_cdf("10_cdf_latencia_10s.png", "Latencia por lectura con período de 10 s (TLS, 8 nodos)",
            lambda t: {"period_ms": 10000})
    fig_cdf("11_cdf_latencia_perdida5.png", "Latencia por lectura con 5 % de pérdida (TLS, 8 nodos)",
            lambda t: {"loss_pct": 5})
    fig_cdf("12_cdf_latencia_rtt200.png", "Latencia por lectura con 200 ms de RTT (TLS, 8 nodos; corregida −100 ms)",
            lambda t: {"rtt_ms": 200}, shift_ms=100.0)
    fig_modelo()
    tablas()
