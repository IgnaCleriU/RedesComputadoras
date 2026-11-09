"""Predicciones teóricas del experimento de sincronización.

La notación es la de la monografía: N osciladores, frecuencias naturales omega,
desintonías Delta = omega - media(omega), acoplamiento K, parámetro de orden r
y u = K * r.

Fuentes de cada resultado:
  - kc_finito: Verwoerd y Mason (2008), Corolario 5 y Teorema 3.
  - r_enganchado y desfasajes: Verwoerd y Mason (2008), Teorema 2.
  - kc_infinito: Strogatz (2000), sección 4.
  - frecuencia_con_retardo: Yeung y Strogatz (1999), con el factor (N - 1) / N
    que aparece al quitar el término propio. Ese factor es una cuenta nuestra.
  - kc_dos_nodos_con_retardo y estado_con_retardo: cuentas nuestras sobre el
    modelo de los nodos.
"""

import numpy as np
from scipy.optimize import brentq, fsolve


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

    K * f(u) = u tiene a lo sumo dos raíces (ver raices_u). Se toma la mayor,
    que es la de mayor r y la localmente estable (ver autovalores_estado).
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


def raices_u(omega, k):
    """Soluciones de K * f(u) = u, de mayor a menor. Lista vacía si K < K_c."""
    delta = desintonias(omega)
    maximo = np.abs(delta).max()
    mayor = u_enganchado(omega, k)
    if mayor is None or maximo == 0.0:
        return [] if mayor is None else [mayor]
    borde = maximo * (1.0 + 1e-13)
    critico = u_critico(omega)
    if mayor <= critico or k * f(borde, delta) - borde >= 0.0:
        return [mayor]
    return [mayor, brentq(lambda u: k * f(u, delta) - u, borde, critico, xtol=1e-12)]


def autovalores_estado(theta, k):
    """Autovalores, de menor a mayor, del modelo linealizado alrededor de las fases theta.

    J_ij = K / N * cos(theta_j - theta_i) para j != i, y cada diagonal es menos la
    suma del resto de su fila. Siempre hay un autovalor nulo (girar todas las fases).
    """
    theta = np.asarray(theta, dtype=float)
    jacobiano = k / len(theta) * np.cos(theta[None, :] - theta[:, None])
    np.fill_diagonal(jacobiano, 0.0)
    jacobiano[np.diag_indices(len(theta))] = -jacobiano.sum(axis=1)
    return np.sort(np.linalg.eigvalsh(jacobiano))


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


def estado_con_retardo(omega, k, tau):
    """Devuelve (Omega, r, beta) del estado enganchado con retardo uniforme tau, o None.

    Modelo de los nodos, sin término propio. Con beta_i = a_i - psi + Omega * tau:
        omega_i + K / N * sin(Omega * tau) - Omega = K * r * sin(beta_i)
        media de exp(i * beta_i) = r * exp(i * Omega * tau)
    De ahí sale Omega = media(omega) - K * (r^2 - 1 / N) * sin(Omega * tau).
    El desfasaje del nodo i respecto de la fase media es beta_i - Omega * tau.
    """
    omega = np.asarray(omega, dtype=float)
    n = len(omega)

    def senos(w, r):
        return (omega + k / n * np.sin(w * tau) - w) / (k * r)

    def residuo(x):
        w, r = x
        s = senos(w, r)
        exceso = np.abs(s).max() - 1.0
        if exceso >= 0.0:  # fuera del dominio de arcsin: empuja al solver hacia adentro
            return [1e3 * (exceso + 1e-3)] * 2
        z = np.exp(1j * np.arcsin(s)).mean() * np.exp(-1j * w * tau)
        return [z.imag, z.real - r]

    media = omega.mean()
    for r0 in (0.87, 0.93, 0.97, 0.75, 0.8, 0.6):
        inicio = (media - k * (r0**2 - 1.0 / n) * np.sin(media * tau), r0)
        (w, r), info, codigo, _ = fsolve(residuo, inicio, full_output=True, xtol=1e-11)
        if codigo == 1 and np.max(np.abs(info["fvec"])) < 1e-8 and 0.0 < r <= 1.0:
            return float(w), float(r), np.arcsin(senos(w, r))
    return None


def umbral_con_retardo(omega, tau, paso=0.002, maximo=1.6):
    """Menor K / K_c, en una grilla, para el que existe el estado con retardo tau."""
    kc = kc_finito(omega)
    for factor in np.arange(1.0, maximo, paso):
        if estado_con_retardo(omega, factor * kc, tau) is not None:
            return float(factor)
    return None
