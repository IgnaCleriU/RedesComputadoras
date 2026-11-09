#!/usr/bin/env python3
"""Analiza las corridas del experimento de Kuramoto a partir de config.json y fases.log.

Para cada corrida:
  1. decodifica a mano los PhaseReport (protobuf) de fases.log;
  2. reconstruye la fase sin reducir de cada nodo, usando la velocidad publicada para
     elegir la rama de 2*pi (con f = 1 Hz y h = 1 s el desenvolvimiento ingenuo da alias);
  3. interpola todas las fases a una grilla temporal común con el t_us de cada muestra
     (spline cúbico de Hermite: se conocen la fase y su derivada en cada muestra);
  4. calcula r(t) y psi(t), y de ahí r medio en la ventana final, frecuencia efectiva de
     cada nodo, si engancharon, tiempo de sincronización y frecuencia común Omega;
  5. agrega las predicciones de teoria.py y el retardo de entrega medido.
Escribe serie.csv y nodos_analisis.csv en la corrida, y resumen.csv en la matriz.

Uso:  analizar.py resultados/<matriz>      (todas las corridas con fases.log)
      analizar.py resultados/<matriz>/<corrida>
"""

import argparse
import csv
import json
import struct
import sys
from pathlib import Path

import numpy as np
from scipy.interpolate import CubicHermiteSpline

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI.parent / "simulacion"))
import teoria  # noqa: E402

COLUMNAS = [
    "corrida", "entrada", "config", "n", "f_hz", "ancho", "k_entrada", "k_rad_s", "kc_rad_s",
    "k_veces_kc", "h_ms", "perfil", "extrapolar", "semilla", "sntp", "nodos_con_datos",
    "mensajes", "perdida_pct", "r_medio", "r_teorico", "enganchado", "omega_dispersion",
    "omega_comun", "t_sync_s", "omega_pred_retardo", "tau_usado_ms", "retardo_p50_ms",
    "retardo_p95_ms", "r_grupo_a", "r_grupo_b", "estado",
]


# --- Decodificador protobuf ---------------------------------------------------------------

def _varint(b, i):
    v = 0
    desplazamiento = 0
    while True:
        byte = b[i]
        i += 1
        v |= (byte & 0x7F) << desplazamiento
        if not byte & 0x80:
            return v, i
        desplazamiento += 7


def decodificar(payload):
    """Decodifica un PhaseReport: devuelve dict con id, theta, velocidad, seq, t_us.

    message PhaseReport { uint32 id=1; float theta=2; float velocidad=3; uint32 seq=4;
                          fixed64 t_us=5; }
    Los campos ausentes valen 0 (proto3). Lanza ValueError si el mensaje está truncado.
    """
    msg = {"id": 0, "theta": 0.0, "velocidad": 0.0, "seq": 0, "t_us": 0}
    i = 0
    try:
        while i < len(payload):
            tag, i = _varint(payload, i)
            campo, tipo = tag >> 3, tag & 7
            if tipo == 0:
                v, i = _varint(payload, i)
            elif tipo == 1:
                v = struct.unpack_from("<Q", payload, i)[0]
                i += 8
            elif tipo == 5:
                v = payload[i:i + 4]
                if len(v) < 4:
                    raise ValueError("truncado")
                i += 4
            elif tipo == 2:
                largo, i = _varint(payload, i)
                v = payload[i:i + largo]
                i += largo
            else:
                raise ValueError(f"tipo de campo {tipo} no soportado")
            if campo == 1 and tipo == 0:
                msg["id"] = v
            elif campo == 2 and tipo == 5:
                msg["theta"] = struct.unpack("<f", v)[0]
            elif campo == 3 and tipo == 5:
                msg["velocidad"] = struct.unpack("<f", v)[0]
            elif campo == 4 and tipo == 0:
                msg["seq"] = v
            elif campo == 5 and tipo == 1:
                msg["t_us"] = v
    except (IndexError, struct.error) as e:
        raise ValueError("mensaje truncado") from e
    return msg


