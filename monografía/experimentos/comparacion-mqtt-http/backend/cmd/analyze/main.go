// analyze recorre <runs>/*/rep*/ (por defecto datos/principal) y calcula las métricas del experimento:
//
//	<runs>/metrics.csv  una fila por corrida
//	<runs>/summary.csv  media y desvío por configuración
//
// Uso, desde experimento/:  ./backend/bin/analyze   (o -runs datos/nagle, datos/smoke, ...)
//
// Solo se analizan las corridas con config.json en estado "ok". Una corrida es
// válida si rtf_min ≥ -min-rtf (0,9 por defecto); summary.csv usa solo las válidas
// y da media y desvío muestral (n−1).
//
// Cada corrida combina tres fuentes (analyzeRun):
//   - readings.csv: lecturas únicas por (esp_id, seq), duplicados y latencia de la
//     primera llegada de cada lectura.
//   - nodes.csv: lecturas producidas (denominador de la entrega), fallidas,
//     descartadas, pendientes, overruns, RTF y desfase SNTP.
//   - capture.pcapng, vía internal/pcap: bytes, paquetes, handshakes y
//     retransmisiones del puerto del servidor de la corrida.
//
// Métricas principales ("por lectura" = dividido por delivered_unique):
//
//	delivery_rate             delivered_unique / produced
//	ip_bytes_per_reading      bytes IP del puerto del servidor / lecturas entregadas
//	                          (incluye TCP, TLS, ACKs, handshakes, cierres y retransmisiones)
//	frame_bytes_per_reading   igual, con bytes de trama Ethernet
//	packets_per_reading       paquetes / lecturas entregadas
//	handshake_bytes_per_conn  bytes de cada conexión antes del primer dato de aplicación
//	connect_ms_*              desde el SYN hasta el último paquete del handshake
//	latency_ms_*              t_recv − t_us de la primera llegada (media, p50, p95, p99)
//	duplicates                lecturas recibidas más de una vez (QoS 1)
//	pending_unsent            lecturas en la cola del nodo al vencer el margen de vaciado
//	overruns                  períodos en los que el productor llegó tarde
//	rtf_min, rtf_mean         Δesp_timer / Δhora del host entre las MARK de la UART
//
// Para agregar una métrica alcanza con agregarla a la lista que devuelve
// analyzeRun: aparece sola en metrics.csv y, con media y desvío, en summary.csv.
package main

import (
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"

	"wireguardians/exp/internal/matrix"
	"wireguardians/exp/internal/pcap"
)

const serverIP = "10.10.0.1"

type runMeta struct {
	matrix.Config
	ConfigID string `json:"config_id"`
	Rep      int    `json:"rep"`
	Port     int    `json:"port"`
	Status   string `json:"status"`
}

// metric es una columna numérica de metrics.csv; las de summary.csv salen de acá.
type metric struct {
	name string
	val  float64
}

