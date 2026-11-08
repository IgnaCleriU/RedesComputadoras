"""Simulación del modelo de los nodos, sin red real.

Integra con Euler la ecuación discreta de la monografía:

    theta_i[k + 1] = theta_i[k]
                     + T_s * (omega_i + K / N * suma_{j != i} sin(hat_ij[k] - theta_i[k]))

donde hat_ij[k] es la última fase del nodo j que recibió el nodo i. La red se
reemplaza por un modelo de entrega: cada nodo publica su fase cada h segundos, con
un desfase propio, y cada copia llega a cada receptor con un retardo.

El retardo puede ser constante (tau), sumarle un jitter, o sortearse de los
percentiles medidos en la plataforma común (perfil). Como MQTT va sobre TCP, una
pérdida de paquetes aparece como retardo, y eso es lo que representan los perfiles
con pérdida. El parámetro perdida descarta copias de verdad, y solo corresponde a
una desconexión o a un descarte en la aplicación.

Mientras un nodo no recibió ninguna fase de otro, ese término no aporta nada.
El divisor N no cambia aunque falten fases.
"""

from collections import deque
from dataclasses import dataclass

import numpy as np

NUNCA = np.iinfo(np.int64).max  # paso de llegada de una copia que no va a llegar

# Retardo por par (p50, p95, p99) en ms, medido con 39 nodos y h = 1 s en la plataforma
# común (eco-mqtt, sección de ruido). Se sortea cada copia de forma independiente, de modo
# que no reproduce la correlación que introduce el bloqueo en cabeza de línea de TCP.
PERFILES_MEDIDOS = {
    "sin-ruido": (13.0, 16.0, 17.0),
    "jitter": (27.0, 36.0, 40.0),
    "wifi": (24.0, 37.0, 42.0),
    "wifi-perdida-1": (29.0, 749.0, 1372.0),
    "wifi-perdida-5": (30.0, 1537.0, 2106.0),
}


@dataclass
class Red:
    """Condiciones de la red simulada. Los tiempos están en segundos."""

    h: float = 0.001
    tau: float = 0.0
    jitter: float = 0.0  # desvío de una normal truncada en cero, sumada a tau
    perdida: float = 0.0  # probabilidad de que una copia no llegue nunca
    perfil: str = ""  # clave de PERFILES_MEDIDOS; se suma a tau
    desfase: bool = True  # cada nodo publica con un desfase propio dentro de h
    extrapolar: bool = False  # el receptor adelanta la fase con la velocidad publicada y su antigüedad


@dataclass
class Resultado:
    t: np.ndarray  # instantes de muestreo
    r: np.ndarray  # parámetro de orden en cada instante
    psi: np.ndarray  # fase media en cada instante
    fases_finales: np.ndarray  # theta_i sin reducir módulo 2 pi
    omega_efectiva: np.ndarray  # velocidad media de cada fase en la ventana final


def parametro_de_orden(theta):
    """Devuelve (r, psi) de un vector de fases."""
    z = np.exp(1j * theta).mean()
    return abs(z), np.angle(z)


