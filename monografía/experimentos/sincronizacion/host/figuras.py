#!/usr/bin/env python3
"""Figuras y tablas del experimento de sincronización, a partir de resultados/final.

Uso (desde experimentos/sincronizacion/):
    uv run --no-sync python host/figuras.py [resultados/final] [docs/resultados/figs]

Antes hay que correr analizar.py y trafico.py sobre la misma matriz. Deja las imágenes PNG, los
CSV de la simulación de referencia y tablas.md en la carpeta de salida.
"""

import csv
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from scipy.interpolate import CubicHermiteSpline  # noqa: E402

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
sys.path.insert(0, str(RAIZ / "simulacion"))
sys.path.insert(0, str(AQUI))
import analizar  # noqa: E402
import teoria  # noqa: E402
from simulador import Red, esta_enganchado, r_medio, simular  # noqa: E402

AZUL, NARANJA, AQUA, AMARILLO = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
TEXTO, SECUNDARIO, TENUE, GRILLA = "#0b0b0b", "#52514e", "#898781", "#e1e0d9"
CORTE = "#e1e0d9"
R_REFERENCIA = 0.937  # r en régimen de la calibración, con K = 1,5 K_c y sin perturbaciones

plt.rcParams.update({
    "font.size": 9, "axes.edgecolor": TENUE, "axes.labelcolor": SECUNDARIO, "text.color": TEXTO,
    "xtick.color": SECUNDARIO, "ytick.color": SECUNDARIO, "axes.spines.top": False,
    "axes.spines.right": False, "axes.grid": True, "grid.color": GRILLA, "grid.linewidth": 0.6,
    "axes.axisbelow": True, "lines.linewidth": 1.6, "savefig.dpi": 200, "figure.dpi": 100,
    "legend.frameon": False,
})
ANCHO, ALTO = 6.3, 2.5


def coma(eje):
    eje.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:g}".replace(".", ",")))


def corridas(base):
    with open(base / "resumen.csv", newline="") as f:
        return {x["corrida"]: x for x in csv.DictReader(f, delimiter=";")}


def serie(base, corrida):
    with open(base / corrida / "serie.csv", newline="") as f:
        filas = list(csv.DictReader(f, delimiter=";"))
    return {k: np.array([float(x[k]) for x in filas]) for k in filas[0]}


def acciones(base, corrida):
    """[(t desde el inicio, duración, nodo)] de los eventos programados."""
    ruta = base / corrida / "eventos_analisis.csv"
    if not ruta.exists():
        return []
    with open(ruta, newline="") as f:
        return [(float(x["t_s"]), float(x["dur_s"] or 0), int(x["nodo"]))
                for x in csv.DictReader(f, delimiter=";") if x["dur_s"]]


def desfases(base, corrida):
    """t, desfase de cada nodo respecto de psi (rad, en (-pi, pi]) e identificadores."""
    d = base / corrida
    cfg = json.loads((d / "config.json").read_text())
    uart, _ = analizar.leer_uart(d)
    datos = {i: analizar.limpiar(x) for i, x in uart.items() if len(x["t"]) >= 3}
    ids = sorted(datos)
    t_ref = cfg["t_inicio_ms"] / 1000.0
    lo, hi = max(datos[i]["t"][0] for i in ids), min(datos[i]["t"][-1] for i in ids)
    grilla = np.arange(lo, hi, 0.1)
    fase = np.array([
        CubicHermiteSpline(datos[i]["t"], analizar.desenvolver(datos[i]["t"], datos[i]["theta"], datos[i]["vel"]),
                           datos[i]["vel"])(grilla) for i in ids])
    _, psi = analizar.parametro_de_orden(fase)
    return grilla - t_ref, analizar.envolver(fase - psi), ids


def guardar(fig, salida, nombre):
    fig.tight_layout()
    fig.savefig(salida / f"{nombre}.png", facecolor="white")
    plt.close(fig)


def sombrear(eje, eventos, etiqueta="Corte"):
    for i, (t, dur, _) in enumerate(eventos):
        eje.axvspan(t, t + dur, color=CORTE, lw=0, label=etiqueta if i == 0 else None, zorder=0)


