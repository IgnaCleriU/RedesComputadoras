// Package matrix arma la lista de configuraciones del experimento a partir de
// un archivo YAML (matrices/principal.yaml, matrices/smoke.yaml, matrices/nagle.yaml).
//
// Formato:
//
//	duration_s: 120
//	repetitions: 5
//	seed: 42                       # orden aleatorio reproducible
//	design: ofat                   # u "factorial"
//	base: {nodes: 8, period_ms: 1000, tls: true, loss_pct: 0, rtt_ms: 0, serialization: pb}
//	transports: [mqtt0, mqtt1, http_req, http_reuse]
//	period_overrides: {http_req: 10000}
//	factors: {nodes: [2, 4, 8], period_ms: [100, 1000, 10000], ...}
//
// Diseños:
//   - "ofat" (por defecto): base + un factor a la vez, para cada transporte. Los
//     niveles iguales a la base dan el mismo ID y se descartan por repetidos.
//   - "factorial": todas las combinaciones de los factores listados.
//
// period_overrides fija un período base distinto para un transporte (p. ej.
// http_req a 10 s porque con TLS satura en QEMU con períodos menores). En ese
// transporte se omiten los niveles de período menores al fijado.
//
// Así salen las 42 configuraciones de matrices/principal.yaml:
//
//	mqtt0, mqtt1, http_reuse: base + nodes 2,4 + period 100,10000 + tls false
//	                          + loss 1,5 + rtt 50,200 + json          = 11 cada uno
//	http_req (base 10 s):     igual, sin niveles de período (100 y 1000 < 10000) = 9
//	11 × 3 + 9 = 42, × 5 repeticiones = 210 corridas.
//
// Para agregar un factor: el campo en Config (y en ID() si debe distinguir
// directorios), el nivel en Factors y un setter en setters(). Si el nodo lo
// necesita, la línea en nodeConfig del runner y la clave en firmware/main/config.c.
package matrix

import (
	"fmt"
	"math/rand/v2"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Transport     string  `yaml:"transport" json:"transport"`
	Nodes         int     `yaml:"nodes" json:"nodes"`
	PeriodMs      int     `yaml:"period_ms" json:"period_ms"`
	TLS           bool    `yaml:"tls" json:"tls"`
	LossPct       float64 `yaml:"loss_pct" json:"loss_pct"`
	RttMs         int     `yaml:"rtt_ms" json:"rtt_ms"`
	Serialization string  `yaml:"serialization" json:"serialization"`
	Nodelay       bool    `yaml:"nodelay" json:"nodelay"` // TCP_NODELAY en HTTP (sin Nagle)
	DurationS     int     `yaml:"-" json:"duration_s"`
	Factor        string  `yaml:"-" json:"factor"` // factor variado ("base" si ninguno)
}

// ID identifica la configuración; también es el nombre del directorio.
func (c Config) ID() string {
	tls := 0
	if c.TLS {
		tls = 1
	}
	id := fmt.Sprintf("%s_n%d_p%d_tls%d_l%g_r%d_%s", c.Transport, c.Nodes, c.PeriodMs, tls, c.LossPct, c.RttMs, c.Serialization)
	if c.Nodelay {
		id += "_nodelay"
	}
	return id
}

func (c Config) IsMQTT() bool { return c.Transport == "mqtt0" || c.Transport == "mqtt1" }

// Port devuelve el puerto del servidor que usan los nodos en esta configuración.
func (c Config) Port() int {
	switch {
	case c.IsMQTT() && c.TLS:
		return 8883
	case c.IsMQTT():
		return 1883
	case c.TLS:
		return 443
	default:
		return 80
	}
}

type Factors struct {
	Nodes         []int     `yaml:"nodes"`
	PeriodMs      []int     `yaml:"period_ms"`
	TLS           []bool    `yaml:"tls"`
	LossPct       []float64 `yaml:"loss_pct"`
	RttMs         []int     `yaml:"rtt_ms"`
	Serialization []string  `yaml:"serialization"`
	Nodelay       []bool    `yaml:"nodelay"`
}

type Matrix struct {
	Design          string         `yaml:"design"` // "ofat" (por defecto) o "factorial"
	DurationS       int            `yaml:"duration_s"`
	Repetitions     int            `yaml:"repetitions"`
	Seed            uint64         `yaml:"seed"`
	Base            Config         `yaml:"base"`
	Transports      []string       `yaml:"transports"`
	Factors         Factors        `yaml:"factors"`
	PeriodOverrides map[string]int `yaml:"period_overrides"`
}

