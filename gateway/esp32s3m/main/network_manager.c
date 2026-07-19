/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "network_manager.h"
#include <stdio.h>
#include <string.h>
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "driver/gpio.h"
#include "cJSON.h"
#include "freertos/task.h"
#include "board_display.h"
#include "gateway_config.h"
#include "local_server.h"
#include "sdkconfig.h"
#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_ble.h"
#include "host/ble_gap.h"

static const char *TAG = "network";
static EventGroupHandle_t s_events;
static int s_retries;
static TaskHandle_t s_reconnect_task;
static TaskHandle_t s_time_task;
static TaskHandle_t s_provisioning_cleanup_task;
static bool s_sntp_initialized;
static volatile bool s_provisioning_active;
static volatile bool s_reset_ui_active;
static volatile bool s_reset_in_progress;

#define PROVISIONING_SUCCESS_FALLBACK_STOP_MS 60000
#define NETWORK_RECONNECT_REQUEST_BIT BIT3
#define NETWORK_RECONNECT_FAILED_BIT BIT4
#define NETWORK_RECONNECT_RESULT_WAIT_MS 12000

#define PROVISIONING_NAME_PREFIX "YaoCore-GW-"
#define PROVISIONING_RESET_GPIO GPIO_NUM_0
#define PROVISIONING_IDENTITY_ENDPOINT "yaocore-id"
#define PROVISIONING_FINISH_ENDPOINT "yaocore-done"

static void get_provisioning_service_name(char *name, size_t size);

static void restore_network_status_screen(void)
{
    EventBits_t bits = xEventGroupGetBits(s_events);
    if (s_provisioning_active) {
        char service_name[32];
        get_provisioning_service_name(service_name, sizeof(service_name));
        board_display_show_provisioning(service_name, gateway_config_get()->provisioning_pop);
    } else if ((bits & NETWORK_CONNECTED_BIT) != 0) {
        if (local_server_is_started()) {
            board_display_show_ready(NULL, gateway_config_get()->local_port);
        } else {
            board_display_show_connected(NULL);
        }
    } else if (s_retries > 0) {
        board_display_show_reconnecting();
    } else {
        board_display_show_connecting();
    }
}

/* Displayed UUID: 7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8.
 * ESP-IDF expects the 128-bit UUID in little-endian byte order. */
static uint8_t s_provisioning_service_uuid[16] = {
    0xb8, 0xe3, 0x2a, 0xc5, 0x13, 0x6d, 0x21, 0x9a,
    0x67, 0x4f, 0x7b, 0x4d, 0x01, 0x00, 0x6e, 0x7a,
};

static void reconnect_task(void *arg)
{
    while (true) {
        xEventGroupWaitBits(s_events, NETWORK_RECONNECT_REQUEST_BIT,
                            pdTRUE, pdTRUE, portMAX_DELAY);

        while (!s_provisioning_active && !s_reset_in_progress &&
               (xEventGroupGetBits(s_events) & NETWORK_CONNECTED_BIT) == 0) {
            int delay_ms = 500 << (s_retries < 5 ? s_retries : 5);
            ESP_LOGI(TAG, "Wi-Fi reconnect attempt=%d, delay=%d ms", s_retries + 1, delay_ms);
            vTaskDelay(pdMS_TO_TICKS(delay_ms));

            if (s_provisioning_active || s_reset_in_progress ||
                (xEventGroupGetBits(s_events) & NETWORK_CONNECTED_BIT) != 0) {
                break;
            }

            xEventGroupClearBits(s_events, NETWORK_RECONNECT_FAILED_BIT);
            esp_err_t err = esp_wifi_connect();
            if (err != ESP_OK && err != ESP_ERR_WIFI_CONN) {
                ESP_LOGW(TAG, "Wi-Fi reconnect call failed: %s", esp_err_to_name(err));
                xEventGroupSetBits(s_events, NETWORK_RECONNECT_FAILED_BIT);
            }

            EventBits_t bits = xEventGroupWaitBits(
                s_events, NETWORK_CONNECTED_BIT | NETWORK_RECONNECT_FAILED_BIT,
                pdFALSE, pdFALSE,
                pdMS_TO_TICKS(NETWORK_RECONNECT_RESULT_WAIT_MS));
            if ((bits & NETWORK_CONNECTED_BIT) != 0) {
                break;
            }
            xEventGroupClearBits(s_events, NETWORK_RECONNECT_FAILED_BIT);
            s_retries++;
        }
    }
}

