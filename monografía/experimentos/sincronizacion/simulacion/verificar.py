"""Compara la teoría y el simulador con los resultados conocidos.

Uso: python3 verificar.py
Termina con código 1 si alguna comprobación falla.
"""

import sys

import numpy as np

import teoria as te
from simulador import Red, esta_enganchado, r_medio, simular

fallas = 0


def comprobar(nombre, medido, esperado, tolerancia):
    global fallas
    correcto = abs(medido - esperado) <= tolerancia
    fallas += not correcto
    print(f"{'ok   ' if correcto else 'FALLA'} {nombre}: {medido:.5f} (esperado {esperado:.5f})")


def comprobar_condicion(nombre, condicion):
    global fallas
    fallas += not condicion
    print(f"{'ok   ' if condicion else 'FALLA'} {nombre}")


print("Teoría")
omega_2 = np.array([2 * np.pi - 0.1, 2 * np.pi + 0.1])
comprobar("K_c con N = 2 es |Delta omega|", te.kc_finito(omega_2), 0.2, 1e-9)

gamma = 2 * np.pi * 0.05
omega_40 = te.frecuencias_equiespaciadas(40, 2 * np.pi, gamma)
k_l = te.kc_finito(omega_40)
delta = te.desintonias(omega_40)
grilla = np.linspace(np.abs(delta).max() * (1 + 1e-9), 3 * np.abs(delta).max(), 400001)
minimo = min(u / te.f(u, delta) for u in grilla[::100])
comprobar("K_c coincide con el mínimo de u / f(u)", k_l, minimo, 1e-3)
comprobar("K_c / gamma con N = 40 equiespaciadas", k_l / gamma, 1.3034, 1e-3)
maximo = np.abs(delta).max()
comprobar_condicion("cotas max|Delta| <= K_c <= 2 max|Delta|", maximo <= k_l <= 2 * maximo)
comprobar("K_c de N infinito con densidad uniforme / gamma", te.kc_infinito(1 / (2 * gamma)) / gamma, 4 / np.pi, 1e-9)
comprobar("K_c sin desintonías", te.kc_finito(np.full(5, 3.0)), 0.0, 1e-12)

print("\nSimulador sin red, N = 40, frecuencias distintas")
for factor, r_teorico in [(1.5, te.r_enganchado(omega_40, 1.5 * k_l)), (3.0, te.r_enganchado(omega_40, 3 * k_l))]:
    resultado = simular(omega_40, factor * k_l, duracion=120.0)
    comprobar(f"r con K = {factor} K_c", r_medio(resultado), r_teorico, 0.005)
    comprobar_condicion(f"enganche con K = {factor} K_c", esta_enganchado(resultado))
    comprobar("frecuencia común igual a la media", resultado.omega_efectiva.mean(), omega_40.mean(), 0.005)

resultado = simular(omega_40, 0.8 * k_l, duracion=120.0)
comprobar_condicion("sin enganche con K = 0.8 K_c", not esta_enganchado(resultado))

print("\nRetardo con N = 2")
media, diferencia = 2 * np.pi, 0.2
omega_par = np.array([media - diferencia / 2, media + diferencia / 2])
for tau in (0.1, 0.2):
    k_critico = te.kc_dos_nodos_con_retardo(media, diferencia, tau)
    red = Red(h=0.001, tau=tau)
    arriba = simular(omega_par, 1.1 * k_critico, red, duracion=400.0, theta0=[0.0, 1.0], ventana_omega=60.0)
    abajo = simular(omega_par, 0.9 * k_critico, red, duracion=400.0, theta0=[0.0, 1.0], ventana_omega=60.0)
    comprobar_condicion(f"tau = {tau}: engancha con 1.1 K_c = {1.1 * k_critico:.3f}", esta_enganchado(arriba))
    comprobar_condicion(f"tau = {tau}: no engancha con 0.9 K_c", not esta_enganchado(abajo))

print("\nRetardo con osciladores idénticos, N = 10")
omega_0, k, tau = 2 * np.pi, 1.0, 0.05
inicio = np.linspace(-0.2, 0.2, 10)
omega_iguales = np.full(10, omega_0)
resultado = simular(omega_iguales, k, Red(h=0.001, tau=tau, desfase=False), duracion=60.0, theta0=inicio)
esperada = te.frecuencia_con_retardo(omega_0, k, tau, n=10)
comprobar("Omega con término propio ausente", resultado.omega_efectiva.mean(), esperada, 0.005)

print("\nPeríodo de publicación como retardo adicional de h / 2 (hipótesis)")
h = 0.1
esperada = te.frecuencia_con_retardo(omega_0, k, h / 2, n=10)
for desfase in (False, True):
    resultado = simular(omega_iguales, k, Red(h=h, desfase=desfase), duracion=60.0, theta0=inicio)
    print(f"info  desfase={desfase}: Omega medida {resultado.omega_efectiva.mean():.5f}, predicción con tau = h / 2: {esperada:.5f}")

print("\nEstado enganchado con retardo uniforme")
r_0 = te.estado_con_retardo(omega_40, 1.5 * k_l, 1e-9)
comprobar("tau -> 0: r coincide con la autoconsistencia", r_0[1], te.r_enganchado(omega_40, 1.5 * k_l), 1e-4)
comprobar("tau -> 0: Omega es la media", r_0[0], omega_40.mean(), 1e-4)
omega_20 = te.frecuencias_equiespaciadas(20, 2 * np.pi * 0.2, 0.2 * 2 * np.pi * 0.2)
k_20 = te.kc_finito(omega_20)
tau = 0.255
w_r, r_r, _ = te.estado_con_retardo(omega_20, 1.5 * k_20, tau)
comprobar("cumple Omega = media - K (r^2 - 1/N) sin(Omega tau)",
          w_r, omega_20.mean() - 1.5 * k_20 * (r_r**2 - 1 / 20) * np.sin(w_r * tau), 1e-8)
resultado = simular(omega_20, 1.5 * k_20, Red(h=0.01, tau=tau, desfase=False), duracion=300.0, t_s=0.01,
                    theta0=te.desfasajes(omega_20, 1.5 * k_20), ventana_omega=60.0)
comprobar("Omega simulada con retardo constante", resultado.omega_efectiva.mean(), w_r, 0.01)
comprobar("r simulado con retardo constante", r_medio(resultado, 60.0), r_r, 0.01)
raices = te.raices_u(omega_20, 1.0001 * k_20)
comprobar_condicion("dos raíces de K f(u) = u justo sobre K_c", len(raices) == 2)
comprobar_condicion("una sola raíz a 1,05 K_c", len(te.raices_u(omega_20, 1.05 * k_20)) == 1)
fase = np.arcsin(te.desintonias(omega_20)[None, :] / np.array(raices)[:, None])
comprobar_condicion("raíz mayor estable, menor inestable",
                    te.autovalores_estado(fase[0], 1.0001 * k_20)[-2] < 0 < te.autovalores_estado(fase[1], 1.0001 * k_20)[-1])

print(f"\n{'Todas las comprobaciones pasaron' if fallas == 0 else str(fallas) + ' comprobaciones fallaron'}")
sys.exit(1 if fallas else 0)
