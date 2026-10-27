// Package sntp es un servidor SNTP mínimo (RFC 4330) que responde con la hora
// del host. Los nodos se sincronizan contra él, así t_us (hora del nodo) y
// t_recv_us (hora del backend) salen del mismo reloj.
//
// Se usa un servidor propio en vez de chrony u otro demonio para no instalar nada
// y para que la referencia sea exactamente el reloj del proceso que registra.
//
// Respuesta (48 bytes):
//
//	byte 0      LI = 0, la versión del pedido, modo 4 (servidor)
//	byte 1      stratum 1: el host es la referencia
//	byte 2      poll, copiado del pedido
//	byte 3      precisión 0xEC = −20, o sea 2⁻²⁰ s ≈ 1 µs
//	12-15       refid "LOCL"
//	16-23       reference = hora de llegada del pedido
//	24-31       originate = transmit del cliente (bytes 40-47 del pedido)
//	32-39       receive   = hora de llegada del pedido
//	40-47       transmit  = hora justo antes de responder
//
// El cliente de lwIP usa transmit como hora actual sin compensar el viaje de
// vuelta: el nodo queda atrasado medio RTT (ver firmware/main/timesync.c).
package sntp

import (
	"encoding/binary"
	"log"
	"net"
	"time"
)

// Segundos entre 1900-01-01 (época NTP) y 1970-01-01 (época Unix).
const ntpEpochOffset = 2208988800

// toNTP convierte al formato NTP de 64 bits: 32 bits de segundos desde 1900 y 32
// bits de fracción de segundo (nanosegundos · 2³² / 10⁹).
func toNTP(t time.Time) uint64 {
	secs := uint64(t.Unix()) + ntpEpochOffset
	frac := (uint64(t.Nanosecond()) << 32) / 1e9
	return secs<<32 | frac
}

// Serve atiende pedidos hasta que la conexión se cierre.
func Serve(conn net.PacketConn) {
	buf := make([]byte, 512)
	for {
		n, addr, err := conn.ReadFrom(buf)
		if err != nil {
			return
		}
		recv := time.Now()
		if n < 48 {
			continue
		}
		req := buf[:48]
		mode := req[0] & 0x7
		if mode != 3 { // solo clientes
			continue
		}
		vn := (req[0] >> 3) & 0x7

		resp := make([]byte, 48)
		resp[0] = 0<<6 | vn<<3 | 4                           // LI=0, misma versión, modo servidor
		resp[1] = 1                                          // stratum 1: el host es la referencia
		resp[2] = req[2]                                     // poll
		resp[3] = 0xEC                                       // precisión ~2^-20 s
		copy(resp[12:16], "LOCL")                            // refid
		binary.BigEndian.PutUint64(resp[16:24], toNTP(recv)) // reference
		copy(resp[24:32], req[40:48])                        // originate = transmit del cliente
		binary.BigEndian.PutUint64(resp[32:40], toNTP(recv)) // receive
		binary.BigEndian.PutUint64(resp[40:48], toNTP(time.Now()))
		if _, err := conn.WriteTo(resp, addr); err != nil {
			log.Printf("sntp: %v", err)
		}
	}
}
