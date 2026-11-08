#!/usr/bin/env python3
"""Corre una matriz de experimentos de Kuramoto sobre nodos ESP32 emulados con QEMU.

Por cada corrida (una combinación entrada x k x perfil x semilla de la matriz JSON):
  1. crea resultados/<matriz>/<corrida>/ y escribe config.json con todos los parámetros;
  2. arma una copia de la flash por nodo, con su config en 0x190000;
  3. levanta mosquitto, el servidor SNTP, netem (si hay perfil), el logger y los QEMU;
  4. espera READY y después DONE de todos los nodos (por la UART);
  5. detiene todo, escribe nodos.csv y, si todos terminaron, fin.ok.
Las corridas con fin.ok se saltean, así que se puede cortar y retomar.

Formato de la matriz (JSON):
  {"defecto": {...campos comunes...},
   "entradas": [{"nombre": "distintas", "n": 40, "config": "distintas", "f_hz": 0.1,
                 "ancho": 0.2, "k": [0.8, 1.05], "h_ms": 1000, "ts_ms": 10,
                 "duracion_s": 600, "semillas": [1, 2, 3],
                 "perfil": ["jitter", "wifi"], "extrapolar": 0}]}
  config "distintas": frecuencias equiespaciadas en f +- ancho*f; k son múltiplos de K_c
  (teoria.kc_finito). config "iguales": todas en f; k en rad/s.
  k, perfil y semillas son listas que se expanden; "" en perfil es sin netem.

Uso:  correr.py --matriz matrices/principal.json [--solo patrón] [--dry-run] [--local]
"""

import argparse
import csv
import fnmatch
import itertools
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import numpy as np

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent  # experimentos/sincronizacion
sys.path.insert(0, str(RAIZ / "simulacion"))
sys.path.insert(0, str(AQUI))

import teoria  # noqa: E402  (se importa desde simulacion/ sin modificarla)
from sntp_server import ServidorSNTP  # noqa: E402

# --- Contrato con el firmware -------------------------------------------------------------

OFFSET_CFG = 0x190000  # dónde empieza la config del nodo dentro de la flash
TAM_CFG = 4096  # tamaño máximo de la región de config
TAM_FLASH = 4 * 1024 * 1024
ENCABEZADO = "KURCFG1\n"
IP_PC = "10.10.0.1"
IP_PC_LOCAL = "10.0.2.2"  # la PC vista desde la red de usuario de QEMU
PUERTO_MQTT = 1883
TOPICO = "kuramoto/phase/+"

# Perfiles de netem por sentido, copiados de plataforma-comun/eco-mqtt/ruido_medir.sh.
# La variación va con "slot" (ráfagas en orden): "delay X Y" reordena y TCP lo vive como pérdida.
PERFILES = {
    "sin-ruido": "",
    "jitter": "delay 3ms slot distribution normal 4ms 2ms",
    "wifi": "delay 3ms slot distribution paretonormal 4ms 4ms",
    "wifi-perdida-1": "delay 3ms slot distribution paretonormal 4ms 4ms loss 1%",
    "wifi-perdida-5": "delay 3ms slot distribution paretonormal 4ms 4ms loss 5%",
}

DEFECTO = {
    "n": 40, "config": "distintas", "f_hz": 0.1, "ancho": 0.2, "k": [1.5], "h_ms": 1000,
    "ts_ms": 10, "duracion_s": 600, "semillas": [1], "perfil": [""], "extrapolar": 0,
}

SOBRECOSTO_S = 15  # arranque de procesos y cierre, para la estimación de duración
MAX_NODOS_CPU = 50  # por encima de esto la CPU de la PC de referencia no alcanza


def lista(v):
    return list(v) if isinstance(v, (list, tuple)) else [v]


# --- Matriz y expansión -------------------------------------------------------------------

def nombre_k(k):
    return f"{k:g}"


