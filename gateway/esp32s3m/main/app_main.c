/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdlib.h>
#include <time.h>
#include "esp_log.h"
#include "nvs_flash.h"
#include "cloud_iotda.h"
#include "board_display.h"
#include "device_router.h"
#include "gateway_config.h"
#include "gateway_security.h"
#include "local_server.h"
#include "network_manager.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "yaocore";

void app_main(void)
{
    setenv("TZ", "UTC0", 1); tzset();
    esp_err_t nvs = nvs_flash_init();
    if (nvs != ESP_OK) {
        /* Never silently erase the persistent replay floor.  A deliberate
         * factory erase must be a physical/service operation. */
        ESP_LOGE(TAG, "NVS unavailable (%s); refusing automatic erase",
            esp_err_to_name(nvs));
        ESP_ERROR_CHECK(nvs);
    }
    esp_err_t display = board_display_init();
    if (display != ESP_OK) ESP_LOGW(TAG, "LCD unavailable: %s; gateway will continue", esp_err_to_name(display));
    if (!gateway_config_validate()) {
        ESP_LOGE(TAG, "invalid configuration; use idf.py menuconfig");
        board_display_show_config_error();
        return;
    }
    ESP_ERROR_CHECK(gateway_security_init()); ESP_ERROR_CHECK(device_router_init()); network_manager_start();
    EventGroupHandle_t network_events = network_manager_events();
    /* BLE provisioning and its controller can still be releasing memory when
     * DHCP completes. Starting the 10 KiB HTTP task in that short window may
     * return ESP_ERR_HTTPD_TASK. This is a recoverable resource transition,
     * not a fatal gateway error, so keep the Wi-Fi session and retry instead
     * of aborting and rebooting after an otherwise successful provisioning. */
    esp_err_t local_server = ESP_FAIL;
    while (!local_server_is_started()) {
        /* A successful provisioning result can be followed by a brief Wi-Fi
         * reconnect while the AP updates its station state.  Do not call
         * listen() against a down netif: lwIP returns EHOSTDOWN and an
         * unconditional retry loop makes the App see an IP with no service. */
        xEventGroupWaitBits(network_events, NETWORK_CONNECTED_BIT,
                            pdFALSE, pdTRUE, portMAX_DELAY);

        local_server = local_server_start();
        if (local_server == ESP_OK) {
            break;
        }

        EventBits_t bits = xEventGroupGetBits(network_events);
        if ((bits & NETWORK_CONNECTED_BIT) == 0) {
            ESP_LOGW(TAG,
                     "local gateway service paused until Wi-Fi obtains an IP");
            continue;
        }

        /* The interface is still valid, so this is most likely a short-lived
         * resource transition (for example BLE controller memory release).
         * Retry at a low rate without rebooting or discarding credentials. */
        ESP_LOGW(TAG, "local gateway service not ready (%s); retrying in 2 s",
                 esp_err_to_name(local_server));
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
    if ((xEventGroupGetBits(network_events) & NETWORK_CONNECTED_BIT) != 0) {
        board_display_show_ready(NULL, gateway_config_get()->local_port);
    }
    ESP_LOGI(TAG, "local gateway started immediately after DHCP; authenticated App time can bootstrap an invalid clock");
    if (gateway_config_get()->iotda_enabled) {
        ESP_LOGI(TAG, "waiting for trusted SNTP time before starting IoTDA");
        xEventGroupWaitBits(network_manager_events(), NETWORK_TIME_READY_BIT,
            pdFALSE, pdTRUE, portMAX_DELAY);
    }
    ESP_ERROR_CHECK(cloud_iotda_start()); ESP_LOGI(TAG, "YaoCore ESP32-S3M gateway started");
}