func main() {
	runsDir := flag.String("runs", "datos/principal", "directorio de corridas")
	minRTF := flag.Float64("min-rtf", 0.9, "factor de tiempo real mínimo para considerar válida una corrida")
	flag.Parse()

	dirs, _ := filepath.Glob(filepath.Join(*runsDir, "*", "rep*"))
	sort.Strings(dirs)

	type row struct {
		meta    runMeta
		metrics []metric
		valid   bool
	}
	var rows []row
	for _, d := range dirs {
		meta, err := loadMeta(d)
		if err != nil || meta.Status != "ok" {
			log.Printf("%s: se omite (%v, estado %q)", d, err, meta.Status)
			continue
		}
		ms, err := analyzeRun(d, meta)
		if err != nil {
			log.Printf("%s: %v", d, err)
			continue
		}
		valid := get(ms, "rtf_min") >= *minRTF
		if !valid {
			log.Printf("%s: RTF mínimo %.3f < %.2f, marcada como no válida", d, get(ms, "rtf_min"), *minRTF)
		}
		rows = append(rows, row{meta, ms, valid})
		log.Printf("%s: %.0f lecturas, %.1f B/lectura, entrega %.2f%%", d,
			get(ms, "delivered_unique"), get(ms, "ip_bytes_per_reading"), 100*get(ms, "delivery_rate"))
	}
	if len(rows) == 0 {
		log.Fatal("no hay corridas completas para analizar")
	}

	// metrics.csv
	confCols := []string{"config_id", "rep", "factor", "transport", "nodes", "period_ms", "tls", "loss_pct", "rtt_ms", "serialization", "nodelay", "duration_s", "valid"}
	confVals := func(m runMeta) []string {
		return []string{m.ConfigID, strconv.Itoa(m.Rep), m.Factor, m.Transport, strconv.Itoa(m.Nodes),
			strconv.Itoa(m.PeriodMs), strconv.FormatBool(m.TLS), strconv.FormatFloat(m.LossPct, 'g', -1, 64),
			strconv.Itoa(m.RttMs), m.Serialization, strconv.FormatBool(m.Nodelay), strconv.Itoa(m.DurationS)}
	}
	names := make([]string, len(rows[0].metrics))
	for i, m := range rows[0].metrics {
		names[i] = m.name
	}
	err := writeCSV(filepath.Join(*runsDir, "metrics.csv"), append(append([]string{}, confCols...), names...), func(w *csv.Writer) {
		for _, r := range rows {
			rec := append(confVals(r.meta), strconv.FormatBool(r.valid))
			for _, m := range r.metrics {
				rec = append(rec, fmtF(m.val))
			}
			w.Write(rec)
		}
	})
	if err != nil {
		log.Fatal(err)
	}

	// summary.csv: solo corridas válidas
	groups := map[string][]row{}
	var order []string
	for _, r := range rows {
		if !r.valid {
			continue
		}
		if _, ok := groups[r.meta.ConfigID]; !ok {
			order = append(order, r.meta.ConfigID)
		}
		groups[r.meta.ConfigID] = append(groups[r.meta.ConfigID], r)
	}
	sort.Strings(order)
	header := append(append([]string{}, confCols[:1]...), confCols[2:12]...)
	header = append(header, "n_runs")
	for _, n := range names {
		header = append(header, n+"_mean", n+"_std")
	}
	err = writeCSV(filepath.Join(*runsDir, "summary.csv"), header, func(w *csv.Writer) {
		for _, id := range order {
			g := groups[id]
			cv := confVals(g[0].meta)
			rec := append(append([]string{}, cv[:1]...), cv[2:12]...)
			rec = append(rec, strconv.Itoa(len(g)))
			for i := range names {
				vals := make([]float64, len(g))
				for j, r := range g {
					vals[j] = r.metrics[i].val
				}
				mean, std := meanStd(vals)
				rec = append(rec, fmtF(mean), fmtF(std))
			}
			w.Write(rec)
		}
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("%d corridas -> %s/metrics.csv, %d configuraciones -> %s/summary.csv", len(rows), *runsDir, len(order), *runsDir)
}

func analyzeRun(dir string, meta runMeta) ([]metric, error) {
	// Lecturas registradas por el backend
	recs, err := readCSV(filepath.Join(dir, "readings.csv"))
	if err != nil {
		return nil, err
	}
	// Filas en orden de llegada: la primera vez que aparece (esp_id, seq) se guarda
	// su latencia y su payload; las siguientes son duplicados.
	type key struct{ esp, seq string }
	firstLat := map[key]float64{}
	received, dup := 0, 0
	payloadSum := 0.0
	for _, r := range recs {
		received++
		k := key{r["esp_id"], r["seq"]}
		lat, _ := strconv.ParseFloat(r["latency_us"], 64)
		if _, ok := firstLat[k]; ok {
			dup++
			continue
		}
		firstLat[k] = lat / 1000 // ms
		p, _ := strconv.ParseFloat(r["bytes_payload"], 64)
		payloadSum += p
	}
	lats := make([]float64, 0, len(firstLat))
	for _, l := range firstLat {
		lats = append(lats, l)
	}
	sort.Float64s(lats)
	unique := float64(len(firstLat))

	// Estado de los nodos según la UART
	nodes, err := readCSV(filepath.Join(dir, "nodes.csv"))
	if err != nil {
		return nil, err
	}
	var produced, sendFailed, queueDrops, pending, overruns, disconnects, httpErrors, httpRetries float64
	rtfMin, rtfSum, syncAbsMax := math.Inf(1), 0.0, 0.0
	for _, n := range nodes {
		produced += atof(n["produced"])
		sendFailed += atof(n["failed"])
		queueDrops += atof(n["queue_drops"])
		pending += atof(n["pending"])
		overruns += atof(n["overruns"])
		disconnects += atof(n["mqtt_disconnects"])
		httpErrors += atof(n["http_errors"])
		httpRetries += atof(n["http_retries_ok"])
		rtf := atof(n["rtf"])
		rtfMin = math.Min(rtfMin, rtf)
		rtfSum += rtf
		syncAbsMax = math.Max(syncAbsMax, math.Abs(atof(n["sync_offset_median_us"]))/1000)
	}

	// Captura
	cap, err := pcap.Analyze(filepath.Join(dir, "capture.pcapng"), serverIP, meta.Port, meta.TLS)
	if err != nil {
		return nil, err
	}
	var conns, hsBytes, hsPkts float64
	var connTimes []float64
	for _, s := range cap.Streams {
		if s.SynTime == 0 {
			continue
		}
		conns++
		hsBytes += float64(s.HandshakeBytes)
		hsPkts += float64(s.HandshakePkts)
		if s.HasAppData {
			connTimes = append(connTimes, s.ConnectTimeS*1000)
		}
	}
	sort.Float64s(connTimes)

	per := func(x float64) float64 { return div(x, unique) }
	return []metric{
		{"produced", produced},
		{"received", float64(received)},
		{"delivered_unique", unique},
		{"duplicates", float64(dup)},
		{"delivery_rate", div(unique, produced)},
		{"duplicate_rate", div(float64(dup), unique)},
		{"send_failed", sendFailed},
		{"queue_drops", queueDrops},
		{"pending_unsent", pending},
		{"payload_bytes_mean", div(payloadSum, unique)},
		{"latency_ms_mean", mean(lats)},
		{"latency_ms_p50", quantile(lats, 0.50)},
		{"latency_ms_p95", quantile(lats, 0.95)},
		{"latency_ms_p99", quantile(lats, 0.99)},
		{"frames", float64(cap.Frames)},
		{"ip_bytes", float64(cap.IPBytes)},
		{"ip_bytes_up", float64(cap.UpBytes)},
		{"ip_bytes_down", float64(cap.DownBytes)},
		{"ip_bytes_per_reading", per(float64(cap.IPBytes))},
		{"frame_bytes_per_reading", per(float64(cap.FrameBytes))},
		{"packets_per_reading", per(float64(cap.Frames))},
		{"connections", conns},
		{"handshake_bytes_per_conn", div(hsBytes, conns)},
		{"handshake_pkts_per_conn", div(hsPkts, conns)},
		{"handshake_bytes_share", div(hsBytes, float64(cap.IPBytes))},
		{"connect_ms_mean", mean(connTimes)},
		{"connect_ms_p50", quantile(connTimes, 0.50)},
		{"retransmissions", float64(cap.Retransmissions)},
		{"ignored_frames_prev_run", float64(cap.IgnoredFrames)},
		{"mqtt_disconnects", disconnects},
		{"http_errors", httpErrors},
		{"http_retries_ok", httpRetries},
		{"overruns", overruns},
		{"rtf_min", rtfMin},
		{"rtf_mean", div(rtfSum, float64(len(nodes)))},
		{"sync_offset_abs_max_ms", syncAbsMax},
	}, nil
}

func get(ms []metric, name string) float64 {
	for _, m := range ms {
		if m.name == name {
			return m.val
		}
	}
	return math.NaN()
}

func loadMeta(dir string) (runMeta, error) {
	var m runMeta
	b, err := os.ReadFile(filepath.Join(dir, "config.json"))
	if err != nil {
		return m, err
	}
	return m, json.Unmarshal(b, &m)
}

func readCSV(path string) ([]map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	r := csv.NewReader(f)
	header, err := r.Read()
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	var out []map[string]string
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		m := make(map[string]string, len(header))
		for i, h := range header {
			if i < len(rec) {
				m[h] = rec[i]
			}
		}
		out = append(out, m)
	}
	return out, nil
}

func writeCSV(path string, header []string, fill func(*csv.Writer)) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	w := csv.NewWriter(f)
	w.Write(header)
	fill(w)
	w.Flush()
	return w.Error()
}

