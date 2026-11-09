"""Muestrea cada segundo la RAM y la CPU de la PC y de los QEMU: python3 monitor.py salida.csv"""
import os, sys, time

HZ = os.sysconf("SC_CLK_TCK")


def meminfo():
    m = {}
    for line in open("/proc/meminfo"):
        k, v = line.split(":")
        m[k] = int(v.split()[0]) // 1024  # MiB
    return m


def cpu_total():
    v = list(map(int, open("/proc/stat").readline().split()[1:]))
    return sum(v), v[3] + v[4]  # total, idle + iowait


def qemus():
    """pid -> (RSS en MiB, ticks de CPU) de cada qemu-system-xtensa."""
    r = {}
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            if open(f"/proc/{pid}/comm").read().strip() != "qemu-system-xte":
                continue
            st = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
            rss = int(st[21]) * os.sysconf("SC_PAGE_SIZE") // 2**20
            r[pid] = (rss, int(st[11]) + int(st[12]))
        except (FileNotFoundError, ProcessLookupError):
            pass
    return r


with open(sys.argv[1], "w") as out:
    out.write("t,qemus,qemu_rss_mb,qemu_cpu_pct,mem_disp_mb,swap_usado_mb,cpu_pct,carga1\n")
    t0 = time.time()
    tot0, idle0 = cpu_total()
    q0 = qemus()
    while True:
        time.sleep(1)
        tot, idle = cpu_total()
        q = qemus()
        m = meminfo()
        cpu = 100 * (1 - (idle - idle0) / max(tot - tot0, 1))
        # % de un núcleo, sumado sobre todos los QEMU (1200 % = los 12 hilos)
        qcpu = 100 * sum(t - q0.get(p, (0, t))[1] for p, (_, t) in q.items()) / HZ
        out.write(f"{time.time() - t0:.0f},{len(q)},{sum(r for r, _ in q.values())},{qcpu:.0f},"
                  f"{m['MemAvailable']},{m['SwapTotal'] - m['SwapFree']},{cpu:.1f},"
                  f"{os.getloadavg()[0]:.2f}\n")
        out.flush()
        tot0, idle0, q0 = tot, idle, q
