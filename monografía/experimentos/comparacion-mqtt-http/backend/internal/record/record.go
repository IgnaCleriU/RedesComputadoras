// Package record es el código de registro común a los dos caminos (MQTT y HTTP).
// Cada lectura que llega, venga del broker o del servidor HTTP(S), pasa por
// Recorder.Record, así la medición es comparable.
//
// Se registran todas las llegadas, duplicados incluidos (pasa con MQTT QoS 1).
// La deduplicación la hace el analizador (cmd/analyze).
//
// Columnas de readings.csv:
//
//	path                          mqtt o http
//	esp_id, seq, t_us, value,     campos del mensaje
//	status
//	t_recv_us                     hora del backend al recibir (epoch, µs)
//	latency_us                    t_recv_us − t_us (relojes unidos por SNTP)
//	serialization                 pb o json
//	bytes_payload                 tamaño del payload de aplicación
//	src_esp                       nodo según el tópico o la URL (para detectar
//	                              inconsistencias con esp_id)
package record

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"sync"

	"google.golang.org/protobuf/proto"

	"wireguardians/exp/internal/pb"
)

// Header es el encabezado de readings.csv.
var Header = []string{
	"path", "esp_id", "seq", "t_us", "t_recv_us", "latency_us",
	"value", "status", "serialization", "bytes_payload", "src_esp",
}

// jsonTelemetry usa los mismos nombres de campo que el .proto.
type jsonTelemetry struct {
	EspID  uint32  `json:"esp_id"`
	Seq    uint32  `json:"seq"`
	TUs    uint64  `json:"t_us"`
	Value  float32 `json:"value"`
	Status uint32  `json:"status"`
}

// Decode interpreta el payload como JSON si empieza con '{' y como protobuf
// en otro caso. Un Telemetry en protobuf nunca empieza con '{' (0x7b): el
// primer byte es la etiqueta de un campo del 1 al 5.
func Decode(payload []byte) (*pb.Telemetry, string, error) {
	if len(payload) > 0 && payload[0] == '{' {
		var j jsonTelemetry
		if err := json.Unmarshal(payload, &j); err != nil {
			return nil, "json", err
		}
		return &pb.Telemetry{EspId: j.EspID, Seq: j.Seq, TUs: j.TUs, Value: j.Value, Status: j.Status}, "json", nil
	}
	var t pb.Telemetry
	if err := proto.Unmarshal(payload, &t); err != nil {
		return nil, "pb", err
	}
	return &t, "pb", nil
}

// EncodeJSON serializa con el mismo formato que usa el firmware.
func EncodeJSON(t *pb.Telemetry) []byte {
	b, _ := json.Marshal(jsonTelemetry{t.EspId, t.Seq, t.TUs, t.Value, t.Status})
	return b
}

// Recorder escribe una fila por lectura recibida, duplicados incluidos.
// El mutex protege al csv.Writer: llegan lecturas desde varias goroutines a la
// vez (una por conexión HTTP y una por mensaje MQTT).
type Recorder struct {
	mu    sync.Mutex
	f     *os.File
	w     *csv.Writer
	count int
	bad   int
}

func New(path string) (*Recorder, error) {
	f, err := os.Create(path)
	if err != nil {
		return nil, err
	}
	w := csv.NewWriter(f)
	if err := w.Write(Header); err != nil {
		f.Close()
		return nil, err
	}
	return &Recorder{f: f, w: w}, nil
}

// Record registra una lectura. path es "mqtt" o "http"; srcEsp es el número
// de nodo tomado del tópico o del endpoint, para detectar inconsistencias.
func (r *Recorder) Record(path string, srcEsp string, payload []byte, tRecvUs int64) error {
	t, ser, err := Decode(payload) // fuera del lock: no toca estado compartido
	r.mu.Lock()
	defer r.mu.Unlock()
	if err != nil {
		r.bad++
		return fmt.Errorf("payload inválido (%d bytes) desde %s/%s: %w", len(payload), path, srcEsp, err)
	}
	r.count++
	return r.w.Write([]string{
		path,
		strconv.FormatUint(uint64(t.EspId), 10),
		strconv.FormatUint(uint64(t.Seq), 10),
		strconv.FormatUint(t.TUs, 10),
		strconv.FormatInt(tRecvUs, 10),
		strconv.FormatInt(tRecvUs-int64(t.TUs), 10),
		strconv.FormatFloat(float64(t.Value), 'f', 4, 32),
		strconv.FormatUint(uint64(t.Status), 10),
		ser,
		strconv.Itoa(len(payload)),
		srcEsp,
	})
}

// Counts devuelve lecturas válidas e inválidas registradas.
func (r *Recorder) Counts() (int, int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.count, r.bad
}

func (r *Recorder) Flush() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.w.Flush()
	return r.w.Error()
}

func (r *Recorder) Close() error {
	if err := r.Flush(); err != nil {
		r.f.Close()
		return err
	}
	return r.f.Close()
}