static void time_sync_task(void *arg)
{
    esp_sntp_config_t config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    if (!s_sntp_initialized) {
        if (esp_netif_sntp_init(&config) == ESP_OK) s_sntp_initialized = true;
    }
    while (s_sntp_initialized) {
        xEventGroupWaitBits(s_events, NETWORK_CONNECTED_BIT, pdFALSE, pdTRUE, portMAX_DELAY);
        if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(10000)) == ESP_OK) {
            xEventGroupSetBits(s_events, NETWORK_TIME_READY_BIT);
            ESP_LOGI(TAG, "SNTP clock synchronized");
            break;
        }
        ESP_LOGW(TAG, "SNTP not ready; authenticated local time bootstrap remains available");
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
    s_time_task = NULL;
    vTaskDelete(NULL);
}

/* The App normally closes BLE through yaocore-done after reading the final
 * IPv4 status. If the phone loses GATT at that exact hand-off, do not leave
 * Bluetooth and the provisioning manager running forever after Wi-Fi is
 * already usable. The delay leaves ample time for normal App acknowledgement. */
static void provisioning_success_cleanup_task(void *arg)
{
    vTaskDelay(pdMS_TO_TICKS(PROVISIONING_SUCCESS_FALLBACK_STOP_MS));
    if (s_provisioning_active) {
        ESP_LOGW(TAG, "No App provisioning-finish acknowledgement; stopping BLE after confirmed Wi-Fi success");
        wifi_prov_mgr_stop_provisioning();
    }
    s_provisioning_cleanup_task = NULL;
    vTaskDelete(NULL);
}

