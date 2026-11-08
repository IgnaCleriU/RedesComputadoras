#!/usr/bin/env python3
"""Tráfico de una corrida a partir de captura.pcap: bytes por sentido y anatomía de un PUBLISH.

Lee la captura de br-kur (Ethernet) a mano. Separa el tráfico hacia el broker (subida) del
que sale de él (bajada), cuenta tramas y bytes, y descompone el PUBLISH más frecuente de cada sentido
que empiece justo al comienzo de un segmento TCP. Los conteos no dependen de que los segmentos
estén alineados con los paquetes MQTT; solo la anatomía lo necesita. Se mide únicamente la
ventana de la corrida, entre t_inicio y t_inicio + duración.

Escribe trafico.csv en la corrida y trafico.csv (una fila por corrida) en la matriz.

Uso:  trafico.py resultados/<matriz>   (todas las corridas con captura.pcap)
"""

import argparse
import collections
import csv
import json
import struct
import sys
from pathlib import Path

PUERTO = 1883
BROKER = bytes([10, 10, 0, 1])
COLUMNAS = [
    "corrida", "n", "h_ms", "alias", "qos", "duracion_captura_s", "tramas_subida", "bytes_subida",
    "tramas_bajada", "bytes_bajada", "bytes_por_s_total", "bytes_por_s_subida_nodo",
    "bytes_por_s_bajada_nodo", "publish_subida_B", "cabecera_mqtt_subida_B", "topico_subida_B",
    "protobuf_subida_B", "publish_bajada_B", "cabecera_mqtt_bajada_B", "topico_bajada_B",
    "protobuf_bajada_B", "retransmisiones",
]


def tramas(ruta):
    """Genera (instante, bytes de la trama) de un pcap Ethernet."""
    with open(ruta, "rb") as f:
        cab = f.read(24)
        if len(cab) < 24:
            return
        magia = struct.unpack("<I", cab[:4])[0]
        if magia in (0xA1B2C3D4, 0xA1B23C4D):
            orden, div = "<", 1e6 if magia == 0xA1B2C3D4 else 1e9
        else:
            orden, div = ">", 1e6
        while len(reg := f.read(16)) == 16:
            seg, frac, guardado, _ = struct.unpack(orden + "IIII", reg)
            dato = f.read(guardado)
            if len(dato) < guardado:
                return
            yield seg + frac / div, dato


def varint_mqtt(b, i):
    """Entero de longitud variable de MQTT. Devuelve (valor, próximo índice)."""
    valor, mult = 0, 1
    while True:
        byte = b[i]
        i += 1
        valor += (byte & 0x7F) * mult
        if not byte & 0x80:
            return valor, i
        mult *= 128


def anatomia_publish(tcp):
    """Descompone un PUBLISH al comienzo del segmento: (total, cabecera, tópico, carga) o None."""
    try:
        if tcp[0] >> 4 != 3:
            return None
        qos = (tcp[0] >> 1) & 3
        resto, i = varint_mqtt(tcp, 1)
        inicio_var = i
        largo_topico = struct.unpack(">H", tcp[i:i + 2])[0]
        topico = tcp[i + 2:i + 2 + largo_topico]
        if largo_topico and not topico.startswith(b"kuramoto/"):
            return None  # el segmento no empieza en un PUBLISH de fase
        i += 2 + largo_topico
        if qos:
            i += 2
        largo_prop, i = varint_mqtt(tcp, i)
        i += largo_prop
        total = inicio_var + resto
        carga = total - i
        if carga <= 0 or total > len(tcp):
            return None
        return total, i, largo_topico, carga
    except (IndexError, struct.error):
        return None


