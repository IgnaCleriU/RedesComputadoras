// Backend de medición contra el nodo de eco MQTT (firmware/).
//
//	eco -label real  suite              # latencia (eco) y throughput (flood) para cada tamaño y QoS
//	eco compare resultados/real resultados/qemu
//	eco -nodes 32 -label escala multi   # los nodos q1..q32 de nodos.sh, todos a la vez
//
// La latencia es el RTT PC→broker→ESP32→broker→PC medido con el reloj de la PC:
// no hace falta sincronizar relojes.
package main

import (
	"encoding/binary"
	"encoding/csv"
	"flag"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
)

var (
	broker   = flag.String("broker", "tcp://127.0.0.1:1883", "URI del broker")
	node     = flag.String("node", "n1", "identificador del nodo (CONFIG_ECO_NODE_ID)")
	label    = flag.String("label", "", "nombre de la corrida (real, qemu, ...): subcarpeta de -out")
	out      = flag.String("out", "resultados", "carpeta de resultados")
	nLat     = flag.Int("n", 1000, "pings por prueba de latencia")
	interval = flag.Duration("interval", 10*time.Millisecond, "pausa entre pings")
	nFlood   = flag.Int("nflood", 2000, "mensajes por prueba de throughput")
	sizes    = flag.String("sizes", "16,256,1024,4096", "tamaños de payload en bytes")
	qoss     = flag.String("qos", "0,1", "niveles de QoS")
	warmup   = flag.Int("warmup", 20, "pings descartados al principio de cada prueba")
	nodes    = flag.Int("nodes", 1, "multi: cantidad de nodos q1..qN")
)

type msg struct {
	t       time.Time
	payload []byte
}

func main() {
	flag.Parse()
	switch flag.Arg(0) {
	case "suite":
		suite()
	case "multi":
		multi()
	case "compare":
		compare(flag.Arg(1), flag.Arg(2))
	default:
		fmt.Fprintln(os.Stderr, "uso: eco [flags] suite | multi | compare <dirA> <dirB>")
		flag.PrintDefaults()
		os.Exit(2)
	}
}

func suite() {
	if *label == "" {
		fail("falta -label")
	}
	dir := filepath.Join(*out, *label)
	must(os.MkdirAll(dir, 0o755))

	c := mqtt.NewClient(mqtt.NewClientOptions().AddBroker(*broker).
		SetClientID(fmt.Sprintf("eco-backend-%d", os.Getpid())).SetOrderMatters(true))
	wait(c.Connect())
	defer c.Disconnect(250)

	res, err := os.Create(filepath.Join(dir, "resumen.csv"))
	must(err)
	defer res.Close()
	w := csv.NewWriter(res)
	defer w.Flush()
	w.Write([]string{"prueba", "bytes", "qos", "enviados", "recibidos", "perdida_pct",
		"min_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms", "media_ms", "desvio_ms", "jitter_ms",
		"kbit_s", "msg_s"})

	for _, q := range ints(*qoss) {
		for _, s := range ints(*sizes) {
			r := latency(c, dir, s, byte(q))
			fmt.Println(strings.Join(r, "\t"))
			w.Write(r)
			r = throughput(c, s, byte(q))
			fmt.Println(strings.Join(r, "\t"))
			w.Write(r)
			w.Flush()
		}
	}
}

// latency manda un ping por vez (8 bytes de secuencia + relleno) y espera el eco.
func latency(c mqtt.Client, dir string, size int, qos byte) []string {
	if size < 8 {
		size = 8
	}
	pongs := make(chan msg, 16)
	topic := "eco/" + *node + "/pong"
	wait(c.Subscribe(topic, qos, func(_ mqtt.Client, m mqtt.Message) {
		pongs <- msg{time.Now(), m.Payload()}
	}))
	defer func() { c.Unsubscribe(topic).Wait() }()

	f, err := os.Create(filepath.Join(dir, fmt.Sprintf("lat_%dB_qos%d.csv", size, qos)))
	must(err)
	defer f.Close()
	fmt.Fprintln(f, "seq,rtt_us")

	buf := make([]byte, size)
	var rtts []float64
	sent := 0
	for seq := uint64(0); seq < uint64(*nLat+*warmup); seq++ {
		binary.LittleEndian.PutUint64(buf, seq)
		t0 := time.Now()
		c.Publish("eco/"+*node+"/ping", qos, false, buf)
		measured := seq >= uint64(*warmup)
		if measured {
			sent++
		}
	recv:
		select {
		case m := <-pongs:
			if len(m.payload) < 8 || binary.LittleEndian.Uint64(m.payload) != seq {
				goto recv // eco atrasado de un ping que ya se dio por perdido
			}
			if measured {
				rtt := m.t.Sub(t0)
				rtts = append(rtts, float64(rtt.Microseconds())/1000)
				fmt.Fprintf(f, "%d,%d\n", seq, rtt.Microseconds())
			}
		case <-time.After(2 * time.Second):
		}
		time.Sleep(*interval)
	}
	return row("latencia", size, qos, sent, rtts, 0, 0)
}

