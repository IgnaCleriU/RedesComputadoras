// runner ejecuta la matriz del experimento. Cada corrida (runOne):
//  1. levanta Mosquitto y el backend (SNTP + HTTP/HTTPS + suscriptor MQTT)
//  2. aplica netem (pérdida y latencia) en los taps
//  3. inicia dumpcap en br-exp
//  4. arma una imagen de flash por nodo con su config y lanza N instancias QEMU
//  5. espera DONE de todos los nodos, detiene todo y guarda los resultados
//
// Necesita root (tc, puertos 80/443/123). Uso típico, desde experimento/:
//
//	sudo ./backend/bin/runner                                   (matrices/principal.yaml → datos/principal)
//	sudo ./backend/bin/runner -matrix matrices/smoke.yaml -runs datos/smoke -only 'mqtt1'
//
// Flags útiles: -matrix <yaml>, -runs <dir> (salida, también recibe runner.log), -only <regex> (filtra por ID), -reps y
// -duration (pruebas cortas), -dry-run (lista las corridas) y -force (repite las
// completas). Se puede cortar con Ctrl-C y relanzar el mismo comando: las
// corridas con config.json en estado "ok" se saltean.
//
// Salida de cada corrida, en <runs>/<config>/rep<k>/ (por defecto <runs> = datos/principal):
//
//	config.json       parámetros, puerto, estado (ok/failed), error y horarios
//	readings.csv      una fila por lectura recibida (la escribe el backend)
//	nodes.csv         contadores y estado de cada nodo, sacados de la UART
//	capture.pcapng    todo el tráfico del bridge
//	uart_espN.log     consola de cada nodo, con la hora del host en µs en cada línea
//	backend.log, mosquitto.log, dumpcap.log
//
// Cada nodo se lanza así (nodo N, tap N−1):
//
//	qemu-system-xtensa -nographic -M esp32 -m 4M \
//	  -global driver=timer.esp32.timg,property=wdt_disable,value=true \
//	  -drive file=flashN.bin,if=mtd,format=raw \
//	  -nic tap,model=open_eth,ifname=tapN-1,script=no,downscript=no,mac=02:00:00:00:00:0N
//
// La opción -nographic deja la UART0 en stdout (con -serial stdio explícito
// choca con el monitor de QEMU y la UART queda desconectada). wdt_disable apaga
// el watchdog de los timers, como idf.py qemu, así un host lento no reinicia al
// nodo. No se pasa strap_mode: en esta versión de QEMU 0x0f es modo descarga y
// el valor por defecto arranca desde flash. script=no porque los taps ya los
// creó infra/net/setup.sh.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"os/user"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"wireguardians/exp/internal/matrix"
)

const (
	serverIP  = "10.10.0.1"
	bridge    = "br-exp"
	cfgOffset = 0x190000 // partición "cfg" (firmware/partitions.csv)
	cfgSize   = 0x1000
)

type opts struct {
	root, matrixPath, only, runsDir          string
	qemu, mosquitto, backend, flash, dumpcap string
	reps, duration                           int
	dryRun, force                            bool
}