def analizar(directorio):
    directorio = Path(directorio)
    cfg = json.loads((directorio / "config.json").read_text())
    fila = dict.fromkeys(COLUMNAS, "")
    fila.update(corrida=cfg["corrida"], n=cfg["n"], h_ms=cfg["h_ms"], alias=cfg.get("alias", 0),
                qos=cfg.get("qos", 0))
    cuenta = {"subida": [0, 0], "bajada": [0, 0]}
    anatomia = {"subida": collections.Counter(), "bajada": collections.Counter()}
    vistos = {}
    retrans = 0
    # Solo la ventana de la corrida: el arranque y el cierre no representan el régimen.
    inicio = cfg["t_inicio_ms"] / 1000.0
    fin = inicio + cfg["duracion_s"]
    for t, f in tramas(directorio / "captura.pcap"):
        if not inicio <= t <= fin:
            continue
        if len(f) < 54 or f[12:14] != b"\x08\x00":
            continue
        ihl = (f[14] & 0x0F) * 4
        if f[23] != 6:
            continue
        ip = 14
        tcp = ip + ihl
        origen, destino = f[ip + 12:ip + 16], f[ip + 16:ip + 20]
        p_org, p_dst, seq = struct.unpack(">HHI", f[tcp:tcp + 8])
        if PUERTO not in (p_org, p_dst):
            continue
        sentido = "subida" if destino == BROKER else "bajada" if origen == BROKER else None
        if sentido is None:
            continue
        cuenta[sentido][0] += 1
        cuenta[sentido][1] += len(f)
        offset = (f[tcp + 12] >> 4) * 4
        largo_ip = struct.unpack(">H", f[ip + 2:ip + 4])[0]
        carga = f[tcp + offset:ip + largo_ip]
        if carga:
            flujo = (origen, destino, p_org, p_dst)
            if seq in vistos.setdefault(flujo, set()):
                retrans += 1
            vistos[flujo].add(seq)
            if a := anatomia_publish(carga):
                anatomia[sentido][a] += 1
    dur = float(cfg["duracion_s"])
    if not cuenta["subida"][0]:
        return fila
    fila.update(
        duracion_captura_s=round(dur, 2), tramas_subida=cuenta["subida"][0],
        bytes_subida=cuenta["subida"][1], tramas_bajada=cuenta["bajada"][0],
        bytes_bajada=cuenta["bajada"][1],
        bytes_por_s_total=round((cuenta["subida"][1] + cuenta["bajada"][1]) / dur, 1),
        bytes_por_s_subida_nodo=round(cuenta["subida"][1] / dur / cfg["n"], 1),
        bytes_por_s_bajada_nodo=round(cuenta["bajada"][1] / dur / cfg["n"], 1),
        retransmisiones=retrans,
    )
    for sentido, conteo in anatomia.items():
        if not conteo:
            continue
        # El caso más frecuente: el primer PUBLISH con alias todavía lleva el tópico.
        (total, cab, topico, pb), _ = conteo.most_common(1)[0]
        fila[f"publish_{sentido}_B"] = total
        fila[f"cabecera_mqtt_{sentido}_B"] = cab
        fila[f"topico_{sentido}_B"] = topico
        fila[f"protobuf_{sentido}_B"] = pb
    return fila


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ruta", help="directorio de una matriz o de una corrida")
    ruta = Path(ap.parse_args().ruta)
    carpetas = [ruta] if (ruta / "captura.pcap").exists() else sorted(
        p.parent for p in ruta.glob("*/captura.pcap"))
    if not carpetas:
        sys.exit("no hay capturas")
    filas = [analizar(c) for c in carpetas]
    for c, f in zip(carpetas, filas):
        with open(c / "trafico.csv", "w", newline="") as a:
            w = csv.DictWriter(a, fieldnames=COLUMNAS, delimiter=";")
            w.writeheader()
            w.writerow(f)
        print(f"{f['corrida']}: {f['bytes_por_s_total']} B/s; PUBLISH subida {f['publish_subida_B']} B, "
              f"bajada {f['publish_bajada_B']} B; retransmisiones {f['retransmisiones']}")
    if len(carpetas) > 1:
        destino = carpetas[0].parent / "trafico.csv"
        with open(destino, "w", newline="") as a:
            w = csv.DictWriter(a, fieldnames=COLUMNAS, delimiter=";")
            w.writeheader()
            w.writerows(filas)
        print(f"escrito {destino}")


if __name__ == "__main__":
    main()