def simular(omega, k, red=None, duracion=120.0, t_s=0.001, semilla=0,
            theta0=None, muestreo=0.01, ventana_omega=20.0):
    """Corre la simulación y devuelve un Resultado.

    omega: frecuencias naturales en rad/s.
    k: acoplamiento en rad/s.
    theta0: fases iniciales; si es None, se sortean con la semilla.
    ventana_omega: duración final sobre la que se mide la frecuencia efectiva.
    """
    red = Red() if red is None else red
    omega = np.asarray(omega, dtype=float)
    n = len(omega)
    rng = np.random.default_rng(semilla)
    theta = rng.uniform(0.0, 2.0 * np.pi, n) if theta0 is None else np.array(theta0, float)

    pasos = int(round(duracion / t_s))
    paso_publicacion = max(1, int(round(red.h / t_s)))
    desfases = (
        rng.integers(0, paso_publicacion, n)
        if red.desfase and paso_publicacion > 1
        else np.zeros(n, dtype=int)
    )
    paso_muestreo = max(1, int(round(muestreo / t_s)))
    paso_ventana = pasos - int(round(ventana_omega / t_s))

    # Última fase conocida por cada receptor (fila) de cada emisor (columna).
    hat = np.zeros((n, n))
    conocida = np.zeros((n, n), dtype=bool)
    hat_velocidad = np.zeros((n, n))
    hat_paso = np.zeros((n, n), dtype=np.int64)
    velocidad = omega.copy()
    ultima_seq = -np.ones((n, n), dtype=int)
    pendientes = deque()  # (seq, fases publicadas, paso de llegada por copia)

    tiempos, valores_r, valores_psi = [], [], []
    theta_ventana = None
    seq = 0

    for paso in range(pasos):
        if paso % paso_muestreo == 0:
            r, psi = parametro_de_orden(theta)
            tiempos.append(paso * t_s)
            valores_r.append(r)
            valores_psi.append(psi)
        if paso == paso_ventana:
            theta_ventana = theta.copy()

        publican = (paso - desfases) % paso_publicacion == 0
        if publican.any():
            demora = np.full((n, n), red.tau)
            if red.perfil:
                p50, p95, p99 = PERFILES_MEDIDOS[red.perfil]
                demora += 1e-3 * np.interp(
                    rng.random((n, n)), [0.0, 0.5, 0.95, 0.99, 1.0], [p50, p50, p95, p99, p99]
                )
            if red.jitter > 0.0:
                demora += np.abs(rng.normal(0.0, red.jitter, (n, n)))
            llegada = paso + np.ceil(demora / t_s).astype(np.int64)
            if red.perdida > 0.0:
                llegada[rng.random((n, n)) < red.perdida] = NUNCA
            np.fill_diagonal(llegada, NUNCA)
            llegada[:, ~publican] = NUNCA
            if llegada.min() < NUNCA:
                pendientes.append([llegada.min(), seq, theta.copy(), llegada, velocidad.copy(), paso])
            seq += 1

        # Solo se revisan las publicaciones que tienen alguna copia por llegar en este paso.
        hubo_vacias = False
        for pendiente in pendientes:
            if pendiente[0] > paso:
                continue
            _, numero, publicadas, llegada, velocidades, paso_publicado = pendiente
            llegaron = llegada <= paso
            # Una copia solo reemplaza a la guardada si es más nueva.
            filas, columnas = np.nonzero(llegaron & (numero > ultima_seq))
            hat[filas, columnas] = publicadas[columnas]
            conocida[filas, columnas] = True
            ultima_seq[filas, columnas] = numero
            hat_velocidad[filas, columnas] = velocidades[columnas]
            hat_paso[filas, columnas] = paso_publicado
            llegada[llegaron] = NUNCA
            pendiente[0] = llegada.min()
            hubo_vacias = hubo_vacias or pendiente[0] == NUNCA
        if hubo_vacias:
            pendientes = deque(p for p in pendientes if p[0] < NUNCA)

        estimada = hat + hat_velocidad * (paso - hat_paso) * t_s if red.extrapolar else hat
        acople = np.sin(estimada - theta[:, None]) * conocida
        velocidad = omega + k / n * acople.sum(axis=1)
        theta = theta + t_s * velocidad

    if theta_ventana is None:
        theta_ventana = theta.copy()
        duracion_ventana = 0.0
    else:
        duracion_ventana = (pasos - paso_ventana) * t_s
    omega_efectiva = (
        (theta - theta_ventana) / duracion_ventana if duracion_ventana > 0.0 else omega.copy()
    )

    return Resultado(
        t=np.array(tiempos),
        r=np.array(valores_r),
        psi=np.array(valores_psi),
        fases_finales=theta,
        omega_efectiva=omega_efectiva,
    )


def esta_enganchado(resultado, tolerancia=0.01):
    """Indica si todas las frecuencias efectivas coinciden dentro de la tolerancia."""
    return np.ptp(resultado.omega_efectiva) < tolerancia


def r_medio(resultado, ultimos=30.0):
    """Promedio de r en los últimos segundos de la corrida."""
    return resultado.r[resultado.t >= resultado.t[-1] - ultimos].mean()


def tiempo_de_sincronizacion(resultado, umbral):
    """Primer instante desde el cual r se mantiene por encima del umbral."""
    por_debajo = np.nonzero(resultado.r < umbral)[0]
    if len(por_debajo) == 0:
        return 0.0
    ultimo = por_debajo[-1]
    if ultimo == len(resultado.r) - 1:
        return None
    return resultado.t[ultimo + 1]
