#!/usr/bin/env python3
"""Prueba sintética de analizar.py.

Simula un Kuramoto enganchado de 10 nodos (RK4, información completa), escribe un fases.log
como lo dejaría el logger (PhaseReport en protobuf, theta reducida a [0, 2*pi), t_us en época)
y comprueba que el análisis recupera r y Omega con menos de 1 % de error.

Casos: (A) f = 0.1 Hz, h = 1 s; (B) f = 1 Hz, h = 1 s, donde el desenvolvimiento ingenuo da
alias, con un 5 % de mensajes perdidos.
"""

import json
import struct
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analizar
import correr

T_EPOCH = 1_800_000_000.0
PASO = 0.005  # paso de la simulación, s


def varint(v):
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        out.append(b | (0x80 if v else 0))
        if not v:
            return bytes(out)


def codificar(i, theta, vel, seq, t_us):
    """PhaseReport { id=1 varint; theta=2 float; velocidad=3 float; seq=4 varint; t_us=5 fixed64 }."""
    return (b"\x08" + varint(i) + b"\x15" + struct.pack("<f", theta) + b"\x1d"
            + struct.pack("<f", vel) + b"\x20" + varint(seq) + b"\x29" + struct.pack("<Q", t_us))


def simular(omega, k, theta0, duracion):
    n = len(omega)

    def deriv(th):
        return omega + k / n * np.sin(th[None, :] - th[:, None]).sum(axis=1)

    pasos = int(round(duracion / PASO))
    tray = np.empty((pasos + 1, n))
    th = theta0.copy()
    tray[0] = th
    for s in range(pasos):
        k1 = deriv(th)
        k2 = deriv(th + PASO / 2 * k1)
        k3 = deriv(th + PASO / 2 * k2)
        k4 = deriv(th + PASO * k3)
        th = th + PASO / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
        tray[s + 1] = th
    return tray


def caso(nombre, f_hz, duracion, perdida, semilla):
    matriz = {"entradas": [{"nombre": nombre, "n": 10, "config": "distintas", "f_hz": f_hz,
                            "ancho": 0.1, "k": [2.0], "h_ms": 1000, "duracion_s": duracion,
                            "semillas": [semilla], "perfil": [""]}]}
    p = correr.parametros_de_corrida(correr.expandir(matriz, "prueba")[0])
    for nodo in p["nodos"]:  # la simulación tiene paso de 5 ms
        nodo["desfase_ms"] = 5 * round(nodo["desfase_ms"] / 5)
    p["t_inicio_ms"] = int(T_EPOCH * 1000)
    n = p["n"]
    omega = np.array([x["omega"] for x in p["nodos"]])
    theta0 = np.array([x["theta0"] for x in p["nodos"]])
    tray = simular(omega, p["k_rad_s"], theta0, duracion)
    h = p["h_ms"] / 1000

    rng = np.random.default_rng(semilla)
    d = Path(tempfile.mkdtemp(prefix="kur-prueba-")) / nombre
    d.mkdir()
    (d / "config.json").write_text(json.dumps(p))
    lineas = []
    primero, ultimo = [], []
    for i, nodo in enumerate(p["nodos"]):
        seq = 0
        t = nodo["desfase_ms"] / 1000
        while t <= duracion - h:
            s = int(round(t / PASO))
            th = tray[s]
            vel = omega[i] + p["k_rad_s"] / n * np.sin(th - th[i]).sum()
            if rng.random() >= perdida:
                payload = codificar(i + 1, float(np.mod(th[i], 2 * np.pi)), float(vel), seq,
                                    int(round((T_EPOCH + t) * 1e6)))
                recv = T_EPOCH + t + 0.02 + rng.random() * 0.01
                lineas.append((recv, f"{recv:.9f} kuramoto/phase/{i + 1} {payload.hex()}"))
            if not primero or len(primero) <= i:
                primero.append(t)
            seq += 1
            ultimo_t = t
            t += h
        ultimo.append(ultimo_t)
    lineas.sort()
    (d / "fases.log").write_text("\n".join(l for _, l in lineas) + "\n")

    # Verdad: mismas definiciones que usa el análisis (ventana del 20 % final de [t_lo, t_hi]).
    t_lo, t_hi = max(primero), min(ultimo)
    w = 0.2 * (t_hi - t_lo)
    grilla = np.arange(t_lo, t_hi, 0.1)
    en_v = (grilla - grilla[0]) >= (grilla[-1] - grilla[0]) - w
    idx = np.round(grilla[en_v] / PASO).astype(int)
    r_verdad = np.abs(np.exp(1j * tray[idx]).mean(axis=1)).mean()
    s_fin, s_ini = int(round(t_hi / PASO)), int(round((t_hi - w) / PASO))
    omega_verdad = ((tray[s_fin] - tray[s_ini]) / (PASO * (s_fin - s_ini))).mean()

    fila = analizar.analizar_corrida(d)
    err_r = abs(fila["r_medio"] - r_verdad) / r_verdad
    err_o = abs(fila["omega_comun"] - omega_verdad) / omega_verdad
    print(f"{nombre}: r analizado {fila['r_medio']:.5f}, verdad {r_verdad:.5f} (error {100 * err_r:.3f} %); "
          f"Omega analizado {fila['omega_comun']:.5f}, verdad {omega_verdad:.5f} rad/s "
          f"(error {100 * err_o:.3f} %); r teórico {fila['r_teorico']}; enganchado={fila['enganchado']}; "
          f"t_sync={fila['t_sync_s']} s; retardo p50 {fila['retardo_p50_ms']} ms; "
          f"pérdida {fila['perdida_pct']} %")
    assert fila["enganchado"] == 1, "debería estar enganchado"
    assert err_r < 0.01, f"error de r {err_r:.4f} >= 1 %"
    assert err_o < 0.01, f"error de Omega {err_o:.4f} >= 1 %"
    assert 18 < fila["retardo_p50_ms"] < 32, "el retardo inyectado era de 20 a 30 ms"
    if f_hz >= 1.0:  # el desenvolvimiento ingenuo, sin la velocidad, falla en este caso
        nodo = analizar.leer_fases(d / "fases.log")[0][1]
        ingenuo = np.polyfit(nodo["t"], np.unwrap(nodo["theta"]), 1)[0]
        print(f"   (con np.unwrap la frecuencia del nodo 1 sería {ingenuo:.3f} rad/s, no {omega_verdad:.3f})")
        assert abs(ingenuo - omega_verdad) / omega_verdad > 0.1


if __name__ == "__main__":
    caso("A_f0.1", 0.1, 300, 0.0, 1)
    caso("B_f1.0_perdida5", 1.0, 120, 0.05, 2)
    print("probar_analisis: OK")
