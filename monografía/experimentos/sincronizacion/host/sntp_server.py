#!/usr/bin/env python3
"""Servidor SNTP mínimo (RFC 4330) que responde con la hora del host.

Port de comparacion-mqtt-http/backend/internal/sntp/sntp.go. Los nodos se sincronizan
contra él, así t_us (hora del nodo) y la hora de recepción del logger salen del mismo reloj.

Respuesta de 48 bytes: LI=0, versión del pedido, modo 4; stratum 1; poll copiado; precisión
0xEC (2^-20 s); refid "LOCL"; reference, receive = hora de llegada; originate = transmit del
cliente; transmit = hora justo antes de responder.

Uso como programa:  sntp_server.py [--host 0.0.0.0] [--puerto 123]
Uso como módulo:    srv = ServidorSNTP(host, puerto); srv.start(); ...; srv.detener()
"""

import argparse
import socket
import struct
import threading
import time

# Segundos entre 1900-01-01 (época NTP) y 1970-01-01 (época Unix).
OFFSET_NTP = 2208988800


def a_ntp(ns):
    """Convierte nanosegundos Unix al formato NTP de 64 bits (32 de segundos + 32 de fracción)."""
    segundos = ns // 1_000_000_000 + OFFSET_NTP
    fraccion = ((ns % 1_000_000_000) << 32) // 1_000_000_000
    return (segundos << 32) | fraccion


def responder(pedido, llegada_ns, ahora_ns):
    """Arma la respuesta a un pedido de cliente, o None si no corresponde responder."""
    if len(pedido) < 48 or (pedido[0] & 0x7) != 3:  # solo modo cliente
        return None
    version = (pedido[0] >> 3) & 0x7
    resp = bytearray(48)
    resp[0] = (version << 3) | 4  # LI=0, misma versión, modo servidor
    resp[1] = 1  # stratum 1: el host es la referencia
    resp[2] = pedido[2]  # poll
    resp[3] = 0xEC  # precisión ~2^-20 s
    resp[12:16] = b"LOCL"
    resp[16:24] = struct.pack(">Q", a_ntp(llegada_ns))  # reference
    resp[24:32] = pedido[40:48]  # originate = transmit del cliente
    resp[32:40] = struct.pack(">Q", a_ntp(llegada_ns))  # receive
    resp[40:48] = struct.pack(">Q", a_ntp(ahora_ns))  # transmit
    return bytes(resp)


class ServidorSNTP(threading.Thread):
    """Hilo que atiende pedidos SNTP hasta que se llama a detener()."""

    def __init__(self, host="0.0.0.0", puerto=123):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # REUSEADDR permite convivir con un chronyd o ntpd que escuche en 0.0.0.0:123.
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((host, puerto))
        self.sock.settimeout(0.2)
        self.puerto = self.sock.getsockname()[1]  # útil si se pidió el puerto 0
        self.atendidos = 0
        self._parar = threading.Event()

    def run(self):
        while not self._parar.is_set():
            try:
                datos, dir_ = self.sock.recvfrom(512)
            except socket.timeout:
                continue
            except OSError:
                return
            llegada = time.time_ns()
            resp = responder(datos, llegada, time.time_ns())
            if resp is not None:
                self.sock.sendto(resp, dir_)
                self.atendidos += 1

    def detener(self):
        self._parar.set()
        self.join(timeout=2)
        self.sock.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--puerto", type=int, default=123)
    a = ap.parse_args()
    srv = ServidorSNTP(a.host, a.puerto)
    print(f"SNTP en {a.host}:{srv.puerto}")
    srv.start()
    try:
        srv.join()
    except KeyboardInterrupt:
        srv.detener()