def fig_modelo_rt(base, salida):
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    for k, color in zip(["0.8", "1.2", "1.5", "2"], [AZUL, NARANJA, AQUA, AMARILLO]):
        s = serie(base, f"modelo_k{k}_sin-netem_s1")
        ax.plot(s["t_s"], s["r"], color=color, label=f"{k.replace('.', ',')}·$K_c$")
    ax.set(xlabel="Tiempo desde el inicio (s)", ylabel="$r$", ylim=(0, 1.02), xlim=(0, 150))
    ax.legend(ncol=4, loc="upper center", bbox_to_anchor=(0.5, 1.2))
    coma(ax)
    guardar(fig, salida, "01_modelo_r_t")


def simulacion(salida):
    """r y enganche de la simulación ideal de referencia, N = 20, h = 0,5 s, f = 0,2 Hz, 5 semillas."""
    om = 2 * np.pi * 0.2
    w = teoria.frecuencias_equiespaciadas(20, om, 0.2 * om)
    kc = float(teoria.kc_finito(w))
    filas = []
    for fk in (0.8, 1.05, 1.2, 1.5, 2.0):
        for s in range(5):
            res = simular(w, fk * kc, red=Red(h=0.5, perfil="sin-ruido"), duracion=150.0, t_s=0.01, semilla=s,
                          ventana_omega=30.0, muestreo=0.05)
            filas.append((fk, s, float(r_medio(res, ultimos=30.0)), int(esta_enganchado(res))))
    with open(salida / "simulacion_modelo.csv", "w", newline="") as f:
        w_csv = csv.writer(f, delimiter=";")
        w_csv.writerow(["k_sobre_kc", "semilla", "r_medio", "enganchado"])
        w_csv.writerows(filas)
    return filas, w, kc


def _ejes_r_k(ax):
    ax.axvline(1.0, color=SECUNDARIO, lw=0.8, ls=":")
    ax.annotate("$K_c$", (1.0, 0.03), xytext=(4, 0), textcoords="offset points", color=SECUNDARIO)
    ax.set(xlabel="$K / K_c$", ylabel="$r$ en régimen", ylim=(0, 1.02), xlim=(0.7, 2.3))
    ax.xaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:g}".replace(".", ",")))
    coma(ax)


def fig_teoria_rk(salida, w):
    """Curva de autoconsistencia para las frecuencias del experimento, sin red."""
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    grilla = np.linspace(1.0, 2.2, 200)
    kc = float(teoria.kc_finito(w))
    ax.plot(grilla, [teoria.r_enganchado(w, x * kc) for x in grilla], color=TENUE, label="Teoría sin retardo")
    _ejes_r_k(ax)
    ax.legend(loc="lower right")
    guardar(fig, salida, "00_teoria_r_k")


def fig_modelo_rk(base, salida, tabla, sim, w):
    filas, _ = sim
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    grilla = np.linspace(1.0, 2.2, 200)
    kc = float(teoria.kc_finito(w))
    ax.plot(grilla, [teoria.r_enganchado(w, x * kc) for x in grilla], color=TENUE, label="Teoría sin retardo")
    sim_k = sorted({x[0] for x in filas})
    ax.plot(sim_k, [np.mean([x[2] for x in filas if x[0] == k]) for k in sim_k], ls="none", marker="s", ms=5,
            color=AZUL, label="Simulación (5 semillas)")
    med = [(float(tabla[f"modelo_k{k}_sin-netem_s1"]["k_veces_kc"]), float(tabla[f"modelo_k{k}_sin-netem_s1"]["r_medio"]))
           for k in ("0.8", "1.2", "1.5", "2")]
    ax.plot(*zip(*med), ls="none", marker="o", ms=6, color=NARANJA, label="Emulación")
    _ejes_r_k(ax)
    ax.legend(loc="lower right")
    guardar(fig, salida, "02_modelo_r_k")


