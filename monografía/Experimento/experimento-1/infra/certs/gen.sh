#!/usr/bin/env bash
# Genera una CA y un único certificado de servidor ECDSA P-256 para
# Mosquitto (8883) y el servidor HTTPS (443). SAN = 10.10.0.1.
# Las claves privadas (*.key) no se suben al repositorio: hay que correr este script
# antes de compilar. Si se regeneran, hay que recompilar el firmware
# (firmware/build.sh copia ca.crt y el nodo la embebe).
#
# - El SAN IP:10.10.0.1 es lo que verifican mbedTLS y Go: los nodos se conectan
#   por IP, así que la IP tiene que estar en el certificado.
# - ECDSA y no RSA: con P-256 el handshake es todo criptografía de curva elíptica
#   (ECDHE + firma ECDSA), mucho más liviana para un cliente con criptografía
#   emulada. La suite ECDHE-ECDSA-AES128-GCM-SHA256 exige un certificado ECDSA.
set -euo pipefail
cd "$(dirname "$0")"
SERVER_IP="${SERVER_IP:-10.10.0.1}"

openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=WireGuardians Exp CA" -out ca.crt

openssl ecparam -name prime256v1 -genkey -noout -out server.key
openssl req -new -key server.key -subj "/CN=${SERVER_IP}" -out server.csr
cat > server.ext <<EXT
basicConstraints=CA:FALSE
keyUsage=digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=IP:${SERVER_IP}
EXT
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 3650 -sha256 -extfile server.ext -out server.crt
rm -f server.csr server.ext ca.srl
chmod 644 server.key   # mosquitto corre con otro usuario
openssl verify -CAfile ca.crt server.crt
