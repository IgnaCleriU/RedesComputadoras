#!/usr/bin/env python3
"""Análisis puntuales de captura.pcap en el experimento de sincronización.

  ventana: por tramos de 10 s, entregas y antigüedad; con QoS 1, entregas sin confirmar por nodo.
  corte:   paquetes de un nodo alrededor de un corte: PINGREQ, PINGRESP, retransmisiones y cierre.

Uso (desde experimentos/sincronizacion/):
    uv run --no-sync python host/capturas.py ventana resultados/final/<corrida>
    uv run --no-sync python host/capturas.py corte resultados/final/<corrida> --nodo 10 --desde 15 --hasta 45
Los tiempos del corte son relativos a t_inicio. La captura ve la bajada antes de netem y la subida después.
"""

import argparse
import collections
import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analizar import decodificar  # noqa: E402
from trafico import BROKER, PUERTO, tramas, varint_mqtt  # noqa: E402

LIMITE_EN_TRANSITO = 20  # max_inflight_messages por defecto de Mosquitto
TIPOS = {1: "CONNECT", 2: "CONNACK", 3: "PUBLISH", 4: "PUBACK", 8: "SUBSCRIBE", 9: "SUBACK",
         12: "PINGREQ", 13: "PINGRESP", 14: "DISCONNECT"}


def segmentos(ruta):
    """Genera (t, ip origen, ip destino, puerto origen, puerto destino, seq, banderas, carga) del tráfico MQTT."""
    for t, f in tramas(ruta):
        if len(f) < 54 or f[12:14] != b"\x08\x00" or f[23] != 6:
            continue
        tcp = 14 + (f[14] & 0x0F) * 4
        origen, destino, seq = struct.unpack(">HHI", f[tcp:tcp + 8])
        if PUERTO not in (origen, destino):
            continue
        inicio = tcp + (f[tcp + 12] >> 4) * 4
        yield t, f[26:30], f[30:34], origen, destino, seq, f[tcp + 13], bytes(f[inicio:14 + struct.unpack(">H", f[16:18])[0]])


def mensajes(partes):
    """Recorre un flujo TCP {seq: (t, carga)} y devuelve [(t, tipo, paquete, inicio del encabezado variable)]."""
    flujo, tiempos, esperado = bytearray(), [], None
    for seq in sorted(partes):
        t, carga = partes[seq]
        if esperado is not None and seq != esperado:
            break  # hueco en la captura: el resto no se puede alinear
        flujo += carga
        tiempos += [t] * len(carga)
        esperado = seq + len(carga)
    i, salida = 0, []
    while i < len(flujo):
        try:
            resto, j = varint_mqtt(flujo, i + 1)
        except IndexError:
            break
        total = j + resto
        if total > len(flujo):
            break
        salida.append((tiempos[total - 1], flujo[i] >> 4, bytes(flujo[i:total]), j - i))
        i = total
    return salida