func main() {
	var o opts
	flag.StringVar(&o.root, "root", ".", "directorio experimento/")
	flag.StringVar(&o.matrixPath, "matrix", "matrices/principal.yaml", "matriz de configuraciones")
	flag.StringVar(&o.runsDir, "runs", "datos/principal", "directorio de salida (relativo a -root)")
	flag.StringVar(&o.only, "only", "", "regex: solo las configuraciones cuyo ID coincide")
	flag.IntVar(&o.reps, "reps", 0, "repeticiones (0 = las de la matriz)")
	flag.IntVar(&o.duration, "duration", 0, "segundos de envío (0 = los de la matriz)")
	flag.StringVar(&o.qemu, "qemu", os.ExpandEnv("$HOME/esp/qemu/qemu/bin/qemu-system-xtensa"), "binario qemu-system-xtensa de Espressif")
	flag.StringVar(&o.mosquitto, "mosquitto", "mosquitto", "binario de Mosquitto")
	flag.StringVar(&o.backend, "backend", "backend/bin/backend", "binario del backend")
	flag.StringVar(&o.flash, "flash", "firmware/build/flash.bin", "imagen de flash compilada")
	flag.StringVar(&o.dumpcap, "dumpcap", "dumpcap", "binario de dumpcap")
	flag.BoolVar(&o.dryRun, "dry-run", false, "solo listar las corridas")
	flag.BoolVar(&o.force, "force", false, "repetir corridas ya completas")
	flag.Parse()

	// Si se corre con sudo, HOME es el de root: resolver la ruta de QEMU del usuario.
	if u := os.Getenv("SUDO_USER"); u != "" && strings.HasPrefix(o.qemu, "/root/") {
		o.qemu = filepath.Join("/home", u, strings.TrimPrefix(o.qemu, "/root/"))
	}

	root, err := filepath.Abs(o.root)
	if err != nil {
		log.Fatal(err)
	}
	o.root = root
	for _, p := range []*string{&o.backend, &o.flash} {
		if !filepath.IsAbs(*p) {
			*p = filepath.Join(root, *p)
		}
	}

	m, err := matrix.Load(filepath.Join(root, o.matrixPath))
	if err != nil {
		log.Fatal(err)
	}
	if o.reps > 0 {
		m.Repetitions = o.reps
	}
	if o.duration > 0 {
		m.DurationS = o.duration
	}
	var re *regexp.Regexp
	if o.only != "" {
		re = regexp.MustCompile(o.only)
	}

	var runs []matrix.Run
	for _, r := range m.Runs() {
		if re != nil && !re.MatchString(r.Config.ID()) {
			continue
		}
		runs = append(runs, r)
	}
	log.Printf("%d configuraciones, %d corridas seleccionadas", len(m.Configs()), len(runs))
	if o.dryRun {
		for _, r := range runs {
			fmt.Println(r.Dir())
		}
		return
	}
	if os.Geteuid() != 0 {
		log.Fatal("el runner necesita root (tc y puertos 80/443/123): sudo ./backend/bin/runner ...")
	}
	if err := preflight(o); err != nil {
		log.Fatal(err)
	}

	// El log del runner va a la terminal y a <runs>/runner.log (se agrega al final,
	// así una matriz cortada y retomada queda en un solo archivo).
	runsRoot := filepath.Join(root, o.runsDir)
	if err := os.MkdirAll(runsRoot, 0o755); err != nil {
		log.Fatal(err)
	}
	logf, err := os.OpenFile(filepath.Join(runsRoot, "runner.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		log.Fatal(err)
	}
	defer logf.Close()
	log.SetOutput(io.MultiWriter(os.Stderr, logf))

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	start := time.Now()
	for i, r := range runs {
		if ctx.Err() != nil {
			break
		}
		dir := filepath.Join(root, o.runsDir, r.Dir())
		if !o.force && runOK(dir) {
			log.Printf("[%d/%d] %s ya está completa, se salta", i+1, len(runs), r.Dir())
			continue
		}
		log.Printf("[%d/%d] %s", i+1, len(runs), r.Dir())
		t0 := time.Now()
		if err := runOne(ctx, o, r, dir); err != nil {
			log.Printf("  FALLÓ: %v", err)
		} else {
			log.Printf("  ok en %s", time.Since(t0).Round(time.Second))
		}
		chownToSudoUser(filepath.Join(root, o.runsDir))
	}
	netem(o, 0, 0) // dejar la red limpia
	log.Printf("terminado en %s", time.Since(start).Round(time.Second))
}

func preflight(o opts) error {
	for _, p := range []string{o.qemu, o.backend, o.flash} {
		if _, err := os.Stat(p); err != nil {
			return fmt.Errorf("falta %s: %w", p, err)
		}
	}
	for _, b := range []string{o.mosquitto, o.dumpcap, "tc"} {
		if _, err := exec.LookPath(b); err != nil {
			return fmt.Errorf("no se encuentra %s en el PATH", b)
		}
	}
	if _, err := net.InterfaceByName(bridge); err != nil {
		return fmt.Errorf("no existe %s: correr antes sudo ./infra/net/setup.sh", bridge)
	}
	return nil
}

func runOK(dir string) bool {
	b, err := os.ReadFile(filepath.Join(dir, "config.json"))
	if err != nil {
		return false
	}
	var meta struct{ Status string }
	return json.Unmarshal(b, &meta) == nil && meta.Status == "ok"
}

// runMeta se guarda en config.json.
type runMeta struct {
	matrix.Config
	ConfigID   string    `json:"config_id"`
	Rep        int       `json:"rep"`
	Port       int       `json:"port"`
	Status     string    `json:"status"`
	Error      string    `json:"error,omitempty"`
	Start      time.Time `json:"start"`
	End        time.Time `json:"end"`
	NodesDone  int       `json:"nodes_done"`
	FlashImage string    `json:"flash_image"`
}

// runOne ejecuta una corrida. Los defer escriben config.json al salir (con
// status ok o failed y el error) y apagan todos los procesos aunque algo falle a
// mitad de camino. Pasos: broker y backend, netem, captura, nodos, espera de
// DONE, cierre y nodes.csv.
func runOne(ctx context.Context, o opts, r matrix.Run, dir string) (err error) {
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	meta := runMeta{Config: r.Config, ConfigID: r.Config.ID(), Rep: r.Rep, Port: r.Config.Port(), Start: time.Now(), FlashImage: o.flash}
	defer func() {
		meta.End = time.Now()
		meta.Status = "ok"
		if err != nil {
			meta.Status = "failed"
			meta.Error = err.Error()
		}
		b, _ := json.MarshalIndent(meta, "", "  ")
		os.WriteFile(filepath.Join(dir, "config.json"), b, 0o644)
	}()

	tmp, err := os.MkdirTemp("", "exp-run-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	var procs procGroup
	defer procs.stopAll()

	// 1. Broker y backend. Se espera a que Mosquitto acepte conexiones en
	// 127.0.0.1:1883 y a que el backend diga "mqtt: suscripto": recién ahí
	// puede recibir por los dos caminos.
	conf, err := os.ReadFile(filepath.Join(o.root, "infra/broker/mosquitto.conf"))
	if err != nil {
		return err
	}
	// Mosquitto corre como root y baja al usuario "mosquitto", que no puede leer
	// dentro de /home: los certificados y la config van al directorio temporal.
	if err := os.Chmod(tmp, 0o755); err != nil {
		return err
	}
	for _, f := range []string{"ca.crt", "server.crt", "server.key"} {
		b, err := os.ReadFile(filepath.Join(o.root, "infra/certs", f))
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(tmp, f), b, 0o644); err != nil {
			return err
		}
	}
	confPath := filepath.Join(tmp, "mosquitto.conf")
	if err := os.WriteFile(confPath, []byte(strings.ReplaceAll(string(conf), "@CERTS@", tmp)), 0o644); err != nil {
		return err
	}
	if _, err := procs.start("mosquitto", filepath.Join(dir, "mosquitto.log"), nil, o.mosquitto, "-c", confPath); err != nil {
		return err
	}
	if err := waitTCP("127.0.0.1:1883", 10*time.Second); err != nil {
		return fmt.Errorf("mosquitto no levantó: %w", err)
	}

	backendReady := make(chan struct{})
	var once sync.Once
	_, err = procs.start("backend", filepath.Join(dir, "backend.log"), func(line string) {
		if strings.Contains(line, "mqtt: suscripto") {
			once.Do(func() { close(backendReady) })
		}
	}, o.backend, "-out", filepath.Join(dir, "readings.csv"), "-certs", filepath.Join(o.root, "infra/certs"))
	if err != nil {
		return err
	}
	select {
	case <-backendReady:
	case <-time.After(10 * time.Second):
		return errors.New("el backend no se suscribió al broker")
	}

	// 2. Condiciones de red
	if err := netem(o, r.Config.LossPct, r.Config.RttMs); err != nil {
		return err
	}
	defer netem(o, 0, 0)

	// 3. Captura de todo br-exp, sin recortar paquetes (-s 0).
	capReady := make(chan struct{})
	var capOnce sync.Once
	// dumpcap tiene capacidades de archivo y, lanzado como root, no puede escribir
	// la captura: se corre como el usuario que llamó a sudo (grupo wireshark).
	cred := sudoCredential()
	if cred != nil {
		if err := os.Chown(dir, int(cred.Uid), int(cred.Gid)); err != nil {
			return err
		}
	}
	_, err = procs.startAs("dumpcap", filepath.Join(dir, "dumpcap.log"), cred, func(line string) {
		if strings.Contains(line, "Capturing on") {
			capOnce.Do(func() { close(capReady) })
		}
	}, o.dumpcap, "-i", bridge, "-s", "0", "-w", filepath.Join(dir, "capture.pcapng"))
	if err != nil {
		return err
	}
	select {
	case <-capReady:
	case <-time.After(10 * time.Second):
		return errors.New("dumpcap no empezó a capturar")
	}

	// 4. Nodos: por cada uno, una copia de la imagen con su config, su log de UART
	// y una instancia QEMU en su tap con su MAC.
	flash, err := os.ReadFile(o.flash)
	if err != nil {
		return err
	}
	nodes := make([]*nodeState, r.Config.Nodes)
	for i := range nodes {
		n := &nodeState{id: i + 1}
		nodes[i] = n
		img := filepath.Join(tmp, fmt.Sprintf("flash%d.bin", n.id))
		if err := os.WriteFile(img, withConfig(flash, nodeConfig(r.Config, n.id)), 0o644); err != nil {
			return err
		}
		logf, err := os.Create(filepath.Join(dir, fmt.Sprintf("uart_esp%d.log", n.id)))
		if err != nil {
			return err
		}
		n.log = logf
		_, err = procs.start("qemu", "", n.handleLine, o.qemu,
			// -nographic deja la UART0 en stdio (con -serial stdio explícito choca con el monitor)
			"-nographic", "-M", "esp32", "-m", "4M",
			"-global", "driver=timer.esp32.timg,property=wdt_disable,value=true",
			"-drive", "file="+img+",if=mtd,format=raw",
			"-nic", fmt.Sprintf("tap,model=open_eth,ifname=tap%d,script=no,downscript=no,mac=%s", i, macFor(n.id)),
		)
		if err != nil {
			logf.Close()
			return fmt.Errorf("qemu nodo %d: %w", n.id, err)
		}
	}
	defer func() {
		for _, n := range nodes {
			if n != nil && n.log != nil {
				n.log.Close()
			}
		}
	}()

	// 5. Esperar a todos los nodos: cada segundo se revisa el estado. Se corta si
	// alguno falló, si todos imprimieron DONE, si pasa duration + 3 min o con Ctrl-C.
	limit := time.Duration(r.Config.DurationS)*time.Second + 3*time.Minute
	deadline := time.After(limit)
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
wait:
	for {
		select {
		case <-ctx.Done():
			return errors.New("interrumpido")
		case <-deadline:
			err = fmt.Errorf("timeout de %s esperando DONE", limit)
			break wait
		case <-tick.C:
			done, failed := 0, 0
			for _, n := range nodes {
				switch n.status() {
				case "done":
					done++
				case "failed":
					failed++
				}
			}
			meta.NodesDone = done
			if failed > 0 {
				err = fmt.Errorf("%d nodo(s) fallaron al iniciar (ver uart_esp*.log)", failed)
				break wait
			}
			if done == len(nodes) {
				break wait
			}
		}
	}

	// Un segundo más de captura para los últimos ACK/FIN.
	time.Sleep(time.Second)
	procs.stopKind("qemu")
	procs.stopAll() // captura, backend (vuelca readings.csv) y broker

	if werr := writeNodes(filepath.Join(dir, "nodes.csv"), nodes); werr != nil && err == nil {
		err = werr
	}
	return err
}

// --- nodos -----------------------------------------------------------------

func macFor(id int) string { return fmt.Sprintf("02:00:00:00:00:%02x", id) }

// nodeConfig arma el texto de la partición cfg que lee firmware/main/config.c.
func nodeConfig(c matrix.Config, id int) string {
	b := func(v bool) int {
		if v {
			return 1
		}
		return 0
	}
	return fmt.Sprintf("EXPCFG1\nesp_id=%d\nip=10.10.0.%d\nserver_ip=%s\nmac=%s\ntransport=%s\ntls=%d\nperiod_ms=%d\nserialization=%s\nduration_s=%d\nnodelay=%d\n",
		id, 10+id, serverIP, macFor(id), c.Transport, b(c.TLS), c.PeriodMs, c.Serialization, c.DurationS, b(c.Nodelay))
}

// withConfig copia la imagen y escribe la config en la partición cfg (resto en 0xFF).
func withConfig(flash []byte, cfg string) []byte {
	img := make([]byte, len(flash))
	copy(img, flash)
	part := img[cfgOffset : cfgOffset+cfgSize]
	for i := range part {
		part[i] = 0xFF
	}
	copy(part, cfg)
	part[len(cfg)] = 0
	return img
}

type mark struct{ hostUs, timerUs int64 }

type nodeState struct {
	id  int
	log *os.File // uart_espN.log, con la hora del host en cada línea

	mu                                                        sync.Mutex
	ready, done, failed                                       bool
	readyHostUs                                               int64
	produced, sent, sendFailed, queueDrops, pending, overruns int64
	marks                                                     []mark
	syncOffsetsUs                                             []int64 // hora del host al leer la línea − epoch del nodo
	disconnects, httpErrors, httpRetries                      int
}

var kvRe = regexp.MustCompile(`(\w+)=(-?\d+)`)

func kv(line string) map[string]int64 {
	out := map[string]int64{}
	for _, m := range kvRe.FindAllStringSubmatch(line, -1) {
		v, _ := strconv.ParseInt(m[2], 10, 64)
		out[m[1]] = v
	}
	return out
}

// handleLine agrega la hora del host a cada línea de UART y extrae los eventos del nodo.
// Corre en la goroutine que lee QEMU; el bucle de espera lee el estado desde otra,
// por eso el mutex.
//
//	READY                    el nodo empezó a producir; se guarda la hora
//	MARK timer_us=…          par (hora del host, timer_us) para el factor de tiempo real
//	SYNC epoch_us=…          hora del host − epoch_us: desfase aproximado del reloj
//	DONE produced= sent= …   nodo terminado; se guardan los contadores
//	FAIL, CFGERR, NETERR,    nodo fallido: se corta la corrida
//	SYNCERR, Guru Meditation, abort()
//	MQTT_DISCONNECTED        suma una desconexión
//	HTTP_ERR, HTTP_STATUS    suma un error HTTP
//	HTTP_RETRY_OK            suma un reintento exitoso
func (n *nodeState) handleLine(raw string) {
	host := time.Now().UnixMicro()
	line := strings.TrimRight(raw, "\r")
	fmt.Fprintf(n.log, "%d %s\n", host, line)
	n.mu.Lock()
	defer n.mu.Unlock()
	switch {
	case strings.HasPrefix(line, "READY"):
		n.ready, n.readyHostUs = true, host
	case strings.HasPrefix(line, "MARK"):
		n.marks = append(n.marks, mark{host, kv(line)["timer_us"]})
	case strings.HasPrefix(line, "SYNC "):
		n.syncOffsetsUs = append(n.syncOffsetsUs, host-kv(line)["epoch_us"])
	case strings.HasPrefix(line, "DONE"):
		v := kv(line)
		n.done = true
		n.produced, n.sent, n.sendFailed = v["produced"], v["sent"], v["failed"]
		n.queueDrops, n.pending, n.overruns = v["queue_drops"], v["pending"], v["overruns"]
	case strings.HasPrefix(line, "FAIL"), strings.HasPrefix(line, "CFGERR"),
		strings.HasPrefix(line, "NETERR"), strings.HasPrefix(line, "SYNCERR"):
		n.failed = true
	case strings.HasPrefix(line, "MQTT_DISCONNECTED"):
		n.disconnects++
	case strings.HasPrefix(line, "HTTP_ERR"), strings.HasPrefix(line, "HTTP_STATUS"):
		n.httpErrors++
	case strings.HasPrefix(line, "HTTP_RETRY_OK"):
		n.httpRetries++
	case strings.Contains(line, "Guru Meditation"), strings.Contains(line, "abort()"):
		n.failed = true
	}
}

func (n *nodeState) status() string {
	n.mu.Lock()
	defer n.mu.Unlock()
	switch {
	case n.done:
		return "done"
	case n.failed:
		return "failed"
	}
	return "running"
}

// rtf: tiempo simulado (esp_timer) / tiempo del host entre la primera y la última MARK.
func (n *nodeState) rtf() float64 {
	if len(n.marks) < 2 {
		return 0
	}
	a, b := n.marks[0], n.marks[len(n.marks)-1]
	if b.hostUs == a.hostUs {
		return 0
	}
	return float64(b.timerUs-a.timerUs) / float64(b.hostUs-a.hostUs)
}

// median de los desfases SYNC (inserción: son pocos valores). Incluye el paso
// por la UART emulada y la tubería, así que es una cota superior del error del reloj.
func median(v []int64) int64 {
	if len(v) == 0 {
		return 0
	}
	s := append([]int64(nil), v...)
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
	return s[len(s)/2]
}

// writeNodes escribe nodes.csv: estado del nodo, contadores de DONE, rtf y
// cantidad de MARK, cantidad de SYNC y mediana del desfase, y eventos de los
// transportes (desconexiones MQTT, errores y reintentos HTTP).
func writeNodes(path string, nodes []*nodeState) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	fmt.Fprintln(f, "esp_id,ready,done,ready_host_us,produced,sent,failed,queue_drops,pending,overruns,rtf,marks,syncs,sync_offset_median_us,mqtt_disconnects,http_errors,http_retries_ok")
	for _, n := range nodes {
		n.mu.Lock()
		fmt.Fprintf(f, "%d,%t,%t,%d,%d,%d,%d,%d,%d,%d,%.4f,%d,%d,%d,%d,%d,%d\n",
			n.id, n.ready, n.done, n.readyHostUs, n.produced, n.sent, n.sendFailed, n.queueDrops, n.pending, n.overruns,
			n.rtf(), len(n.marks), len(n.syncOffsetsUs), median(n.syncOffsetsUs), n.disconnects, n.httpErrors, n.httpRetries)
		n.mu.Unlock()
	}
	return nil
}