func atof(s string) float64 {
	v, _ := strconv.ParseFloat(s, 64)
	return v
}

func div(a, b float64) float64 {
	if b == 0 {
		return math.NaN()
	}
	return a / b
}

func mean(v []float64) float64 {
	if len(v) == 0 {
		return math.NaN()
	}
	s := 0.0
	for _, x := range v {
		s += x
	}
	return s / float64(len(v))
}

// meanStd devuelve la media y el desvío estándar muestral (n-1).
func meanStd(v []float64) (float64, float64) {
	m := mean(v)
	if len(v) < 2 {
		return m, math.NaN()
	}
	ss := 0.0
	for _, x := range v {
		ss += (x - m) * (x - m)
	}
	return m, math.Sqrt(ss / float64(len(v)-1))
}

// quantile sobre un slice ordenado (interpolación lineal entre los dos valores
// vecinos de la posición q·(n−1), contando desde 0).
func quantile(sorted []float64, q float64) float64 {
	if len(sorted) == 0 {
		return math.NaN()
	}
	pos := q * float64(len(sorted)-1)
	lo := int(math.Floor(pos))
	hi := int(math.Ceil(pos))
	return sorted[lo] + (sorted[hi]-sorted[lo])*(pos-float64(lo))
}

func fmtF(v float64) string {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return ""
	}
	return strconv.FormatFloat(v, 'f', 4, 64)
}
