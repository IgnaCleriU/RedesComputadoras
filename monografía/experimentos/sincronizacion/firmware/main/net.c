// Ethernet "open_eth" de QEMU. Dos modos (clave red de la config):
//  - tap:  IP estática /24, gateway server_ip y MAC propia (varias instancias
//          QEMU en un mismo puente no pueden compartir la MAC de fábrica).
//  - user: red de usuario de QEMU (sin root): DHCP; se espera el evento de IP.
//          server_ip suele ser 10.0.2.2.
// IPv6 está desactivado en sdkconfig: sin tráfico MLD/RS.
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
#define GOT_IP_BIT BIT1

static EventGroupHandle_t s_events;

static void on_eth_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (id == ETHERNET_EVENT_CONNECTED) {
        xEventGroupSetBits(s_events, LINK_UP_BIT);
    } else if (id == ETHERNET_EVENT_DISCONNECTED) {
        printf("LINKDOWN\n");
    }
}

static void on_got_ip(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    xEventGroupSetBits(s_events, GOT_IP_BIT);
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
    if (cfg->mac_set) {
        // La MAC se fija antes de unir el driver a netif: el glue la copia al attach.
        ESP_ERROR_CHECK(esp_eth_ioctl(eth, ETH_CMD_S_MAC_ADDR, (void *)cfg->mac));
    }
    ESP_ERROR_CHECK(esp_netif_attach(netif, esp_eth_new_netif_glue(eth)));

    if (cfg->red_tap) {
        esp_netif_dhcpc_stop(netif);
        esp_netif_ip_info_t ip = {0};
        ip.ip.addr = esp_ip4addr_aton(cfg->ip);
        ip.gw.addr = esp_ip4addr_aton(cfg->server_ip);
        ip.netmask.addr = esp_ip4addr_aton("255.255.255.0");
        ESP_ERROR_CHECK(esp_netif_set_ip_info(netif, &ip));
    } else {
        ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_ETH_GOT_IP, on_got_ip, NULL));
    }

    ESP_ERROR_CHECK(esp_event_handler_register(ETH_EVENT, ESP_EVENT_ANY_ID, on_eth_event, NULL));
    ESP_ERROR_CHECK(esp_eth_start(eth));

    EventBits_t want = cfg->red_tap ? LINK_UP_BIT : (LINK_UP_BIT | GOT_IP_BIT);
    EventBits_t bits = xEventGroupWaitBits(s_events, want, pdFALSE, pdTRUE, pdMS_TO_TICKS(20000));
    if ((bits & want) != want) {
        printf("NETERR %s\n", (bits & LINK_UP_BIT) ? "sin IP por DHCP" : "link no levanta");
        return false;
    }
    esp_netif_ip_info_t got;
    esp_netif_get_ip_info(netif, &got);
    printf("NET ip=" IPSTR "\n", IP2STR(&got.ip));
    return true;
}