static void provisioning_reset_button_task(void *arg)
{
    /* GPIO0 is shared with the USB-UART automatic download circuit.  A flash
     * or serial reset can leave it low while the application starts, which
     * must never be interpreted as a physical five-second BOOT hold.  Arm
     * reset handling only after a released/high level has been observed. */
    bool armed = false;
    bool tracking = false;
    TickType_t pressed_at = 0;
    int displayed_seconds = -1;
    const TickType_t hold_ticks = pdMS_TO_TICKS(CONFIG_YAOCORE_PROV_RESET_HOLD_SECONDS * 1000);

    while (true) {
        bool pressed = gpio_get_level(PROVISIONING_RESET_GPIO) == 0;
        if (!armed) {
            if (!pressed) armed = true;
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }
        if (pressed && !tracking) {
            tracking = true;
            pressed_at = xTaskGetTickCount();
            displayed_seconds = CONFIG_YAOCORE_PROV_RESET_HOLD_SECONDS;
            s_reset_ui_active = true;
            board_display_show_reset_countdown(displayed_seconds);
            ESP_LOGI(TAG, "BOOT pressed; hold for %d seconds to reset Wi-Fi",
                     CONFIG_YAOCORE_PROV_RESET_HOLD_SECONDS);
        } else if (!pressed) {
            if (tracking) {
                tracking = false;
                displayed_seconds = -1;
                s_reset_ui_active = false;
                restore_network_status_screen();
            }
        } else if (tracking && (xTaskGetTickCount() - pressed_at) >= hold_ticks) {
            ESP_LOGW(TAG, "BOOT long press confirmed; clearing Wi-Fi credentials");
            s_reset_in_progress = true;
            /* The manager has already been deinitialized after provisioning.
             * In IDF 5.2 wifi_prov_mgr_reset_provisioning() is only a wrapper
             * around this Wi-Fi API; call it directly to avoid lifecycle ambiguity. */
            esp_err_t err = esp_wifi_restore();
            if (err == ESP_OK) {
                /* GPIO0 is also the ESP32-S3 download-mode strapping pin. Restarting
                 * while it is still low would boot the ROM downloader instead of the
                 * application, so always wait for a physical button release. */
                ESP_LOGI(TAG, "Wi-Fi credentials cleared; release BOOT to restart into BLE provisioning");
                board_display_show_wifi_cleared();
                while (gpio_get_level(PROVISIONING_RESET_GPIO) == 0) {
                    vTaskDelay(pdMS_TO_TICKS(50));
                }
                board_display_show_restarting();
                vTaskDelay(pdMS_TO_TICKS(600));
                esp_restart();
            }
            ESP_LOGE(TAG, "Unable to clear Wi-Fi credentials: %s", esp_err_to_name(err));
            while (gpio_get_level(PROVISIONING_RESET_GPIO) == 0) {
                vTaskDelay(pdMS_TO_TICKS(50));
            }
            s_reset_in_progress = false;
            s_reset_ui_active = false;
            board_display_show_reset_failed();
            tracking = false;
            displayed_seconds = -1;
        } else if (tracking) {
            TickType_t elapsed = xTaskGetTickCount() - pressed_at;
            int seconds_remaining = CONFIG_YAOCORE_PROV_RESET_HOLD_SECONDS -
                (int)(elapsed / pdMS_TO_TICKS(1000));
            if (seconds_remaining < 1) seconds_remaining = 1;
            if (seconds_remaining != displayed_seconds) {
                displayed_seconds = seconds_remaining;
                board_display_show_reset_countdown(displayed_seconds);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

static void start_reset_button_monitor(void)
{
    gpio_config_t config = {
        .pin_bit_mask = 1ULL << PROVISIONING_RESET_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&config));
    BaseType_t created = xTaskCreate(provisioning_reset_button_task, "wifi_reset_button", 3072,
                                     NULL, 5, NULL);
    ESP_ERROR_CHECK(created == pdPASS ? ESP_OK : ESP_ERR_NO_MEM);
}

static void get_provisioning_service_name(char *name, size_t size)
{
    uint8_t mac[6] = {0};
    ESP_ERROR_CHECK(esp_wifi_get_mac(WIFI_IF_STA, mac));
    snprintf(name, size, PROVISIONING_NAME_PREFIX "%02X%02X%02X", mac[3], mac[4], mac[5]);
}

static void start_wifi_station(void)
{
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());
}

static void ble_advertising_health_task(void *context)
{
    (void)context;
    vTaskDelay(pdMS_TO_TICKS(400));
    if (s_provisioning_active) {
        if (ble_gap_adv_active()) {
            ESP_LOGI(TAG, "BLE provisioning advertisement active");
        } else {
            ESP_LOGE(TAG, "BLE provisioning manager started but advertisement is inactive");
            board_display_show_ble_error();
        }
    }
    vTaskDelete(NULL);
}

/* wifi_prov_mgr routes custom endpoints through the negotiated protocomm
 * security session.  The app uses this PoP-authenticated identity only as an
 * enrollment correlation value; the command HMAC secret is never sent over BLE. */
static esp_err_t provisioning_identity_handler(uint32_t session_id,
                                               const uint8_t *inbuf,
                                               ssize_t inlen,
                                               uint8_t **outbuf,
                                               ssize_t *outlen,
                                               void *priv_data)
{
    (void)session_id;
    (void)priv_data;
    if (inbuf == NULL || outbuf == NULL || outlen == NULL || inlen < 2 || inlen > 96) {
        return ESP_ERR_INVALID_ARG;
    }

    char request[97];
    for (ssize_t i = 0; i < inlen; ++i) {
        if (inbuf[i] == 0) return ESP_ERR_INVALID_ARG;
    }
    memcpy(request, inbuf, (size_t)inlen);
    request[inlen] = '\0';
    cJSON *root = cJSON_Parse(request);
    if (root == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    const cJSON *operation = cJSON_GetObjectItemCaseSensitive(root, "op");
    const cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "protocolVersion");
    bool valid = cJSON_IsObject(root) && cJSON_GetArraySize(root) == 2 &&
                 cJSON_IsString(operation) && cJSON_IsString(version) &&
                 strcmp(operation->valuestring, "get_identity") == 0 &&
                 strcmp(version->valuestring, "2.0") == 0;
    cJSON_Delete(root);
    if (!valid) {
        return ESP_ERR_INVALID_ARG;
    }

    const gateway_config_t *cfg = gateway_config_get();
    cJSON *response = cJSON_CreateObject();
    if (response == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddStringToObject(response, "protocolVersion", "2.0");
    cJSON_AddStringToObject(response, "serviceId", "YaoCoreGateway");
    cJSON_AddStringToObject(response, "gatewayId", cfg->gateway_id);
    cJSON_AddStringToObject(response, "gatewayName", cfg->gateway_name);
    char *serialized = cJSON_PrintUnformatted(response);
    cJSON_Delete(response);
    if (serialized == NULL) {
        return ESP_ERR_NO_MEM;
    }
    *outbuf = (uint8_t *)serialized;
    *outlen = (ssize_t)strlen(serialized);
    return ESP_OK;
}

/* Keep BLE alive until the App has received the connected status and IPv4
 * address. Without this explicit final acknowledgement ESP-IDF may tear down
 * GATT between the prov-config write and the following characteristic read,
 * leaving the App without the address needed for deterministic LAN binding. */
static esp_err_t provisioning_finish_handler(uint32_t session_id,
                                             const uint8_t *inbuf,
                                             ssize_t inlen,
                                             uint8_t **outbuf,
                                             ssize_t *outlen,
                                             void *priv_data)
{
    (void)session_id;
    (void)priv_data;
    if (inbuf == NULL || outbuf == NULL || outlen == NULL || inlen < 2 || inlen > 96) {
        return ESP_ERR_INVALID_ARG;
    }
    char request[97];
    for (ssize_t i = 0; i < inlen; ++i) {
        if (inbuf[i] == 0) return ESP_ERR_INVALID_ARG;
    }
    memcpy(request, inbuf, (size_t)inlen);
    request[inlen] = '\0';
    cJSON *root = cJSON_Parse(request);
    if (root == NULL) return ESP_ERR_INVALID_ARG;
    const cJSON *operation = cJSON_GetObjectItemCaseSensitive(root, "op");
    const cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "protocolVersion");
    bool valid = cJSON_IsObject(root) && cJSON_GetArraySize(root) == 2 &&
                 cJSON_IsString(operation) && cJSON_IsString(version) &&
                 strcmp(operation->valuestring, "finish") == 0 &&
                 strcmp(version->valuestring, "2.0") == 0;
    cJSON_Delete(root);
    if (!valid) return ESP_ERR_INVALID_ARG;

    const char *ack = "{\"status\":\"accepted\",\"protocolVersion\":\"2.0\"}";
    *outbuf = (uint8_t *)strdup(ack);
    if (*outbuf == NULL) return ESP_ERR_NO_MEM;
    *outlen = (ssize_t)strlen((const char *)*outbuf);
    ESP_LOGI(TAG, "App received connected status; scheduling BLE provisioning shutdown");
    wifi_prov_mgr_stop_provisioning();
    return ESP_OK;
}

static void start_ble_provisioning(void)
{
    const gateway_config_t *cfg = gateway_config_get();
    char service_name[32];
    get_provisioning_service_name(service_name, sizeof(service_name));

    const char *capabilities[5] = {"wifi_scan", "security1", "local_control", "secure_identity", NULL};
    size_t capability_count = 4;
    if (cfg->iotda_enabled) {
        capabilities[capability_count++] = "iotda";
    }
    ESP_ERROR_CHECK(wifi_prov_mgr_set_app_info("yaocore", "2.0", capabilities,
                                               capability_count));
    ESP_ERROR_CHECK(wifi_prov_scheme_ble_set_service_uuid(s_provisioning_service_uuid));
    ESP_ERROR_CHECK(wifi_prov_mgr_endpoint_create(PROVISIONING_IDENTITY_ENDPOINT));
    ESP_ERROR_CHECK(wifi_prov_mgr_endpoint_create(PROVISIONING_FINISH_ENDPOINT));
    /* The App explicitly closes provisioning through yaocore-done after it has
     * received the final IP address. Cleanup remains delayed so the encrypted
     * acknowledgement can be read before GATT is released. */
    ESP_ERROR_CHECK(wifi_prov_mgr_disable_auto_stop(1000));

    s_provisioning_active = true;
    xEventGroupSetBits(s_events, NETWORK_PROVISIONING_BIT);
    ESP_LOGI(TAG, "Starting BLE provisioning as %s (Security1 + PoP)", service_name);
    board_display_show_provisioning(service_name, cfg->provisioning_pop);
    ESP_LOGI(TAG, "Use the per-device PoP configured in YaoCore Gateway menuconfig");
    ESP_ERROR_CHECK(wifi_prov_mgr_start_provisioning(WIFI_PROV_SECURITY_1,
                                                     (const void *)cfg->provisioning_pop,
                                                     service_name, NULL));
    ESP_ERROR_CHECK(wifi_prov_mgr_endpoint_register(PROVISIONING_IDENTITY_ENDPOINT,
                                                    provisioning_identity_handler, NULL));
    ESP_ERROR_CHECK(wifi_prov_mgr_endpoint_register(PROVISIONING_FINISH_ENDPOINT,
                                                    provisioning_finish_handler, NULL));
}

static void event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_PROV_EVENT) {
        switch (id) {
        case WIFI_PROV_START:
            ESP_LOGI(TAG, "BLE provisioning manager started; verifying advertisement");
            if (xTaskCreate(ble_advertising_health_task, "ble_adv_health", 2048,
                    NULL, 5, NULL) != pdPASS) {
                ESP_LOGE(TAG, "Unable to create BLE advertising health check");
                board_display_show_ble_error();
            }
            break;
        case WIFI_PROV_CRED_RECV: {
            wifi_sta_config_t *wifi = (wifi_sta_config_t *)data;
            ESP_LOGI(TAG, "Received Wi-Fi credentials for SSID: %.*s",
                     (int)sizeof(wifi->ssid), (const char *)wifi->ssid);
            break;
        }
        case WIFI_PROV_CRED_FAIL: {
            wifi_prov_sta_fail_reason_t reason = *(wifi_prov_sta_fail_reason_t *)data;
            ESP_LOGE(TAG, "Provisioning failed: %s; ready for another credential attempt",
                     reason == WIFI_PROV_STA_AUTH_ERROR ? "authentication error" : "access point not found");
            esp_err_t err = wifi_prov_mgr_reset_sm_state_on_failure();
            if (err != ESP_OK) ESP_LOGE(TAG, "Unable to reset provisioning state: %s", esp_err_to_name(err));
            char service_name[32];
            get_provisioning_service_name(service_name, sizeof(service_name));
            board_display_show_provisioning(service_name,
                gateway_config_get()->provisioning_pop);
            break;
        }
        case WIFI_PROV_CRED_SUCCESS:
            ESP_LOGI(TAG, "Wi-Fi provisioning successful");
            break;
        case WIFI_PROV_END:
            s_provisioning_active = false;
            xEventGroupClearBits(s_events, NETWORK_PROVISIONING_BIT);
            wifi_prov_mgr_deinit();
            ESP_LOGI(TAG, "BLE provisioning stopped and Bluetooth memory released");
            break;
        default:
            break;
        }
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        /* This board is a continuously powered gateway.  Modem sleep adds
         * hundreds of milliseconds of jitter to short authenticated LAN
         * exchanges and can make the App's post-provisioning verification
         * appear to fail. */
        esp_err_t power_save_err = esp_wifi_set_ps(WIFI_PS_NONE);
        if (power_save_err != ESP_OK) {
            ESP_LOGW(TAG, "Unable to disable Wi-Fi power save: %s",
                     esp_err_to_name(power_save_err));
        }
        /* During provisioning the manager owns connection attempts after it
         * receives credentials. Avoid connecting here with an empty config. */
        if (!s_provisioning_active) {
            esp_err_t err = esp_wifi_connect();
            if (err != ESP_OK && err != ESP_ERR_WIFI_CONN) {
                ESP_LOGW(TAG, "Initial Wi-Fi connect failed: %s", esp_err_to_name(err));
                xEventGroupSetBits(s_events, NETWORK_RECONNECT_REQUEST_BIT);
            }
        }
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        const wifi_event_sta_disconnected_t *event = (const wifi_event_sta_disconnected_t *)data;
        xEventGroupClearBits(s_events, NETWORK_CONNECTED_BIT | NETWORK_TIME_READY_BIT);
        ESP_LOGW(TAG, "Wi-Fi disconnected, reason=%u, provisioning=%s, retry=%d",
                 event != NULL ? event->reason : 0,
                 s_provisioning_active ? "yes" : "no", s_retries);
        if (!s_provisioning_active) {
            if (!s_reset_ui_active) board_display_show_reconnecting();
            xEventGroupSetBits(s_events, NETWORK_RECONNECT_REQUEST_BIT | NETWORK_RECONNECT_FAILED_BIT);
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)data;
        s_retries = 0;
        xEventGroupClearBits(s_events, NETWORK_RECONNECT_REQUEST_BIT | NETWORK_RECONNECT_FAILED_BIT);
        xEventGroupSetBits(s_events, NETWORK_CONNECTED_BIT);
        ESP_LOGI(TAG, "Wi-Fi connected, IPv4=" IPSTR, IP2STR(&event->ip_info.ip));
        char ip[16];
        snprintf(ip, sizeof(ip), IPSTR, IP2STR(&event->ip_info.ip));
        if (!s_reset_ui_active) {
            if (local_server_is_started()) {
                board_display_show_ready(ip, gateway_config_get()->local_port);
            } else {
                board_display_show_connected(ip);
            }
        }
        if (s_provisioning_active && s_provisioning_cleanup_task == NULL &&
            xTaskCreate(provisioning_success_cleanup_task, "prov_cleanup", 2048,
                        NULL, 5, &s_provisioning_cleanup_task) != pdPASS) {
            s_provisioning_cleanup_task = NULL;
            ESP_LOGE(TAG, "Unable to create provisioning cleanup task");
        }
        if (s_time_task == NULL && xTaskCreate(time_sync_task, "sntp_sync", 3072, NULL, 5,
                                               &s_time_task) != pdPASS) {
            s_time_task = NULL;
            ESP_LOGE(TAG, "Unable to create SNTP task");
        }
    }
}

