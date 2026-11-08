"""Predicciones teóricas del experimento de sincronización.

La notación es la de la monografía: N osciladores, frecuencias naturales omega,
desintonías Delta = omega - media(omega), acoplamiento K, parámetro de orden r
y u = K * r.

Fuentes de cada resultado:
  - kc_finito, r_enganchado y desfasajes: Verwoerd y Mason (2008), Corolario 5
    y Teorema 3.
  - kc_infinito: Strogatz (2000), sección 4.
  - frecuencia_con_retardo: Yeung y Strogatz (1999), con el factor (N - 1) / N
    que aparece al quitar el término propio. Ese factor es una cuenta nuestra.
  - kc_dos_nodos_con_retardo: cuenta nuestra sobre el modelo de los nodos.
"""

import numpy as np
from scipy.optimize import brentq


def frecuencias_equiespaciadas(n, media, semiancho):
    """Devuelve n frecuencias repartidas de forma pareja en media +- semiancho."""
    if n == 1:
        return np.array([media], dtype=float)
    return media + np.linspace(-semiancho, semiancho, n)


def desintonias(omega):
    omega = np.asarray(omega, dtype=float)
    return omega - omega.mean()


def f(u, delta):
    """Lado derecho de la condición de autoconsistencia, r = u / K = f(u)."""
    return np.mean(np.sqrt(1.0 - (delta / u) ** 2))


def _condicion_de_minimo(u, delta):
    """Se anula en el mínimo de u / f(u); es creciente en u."""
    raices = np.sqrt(1.0 - (delta / u) ** 2)
    return 2.0 * np.mean(raices) - np.mean(1.0 / raices)


def u_critico(omega):
    """Valor de u en el que u / f(u) alcanza su mínimo.

    Se busca por bisección en (max|Delta|, sqrt(2) * max|Delta|], el intervalo
    en el que Verwoerd y Mason ubican la solución. El paper escribe el punto
    medio como (b - a) / 2 en su algoritmo; acá se usa (a + b) / 2.
    """
    delta = desintonias(omega)
    maximo = np.abs(delta).max()
    if maximo == 0.0:
        return 0.0
    a = maximo * (1.0 + 1e-12)
    b = np.sqrt(2.0) * maximo
    while b - a > 1e-12 * maximo:
        medio = 0.5 * (a + b)
        if _condicion_de_minimo(medio, delta) > 0.0:
            b = medio
        else:
            a = medio
    return 0.5 * (a + b)


def kc_finito(omega):
    """Menor K para el que existe un estado con todos los osciladores enganchados."""
    u = u_critico(omega)
    if u == 0.0:
        return 0.0
    return u / f(u, desintonias(omega))


def kc_infinito(g0):
    """Umbral de sincronización parcial para N infinito, dado g(0)."""
    return 2.0 / (np.pi * g0)


def u_enganchado(omega, k):
    """Devuelve u = K * r del estado enganchado, o None si K < K_c.

    K * f(u) = u tiene dos raíces cuando K > K_c. La mayor corresponde al
    estado con mayor r, que es el que se observa en las simulaciones.
    """
    delta = desintonias(omega)
    if np.abs(delta).max() == 0.0:
        return float(k)
    critico = u_critico(omega)
    if k < critico / f(critico, delta):
        return None
    if np.isclose(k, critico / f(critico, delta)):
        return critico
    return brentq(lambda u: k * f(u, delta) - u, critico, k, xtol=1e-12)


def r_enganchado(omega, k):
    """Parámetro de orden del estado enganchado, o None si K < K_c."""
    u = u_enganchado(omega, k)
    return None if u is None else u / k


def desfasajes(omega, k):
    """Desfasaje de cada oscilador respecto de la fase media, en radianes."""
    u = u_enganchado(omega, k)
    if u is None:
        return None
    if u == 0.0:
        return np.zeros(len(omega))
    return np.arcsin(desintonias(omega) / u)


def frecuencia_con_retardo(omega0, k, tau, n=None):
    """Frecuencia común de osciladores idénticos con retardo uniforme tau.

    Resuelve Omega = omega0 - K * c * sin(Omega * tau), con c = (N - 1) / N si
    se pasa n (nodos sin término propio) o c = 1 si no (Yeung y Strogatz).
    Entre las soluciones con cos(Omega * tau) > 0 devuelve la más cercana a
    omega0, o None si no hay ninguna.
    """
    c = 1.0 if n is None else (n - 1) / n
    if tau == 0.0 or k == 0.0:
        return float(omega0)
    residuo = lambda w: w - omega0 + k * c * np.sin(w * tau)
    grilla = np.linspace(omega0 - k * c - 1e-6, omega0 + k * c + 1e-6, 20001)
    valores = residuo(grilla)
    raices = [
        brentq(residuo, grilla[i], grilla[i + 1], xtol=1e-12)
        for i in range(len(grilla) - 1)
        if valores[i] * valores[i + 1] < 0.0
    ]
    estables = [w for w in raices if np.cos(w * tau) > 0.0]
    if not estables:
        return None
    return min(estables, key=lambda w: abs(w - omega0))


def kc_dos_nodos_con_retardo(omega_media, delta_omega, tau):
    """Umbral de enganche con N = 2 y retardo tau igual en ambos sentidos.

    En el umbral sin(phi) = 1, por lo que cos(phi) = 0 y Omega = omega_media.
    """
    return abs(delta_omega) / abs(np.cos(omega_media * tau))