def leer_fases(ruta):
    """Lee fases.log (líneas `<recv> <topico> <hex>`) y agrupa las muestras por nodo.

    Devuelve (dict id -> dict de arreglos, cantidad de líneas inválidas).
    """
    filas = {}
    malas = 0
    with open(ruta, "r", errors="replace") as f:
        for linea in f:
            partes = linea.split()
            if len(partes) != 3:
                malas += 1
                continue
            if "/estado/" in partes[1]:  # última voluntad: no es un PhaseReport
                continue
            try:
                m = decodificar(bytes.fromhex(partes[2]))
                recv = float(partes[0])
            except ValueError:
                malas += 1
                continue
            filas.setdefault(m["id"], []).append(
                (m["t_us"] * 1e-6, m["theta"], m["velocidad"], m["seq"], recv))
    datos = {}
    for i, v in filas.items():
        a = np.array(v)
        datos[i] = {"t": a[:, 0], "theta": a[:, 1], "vel": a[:, 2], "seq": a[:, 3], "recv": a[:, 4]}
    return datos, malas


def leer_uart(directorio):
    """Fase real de cada nodo y sus eventos, de las líneas F y EV de uart<i>.log.

    Devuelve (dict id -> dict de arreglos, lista de eventos (id, tipo, t_epoch, otro nodo)).
    Las líneas truncadas al final del archivo se ignoran.
    """
    filas, eventos = {}, []
    for ruta in Path(directorio).glob("uart*.log"):
        nodo = int(ruta.stem[4:])
        with open(ruta, "r", errors="replace") as f:
            for linea in f:
                p = linea.split()
                try:
                    if len(p) == 6 and p[0] == "F":
                        filas.setdefault(int(p[1]), []).append(
                            (int(p[3]) * 1e-6, float(p[4]), float(p[5]), int(p[2]), np.nan))
                    elif len(p) == 3 and p[0] == "EV":
                        eventos.append((nodo, p[1], int(p[2]) * 1e-6, 0))
                    elif len(p) == 4 and p[0] == "EV":
                        eventos.append((nodo, p[1], int(p[3]) * 1e-6, int(p[2])))
                except ValueError:
                    continue
    datos = {}
    for i, v in filas.items():
        a = np.array(v)
        datos[i] = {"t": a[:, 0], "theta": a[:, 1], "vel": a[:, 2], "seq": a[:, 3], "recv": a[:, 4]}
    return datos, eventos


def leer_voluntades(ruta):
    """Instantes en que el broker publicó una última voluntad: [(id, hora de llegada)]."""
    res = []
    with open(ruta, "r", errors="replace") as f:
        for linea in f:
            p = linea.split()
            if len(p) >= 2 and "/estado/" in p[1]:
                res.append((int(p[1].rsplit("/", 1)[1]), float(p[0])))
    return res


# --- Reconstrucción de la fase ------------------------------------------------------------

def envolver(x):
    """Lleva a (-pi, pi]."""
    return np.pi - np.mod(np.pi - x, 2 * np.pi)


def desenvolver(t, theta, vel):
    """Fase sin reducir módulo 2 pi, eligiendo la rama con la velocidad publicada.

    Entre dos muestras la fase avanza aproximadamente la velocidad media por el tiempo
    transcurrido; la diferencia medida (reducida) se toma como la corrección respecto de
    ese avance esperado. Así funciona aunque el avance real supere pi por muestra.
    """
    esperado = 0.5 * (vel[:-1] + vel[1:]) * np.diff(t)
    salto = esperado + envolver(np.diff(theta) - esperado)
    return theta[0] + np.concatenate([[0.0], np.cumsum(salto)])


def limpiar(d):
    """Ordena por t_us y descarta repetidos (misma seq o mismo instante)."""
    orden = np.argsort(d["t"], kind="stable")
    d = {k: v[orden] for k, v in d.items()}
    _, ok = np.unique(d["seq"], return_index=True)
    ok = np.sort(ok)
    d = {k: v[ok] for k, v in d.items()}
    mantener = np.concatenate([[True], np.diff(d["t"]) > 0])
    return {k: v[mantener] for k, v in d.items()}


def parametro_de_orden(theta):
    """theta: (nodos, tiempos). Devuelve r(t) y psi(t)."""
    z = np.exp(1j * theta).mean(axis=0)
    return np.abs(z), np.angle(z)


# --- Análisis de una corrida --------------------------------------------------------------