void network_manager_start(void)
{
    s_events = xEventGroupCreate();
    ESP_ERROR_CHECK(s_events ? ESP_OK : ESP_ERR_NO_MEM);
    ESP_ERROR_CHECK(xTaskCreate(reconnect_task, "wifi_reconnect", 2560, NULL, 5,
                                &s_reconnect_task) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM);
    ESP_ERROR_CHECK(esp_netif_init()); ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT(); ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_FLASH));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_PROV_EVENT, ESP_EVENT_ANY_ID, event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, event_handler, NULL));

    wifi_prov_mgr_config_t manager_config = {
        .scheme = wifi_prov_scheme_ble,
        .scheme_event_handler = WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM,
    };
    ESP_ERROR_CHECK(wifi_prov_mgr_init(manager_config));

    bool provisioned = false;
    ESP_ERROR_CHECK(wifi_prov_mgr_is_provisioned(&provisioned));
    start_reset_button_monitor();
    if (provisioned) {
        ESP_LOGI(TAG, "Stored Wi-Fi credentials found; starting station mode");
        board_display_show_connecting();
        wifi_prov_mgr_deinit();
        start_wifi_station();
    } else {
        ESP_LOGI(TAG, "No stored Wi-Fi credentials found");
        start_ble_provisioning();
    }
}

EventGroupHandle_t network_manager_events(void) { return s_events; }