// --- procesos y red ----------------------------------------------------------

type proc struct {
	kind string
	cmd  *exec.Cmd
	done chan struct{} // se cierra cuando el proceso terminó
}

type procGroup struct {
	mu    sync.Mutex
	procs []*proc
}

// start lanza un proceso con stdout y stderr unidos. Cada línea se escribe en
// logPath (si no es vacío) y se pasa a onLine (si no es nil).
//
// Dos goroutines por proceso: una lee la tubería línea por línea; la otra espera
// a que el proceso termine, cierra la tubería, espera a que la primera procese
// todas las líneas y recién ahí cierra done. Así no se pierden las últimas líneas
// de la UART (por ejemplo, un DONE impreso justo antes de apagar).
func (g *procGroup) start(kind, logPath string, onLine func(string), name string, args ...string) (*proc, error) {
	return g.startAs(kind, logPath, nil, onLine, name, args...)
}

// startAs es start con otro usuario (cred != nil).
func (g *procGroup) startAs(kind, logPath string, cred *syscall.Credential, onLine func(string), name string, args ...string) (*proc, error) {
	var logf *os.File
	if logPath != "" {
		var err error
		if logf, err = os.Create(logPath); err != nil {
			return nil, err
		}
	}
	cmd := exec.Command(name, args...)
	if cred != nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{Credential: cred}
	}
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	if err := cmd.Start(); err != nil {
		if logf != nil {
			logf.Close()
		}
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	p := &proc{kind: kind, cmd: cmd, done: make(chan struct{})}
	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		for sc.Scan() {
			if logf != nil {
				fmt.Fprintln(logf, sc.Text())
			}
			if onLine != nil {
				onLine(sc.Text())
			}
		}
		io.Copy(io.Discard, pr)
	}()
	go func() {
		cmd.Wait()
		pw.Close()
		<-readDone // todas las líneas procesadas antes de marcar el fin
		if logf != nil {
			logf.Close()
		}
		close(p.done)
	}()
	g.mu.Lock()
	g.procs = append(g.procs, p)
	g.mu.Unlock()
	return p, nil
}

