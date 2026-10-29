// backend recibe lecturas por los dos caminos y las registra con el mismo código:
//   - HTTP  POST /tel/{esp}  en -http  (sin TLS) y -https (con TLS)
//   - MQTT  suscripción a exp/tel/+ en el broker local (fuera de la captura)
//
// También sirve SNTP para que los nodos usen el reloj del host.
//
//	ESP32 ──PUBLISH exp/tel/{esp}──► mosquitto 10.10.0.1:1883/8883 ──(127.0.0.1)──┐
//	  │                                                                            ├─► record.Record ─► readings.csv
//	  └──────POST /tel/{esp}───────► backend   10.10.0.1:80/443 ───────────────────┘
//
// Los dos caminos terminan en record.Record con el payload tal como llegó: es lo
// que hace comparables las mediciones.
//
// Ciclo de vida:
//  1. Abre el CSV, el SNTP, los servidores HTTP(S) y la conexión al broker.
//  2. Imprime BACKEND_READY y, al suscribirse, "mqtt: suscripto a exp/tel/+":
//     el runner espera esta segunda línea antes de lanzar los nodos.
//  3. Cada 2 s vuelca el CSV a disco (si la corrida se corta, se pierden ≤ 2 s).
//  4. Con SIGTERM/SIGINT se desconecta del broker, cierra los servidores, vacía el
//     CSV y deja en el log el total de lecturas válidas e inválidas.
//
// Para probarlo sin QEMU ni root, ver cmd/testclient.
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"

	"wireguardians/exp/internal/record"
	"wireguardians/exp/internal/sntp"
)

func main() {
	out := flag.String("out", "readings.csv", "CSV de salida")
	httpAddr := flag.String("http", "10.10.0.1:80", "dirección HTTP sin TLS (vacío = desactivado)")
	httpsAddr := flag.String("https", "10.10.0.1:443", "dirección HTTPS (vacío = desactivado)")
	broker := flag.String("mqtt", "tcp://127.0.0.1:1883", "broker para suscribirse (vacío = desactivado)")
	sntpAddr := flag.String("sntp", "10.10.0.1:123", "dirección SNTP UDP (vacío = desactivado)")
	certDir := flag.String("certs", "../infra/certs", "directorio con server.crt y server.key")
	flag.Parse()

	rec, err := record.New(*out)
	if err != nil {
		log.Fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// SNTP
	if *sntpAddr != "" {
		pc, err := net.ListenPacket("udp4", *sntpAddr)
		if err != nil {
			log.Fatalf("sntp: %v", err)
		}
		defer pc.Close()
		go sntp.Serve(pc)
	}

	// HTTP(S): una sola ruta para las dos variantes. {esp} es el número de nodo.
	mux := http.NewServeMux()
	mux.HandleFunc("POST /tel/{esp}", func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(io.LimitReader(r.Body, 4096))
		// Hora de recepción después de leer el cuerpo completo: la lectura terminó de llegar.
		tRecv := time.Now().UnixMicro()
		if err != nil {
			http.Error(w, "read", http.StatusBadRequest)
			return
		}
		if err := rec.Record("http", r.PathValue("esp"), body, tRecv); err != nil {
			log.Print(err)
			http.Error(w, "bad payload", http.StatusBadRequest)
			return
		}
		// 204 sin cuerpo: la respuesta mínima, igual para todas las corridas.
		w.WriteHeader(http.StatusNoContent)
	})

	var servers []*http.Server
	newServer := func(addr string) *http.Server {
		s := &http.Server{
			Addr:              addr,
			Handler:           mux,
			ReadHeaderTimeout: 30 * time.Second,
			IdleTimeout:       60 * time.Second, // mayor que el período más largo (10 s)
			// Sin log de net/http: los cortes de conexión con pérdida llenarían backend.log.
			ErrorLog: log.New(io.Discard, "", 0),
		}
		servers = append(servers, s)
		return s
	}
	if *httpAddr != "" {
		s := newServer(*httpAddr)
		go serve(s.ListenAndServe, "http")
	}
	if *httpsAddr != "" {
		cert, err := tls.LoadX509KeyPair(filepath.Join(*certDir, "server.crt"), filepath.Join(*certDir, "server.key"))
		if err != nil {
			log.Fatalf("certificados: %v", err)
		}
		s := newServer(*httpsAddr)
		// Mismo perfil que Mosquitto: TLS 1.2, una sola suite, sin tickets.
		s.TLSConfig = &tls.Config{
			Certificates:           []tls.Certificate{cert},
			MinVersion:             tls.VersionTLS12,
			MaxVersion:             tls.VersionTLS12,
			CipherSuites:           []uint16{tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256},
			SessionTicketsDisabled: true,
			NextProtos:             []string{"http/1.1"},
		}
		s.TLSNextProto = map[string]func(*http.Server, *tls.Conn, http.Handler){} // sin HTTP/2
		go serve(func() error { return s.ListenAndServeTLS("", "") }, "https")
	}

	// MQTT. SetOrderMatters(false): cada mensaje se procesa en su propia goroutine,
	// así una lectura lenta no frena a las demás. Con ConnectRetry y AutoReconnect
	// reintenta solo si el broker todavía no está o se cae. OnConnect corre en cada
	// conexión, también en las reconexiones, así la suscripción se rehace.
	var client mqtt.Client
	if *broker != "" {
		opts := mqtt.NewClientOptions().
			AddBroker(*broker).
			SetClientID(fmt.Sprintf("backend-%d", os.Getpid())).
			SetCleanSession(true).
			SetOrderMatters(false).
			SetConnectRetry(true).
			SetConnectRetryInterval(500 * time.Millisecond).
			SetAutoReconnect(true)
		opts.SetOnConnectHandler(func(c mqtt.Client) {
			// QoS 1 en la suscripción para no bajar la QoS de los publicadores: el
			// broker entrega con el mínimo entre la QoS de publicación y la de
			// suscripción. El nodo sale del último nivel del tópico (exp/tel/3 → 3).
			t := c.Subscribe("exp/tel/+", 1, func(_ mqtt.Client, m mqtt.Message) {
				tRecv := time.Now().UnixMicro()
				esp := m.Topic()[strings.LastIndexByte(m.Topic(), '/')+1:]
				if err := rec.Record("mqtt", esp, m.Payload(), tRecv); err != nil {
					log.Print(err)
				}
			})
			t.Wait()
			if t.Error() != nil {
				log.Printf("subscribe: %v", t.Error())
				return
			}
			log.Print("mqtt: suscripto a exp/tel/+")
		})
		client = mqtt.NewClient(opts)
		client.Connect() // reintenta en segundo plano hasta que el broker esté
	}

	log.Printf("backend listo (out=%s)", *out)
	fmt.Println("BACKEND_READY") // el runner espera esta línea

	// Volcado periódico para no perder datos si la corrida se corta.
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()
loop:
	for {
		select {
		case <-ctx.Done():
			break loop
		case <-tick.C:
			if err := rec.Flush(); err != nil {
				log.Print(err)
			}
		}
	}

	if client != nil {
		client.Disconnect(250)
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for _, s := range servers {
		s.Shutdown(shutdownCtx)
	}
	n, bad := rec.Counts()
	if err := rec.Close(); err != nil {
		log.Print(err)
	}
	log.Printf("backend: %d lecturas registradas, %d inválidas", n, bad)
}

func serve(f func() error, name string) {
	if err := f(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("%s: %v", name, err)
	}
}
