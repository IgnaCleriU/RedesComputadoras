# Componente principal del nodo: los 8 .c, los componentes de ESP-IDF que usa y
# la CA embebida. EMBED_TXTFILES crea el símbolo _binary_ca_crt_start (ver node.h).
idf_component_register(
    SRCS "main.c" "config.c" "net.c" "timesync.c" "encode.c"
         "transport_mqtt.c" "transport_http.c" "telemetry.pb.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES esp_eth esp_netif esp_event esp_timer esp_partition
                  mqtt esp_http_client esp-tls nanopb
    EMBED_TXTFILES "ca.crt")