def analizar_corrida(directorio, dt=0.1, ventana_frac=0.2, tol_omega=0.01, umbral_sync=0.9,
                     escribir=True):
    """Analiza una corrida y devuelve un dict con las columnas de COLUMNAS."""
    directorio = Path(directorio)
    cfg = json.loads((directorio / "config.json").read_text())
    n = cfg["n"]
    omega = np.array([x["omega"] for x in cfg["nodos"]])
    sntp = cfg.get("sntp", 1)  # 0: t_us y t_inicio_ms no están en hora común (prueba local)
    fila = {c: "" for c in COLUMNAS}
    fila.update(
        corrida=cfg["corrida"], entrada=cfg["entrada"], config=cfg["config"], n=n,
        f_hz=cfg["f_hz"], ancho=cfg["ancho"], k_entrada=cfg["k_entrada"],
        k_rad_s=cfg["k_rad_s"], kc_rad_s=cfg["kc_rad_s"],
        k_veces_kc="" if cfg["k_veces_kc"] is None else cfg["k_veces_kc"], h_ms=cfg["h_ms"],
        perfil=cfg["perfil"], extrapolar=cfg["extrapolar"], semilla=cfg["semilla"], sntp=sntp,
    )

    red, _ = leer_fases(directorio / "fases.log")
    red = {i: limpiar(d) for i, d in red.items() if len(d["t"]) >= 3}
    # La UART trae la fase real aunque el broker o el enlace estén caídos, y sin importar con
    # qué esquema viajó. fases.log queda para contar mensajes y medir el retardo.
    uart, eventos_uart = leer_uart(directorio)
    uart = {i: limpiar(d) for i, d in uart.items() if len(d["t"]) >= 3}
    datos = uart or red
    fila["nodos_con_datos"] = len(datos)
    if len(datos) < 2:
        fila["estado"] = "sin_datos"
        return fila

    if red:
        mensajes = sum(len(d["t"]) for d in red.values())
        esperados = sum(int(d["seq"].max() - d["seq"].min() + 1) for d in red.values())
        fila["mensajes"] = mensajes
        fila["perdida_pct"] = round(100.0 * (1 - mensajes / esperados), 3)

    # Fase sin reducir de cada nodo y grilla común.
    ids = sorted(datos)
    fase = {i: desenvolver(datos[i]["t"], datos[i]["theta"], datos[i]["vel"]) for i in ids}
    t_lo = max(datos[i]["t"][0] for i in ids)
    t_hi = min(datos[i]["t"][-1] for i in ids)
    if t_hi <= t_lo:
        fila["estado"] = "sin_solape"
        return fila
    t_ref = cfg["t_inicio_ms"] / 1000.0 if sntp else t_lo  # origen del tiempo de la corrida
    grilla = np.arange(t_lo, t_hi, dt)
    theta = np.array([
        CubicHermiteSpline(datos[i]["t"] - t_ref, fase[i], datos[i]["vel"])(grilla - t_ref)
        for i in ids])
    r, psi = parametro_de_orden(theta)
    t_rel = grilla - t_ref

    # Con dos esquemas conviviendo, el orden de cada grupo por separado.
    esquema = {x["id"]: x.get("esquema", 0) for x in cfg["nodos"]}
    grupos = sorted({esquema[i] for i in ids})
    r_grupos = None
    if len(grupos) == 2:
        r_grupos = [parametro_de_orden(theta[[esquema[i] == g for i in ids]])[0] for g in grupos]

    # Ventana final.
    ancho_v = ventana_frac * (t_hi - t_lo)
    en_ventana = t_rel >= t_rel[-1] - ancho_v
    r_medio = float(r[en_ventana].mean())

    # Frecuencia efectiva de cada nodo: pendiente de su fase en la ventana, con las muestras reales.
    omega_ef = {}
    for i in ids:
        d = datos[i]
        m = d["t"] >= t_hi - ancho_v
        if m.sum() >= 3:
            omega_ef[i] = np.polyfit(d["t"][m] - t_hi, fase[i][m], 1)[0]
    ef = np.array(list(omega_ef.values()))
    dispersion = float(np.ptp(ef)) if len(ef) else float("nan")
    enganchado = bool(len(ef) == n and dispersion < tol_omega)
    omega_comun = float(ef.mean()) if len(ef) else float("nan")

    # Tiempo de sincronización: primer instante desde el cual r se mantiene sobre el umbral.
    t_sync = None
    if enganchado:
        debajo = np.nonzero(r < umbral_sync * r_medio)[0]
        if len(debajo) == 0:
            t_sync = float(t_rel[0])
        elif debajo[-1] + 1 < len(r):
            t_sync = float(t_rel[debajo[-1] + 1])

    # Retardo de entrega (solo tiene sentido con relojes sincronizados por SNTP).
    retardos = {i: (red[i]["recv"] - red[i]["t"]) * 1e3 for i in red} if sntp else {}
    todos = np.concatenate(list(retardos.values())) if retardos else np.array([])
    tau_ms = float(np.median(todos)) if len(todos) else 0.0

    # Predicciones de teoria.py.
    r_teo = teoria.r_enganchado(omega, cfg["k_rad_s"])
    omega_pred = None
    if cfg["config"] == "iguales":
        tau = tau_ms * 1e-3 + cfg["h_ms"] * 1e-3 / 2
        omega_pred = teoria.frecuencia_con_retardo(float(omega[0]), cfg["k_rad_s"], tau, n)

    fila.update(
        r_medio=round(r_medio, 5),
        r_teorico="" if r_teo is None else round(float(r_teo), 5),
        enganchado=int(enganchado),
        omega_dispersion=round(dispersion, 6),
        omega_comun=round(omega_comun, 6),
        t_sync_s="" if t_sync is None else round(t_sync, 2),
        omega_pred_retardo="" if omega_pred is None else round(float(omega_pred), 6),
        tau_usado_ms=round(tau_ms, 2),
        retardo_p50_ms=round(float(np.percentile(todos, 50)), 2) if len(todos) else "",
        retardo_p95_ms=round(float(np.percentile(todos, 95)), 2) if len(todos) else "",
        r_grupo_a="" if r_grupos is None else round(float(r_grupos[0][en_ventana].mean()), 5),
        r_grupo_b="" if r_grupos is None else round(float(r_grupos[1][en_ventana].mean()), 5),
        estado="ok" if len(datos) == n else f"faltan_{n - len(datos)}_nodos",
    )

    if escribir:
        with open(directorio / "serie.csv", "w", newline="") as f:
            w = csv.writer(f, delimiter=";")
            w.writerow(["t_s", "r", "psi"] + (["r_grupo_a", "r_grupo_b"] if r_grupos else []))
            cols = [np.round(t_rel, 3), np.round(r, 5), np.round(psi, 5)]
            cols += [np.round(x, 5) for x in r_grupos] if r_grupos else []
            w.writerows(zip(*cols))
        with open(directorio / "nodos_analisis.csv", "w", newline="") as f:
            w = csv.writer(f, delimiter=";")
            w.writerow(["id", "omega_natural", "omega_efectiva", "mensajes", "perdidos",
                        "retardo_p50_ms", "retardo_p95_ms"])
            for i in ids:
                d = datos[i]
                rt = retardos.get(i)
                w.writerow([
                    i, round(omega[i - 1], 6), round(omega_ef.get(i, float("nan")), 6),
                    len(d["t"]), int(d["seq"].max() - d["seq"].min() + 1 - len(d["t"])),
                    "" if rt is None else round(float(np.percentile(rt, 50)), 2),
                    "" if rt is None else round(float(np.percentile(rt, 95)), 2)])
        analizar_eventos(directorio, cfg, t_ref, t_rel, r, theta, psi, ids, eventos_uart)
    return fila


