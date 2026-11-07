// Package pcap extrae de una captura (vía tshark) los bytes, paquetes,
// handshakes y retransmisiones del tráfico entre los nodos y el servidor.
//
// En vez de decodificar paquetes en Go usa tshark, que ya reconstruye las
// conexiones TCP (tcp.stream), reconoce registros TLS y detecta retransmisiones.
// Analyze hace dos pasadas sobre la captura, filtrando por el puerto de la corrida:
//
//  1. Un registro por paquete: hora, conexión, origen (si es 10.10.0.1, es
//     servidor → nodo), bytes de trama, IP y payload TCP, flags SYN/ACK y tipos de
//     registro TLS (22 handshake, 23 datos de aplicación).
//  2. Solo el número de conexión de cada paquete marcado como retransmisión.
//
// Solo cuentan las conexiones con el SYN del cliente en la captura. Las demás
// empezaron antes de la corrida (por ejemplo, FIN que el kernel sigue
// retransmitiendo a un nodo de la corrida anterior) y van a IgnoredFrames.
package pcap

import (
	"bufio"
	"bytes"
	"fmt"
	"os/exec"
	"sort"
	"strconv"
	"strings"
)

// Stream resume una conexión TCP.
type Stream struct {
	ID             int
	SynTime        float64 // epoch s del SYN del cliente (0 si la captura empezó después)
	HandshakeBytes int     // bytes IP antes del primer dato de aplicación
	HandshakePkts  int
	ConnectTimeS   float64 // SYN -> último paquete antes del primer dato de aplicación
	HasAppData     bool
}

// Summary agrega toda la captura filtrada por el puerto del servidor.
type Summary struct {
	Frames          int
	FrameBytes      int // bytes de trama Ethernet
	IPBytes         int // bytes IP (cabeceras IP + TCP + TLS + aplicación)
	UpBytes         int // IP, nodo -> servidor
	DownBytes       int // IP, servidor -> nodo
	PayloadTCPBytes int // bytes de payload TCP (TLS + aplicación)
	Retransmissions int
	IgnoredFrames   int // paquetes de conexiones abiertas antes de la corrida
	Streams         []Stream
}

type frame struct {
	t               float64
	stream          int
	src             string
	frameLen, ipLen int
	tcpLen          int
	syn, ack        bool
	tlsTypes        string
}

// Analyze lee la captura y considera solo el tráfico TCP con el puerto port.
func Analyze(path, serverIP string, port int, tls bool) (*Summary, error) {
	filter := fmt.Sprintf("tcp.port==%d", port)
	out, err := tshark(path, filter,
		"frame.time_epoch", "tcp.stream", "ip.src", "frame.len", "ip.len", "tcp.len",
		"tcp.flags.syn", "tcp.flags.ack", "tls.record.content_type")
	if err != nil {
		return nil, err
	}
	s := &Summary{}
	byStream := map[int][]frame{}
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		f := strings.Split(sc.Text(), "\t")
		if len(f) < 9 {
			continue
		}
		fr := frame{src: f[2], tlsTypes: f[8]}
		fr.t, _ = strconv.ParseFloat(f[0], 64)
		fr.stream, _ = strconv.Atoi(f[1])
		fr.frameLen, _ = strconv.Atoi(f[3])
		fr.ipLen, _ = strconv.Atoi(f[4])
		fr.tcpLen, _ = strconv.Atoi(f[5])
		fr.syn = isTrue(f[6])
		fr.ack = isTrue(f[7])

		byStream[fr.stream] = append(byStream[fr.stream], fr)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}

	// Solo cuentan las conexiones abiertas durante la corrida (con SYN en la
	// captura). Así se descartan restos de la corrida anterior, como FIN que el
	// kernel del host sigue retransmitiendo a un nodo que ya se apagó.
	ids := make([]int, 0, len(byStream))
	for id, frames := range byStream {
		if hasClientSyn(frames) {
			ids = append(ids, id)
		} else {
			s.IgnoredFrames += len(frames)
		}
	}
	sort.Ints(ids)
	valid := map[int]bool{}
	for _, id := range ids {
		valid[id] = true
		for _, fr := range byStream[id] {
			s.Frames++
			s.FrameBytes += fr.frameLen
			s.IPBytes += fr.ipLen
			s.PayloadTCPBytes += fr.tcpLen
			if fr.src == serverIP {
				s.DownBytes += fr.ipLen
			} else {
				s.UpBytes += fr.ipLen
			}
		}
		s.Streams = append(s.Streams, streamSummary(id, byStream[id], tls))
	}

	retr, err := tshark(path, filter+" && tcp.analysis.retransmission", "tcp.stream")
	if err != nil {
		return nil, err
	}
	for _, line := range strings.Split(string(retr), "\n") {
		if id, err := strconv.Atoi(strings.TrimSpace(line)); err == nil && valid[id] {
			s.Retransmissions++
		}
	}
	return s, nil
}

func hasClientSyn(frames []frame) bool {
	for _, f := range frames {
		if f.syn && !f.ack {
			return true
		}
	}
	return false
}

// streamSummary calcula el costo de abrir la conexión. El primer dato de
// aplicación es el primer registro TLS application_data (tipo 23) con TLS, o
// el primer segmento con payload sin TLS (CONNECT de MQTT o el POST).
// Todo lo anterior es el handshake: SYN, SYN-ACK, ACK y, con TLS, ClientHello,
// ServerHello, certificado, intercambio de claves y Finished. En MQTT el
// CONNECT/CONNACK queda fuera (es dato de aplicación), así los handshakes MQTT y
// HTTP son comparables.
func streamSummary(id int, frames []frame, tls bool) Stream {
	st := Stream{ID: id}
	first := -1
	for i, f := range frames {
		if f.syn && !f.ack && st.SynTime == 0 {
			st.SynTime = f.t
		}
		isApp := (tls && hasTLSType(f.tlsTypes, "23")) || (!tls && f.tcpLen > 0)
		if isApp {
			first = i
			break
		}
	}
	if first < 0 {
		first = len(frames)
	} else {
		st.HasAppData = true
	}
	for _, f := range frames[:first] {
		st.HandshakeBytes += f.ipLen
		st.HandshakePkts++
	}
	if st.SynTime > 0 && first > 0 && st.HasAppData {
		st.ConnectTimeS = frames[first-1].t - st.SynTime
	}
	return st
}

func hasTLSType(list, typ string) bool {
	for _, t := range strings.Split(list, ",") {
		if t == typ {
			return true
		}
	}
	return false
}

func isTrue(v string) bool { return v == "1" || v == "True" || v == "true" }

// tshark corre "tshark -r <captura> -n -Y <filtro> -T fields -e <campo>…": una
// línea por paquete con los campos separados por tabulador. Si un campo aparece
// varias veces en un paquete (varios registros TLS), occurrence=a + aggregator=,
// los junta separados por coma.
func tshark(path, filter string, fields ...string) ([]byte, error) {
	args := []string{"-r", path, "-n", "-Y", filter, "-T", "fields",
		"-E", "separator=/t", "-E", "occurrence=a", "-E", "aggregator=,"}
	for _, f := range fields {
		args = append(args, "-e", f)
	}
	cmd := exec.Command("tshark", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("tshark %s: %v: %s", path, err, stderr.String())
	}
	return out, nil
}
