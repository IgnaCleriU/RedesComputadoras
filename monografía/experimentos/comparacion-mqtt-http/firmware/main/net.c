// Ethernet "open_eth" de QEMU con IP estática y MAC tomada de la config.
//
// QEMU no emula la radio WiFi del ESP32, pero sí un controlador Ethernet
// OpenCores (open_eth), y ESP-IDF trae su driver. Se inicializa igual que en los
// ejemplos de ESP-IDF (MAC openeth + PHY dp83848), con dos cambios:
//  - MAC propia: todas las instancias QEMU tendrían la misma MAC de efuse; con
//    MACs repetidas en el mismo bridge ARP no funciona, por eso cada nodo usa la
//    suya (02:00:00:00:00:NN, administrada localmente, igual que en -nic de QEMU).
//  - IP estática 10.10.0.(10+N)/24, gateway 10.10.0.1, sin DHCP: arranque más
//    rápido y sin tráfico extra en la captura.
// IPv6 está desactivado en sdkconfig: sin tráfico MLD/RS en la captura.
#include <stdio.h>
#include <string.h>

#include "esp_eth.h"
#include "esp_eth_mac_openeth.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "node.h"

#define LINK_UP_BIT BIT0

static EventGroupHandle_t s_events;

static void on_eth_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (id == ETHERNET_EVENT_CONNECTED) {
        xEventGroupSetBits(s_events, LINK_UP_BIT);
    } else if (id == ETHERNET_EVENT_DISCONNECTED) {
        printf("LINKDOWN\n");
    }
}

bool net_start(const node_config_t *cfg)
{
    s_events = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    esp_netif_config_t netif_cfg = ESP_NETIF_DEFAULT_ETH();
    esp_netif_t *netif = esp_netif_new(&netif_cfg);

    eth_mac_config_t mac_config = ETH_MAC_DEFAULT_CONFIG();
    eth_phy_config_t phy_config = ETH_PHY_DEFAULT_CONFIG();
    phy_config.autonego_timeout_ms = 100; // en QEMU el enlace levanta enseguida
    esp_eth_mac_t *mac = esp_eth_mac_new_openeth(&mac_config);
    esp_eth_phy_t *phy = esp_eth_phy_new_dp83848(&phy_config);

    esp_eth_config_t eth_config = ETH_DEFAULT_CONFIG(mac, phy);
    esp_eth_handle_t eth = NULL;
    ESP_ERROR_CHECK(esp_eth_driver_install(&eth_config, &eth));
    // La MAC se fija antes de unir el driver a netif: el glue la copia al attach.
    ESP_ERROR_CHECK(esp_eth_ioctl(eth, ETH_CMD_S_MAC_ADDR, (void *)cfg->mac));
    ESP_ERROR_CHECK(esp_netif_attach(netif, esp_eth_new_netif_glue(eth)));

    esp_netif_dhcpc_stop(netif);
    esp_netif_ip_info_t ip = {0};
    ip.ip.addr = esp_ip4addr_aton(cfg->ip);
    ip.gw.addr = esp_ip4addr_aton(cfg->server_ip);
    ip.netmask.addr = esp_ip4addr_aton("255.255.255.0");
    ESP_ERROR_CHECK(esp_netif_set_ip_info(netif, &ip));

    ESP_ERROR_CHECK(esp_event_handler_register(ETH_EVENT, ESP_EVENT_ANY_ID, on_eth_event, NULL));
    ESP_ERROR_CHECK(esp_eth_start(eth));

    // on_eth_event pone LINK_UP_BIT al recibir ETHERNET_EVENT_CONNECTED.
    EventBits_t bits = xEventGroupWaitBits(s_events, LINK_UP_BIT, pdFALSE, pdTRUE, pdMS_TO_TICKS(10000));
    if (!(bits & LINK_UP_BIT)) {
        printf("NETERR link no levanta\n");
        return false;
    }
    printf("NET ip=%s mac=%02x:%02x:%02x:%02x:%02x:%02x\n", cfg->ip, cfg->mac[0], cfg->mac[1],
           cfg->mac[2], cfg->mac[3], cfg->mac[4], cfg->mac[5]);
    return true;
}