def analizar_eventos(directorio, cfg, t_ref, t_rel, r, theta, psi, ids, eventos_uart):
    """Escribe eventos_analisis.csv: efecto de cada caída del broker, corte o nodo que se suma."""
    ruta = directorio / "eventos.csv"
    filas = []
    if ruta.exists():
        with open(ruta, newline="") as f:
            # Instante programado: el registrado puede ser posterior a la acción.
            acciones = [(t_ref + float(x["t_previsto_s"]), x["accion"], int(x["nodo"]))
                        for x in csv.DictReader(f, delimiter=";")]
        voluntades = leer_voluntades(directorio / "fases.log")
        inicios = [a for a in acciones if a[1] in ("broker_cae", "corte_on")]
        for t_on, accion, nodo in inicios:
            cierre = "broker_vuelve" if accion == "broker_cae" else "corte_off"
            t_off = min(a[0] for a in acciones if a[1] == cierre and a[2] == nodo and a[0] > t_on)
            siguiente = min([a[0] for a in inicios if a[0] > t_on], default=np.inf)
            on, off, limite = t_on - t_ref, t_off - t_ref, min(siguiente - t_ref, t_rel[-1])
            antes = (t_rel >= on - 5.0) & (t_rel < on)
            r_antes = float(r[antes].mean()) if antes.any() else float("nan")
            durante = (t_rel >= on) & (t_rel <= limite)
            despues = (t_rel >= off) & (t_rel <= limite)
            debajo = np.nonzero(r[despues] < 0.95 * r_antes)[0]
            t_rec = 0.0 if len(debajo) == 0 else None
            if len(debajo) and debajo[-1] + 1 < despues.sum():
                t_rec = float(t_rel[despues][debajo[-1] + 1] - off)

            afectados = [nodo] if nodo else ids
            def primera_demora(tipo, desde):
                d = [min((t for i, ti, t, _ in eventos_uart if i == a and ti == tipo and t >= desde),
                         default=np.nan) - desde for a in afectados]
                return "" if np.all(np.isnan(d)) else round(float(np.nanmedian(d)), 3)

            desfase = ""
            if nodo in ids:
                k = ids.index(nodo)
                en_off = np.argmin(np.abs(t_rel - off))
                desfase = round(abs(float(envolver(theta[k, en_off] - psi[en_off]))), 4)
            # Solo hasta el próximo evento: al apagar los QEMU el broker publica todas las voluntades.
            will = [t - t_on for j, t in voluntades
                    if t_on <= t <= limite + t_ref and (not nodo or j == nodo)]
            filas.append({
                "evento": accion, "nodo": nodo, "t_s": round(on, 2), "dur_s": round(off - on, 2),
                "r_antes": round(r_antes, 4),
                "r_al_terminar": round(float(r[np.argmin(np.abs(t_rel - off))]), 4),
                "r_min": round(float(r[durante].min()), 4) if durante.any() else "",
                "t_recuperacion_s": "" if t_rec is None else round(t_rec, 2),
                "desfase_nodo_rad": desfase,
                "cliente_detecta_s": primera_demora("DESC", t_on),
                "cliente_reconecta_s": primera_demora("CONN", t_off),
                "voluntad_llega_s": round(min(will), 3) if will else "",
            })
    for i, tipo, t, _ in eventos_uart:
        if tipo == "UNION" and i in ids:
            k, on = ids.index(i), t - t_ref
            des = np.abs(envolver(theta[k] - psi))
            desp = t_rel >= on
            # Integrado: su desfase respecto de psi queda cerca del valor con el que termina.
            final = t_rel >= t_rel[-1] - 10.0
            fuera = np.nonzero(np.abs(des[desp] - des[final].mean()) >= 0.15)[0]
            filas.append({
                "evento": "union", "nodo": i, "t_s": round(on, 2), "dur_s": "",
                "r_antes": "", "r_al_terminar": "", "r_min": "",
                "t_recuperacion_s": "" if len(fuera) and fuera[-1] + 1 >= desp.sum() else
                    (0.0 if len(fuera) == 0 else round(float(t_rel[desp][fuera[-1] + 1] - on), 2)),
                "desfase_nodo_rad": round(float(des[desp][-1]), 4), "cliente_detecta_s": "",
                "cliente_reconecta_s": "", "voluntad_llega_s": "",
            })
    if filas:
        with open(directorio / "eventos_analisis.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(filas[0]), delimiter=";")
            w.writeheader()
            w.writerows(filas)


def main():
    ap = argparse.ArgumentParser(description="Analiza corridas de Kuramoto.")
    ap.add_argument("ruta", help="directorio de una matriz o de una corrida")
    ap.add_argument("--dt", type=float, default=0.1, help="paso de la grilla común, en s")
    ap.add_argument("--ventana", type=float, default=0.2, help="fracción final para r medio y Omega")
    ap.add_argument("--tol-omega", type=float, default=0.01,
                    help="dispersión máxima de frecuencias efectivas para decir que engancharon (rad/s)")
    ap.add_argument("--umbral-sync", type=float, default=0.9,
                    help="fracción de r medio que r(t) debe mantener para dar por sincronizado")
    a = ap.parse_args()

    ruta = Path(a.ruta)
    if (ruta / "config.json").exists():
        carpetas, destino = [ruta], ruta.parent / "resumen.csv"
    else:
        carpetas = sorted(p.parent for p in ruta.glob("*/fases.log"))
        destino = ruta / "resumen.csv"
    if not carpetas:
        sys.exit("no hay corridas con fases.log")
    filas = []
    for c in carpetas:
        fila = analizar_corrida(c, a.dt, a.ventana, a.tol_omega, a.umbral_sync)
        filas.append(fila)
        print(f"{fila['corrida']}: r={fila['r_medio']} (teoría {fila['r_teorico']}) "
              f"enganchado={fila['enganchado']} Omega={fila['omega_comun']} [{fila['estado']}]")
    with open(destino, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNAS, delimiter=";")
        w.writeheader()
        w.writerows(filas)
    print(f"escrito {destino}")


if __name__ == "__main__":
    main()