def expandir(matriz, nombre_matriz):
    """Devuelve la lista de corridas (dicts con todos los parámetros, sin sorteos)."""
    comun = {**DEFECTO, **matriz.get("defecto", {})}
    corridas = []
    for e in matriz["entradas"]:
        e = {**comun, **e}
        if e["config"] not in ("distintas", "iguales"):
            raise ValueError(f"config desconocida: {e['config']}")
        for k, perfil, semilla in itertools.product(
            lista(e["k"]), lista(e["perfil"]), lista(e["semillas"])
        ):
            if perfil and perfil not in PERFILES:
                raise ValueError(f"perfil desconocido: {perfil}")
            corridas.append({
                "matriz": nombre_matriz, "entrada": e["nombre"],
                "corrida": f"{e['nombre']}_k{nombre_k(k)}_{perfil or 'sin-netem'}_s{semilla}",
                "n": int(e["n"]), "config": e["config"], "f_hz": float(e["f_hz"]),
                "ancho": float(e["ancho"]), "k_entrada": float(k), "h_ms": int(e["h_ms"]),
                "ts_ms": int(e["ts_ms"]), "duracion_s": int(e["duracion_s"]),
                "semilla": int(semilla), "perfil": perfil, "extrapolar": int(e["extrapolar"]),
            })
    nombres = [c["corrida"] for c in corridas]
    if len(set(nombres)) != len(nombres):
        raise ValueError("hay corridas con el mismo nombre en la matriz")
    return corridas


def parametros_de_corrida(c, local=False):
    """Completa la corrida con omega, K y el sorteo de theta0 y desfase de cada nodo.

    Todo el azar sale de un generador de numpy sembrado con la semilla, así que repetir
    una corrida reproduce las mismas condiciones iniciales.
    """
    n = c["n"]
    if c["config"] == "distintas":
        omega = 2 * np.pi * teoria.frecuencias_equiespaciadas(n, c["f_hz"], c["ancho"] * c["f_hz"])
        kc = float(teoria.kc_finito(omega))
        k = c["k_entrada"] * kc
        k_veces_kc = c["k_entrada"]
    else:
        omega = np.full(n, 2 * np.pi * c["f_hz"])
        kc = 0.0  # con frecuencias iguales cualquier K > 0 engancha
        k = c["k_entrada"]
        k_veces_kc = None
    rng = np.random.default_rng(c["semilla"])
    theta0 = rng.uniform(0.0, 2 * np.pi, n)
    desfase = rng.integers(0, c["h_ms"], n)  # uniforme en [0, h), en ms enteros
    p = dict(c)
    p.update(
        k_rad_s=float(k), kc_rad_s=kc, k_veces_kc=k_veces_kc,
        perfil_args="" if local else PERFILES.get(c["perfil"], ""),
        sntp=0 if local else 1, red="user" if local else "tap",
        server_ip=IP_PC_LOCAL if local else IP_PC,
        nodos=[{
            "id": i + 1, "omega": float(omega[i]), "theta0": float(theta0[i]),
            "desfase_ms": int(desfase[i]),
        } for i in range(n)],
    )
    return p


# --- Config de nodo e imagen de flash -----------------------------------------------------

def mac_de(i):
    return f"02:00:00:00:00:{i:02x}"


def texto_config(p, nodo, t_inicio_ms, local):
    """Texto de la partición de config del nodo: KURCFG1 y líneas clave=valor."""
    i = nodo["id"]
    claves = [
        ("id", i), ("n", p["n"]),
        ("ip", "10.0.2.15" if local else f"10.10.0.{10 + i}"),
        ("server_ip", IP_PC_LOCAL if local else IP_PC),
        ("mac", mac_de(i)),
        ("omega", f"{nodo['omega']:.9g}"), ("k", f"{p['k_rad_s']:.9g}"),
        ("theta0", f"{nodo['theta0']:.9g}"),
        ("h_ms", p["h_ms"]), ("ts_ms", p["ts_ms"]), ("desfase_ms", nodo["desfase_ms"]),
        ("t_inicio_ms", t_inicio_ms), ("duracion_s", p["duracion_s"]),
        ("extrapolar", p["extrapolar"]), ("sntp", 0 if local else 1),
        ("red", "user" if local else "tap"),
    ]
    return ENCABEZADO + "".join(f"{k}={v}\n" for k, v in claves)