func (g *procGroup) stopKind(kind string) {
	g.mu.Lock()
	var stop, keep []*proc
	for _, p := range g.procs {
		if p.kind == kind {
			stop = append(stop, p)
		} else {
			keep = append(keep, p)
		}
	}
	g.procs = keep
	g.mu.Unlock()
	for _, p := range stop {
		p.terminate()
	}
}

// stopAll detiene en orden inverso al de inicio (nodos, captura, backend, broker).
func (g *procGroup) stopAll() {
	g.mu.Lock()
	ps := g.procs
	g.procs = nil
	g.mu.Unlock()
	for i := len(ps) - 1; i >= 0; i-- {
		ps[i].terminate()
	}
}

// terminate manda SIGTERM (dumpcap y el backend cierran sus archivos) y mata
// el proceso si no terminó en 5 s.
func (p *proc) terminate() {
	select {
	case <-p.done:
		return
	default:
	}
	p.cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-p.done:
	case <-time.After(5 * time.Second):
		p.cmd.Process.Kill()
		<-p.done
	}
}

func waitTCP(addr string, timeout time.Duration) error {
	end := time.Now().Add(timeout)
	for {
		c, err := net.DialTimeout("tcp", addr, 500*time.Millisecond)
		if err == nil {
			c.Close()
			return nil
		}
		if time.Now().After(end) {
			return err
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func netem(o opts, loss float64, rtt int) error {
	script := filepath.Join(o.root, "infra/net/netem.sh")
	var cmd *exec.Cmd
	if loss == 0 && rtt == 0 {
		cmd = exec.Command(script, "clear")
	} else {
		cmd = exec.Command(script, strconv.FormatFloat(loss, 'f', -1, 64), strconv.Itoa(rtt))
	}
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("netem: %v: %s", err, out)
	}
	return nil
}

// sudoCredential devuelve el usuario que llamó a sudo, con sus grupos
// suplementarios (wireshark), o nil si no se usó sudo.
func sudoCredential() *syscall.Credential {
	uid, err1 := strconv.Atoi(os.Getenv("SUDO_UID"))
	gid, err2 := strconv.Atoi(os.Getenv("SUDO_GID"))
	if err1 != nil || err2 != nil || uid == 0 {
		return nil
	}
	cred := &syscall.Credential{Uid: uint32(uid), Gid: uint32(gid)}
	if u, err := user.LookupId(strconv.Itoa(uid)); err == nil {
		if gids, err := u.GroupIds(); err == nil {
			for _, g := range gids {
				if v, err := strconv.Atoi(g); err == nil {
					cred.Groups = append(cred.Groups, uint32(v))
				}
			}
		}
	}
	return cred
}

// chownToSudoUser devuelve los archivos al usuario que llamó a sudo.
func chownToSudoUser(path string) {
	uid, err1 := strconv.Atoi(os.Getenv("SUDO_UID"))
	gid, err2 := strconv.Atoi(os.Getenv("SUDO_GID"))
	if err1 != nil || err2 != nil {
		return
	}
	filepath.Walk(path, func(p string, _ os.FileInfo, err error) error {
		if err == nil {
			os.Lchown(p, uid, gid)
		}
		return nil
	})
}
