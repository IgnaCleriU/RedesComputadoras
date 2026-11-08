idf_component_register(SRCS "main.c"
                       PRIV_REQUIRES mqtt nvs_flash esp_netif esp_wifi esp_eth spi_flash protocol_examples_common)
