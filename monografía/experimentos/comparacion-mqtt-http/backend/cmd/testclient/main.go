// testclient imita a un nodo para probar el backend sin QEMU.
//
//	go run ./cmd/testclient -mode https -server 127.0.0.1:8443 -n 5
//	go run ./cmd/testclient -mode mqtt  -server tcp://127.0.0.1:1883 -qos 1
//
// Manda el mismo mensaje Telemetry que el firmware, con la hora actual y un valor
// aleatorio. Sirve para probar el backend en 127.0.0.1 con puertos altos, sin
// QEMU ni root (desde backend/):
//
//	./bin/backend -out /tmp/r.csv -http 127.0.0.1:18080 -https 127.0.0.1:18443 -mqtt "" -sntp "" -certs ../certs &
//	./bin/testclient -mode https -server 127.0.0.1:18443 -n 5 -certs ../certs
//	./bin/testclient -mode http  -server 127.0.0.1:18080 -n 5 -json
package main

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
	"path/filepath"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"google.golang.org/protobuf/proto"

	"wireguardians/exp/internal/pb"
	"wireguardians/exp/internal/record"
)

func main() {
	mode := flag.String("mode", "http", "http | https | mqtt")
	server := flag.String("server", "127.0.0.1:8080", "host:puerto (http/https) o URL del broker (mqtt)")
	esp := flag.Uint("esp", 1, "número de nodo")
	n := flag.Int("n", 5, "lecturas a enviar")
	period := flag.Duration("period", 200*time.Millisecond, "período")
	useJSON := flag.Bool("json", false, "serializar en JSON")
	qos := flag.Int("qos", 1, "QoS MQTT")
	certDir := flag.String("certs", "../infra/certs", "directorio con ca.crt")
	flag.Parse()

	encode := func(seq uint32) ([]byte, string) {
		t := &pb.Telemetry{EspId: uint32(*esp), Seq: seq, TUs: uint64(time.Now().UnixMicro()), Value: rand.Float32() * 100, Status: 0}
		if *useJSON {
			return record.EncodeJSON(t), "application/json"
		}
		b, _ := proto.Marshal(t)
		return b, "application/x-protobuf"
	}

	switch *mode {
	case "http", "https":
		scheme := *mode
		tr := &http.Transport{}
		if scheme == "https" {
			ca, err := os.ReadFile(filepath.Join(*certDir, "ca.crt"))
			if err != nil {
				log.Fatal(err)
			}
			pool := x509.NewCertPool()
			pool.AppendCertsFromPEM(ca)
			// El certificado es para 10.10.0.1; en pruebas locales se fija ServerName.
			tr.TLSClientConfig = &tls.Config{RootCAs: pool, ServerName: "10.10.0.1"}
		}
		c := &http.Client{Transport: tr, Timeout: 5 * time.Second}
		for i := 0; i < *n; i++ {
			body, ct := encode(uint32(i))
			resp, err := c.Post(fmt.Sprintf("%s://%s/tel/%d", scheme, *server, *esp), ct, bytes.NewReader(body))
			if err != nil {
				log.Fatal(err)
			}
			resp.Body.Close()
			log.Printf("seq=%d -> %s", i, resp.Status)
			time.Sleep(*period)
		}
	case "mqtt":
		c := mqtt.NewClient(mqtt.NewClientOptions().AddBroker(*server).SetClientID(fmt.Sprintf("test-%d", *esp)))
		if t := c.Connect(); t.Wait() && t.Error() != nil {
			log.Fatal(t.Error())
		}
		for i := 0; i < *n; i++ {
			body, _ := encode(uint32(i))
			t := c.Publish(fmt.Sprintf("exp/tel/%d", *esp), byte(*qos), false, body)
			t.Wait()
			log.Printf("seq=%d publicado", i)
			time.Sleep(*period)
		}
		c.Disconnect(250)
	default:
		log.Fatalf("modo desconocido %q", *mode)
	}
}