def fig_esquemas(base, salida):
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    c = serie(base, "cruzado_k1.5_sin-netem_s1")
    ax.axhline(R_REFERENCIA, color=TENUE, ls="--", label="Esquema único (referencia)")
    ax.plot(c["t_s"], c["r"], color=AZUL, label="Cruzado: todos los nodos")
    ax.plot(c["t_s"], c["r_grupo_a"], color=NARANJA, lw=1.1, label="Cruzado: grupo con esquema normal")
    ax.plot(c["t_s"], c["r_grupo_b"], color=AQUA, lw=1.1, label="Cruzado: grupo con esquema cruzado")
    ax.set(xlabel="Tiempo desde el inicio (s)", ylabel="$r$", ylim=(0, 1.02), xlim=(0, 120))
    ax.legend(ncol=2, loc="upper center", bbox_to_anchor=(0.5, 1.3))
    coma(ax)
    guardar(fig, salida, "03_esquema_cruzado")


def fig_broker(base, salida):
    nombre = "broker_k1.5_sin-netem_s1"
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    s = serie(base, nombre)
    sombrear(ax, acciones(base, nombre), "Broker detenido")
    ax.plot(s["t_s"], s["r"], color=AZUL, label="$r(t)$ medido")
    # Oscilación libre desde el estado enganchado, mientras los nodos están desconectados.
    cfg = json.loads((base / nombre / "config.json").read_text())
    w = np.array([x["omega"] for x in cfg["nodos"]])
    fase = teoria.desfasajes(w, cfg["k_rad_s"])
    for i, (ini, fin) in enumerate(((31.05, 46.0), (120.04, 150.0))):
        t = np.arange(ini, fin, 0.1)
        ax.plot(t, np.abs(np.exp(1j * (fase + w * (t[:, None] - ini))).mean(axis=1)), color=NARANJA, ls="--", lw=1.1,
                label="Predicción sin acoplamiento" if i == 0 else None)
    ax.set(xlabel="Tiempo desde el inicio (s)", ylabel="$r$", ylim=(0, 1.02), xlim=(0, 240))
    ax.legend(ncol=3, loc="upper center", bbox_to_anchor=(0.5, 1.2))
    coma(ax)
    guardar(fig, salida, "04_broker")


def fig_keepalive(base, salida):
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    nombres = (("keepalive_sin_voluntad_k1.5_sin-netem_s1", AZUL, "Sin última voluntad"),
               ("keepalive_con_voluntad_k1.5_sin-netem_s1", NARANJA, "Con última voluntad"))
    for nombre, color, etiqueta in nombres:
        t, d, ids = desfases(base, nombre)
        ax.plot(t, d[ids.index(11)], color=color, label=etiqueta)
    sombrear(ax, [e for e in acciones(base, nombres[0][0]) if e[2] == 11], "Enlace del nodo 11 cortado")
    ax.set(xlabel="Tiempo desde el inicio (s)", ylabel="Desfase del nodo 11\nrespecto de $\\psi$ (rad)", xlim=(70, 130))
    ax.legend(ncol=3, loc="upper center", bbox_to_anchor=(0.5, 1.2))
    coma(ax)
    guardar(fig, salida, "05_keepalive_nodo")


def fig_union(base, salida):
    nombre = "union_k1.5_sin-netem_s1"
    t, d, ids = desfases(base, nombre)
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    y = d[ids.index(20)].copy()
    y[1:][np.abs(np.diff(y)) > np.pi] = np.nan  # no unir el paso de pi a -pi
    ax.plot(t, y, color=AZUL, label="Nodo 20")
    ax.axvline(45, color=SECUNDARIO, lw=0.8, ls=":")
    ax.annotate("Se conecta al broker", (45, ax.get_ylim()[1]), xytext=(4, -10), textcoords="offset points",
                color=SECUNDARIO)
    ax.set(xlabel="Tiempo desde el inicio (s)", ylabel="Desfase respecto\nde $\\psi$ (rad)", xlim=(30, 90))
    coma(ax)
    guardar(fig, salida, "06_union")