def ventana(directorio):
    cfg = json.loads((directorio / "config.json").read_text())
    inicio, fin = cfg["t_inicio_ms"] / 1000.0, cfg["t_inicio_ms"] / 1000.0 + cfg["duracion_s"]
    bajada, subida = collections.defaultdict(dict), collections.defaultdict(dict)
    for t, ip_o, ip_d, p_o, p_d, seq, _, carga in segmentos(directorio / "captura.pcap"):
        if not carga:
            continue
        if ip_o == BROKER:
            bajada[(ip_d, p_d)].setdefault(seq, (t, carga))
        else:
            subida[(ip_o, p_o)].setdefault(seq, (t, carga))
    edades, en_transito = [], []
    for clave, partes in bajada.items():
        publicados = [m for m in mensajes(partes) if m[1] == 3 and inicio <= m[0] <= fin]
        if not publicados:
            continue
        for t, _, b, j in publicados:
            k = j + 2 + struct.unpack(">H", b[j:j + 2])[0] + (2 if (b[0] >> 1) & 3 else 0)
            largo, k = varint_mqtt(b, k)
            edades.append((t - inicio, t - decodificar(b[k + largo:])["t_us"] * 1e-6))
        acks = np.array([m[0] for m in mensajes(subida.get(clave, {})) if m[1] == 4 and inicio <= m[0] <= fin])
        if len(acks):
            # Los instantes se ordenan: en orden de flujo, una retransmisión puede quedar desordenada en el tiempo.
            t_pub, acks = np.sort([m[0] for m in publicados]), np.sort(acks)
            sin_confirmar = np.arange(1, len(t_pub) + 1) - np.searchsorted(acks, t_pub, side="right")
            # Ocupación ponderada por tiempo: +1 en cada envío, -1 en cada confirmación.
            cambios = np.concatenate([t_pub, acks])
            signos = np.concatenate([np.ones(len(t_pub)), -np.ones(len(acks))])
            orden = np.argsort(cambios, kind="stable")
            nivel = np.clip(np.cumsum(signos[orden]), 0, None)
            duracion = np.diff(cambios[orden])
            en_limite = duracion[nivel[:-1] >= LIMITE_EN_TRANSITO].sum() / duracion.sum()
            en_transito.append((int(sin_confirmar.max()), float(np.median(sin_confirmar)), float(en_limite)))
    a = np.array(edades)
    print(f"{directorio.name}: {len(a)} entregas")
    for desde in range(0, int(cfg["duracion_s"]), 10):
        m = (a[:, 0] >= desde) & (a[:, 0] < desde + 10)
        if m.any():
            print(f"  {desde:3d}-{desde + 10:3d} s: {m.sum():5d} entregas, antigüedad p50 {np.median(a[m, 1]) * 1e3:9.1f} ms, "
                  f"p95 {np.percentile(a[m, 1], 95) * 1e3:9.1f} ms")
    if en_transito:
        b = np.array(en_transito)
        print(f"  sin confirmar: máximo por nodo {b[:, 0].min():.0f} a {b[:, 0].max():.0f}, mediana en cada envío {np.median(b[:, 1]):.0f}, "
              f"tiempo en el límite de {LIMITE_EN_TRANSITO}: {100 * b[:, 2].min():.0f} a {100 * b[:, 2].max():.0f} % según el nodo")


def corte(directorio, nodo, desde, hasta):
    cfg = json.loads((directorio / "config.json").read_text())
    inicio = cfg["t_inicio_ms"] / 1000.0
    ip_nodo = bytes([10, 10, 0, 10 + nodo])
    vistos = set()
    print(f"{directorio.name}: nodo {nodo}")
    print((directorio / "eventos.csv").read_text().strip())
    for t, ip_o, ip_d, _, _, seq, banderas, carga in segmentos(directorio / "captura.pcap"):
        if ip_nodo not in (ip_o, ip_d):
            continue
        sentido = "nodo -> broker" if ip_o == ip_nodo else "broker -> nodo"
        repetido = bool(carga) and (sentido, seq) in vistos
        if carga:
            vistos.add((sentido, seq))
        tipo = TIPOS.get(carga[0] >> 4, "") if carga else ""
        marcas = "".join(n for n, bit in (("SYN ", 2), ("FIN ", 1), ("RST ", 4)) if banderas & bit)
        if desde <= t - inicio <= hasta and (repetido or marcas or tipo in ("PINGREQ", "PINGRESP")):
            print(f"  {t - inicio:8.3f} s  {sentido}  {len(carga):4d} B  {tipo:9s} {marcas}{'retransmisión' if repetido else ''}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("analisis", choices=["ventana", "corte"])
    ap.add_argument("corrida", type=Path)
    ap.add_argument("--nodo", type=int, default=10)
    ap.add_argument("--desde", type=float, default=0.0)
    ap.add_argument("--hasta", type=float, default=1e9)
    a = ap.parse_args()
    if a.analisis == "ventana":
        ventana(a.corrida)
    else:
        corte(a.corrida, a.nodo, a.desde, a.hasta)


if __name__ == "__main__":
    main()