// multi hace la prueba de latencia (16 B, QoS 0) contra q1..qN al mismo tiempo, un ping
// pendiente por nodo, y agrega una fila a multi.csv con el resultado conjunto.
func multi() {
	if *label == "" {
		fail("falta -label")
	}
	dir := filepath.Join(*out, *label)
	must(os.MkdirAll(dir, 0o755))
	c := mqtt.NewClient(mqtt.NewClientOptions().AddBroker(*broker).
		SetClientID(fmt.Sprintf("eco-backend-%d", os.Getpid())).SetOrderMatters(true))
	wait(c.Connect())
	defer c.Disconnect(250)

	pongs := make([]chan msg, *nodes+1)
	for i := range pongs {
		pongs[i] = make(chan msg, 16)
	}
	wait(c.Subscribe("eco/+/pong", 0, func(_ mqtt.Client, m mqtt.Message) {
		var i int
		if _, err := fmt.Sscanf(m.Topic(), "eco/q%d/pong", &i); err == nil && i > 0 && i <= *nodes {
			pongs[i] <- msg{time.Now(), m.Payload()}
		}
	}))

	f, err := os.Create(filepath.Join(dir, fmt.Sprintf("multi_%d.csv", *nodes)))
	must(err)
	defer f.Close()
	fmt.Fprintln(f, "nodo,seq,rtt_us")

	type sample struct{ node, seq, us int }
	samples := make(chan sample, 1024)
	done := make(chan int, *nodes) // nodos que contestaron al menos un ping
	for i := 1; i <= *nodes; i++ {
		go func(i int) {
			buf := make([]byte, 16)
			ok := 0
			for seq := uint64(0); seq < uint64(*nLat+*warmup); seq++ {
				binary.LittleEndian.PutUint64(buf, seq)
				t0 := time.Now()
				c.Publish(fmt.Sprintf("eco/q%d/ping", i), 0, false, buf)
				timeout := time.After(2 * time.Second)
			recv:
				select {
				case m := <-pongs[i]:
					if len(m.payload) < 8 || binary.LittleEndian.Uint64(m.payload) != seq {
						goto recv
					}
					if seq >= uint64(*warmup) {
						samples <- sample{i, int(seq), int(m.t.Sub(t0).Microseconds())}
						ok++
					}
				case <-timeout:
				}
				time.Sleep(*interval)
			}
			done <- ok
		}(i)
	}
	var rtts []float64
	alive := 0
	for finished := 0; finished < *nodes; {
		select {
		case s := <-samples:
			rtts = append(rtts, float64(s.us)/1000)
			fmt.Fprintf(f, "%d,%d,%d\n", s.node, s.seq, s.us)
		case ok := <-done:
			finished++
			if ok > 0 {
				alive++
			}
		}
	}
	for len(samples) > 0 {
		s := <-samples
		rtts = append(rtts, float64(s.us)/1000)
		fmt.Fprintf(f, "%d,%d,%d\n", s.node, s.seq, s.us)
	}

	path := filepath.Join(dir, "multi.csv")
	_, statErr := os.Stat(path)
	res, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	must(err)
	defer res.Close()
	w := csv.NewWriter(res)
	defer w.Flush()
	if statErr != nil {
		w.Write([]string{"nodos", "respondieron", "enviados", "recibidos", "perdida_pct",
			"min_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms", "media_ms", "desvio_ms"})
	}
	sent := *nodes * *nLat
	r := []string{strconv.Itoa(*nodes), strconv.Itoa(alive), strconv.Itoa(sent), strconv.Itoa(len(rtts)),
		ff(100 * float64(sent-len(rtts)) / float64(sent))}
	if len(rtts) > 0 {
		s := append([]float64(nil), rtts...)
		sort.Float64s(s)
		mean, sd := meanSD(rtts)
		r = append(r, ff(s[0]), ff(pct(s, 50)), ff(pct(s, 95)), ff(pct(s, 99)), ff(s[len(s)-1]), ff(mean), ff(sd))
	}
	w.Write(r)
	fmt.Println(strings.Join(r, "\t"))
}