def region_config(texto):
    """Los 4 KB de config: texto, un 0 y el resto en 0xFF."""
    datos = texto.encode() + b"\0"
    if len(datos) > TAM_CFG:
        raise ValueError(f"la config ocupa {len(datos)} bytes (máximo {TAM_CFG})")
    return datos + b"\xff" * (TAM_CFG - len(datos))


def construir_imagen(flash, texto):
    """Copia de la flash con la config en 0x190000."""
    img = bytearray(flash)
    img[OFFSET_CFG:OFFSET_CFG + TAM_CFG] = region_config(texto)
    return bytes(img)


def leer_region(region):
    """Lee de vuelta la config de sus 4 KB como dict de strings (inversa de region_config)."""
    fin = region.index(b"\0")
    if region[fin + 1:] != b"\xff" * (TAM_CFG - fin - 1):
        raise ValueError("el resto de la región de config no es 0xFF")
    texto = region[:fin].decode()
    if not texto.startswith(ENCABEZADO):
        raise ValueError("falta el encabezado KURCFG1")
    return dict(l.split("=", 1) for l in texto[len(ENCABEZADO):].splitlines())


def leer_config(img):
    return leer_region(bytes(img[OFFSET_CFG:OFFSET_CFG + TAM_CFG]))


def cargar_flash(ruta, permitir_falta):
    ruta = Path(ruta)
    if not ruta.exists():
        if not permitir_falta:
            sys.exit(f"no existe la imagen de flash {ruta} (compilar el firmware primero)")
        print(f"AVISO: no existe {ruta}; se usa una imagen de prueba de 4 MB en 0xFF")
        return b"\xff" * TAM_FLASH
    flash = ruta.read_bytes()
    if len(flash) != TAM_FLASH:
        sys.exit(f"{ruta} mide {len(flash)} bytes y se esperaban {TAM_FLASH} (4 MB)")
    return flash


def verificar_imagenes(flash, p, t_inicio_ms, local):
    """Comprueba que la config de cada nodo se lee de vuelta igual.

    Las imágenes completas (con la flash intacta antes y después de la config) se arman
    para el primer y el último nodo; en los demás alcanza con la región de config.
    """
    for pos, nodo in enumerate(p["nodos"]):
        texto = texto_config(p, nodo, t_inicio_ms, local)
        esperado = dict(l.split("=", 1) for l in texto[len(ENCABEZADO):].splitlines())
        leido = leer_region(region_config(texto))
        if pos in (0, len(p["nodos"]) - 1):
            img = construir_imagen(flash, texto)
            assert len(img) == TAM_FLASH
            assert img[:OFFSET_CFG] == flash[:OFFSET_CFG], "se modificó la flash antes de la config"
            assert img[OFFSET_CFG + TAM_CFG:] == flash[OFFSET_CFG + TAM_CFG:], "se modificó la flash después"
            leido = leer_config(img)
        assert leido == esperado, f"la config del nodo {nodo['id']} no se leyó igual"
        assert int(leido["id"]) == nodo["id"] and float(leido["omega"]) == float(f"{nodo['omega']:.9g}")


# --- Procesos -----------------------------------------------------------------------------

class Procesos:
    """Procesos hijos de una corrida; se detienen siempre, en orden inverso al de arranque."""

    def __init__(self):
        self.lista = []

    def arrancar(self, nombre, args, stdout=None, **kw):
        p = subprocess.Popen(args, stdout=stdout, stderr=subprocess.STDOUT if stdout else None,
                             stdin=subprocess.DEVNULL, start_new_session=True, **kw)
        self.lista.append((nombre, p))
        return p

    def detener(self, prefijo=""):
        for nombre, p in reversed(self.lista):
            if not nombre.startswith(prefijo) or p.poll() is not None:
                continue
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        limite = time.time() + 5
        for nombre, p in self.lista:
            if not nombre.startswith(prefijo):
                continue
            try:
                p.wait(timeout=max(0.1, limite - time.time()))
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                p.wait()
        self.lista = [(n, p) for n, p in self.lista if not n.startswith(prefijo)]

    def caido(self, prefijo):
        """Nombre del primer proceso con ese prefijo que ya terminó, o None."""
        for nombre, p in self.lista:
            if nombre.startswith(prefijo) and p.poll() is not None:
                return nombre
        return None


