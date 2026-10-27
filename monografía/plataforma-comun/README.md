# Plataforma común

Paquetes usados para emular los nodos ESP32 con QEMU y conectarlos por MQTT. Versiones probadas en Arch Linux (x86_64).

## Paquetes del sistema

| Paquete | Versión | Para qué |
|---|---|---|
| `gcc`, `make` | 16.2.1, 4.4.1 | Compilación nativa (herramientas de ESP-IDF) |
| `cmake`, `ninja` | 4.4.4, 1.13.2 | Sistema de build de ESP-IDF |
| `flex`, `bison`, `gperf` | 2.6.4, 3.8.2, 3.3 | Dependencias de build de ESP-IDF (Kconfig) |
| `ccache` | 4.14.1 | Caché de compilación |
| `dfu-util`, `libusb` | 0.11, 1.0.30 | Requeridos por ESP-IDF (flasheo por USB) |
| `python` | 3.14.8 | Herramientas de ESP-IDF (`idf.py`, `esptool`) |
| `git` | 2.56.0 | Clonar ESP-IDF y sus submódulos |
| `libgcrypt`, `glib2`, `pixman`, `sdl2-compat`, `libslirp` | 1.12.4, 2.90.1, 0.46.4, 2.32.74, 4.9.5 | Bibliotecas que usa QEMU |
| `mosquitto` | 2.1.2 | Broker MQTT (y `mosquitto_pub` / `mosquitto_sub`) |
| `protobuf` | 36.1 | Compilador `protoc` |
| `iproute2` | 7.2.0 | `ip` y `tc` (netem) para emular la red |
| `tcpdump`, `wireshark-cli` | 4.99.7, 4.7.4 | Captura y análisis de tráfico (`tshark`) |

## ESP-IDF y QEMU

| Componente | Versión |
|---|---|
| ESP-IDF | v5.5.6 |
| Toolchain `xtensa-esp-elf-gcc` | 14.2.0 (esp-14.2.0_20260121) |
| QEMU de Espressif (`qemu-system-xtensa`) | 9.2.2 (esp_develop_9.2.2_20260417) |

El QEMU de los repositorios de Arch no emula el ESP32; hace falta el fork de Espressif, que se instala con las herramientas de ESP-IDF.