func Load(path string) (*Matrix, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Matrix
	if err := yaml.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if m.Repetitions <= 0 {
		m.Repetitions = 1
	}
	switch m.Design {
	case "", "ofat", "factorial":
	default:
		return nil, fmt.Errorf("%s: design desconocido %q", path, m.Design)
	}
	return &m, nil
}

// setter aplica un nivel de un factor a una configuración. Tener todos los
// factores en una lista permite recorrerlos con el mismo código en los dos diseños.
type setter struct {
	name   string
	levels int
	apply  func(c *Config, i int)
}

func (m *Matrix) setters() []setter {
	f := m.Factors
	return []setter{
		{"nodes", len(f.Nodes), func(c *Config, i int) { c.Nodes = f.Nodes[i] }},
		{"period_ms", len(f.PeriodMs), func(c *Config, i int) { c.PeriodMs = f.PeriodMs[i] }},
		{"tls", len(f.TLS), func(c *Config, i int) { c.TLS = f.TLS[i] }},
		{"loss_pct", len(f.LossPct), func(c *Config, i int) { c.LossPct = f.LossPct[i] }},
		{"rtt_ms", len(f.RttMs), func(c *Config, i int) { c.RttMs = f.RttMs[i] }},
		{"serialization", len(f.Serialization), func(c *Config, i int) { c.Serialization = f.Serialization[i] }},
		{"nodelay", len(f.Nodelay), func(c *Config, i int) { c.Nodelay = f.Nodelay[i] }},
	}
}

// Configs devuelve las configuraciones sin repetir, en orden estable.
func (m *Matrix) Configs() []Config {
	var out []Config
	seen := map[string]bool{}
	add := func(c Config, factor string) {
		if min, ok := m.PeriodOverrides[c.Transport]; ok && c.PeriodMs < min {
			return // período por debajo del mínimo de este transporte
		}
		c.DurationS = m.DurationS
		c.Factor = factor
		if !seen[c.ID()] {
			seen[c.ID()] = true
			out = append(out, c)
		}
	}
	for _, tr := range m.Transports {
		base := m.Base
		base.Transport = tr
		if p, ok := m.PeriodOverrides[tr]; ok {
			base.PeriodMs = p
		}
		if m.Design == "factorial" {
			m.factorial(base, add)
			continue
		}
		add(base, "base")
		for _, s := range m.setters() {
			for i := 0; i < s.levels; i++ {
				c := base
				s.apply(&c, i)
				add(c, s.name)
			}
		}
	}
	return out
}

// factorial recorre todas las combinaciones de los factores con niveles, como un
// odómetro: un índice por factor; se incrementa el primero y, cuando pasa de su
// último nivel, vuelve a 0 y se incrementa el siguiente, hasta que el último da
// la vuelta.
func (m *Matrix) factorial(base Config, add func(Config, string)) {
	var active []setter
	for _, s := range m.setters() {
		if s.levels > 0 {
			active = append(active, s)
		}
	}
	idx := make([]int, len(active))
	for {
		c := base
		for k, s := range active {
			s.apply(&c, idx[k])
		}
		add(c, "factorial")
		k := 0
		for ; k < len(active); k++ {
			idx[k]++
			if idx[k] < active[k].levels {
				break
			}
			idx[k] = 0
		}
		if k == len(active) {
			return
		}
	}
}

type Run struct {
	Config Config
	Rep    int // 1..Repetitions
}

func (r Run) Dir() string { return fmt.Sprintf("%s/rep%d", r.Config.ID(), r.Rep) }

// Runs devuelve todas las corridas en orden aleatorio reproducible (semilla fija),
// para que la deriva del host no se confunda con un factor: si el host se degrada
// a lo largo de horas, el efecto se reparte entre todas las configuraciones. Con
// la misma semilla el orden es siempre el mismo.
func (m *Matrix) Runs() []Run {
	var runs []Run
	for _, c := range m.Configs() {
		for rep := 1; rep <= m.Repetitions; rep++ {
			runs = append(runs, Run{c, rep})
		}
	}
	rng := rand.New(rand.NewPCG(m.Seed, 0x5eed))
	rng.Shuffle(len(runs), func(i, j int) { runs[i], runs[j] = runs[j], runs[i] })
	return runs
}
