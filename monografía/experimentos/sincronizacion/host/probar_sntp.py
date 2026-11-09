#!/usr/bin/env python3
"""Prueba del servidor SNTP con un pedido UDP local en un puerto sin privilegios."""

import socket
import struct
import time

from sntp_server import OFFSET_NTP, ServidorSNTP

srv = ServidorSNTP("127.0.0.1", 0)
srv.start()
c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
c.settimeout(2)
pedido = bytearray(48)
pedido[0] = (0 << 6) | (4 << 3) | 3  # LI=0, v4, modo cliente
pedido[2] = 6
pedido[40:48] = b"\x01\x02\x03\x04\x05\x06\x07\x08"
antes = time.time()
c.sendto(bytes(pedido), ("127.0.0.1", srv.puerto))
resp, _ = c.recvfrom(512)
despues = time.time()
srv.detener()

assert len(resp) == 48
assert resp[0] & 0x7 == 4 and (resp[0] >> 3) & 0x7 == 4 and resp[1] == 1
assert resp[24:32] == pedido[40:48], "originate debe copiar el transmit del cliente"
seg, frac = struct.unpack(">II", resp[40:48])
t = seg - OFFSET_NTP + frac / 2**32
assert antes - 0.01 <= t <= despues + 0.01, (antes, t, despues)
print(f"SNTP ok: transmit dentro de la ventana, desvio {1e3 * (t - antes):.3f} ms, puerto {srv.puerto}")
