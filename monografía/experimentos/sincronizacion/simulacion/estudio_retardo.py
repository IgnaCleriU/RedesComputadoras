"""Cálculos del experimento de sincronización con el retardo del período de publicación.

Escribe docs/resultados/figs/estudio_retardo.md con los valores que usa la monografía:
  - aplicación de Verwoerd y Mason a las 20 frecuencias y estabilidad de cada raíz;
  - estado enganchado con retardo uniforme: Omega, r, umbral y desfasaje del nodo más rápido;
  - umbral del modelo de los nodos, por simulación, con h = 500 ms;
  - simulación del esquema cruzado.

Uso (desde experimentos/sincronizacion/): uv run --no-sync python simulacion/estudio_retardo.py
Tarda unos minutos.
"""

from pathlib import Path

import numpy as np

import teoria as te
from simulador import Red, esta_enganchado, r_medio, simular

SALIDA = Path(__file__).resolve().parent.parent / "docs" / "resultados" / "figs" / "estudio_retardo.md"
OMEGA_MEDIA = 2 * np.pi * 0.2
OMEGA = te.frecuencias_equiespaciadas(20, OMEGA_MEDIA, 0.2 * OMEGA_MEDIA)
KC = te.kc_finito(OMEGA)
TAU_500, TAU_250 = 0.255, 0.131  # h / 2 más el transporte


def aplicacion():
    delta = te.desintonias(OMEGA)
    maximo = np.abs(delta).max()
    u = te.u_critico(OMEGA)
    borde = maximo / te.f(maximo * (1 + 1e-12), delta)
    filas = [
        ("Desintonía máxima (rad/s)", f"{maximo:.4f}"), ("u* (rad/s)", f"{u:.4f}"),
        ("K_c (rad/s)", f"{KC:.4f}"), ("r en K_c", f"{te.f(u, delta):.4f}"),
        ("Cotas de K_c (rad/s)", f"{maximo:.4f} a {2 * maximo:.4f}"),
        ("N infinito con densidad uniforme (rad/s)", f"{4 * maximo / np.pi:.4f}"),
        ("Dos raíces de K f(u) = u hasta K / K_c", f"{borde / KC:.4f}"),
    ]
    salida = ["## Aplicación a las 20 frecuencias\n", "| Cantidad | Valor |", "|---|---|"]
    salida += [f"| {a} | {b} |" for a, b in filas]
    salida += ["\n| K / K_c | Raíz | r | Mayor autovalor no trivial |", "|---|---|---|---|"]
    for factor in (1.0001, 1.05, 1.2, 1.5, 2.0):
        k = factor * KC
        for nombre, u_i in zip(("mayor", "menor"), te.raices_u(OMEGA, k)):
            autovalores = te.autovalores_estado(np.arcsin(delta / u_i), k)
            # Se descarta el autovalor nulo de girar todas las fases.
            resto = np.delete(autovalores, np.argmin(np.abs(autovalores)))
            salida.append(f"| {factor:g} | {nombre} | {u_i / k:.4f} | {resto.max():+.5f} |")
    return salida


def con_retardo():
    salida = ["\n## Estado enganchado con retardo uniforme\n",
              "| h (ms) | tau (ms) | K / K_c | Omega (rad/s) | r | Desfasaje del nodo 20 (rad) |", "|---|---|---|---|---|---|"]
    for h, tau, factores in ((500, TAU_500, (1.2, 1.5, 2.0)), (250, TAU_250, (1.1, 1.5))):
        for factor in factores:
            w, r, beta = te.estado_con_retardo(OMEGA, factor * KC, tau)
            salida.append(f"| {h} | {tau * 1e3:.0f} | {factor:g} | {w:.4f} | {r:.4f} | {beta[-1] - w * tau:.4f} |")
    salida += ["\n| h (ms) | tau (ms) | Umbral K / K_c | Factor 1 / cos(omega_media tau) |", "|---|---|---|---|"]
    for h, tau in ((500, TAU_500), (250, TAU_250)):
        salida.append(f"| {h} | {tau * 1e3:.0f} | {te.umbral_con_retardo(OMEGA, tau):.3f} | {1 / np.cos(OMEGA_MEDIA * tau):.3f} |")
    return salida


def umbral_simulado():
    salida = ["\n## Umbral simulado desde el estado enganchado (h = 500 ms, retardo de un paso, 800 s)\n",
              "| K / K_c | Engancha | Dispersión de frecuencias (rad/s) | r |", "|---|---|---|---|"]
    for factor in (1.05, 1.1, 1.15, 1.18, 1.19, 1.2, 1.25):
        k = factor * KC
        res = simular(OMEGA, k, Red(h=0.5, tau=0.005), duracion=800.0, t_s=0.01, theta0=te.desfasajes(OMEGA, k),
                      ventana_omega=200.0, muestreo=0.05, semilla=3)
        salida.append(f"| {factor:g} | {'Sí' if esta_enganchado(res) else 'No'} | {np.ptp(res.omega_efectiva):.5f} | {r_medio(res, 200.0):.4f} |")
    return salida


def cruzado():
    salida = ["\n## Esquema cruzado (h = 500 ms, retardo de un paso, 120 s, desde el estado enganchado de 1,5 K_c)\n",
              "| K / K_c | Semillas | r total | r esquema normal | r esquema cruzado |", "|---|---|---|---|---|"]
    theta0 = te.desfasajes(OMEGA, 1.5 * KC)
    for factor, semillas in ((1.5, 8), (2.5, 4), (3.0, 4), (4.0, 4)):
        filas = []
        for semilla in range(semillas):
            inicio = theta0 + np.random.default_rng(semilla).uniform(0.0, 2 * np.pi)
            res = simular(OMEGA, factor * KC, Red(h=0.5, tau=0.006, cruzado=True), duracion=120.0, t_s=0.01,
                          theta0=inicio, muestreo=0.1, semilla=semilla)
            final = res.t >= 0.8 * res.t[-1]
            filas.append((res.r[final].mean(), res.r_grupos[0][final].mean(), res.r_grupos[1][final].mean()))
        a = np.array(filas)
        celdas = " | ".join(f"{a[:, i].mean():.3f} ({a[:, i].min():.3f} a {a[:, i].max():.3f})" for i in range(3))
        salida.append(f"| {factor:g} | {semillas} | {celdas} |")
    return salida


def main():
    texto = ["# Estudio del retardo en el experimento de sincronización\n"]
    for parte in (aplicacion, con_retardo, umbral_simulado, cruzado):
        texto += parte()
    SALIDA.write_text("\n".join(texto) + "\n", encoding="utf8")
    print("\n".join(texto))


if __name__ == "__main__":
    main()