def como_root(args):
    return list(args) if os.geteuid() == 0 else ["sudo", "-n", *args]


def esperar_puerto(host, puerto, plazo=10):
    fin = time.time() + plazo
    while time.time() < fin:
        try:
            socket.create_connection((host, puerto), timeout=0.5).close()
            return True
        except OSError:
            time.sleep(0.2)
    return False


class Nodo:
    """Estado de un nodo según las líneas que imprime por la UART."""

    def __init__(self, i, ruta_uart):
        self.id = i
        self.ruta = ruta_uart
        self.pos = 0
        self.resto = ""
        self.ready = False
        self.done = False
        self.error = ""
        self.contadores = {}

    def leer(self):
        try:
            with open(self.ruta, "rb") as f:
                f.seek(self.pos)
                nuevo = f.read()
        except FileNotFoundError:
            return
        self.pos += len(nuevo)
        texto = self.resto + nuevo.decode(errors="replace")
        *lineas, self.resto = texto.split("\n")
        for l in lineas:
            l = l.strip()
            if l.startswith("READY"):
                self.ready = True
            elif l.startswith("DONE"):
                self.done = True
                self.contadores = dict(t.split("=", 1) for t in l.split()[1:] if "=" in t)
            elif l.startswith(("CFGERR", "SYNCERR", "MQTTERR", "Guru Meditation")) and not self.error:
                self.error = l


def escribir_nodos_csv(ruta, nodos):
    with open(ruta, "w", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["id", "ready", "done", "error", "enviados", "recibidos", "overruns"])
        for n in nodos:
            c = n.contadores
            w.writerow([n.id, int(n.ready), int(n.done), n.error,
                        c.get("enviados", ""), c.get("recibidos", ""), c.get("overruns", "")])


# --- Una corrida --------------------------------------------------------------------------