// throughput le pide al nodo que publique nFlood mensajes seguidos y mide cuánto tardan en llegar.
func throughput(c mqtt.Client, size int, qos byte) []string {
	arrivals := make(chan time.Time, *nFlood)
	topic := "eco/" + *node + "/flood"
	wait(c.Subscribe(topic, qos, func(_ mqtt.Client, m mqtt.Message) { arrivals <- time.Now() }))
	defer func() { c.Unsubscribe(topic).Wait() }()

	wait(c.Publish("eco/"+*node+"/cmd", 1, false, fmt.Sprintf("flood %d %d %d", *nFlood, size, qos)))
	var first, last time.Time
	n := 0
	for n < *nFlood {
		select {
		case t := <-arrivals:
			if n == 0 {
				first = t
			}
			last, n = t, n+1
			continue
		case <-time.After(3 * time.Second):
		}
		break
	}
	kbps, mps := 0.0, 0.0
	if d := last.Sub(first).Seconds(); n > 1 && d > 0 {
		kbps = float64((n-1)*size*8) / d / 1000
		mps = float64(n-1) / d
	}
	return row("throughput", size, qos, *nFlood, make([]float64, n), kbps, mps)
}

func row(test string, size int, qos byte, sent int, v []float64, kbps, mps float64) []string {
	loss := 100 * float64(sent-len(v)) / float64(sent)
	r := []string{test, strconv.Itoa(size), strconv.Itoa(int(qos)), strconv.Itoa(sent),
		strconv.Itoa(len(v)), ff(loss)}
	if test == "latencia" && len(v) > 0 {
		s := append([]float64(nil), v...)
		sort.Float64s(s)
		mean, sd := meanSD(v)
		jit := 0.0 // variación media entre RTT consecutivos (RFC 3550, sin suavizado)
		for i := 1; i < len(v); i++ {
			jit += math.Abs(v[i] - v[i-1])
		}
		if len(v) > 1 {
			jit /= float64(len(v) - 1)
		}
		r = append(r, ff(s[0]), ff(pct(s, 50)), ff(pct(s, 95)), ff(pct(s, 99)), ff(s[len(s)-1]),
			ff(mean), ff(sd), ff(jit), "", "")
	} else {
		r = append(r, "", "", "", "", "", "", "", "", ff(kbps), ff(mps))
	}
	return r
}

// compare imprime una tabla Markdown con las dos corridas lado a lado.
func compare(a, b string) {
	ra, rb := readRes(a), map[string]map[string]string{}
	for _, y := range readRes(b) {
		rb[y["prueba"]+y["bytes"]+y["qos"]] = y
	}
	na, nb := filepath.Base(a), filepath.Base(b)
	fmt.Printf("| prueba | bytes | QoS | p50 %s | p50 %s | p99 %s | p99 %s | jitter %s | jitter %s | kbit/s %s | kbit/s %s | pérdida %s | pérdida %s |\n",
		na, nb, na, nb, na, nb, na, nb, na, nb)
	fmt.Println("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for _, x := range ra {
		k := x["prueba"] + x["bytes"] + x["qos"]
		y := rb[k]
		if y == nil {
			continue
		}
		fmt.Printf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s%% | %s%% |\n",
			x["prueba"], x["bytes"], x["qos"], x["p50_ms"], y["p50_ms"], x["p99_ms"], y["p99_ms"],
			x["jitter_ms"], y["jitter_ms"], x["kbit_s"], y["kbit_s"], x["perdida_pct"], y["perdida_pct"])
	}
}

// readRes devuelve las filas de resumen.csv, en orden, como mapas columna→valor.
func readRes(dir string) []map[string]string {
	f, err := os.Open(filepath.Join(dir, "resumen.csv"))
	must(err)
	defer f.Close()
	rows, err := csv.NewReader(f).ReadAll()
	must(err)
	var m []map[string]string
	for _, r := range rows[1:] {
		x := map[string]string{}
		for i, h := range rows[0] {
			x[h] = r[i]
		}
		m = append(m, x)
	}
	return m
}

func pct(s []float64, p float64) float64 {
	return s[int(math.Ceil(p/100*float64(len(s))))-1]
}

func meanSD(v []float64) (float64, float64) {
	var sum, sq float64
	for _, x := range v {
		sum += x
	}
	mean := sum / float64(len(v))
	for _, x := range v {
		sq += (x - mean) * (x - mean)
	}
	return mean, math.Sqrt(sq / float64(len(v)))
}

func ints(s string) []int {
	var r []int
	for _, p := range strings.Split(s, ",") {
		n, err := strconv.Atoi(strings.TrimSpace(p))
		must(err)
		r = append(r, n)
	}
	return r
}

func ff(x float64) string { return strconv.FormatFloat(x, 'f', 3, 64) }

func wait(t mqtt.Token) {
	t.Wait()
	must(t.Error())
}

func must(err error) {
	if err != nil {
		fail(err.Error())
	}
}

func fail(s string) {
	fmt.Fprintln(os.Stderr, "eco:", s)
	os.Exit(1)
}