def fig_qos(base, salida):
    fig, ax = plt.subplots(figsize=(ANCHO, ALTO))
    ax.axhline(R_REFERENCIA, color=TENUE, ls="--", label="Sin pérdida (referencia)")
    casos = (("qos0_perdida_k1.5_perdida-5_s1", AZUL, "QoS 0, 5 % de pérdida"),
             ("qos1_perdida_k1.5_perdida-5_s1", NARANJA, "QoS 1, 5 % de pérdida"))
    for nombre, color, etiqueta in casos:
        s = serie(base, nombre)
        ax.plot(s["t_s"], s["r"], color=color, label=etiqueta)
    ax.set(xlabel="Tiempo desde el inicio (s)", ylabel="$r$", ylim=(0, 1.02), xlim=(0, 90))
    ax.legend(ncol=3, loc="upper center", bbox_to_anchor=(0.5, 1.2))
    coma(ax)
    guardar(fig, salida, "07_qos")


def validez(base):
    filas = []
    for d in sorted(p for p in base.iterdir() if (p / "nodos.csv").exists()):
        with open(d / "nodos.csv", newline="") as f:
            n = list(csv.DictReader(f, delimiter=";"))
        uart, _ = analizar.leer_uart(d)
        pasos = np.concatenate([np.diff(analizar.limpiar(x)["t"]) for x in uart.values()])
        filas.append((d.name, len(n), sum(int(x["overruns"] or 0) for x in n), round(float(np.median(pasos)), 3),
                      round(float(pasos.max()), 3)))
    return filas


def tablas(base, salida, tabla, sim):
    filas, _ = sim
    with open(base / "trafico.csv", newline="") as f:
        tr = {x["corrida"]: x for x in csv.DictReader(f, delimiter=";")}
    out = ["# Tablas del experimento de sincronización\n"]
    out += ["## Modelo\n", "| K/K_c | r emulación | r simulación (media de 5) | r teoría | Engancha |", "|---|---|---|---|---|"]
    for k in ("0.8", "1.2", "1.5", "2"):
        x = tabla[f"modelo_k{k}_sin-netem_s1"]
        rs = [y[2] for y in filas if abs(y[0] - float(k)) < 1e-9]
        out.append(f"| {k} | {x['r_medio']} | {np.mean(rs):.4f} | {x['r_teorico'] or '-'} | {x['enganchado']} |")
    out += ["\n## Tráfico\n",
            "| Corrida | N | QoS | Alias | Total B/s | Subida B/s·nodo | Bajada B/s·nodo | PUBLISH bajada B | Tópico | Protobuf B | Retrans. | Edad p50 ms | p95 ms | p99 ms |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for nombre, x in tr.items():
        out.append(f"| {nombre} | {x['n']} | {x['qos']} | {x['alias']} | {x['bytes_por_s_total']} | {x['bytes_por_s_subida_nodo']} | "
                   f"{x['bytes_por_s_bajada_nodo']} | {x['publish_bajada_B']} | {x['topico_bajada_B']} | {x['protobuf_bajada_B']} | "
                   f"{x['retransmisiones']} | {x['edad_entrega_p50_ms']} | {x['edad_entrega_p95_ms']} | {x['edad_entrega_p99_ms']} |")
    out += ["\n## Validez\n", "| Corrida | Nodos | Overruns | Paso UART mediano s | Paso máximo s |", "|---|---|---|---|---|"]
    for f_ in validez(base):
        out.append("| " + " | ".join(str(v) for v in f_) + " |")
    (salida / "tablas.md").write_text("\n".join(out) + "\n")


def main():
    base = Path(sys.argv[1] if len(sys.argv) > 1 else RAIZ / "resultados" / "final")
    salida = Path(sys.argv[2] if len(sys.argv) > 2 else RAIZ / "docs" / "resultados" / "figs")
    salida.mkdir(parents=True, exist_ok=True)
    tabla = corridas(base)
    filas, w, kc = simulacion(salida)
    sim = (filas, kc)
    fig_teoria_rk(salida, w)
    fig_modelo_rt(base, salida)
    fig_modelo_rk(base, salida, tabla, sim, w)
    fig_esquemas(base, salida)
    fig_broker(base, salida)
    fig_keepalive(base, salida)
    fig_union(base, salida)
    fig_qos(base, salida)
    tablas(base, salida, tabla, sim)
    print(f"figuras y tablas en {salida}")


if __name__ == "__main__":
    main()