def correr_una(p, args, flash, directorio, tmp):
    """Ejecuta la corrida ya preparada. Devuelve None si salió bien, o el motivo del fallo."""
    local = args.local
    n = p["n"]
    margen = args.margen if args.margen is not None else max(20.0, 2.25 * n)
    procs = Procesos()
    netem = False
    nodos = []
    srv = None
    try:
        conf = AQUI / ("mosquitto-local.conf" if local else "mosquitto.conf")
        log_mosq = open(directorio / "mosquitto.log", "wb")
        procs.arrancar("mosquitto", [args.mosquitto, "-c", str(conf)], stdout=log_mosq)
        if not esperar_puerto("127.0.0.1", PUERTO_MQTT):
            return "mosquitto no abrió el puerto 1883 (ver mosquitto.log)"

        if not local:
            srv = ServidorSNTP(args.sntp_bind, args.sntp_puerto)
            srv.start()
            if p["perfil_args"]:
                netem = True
                subprocess.run(como_root([str(AQUI / "red.sh"), "netem", p["perfil_args"]]), check=True)

        fases = open(directorio / "fases.log", "wb")
        procs.arrancar("logger", [
            args.mosquitto_sub, "-h", "127.0.0.1", "-V", "5", "-t", TOPICO,
            "-F", "%U %t %x"], stdout=fases)
        time.sleep(0.5)
        if procs.caido("logger"):
            return "el logger (mosquitto_sub) terminó al arrancar"
        if args.captura and not local:
            procs.arrancar("tcpdump", como_root(
                ["tcpdump", "-i", "br-kur", "-s", "256", "-w", str(directorio / "captura.pcap")]))

        # t_inicio: hora común de arranque. Con SNTP es epoch en ms; en --local (sin SNTP)
        # es ms desde el arranque de cada nodo.
        lanzado = time.time()
        t_inicio_ms = int(margen * 1000) if local else int((lanzado + margen) * 1000)
        p["t_inicio_ms"] = t_inicio_ms
        (directorio / "config.json").write_text(json.dumps(p, indent=1))

        for nodo in p["nodos"]:
            i = nodo["id"]
            img = tmp / f"flash{i}.bin"
            img.write_bytes(construir_imagen(flash, texto_config(p, nodo, t_inicio_ms, local)))
            uart = directorio / f"uart{i}.log"
            nodos.append(Nodo(i, uart))
            red = (["-nic", f"user,model=open_eth,mac={mac_de(i)}"] if local else
                   ["-nic", f"tap,ifname=tapk{i},script=no,downscript=no,model=open_eth,mac={mac_de(i)}"])
            procs.arrancar(f"qemu{i}", [
                args.qemu, "-machine", "esp32", "-display", "none", "-monitor", "none",
                # Sin el watchdog de los timers: un host cargado no debe reiniciar al nodo.
                "-global", "driver=timer.esp32.timg,property=wdt_disable,value=true",
                "-serial", f"file:{uart}", "-drive", f"file={img},if=mtd,format=raw", *red],
                stdout=subprocess.DEVNULL)
            time.sleep(args.escalonado)  # evita la tormenta de arranque

        def revisar():
            for nd in nodos:
                nd.leer()
                if nd.error:
                    return f"nodo {nd.id}: {nd.error}"
            terminados = {nd.id for nd in nodos if nd.done}
            for nombre, proc in procs.lista:
                if proc.poll() is None:
                    continue
                # un QEMU puede salir después de su DONE; cualquier otro caso es un fallo
                if nombre.startswith("qemu") and int(nombre[4:]) in terminados:
                    continue
                return f"terminó el proceso {nombre}"
            return None

        # READY de todos antes de la hora de inicio.
        limite = lanzado + margen + 5
        while not all(nd.ready for nd in nodos):
            if (m := revisar()):
                return m
            if time.time() > limite:
                faltan = [nd.id for nd in nodos if not nd.ready]
                return f"timeout esperando READY de los nodos {faltan}"
            time.sleep(0.5)
        print(f"    {n} nodos READY ({time.time() - lanzado:.0f} s tras el lanzamiento)", flush=True)

        # DONE de todos.
        limite = lanzado + margen + p["duracion_s"] + args.espera_done
        while not all(nd.done for nd in nodos):
            if (m := revisar()):
                return m
            if time.time() > limite:
                faltan = [nd.id for nd in nodos if not nd.done]
                return f"timeout esperando DONE de los nodos {faltan}"
            time.sleep(0.5)
        time.sleep(2)  # los últimos mensajes llegan al logger
        return None
    finally:
        for nd in nodos:
            nd.leer()
        procs.detener("qemu")
        procs.detener("tcpdump")
        procs.detener("logger")
        procs.detener("mosquitto")
        if srv is not None:
            srv.detener()
        if netem:
            subprocess.run(como_root([str(AQUI / "red.sh"), "clear"]), check=False)
        if nodos:
            escribir_nodos_csv(directorio / "nodos.csv", nodos)


