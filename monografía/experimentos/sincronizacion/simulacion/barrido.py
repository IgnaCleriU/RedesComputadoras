"""Barre valores de K y escribe un CSV con los resultados de cada corrida.

Las dos configuraciones del experimento:
  - distintas: frecuencias equiespaciadas en f +- ancho * f. K se expresa como
    múltiplo de K_c, que se calcula para esas frecuencias.
  - iguales: todas las frecuencias valen f. K_c es 0, de modo que K se toma en
    rad/s y lo que se compara es la frecuencia común con la predicción con retardo.

Ejemplos:
  python3 barrido.py --config distintas --n 40 --f 0.1 --perfil sin-ruido --salida datos/d.csv
  python3 barrido.py --config iguales --n 40 --f 0.1 --k 0.05 0.1 --perfil sin-ruido --salida datos/i.csv
"""

import argparse
import csv
from pathlib import Path

import numpy as np

import teoria as te
from simulador import PERFILES_MEDIDOS, Red, esta_enganchado, r_medio, simular, tiempo_de_sincronizacion

FACTORES_POR_DEFECTO = [0.5, 0.8, 0.95, 1.05, 1.2, 1.5, 2.0, 3.0]


def argumentos():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--config", choices=["distintas", "iguales"], required=True)
    p.add_argument("--n", type=int, required=True, help="cantidad de osciladores")
    p.add_argument("--f", type=float, required=True, help="frecuencia media en Hz")
    p.add_argument("--ancho", type=float, default=0.05, help="semiancho relativo de las frecuencias")
    p.add_argument("--k", type=float, nargs="+", help="K: múltiplos de K_c (distintas) o rad/s (iguales)")
    p.add_argument("--h", type=float, default=1.0, help="período de publicación en s (1 s es lo medido con N = 40)")
    p.add_argument("--tau", type=float, default=0.0, help="retardo en s")
    p.add_argument("--jitter", type=float, default=0.0, help="desvío del jitter en s")
    p.add_argument("--perdida", type=float, default=0.0, help="copias que no llegan nunca (desconexión, no pérdida de TCP)")
    p.add_argument("--perfil", choices=sorted(PERFILES_MEDIDOS), default="", help="retardo sorteado de lo medido")
    p.add_argument("--t-s", type=float, default=0.01, help="paso de integración en s")
    p.add_argument("--duracion", type=float, default=600.0, help="duración de cada corrida en s")
    p.add_argument("--semillas", type=int, default=3, help="repeticiones con fases iniciales distintas")
    p.add_argument("--salida", type=Path, required=True, help="archivo CSV de salida")
    return p.parse_args()


def main():
    a = argumentos()
    omega_media = 2.0 * np.pi * a.f
    if a.config == "distintas":
        omega = te.frecuencias_equiespaciadas(a.n, omega_media, a.ancho * omega_media)
        k_c = te.kc_finito(omega)
        valores_k = [factor * k_c for factor in (a.k or FACTORES_POR_DEFECTO)]
    else:
        if not a.k:
            raise SystemExit("con --config iguales hay que indicar --k en rad/s")
        omega = np.full(a.n, omega_media)
        k_c = 0.0
        valores_k = a.k

    red = Red(h=a.h, tau=a.tau, jitter=a.jitter, perdida=a.perdida, perfil=a.perfil)
    tau_medio = a.tau + (1e-3 * PERFILES_MEDIDOS[a.perfil][0] if a.perfil else 0.0)
    a.salida.parent.mkdir(parents=True, exist_ok=True)
    campos = ["config", "n", "f", "ancho", "perfil", "k", "k_sobre_kc", "semilla", "h", "tau", "jitter", "perdida",
              "r_medio", "r_teorico", "enganchado", "t_sinc", "omega_comun", "omega_teorica"]

    with a.salida.open("w", newline="") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=campos)
        escritor.writeheader()
        for k in valores_k:
            r_teorico = te.r_enganchado(omega, k)
            umbral = 0.9 * r_teorico if r_teorico is not None else 0.9
            # Predicción solo para osciladores idénticos; el período h suma alrededor de h / 2 al retardo.
            omega_teorica = te.frecuencia_con_retardo(omega_media, k, tau_medio + a.h / 2.0, n=a.n) if a.config == "iguales" else None
            for semilla in range(a.semillas):
                resultado = simular(omega, k, red, duracion=a.duracion, t_s=a.t_s, semilla=semilla)
                t_sinc = tiempo_de_sincronizacion(resultado, umbral)
                escritor.writerow({
                    "config": a.config, "n": a.n, "f": a.f, "ancho": a.ancho, "perfil": a.perfil, "k": f"{k:.6f}",
                    "k_sobre_kc": f"{k / k_c:.4f}" if k_c > 0.0 else "",
                    "semilla": semilla, "h": a.h, "tau": a.tau, "jitter": a.jitter, "perdida": a.perdida,
                    "r_medio": f"{r_medio(resultado):.5f}",
                    "r_teorico": "" if r_teorico is None else f"{r_teorico:.5f}",
                    "enganchado": int(esta_enganchado(resultado)),
                    "t_sinc": "" if t_sinc is None else f"{t_sinc:.2f}",
                    "omega_comun": f"{resultado.omega_efectiva.mean():.5f}",
                    "omega_teorica": "" if omega_teorica is None else f"{omega_teorica:.5f}",
                })
                archivo.flush()


if __name__ == "__main__":
    main()
