# Componente principal del nodo Kuramoto: los .c y los componentes de ESP-IDF que usa.
idf_component_register(
    SRCS "main.c" "config.c" "net.c" "timesync.c" "mqtt.c" "kuramoto.pb.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES esp_eth esp_netif esp_event esp_timer esp_partition mqtt nanopb nvs_flash)