def mantener_sudo(parar):
    """Renueva el ticket de sudo cada minuto, para que los netem de una matriz larga no fallen."""
    while not parar.wait(60):
        subprocess.run(["sudo", "-n", "-v"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def comprobar_entorno(args, corridas):
    if shutil.which(args.qemu) is None and not Path(args.qemu).exists():
        sys.exit(f"no se encuentra qemu-system-xtensa ({args.qemu}); usar --qemu")
    for exe in (args.mosquitto, args.mosquitto_sub):
        if shutil.which(exe) is None:
            sys.exit(f"falta el ejecutable {exe}")
    n = max(c["n"] for c in corridas)
    if args.local:
        return
    r = subprocess.run(["ip", "link", "show", "br-kur"], capture_output=True)
    if r.returncode:
        sys.exit("no existe br-kur: correr antes `sudo host/red.sh up N`")
    for i in range(1, n + 1):
        if subprocess.run(["ip", "link", "show", f"tapk{i}"], capture_output=True).returncode:
            sys.exit(f"falta tapk{i}: correr `sudo host/red.sh up {n}`")
    if not args.local and any(c["perfil"] for c in corridas) and os.geteuid() != 0:
        if subprocess.run(["sudo", "-n", "true"], capture_output=True).returncode:
            sys.exit("hay perfiles de netem y sudo pide contraseña: correr antes `sudo -v`")


# --- Principal ----------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Corre una matriz de experimentos de Kuramoto.")
    ap.add_argument("--matriz", required=True, help="archivo JSON de la matriz")
    ap.add_argument("--qemu", default="qemu-system-xtensa", help="ruta de qemu-system-xtensa")
    ap.add_argument("--flash", default=str(RAIZ / "firmware" / "build" / "flash.bin"))
    ap.add_argument("--solo", help="solo entradas o corridas que coincidan (patrón tipo shell)")
    ap.add_argument("--dry-run", action="store_true",
                    help="muestra el plan y verifica las imágenes, sin arrancar nada")
    ap.add_argument("--local", action="store_true",
                    help="prueba sin privilegios: red de usuario de QEMU, sin SNTP, tap ni netem")
    ap.add_argument("--margen", type=float, help="segundos entre el lanzamiento y t_inicio "
                    "(por defecto max(20, 2.25*N): 90 con 40 nodos)")
    ap.add_argument("--captura", action="store_true", help="captura br-kur con tcpdump (pcap)")
    ap.add_argument("--salida", default=str(RAIZ / "resultados"), help="directorio de resultados")
    ap.add_argument("--escalonado", type=float, default=0.2, help="segundos entre arranques de QEMU")
    ap.add_argument("--espera-done", type=float, default=60.0, help="holgura sobre la duración")
    ap.add_argument("--mosquitto", default="mosquitto")
    ap.add_argument("--mosquitto-sub", default="mosquitto_sub")
    ap.add_argument("--sntp-bind", default=IP_PC, help="dirección donde escucha el SNTP")
    ap.add_argument("--sntp-puerto", type=int, default=123)
    ap.add_argument("-v", "--verbose", action="store_true", help="lista todas las corridas")
    args = ap.parse_args()

    ruta = Path(args.matriz)
    matriz = json.loads(ruta.read_text())
    nombre_matriz = matriz.get("matriz", ruta.stem)
    corridas = expandir(matriz, nombre_matriz)
    if args.solo:
        corridas = [c for c in corridas
                    if fnmatch.fnmatch(c["corrida"], args.solo) or fnmatch.fnmatch(c["entrada"], args.solo)]
    if not corridas:
        sys.exit("ninguna corrida coincide")
    if args.local and any(c["n"] > 4 for c in corridas):
        print("AVISO: --local está pensado para 2 nodos")
    for c in corridas:
        if c["n"] > MAX_NODOS_CPU:
            print(f"AVISO: {c['corrida']} usa {c['n']} nodos (> {MAX_NODOS_CPU}): la CPU no alcanza")
            break

    salida = Path(args.salida) / nombre_matriz
    pendientes = [c for c in corridas if not (salida / c["corrida"] / "fin.ok").exists()]
    total_s = 0.0
    for c in pendientes:
        margen = args.margen if args.margen is not None else max(20.0, 2.25 * c["n"])
        total_s += margen + c["duracion_s"] + SOBRECOSTO_S
    print(f"matriz {nombre_matriz}: {len(corridas)} corridas, {len(pendientes)} pendientes, "
          f"duración estimada {total_s / 3600:.1f} h")

    if args.dry_run:
        return dry_run(args, pendientes, nombre_matriz)

    comprobar_entorno(args, pendientes)
    flash = cargar_flash(args.flash, permitir_falta=False)
    parar_sudo = threading.Event()
    if any(c["perfil"] for c in pendientes) and os.geteuid() != 0 and not args.local:
        threading.Thread(target=mantener_sudo, args=(parar_sudo,), daemon=True).start()

    def al_terminar(signo, _marco):
        raise KeyboardInterrupt  # para que corran los finally

    signal.signal(signal.SIGTERM, al_terminar)

    fallos = seguidos = 0
    try:
        for idx, c in enumerate(pendientes, 1):
            p = parametros_de_corrida(c, args.local)
            directorio = salida / c["corrida"]
            directorio.mkdir(parents=True, exist_ok=True)
            for viejo in ("fin.ok", "fallo.txt"):
                (directorio / viejo).unlink(missing_ok=True)
            (directorio / "config.json").write_text(json.dumps(p, indent=1))
            print(f"[{idx}/{len(pendientes)}] {c['corrida']}  K={p['k_rad_s']:.4g} rad/s", flush=True)
            tmp = Path(tempfile.mkdtemp(prefix="kur-"))
            try:
                motivo = correr_una(p, args, flash, directorio, tmp)
            except Exception as e:  # noqa: BLE001  (cualquier fallo se registra y sigue la matriz)
                motivo = f"excepción: {e!r}"
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
            if motivo is None:
                (directorio / "fin.ok").write_text(time.strftime("%Y-%m-%dT%H:%M:%S\n"))
                seguidos = 0
            else:
                (directorio / "fallo.txt").write_text(motivo + "\n")
                print(f"    FALLO: {motivo}", flush=True)
                fallos += 1
                seguidos += 1
                if seguidos >= 3:
                    print("tres fallos seguidos: se corta la matriz")
                    break
    except KeyboardInterrupt:
        print("interrumpido; lo hecho queda y se retoma al volver a correr")
        fallos += 1
    finally:
        parar_sudo.set()
    sys.exit(1 if fallos else 0)


def dry_run(args, corridas, nombre_matriz):
    """Plan y verificación de imágenes sin arrancar procesos ni tocar la red."""
    local = args.local
    flash = cargar_flash(args.flash, permitir_falta=True)
    tmp = Path(tempfile.mkdtemp(prefix="kur-dryrun-"))
    por_entrada = {}
    for c in corridas:
        por_entrada.setdefault(c["entrada"], []).append(c)
    for entrada, cs in por_entrada.items():
        c0 = cs[0]
        print(f"  {entrada}: {len(cs)} corridas, N={c0['n']}, config={c0['config']}, "
              f"f={c0['f_hz']} Hz, h={c0['h_ms']} ms, ts={c0['ts_ms']} ms, "
              f"duración={c0['duracion_s']} s, extrapolar={c0['extrapolar']}")
    verificadas = 0
    for idx, c in enumerate(corridas):
        p = parametros_de_corrida(c, local)
        t_inicio_ms = int((time.time() + 90) * 1000) if not local else 90000
        p["t_inicio_ms"] = t_inicio_ms
        verificar_imagenes(flash, p, t_inicio_ms, local)
        verificadas += 1
        d = tmp / nombre_matriz / c["corrida"]
        d.mkdir(parents=True)
        (d / "config.json").write_text(json.dumps(p, indent=1))
        if args.verbose:
            kc = f"  K/Kc={p['k_veces_kc']:g}" if p["k_veces_kc"] else ""
            print(f"    {c['corrida']}: K={p['k_rad_s']:.4g} rad/s{kc}  netem=[{p['perfil_args']}]")
        if idx == 0:
            nodo = p["nodos"][0]
            (tmp / "nodo1.bin").write_bytes(
                construir_imagen(flash, texto_config(p, nodo, t_inicio_ms, local)))
    print(f"imágenes verificadas: {verificadas} corridas (todos los nodos), config en "
          f"0x{OFFSET_CFG:X} bien escrita")
    print(f"dry-run: configs y una imagen de ejemplo (nodo1.bin) en {tmp}; no se arrancó nada")


if __name__ == "__main__":
    main()
