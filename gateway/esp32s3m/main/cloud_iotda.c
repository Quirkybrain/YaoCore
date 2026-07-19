/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "cloud_iotda.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "cJSON.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "mqtt_client.h"
#include "mbedtls/md.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "device_router.h"
#include "gateway_config.h"
#include "gateway_security.h"

static const char *TAG = "iotda";
static esp_mqtt_client_handle_t s_client;
static char s_report_topic[320];
static char s_client_id[320];
static char s_password[65];
static bool s_connected;
static TaskHandle_t s_report_task;
static char *s_rx_topic;
static char *s_rx_payload;
static int s_rx_total;

static const char *cloud_type_name(device_type_t type)
{
    const char *names[] = {"door", "light", "sensor", "ac", "switch",
        "camera", "gateway", "curtain", "fan", "speaker"};
    return type <= DEVICE_SPEAKER ? names[type] : "switch";
}

static bool build_credentials(const gateway_config_t *cfg)
{
    time_t now = time(NULL);
    if (now < 1700000000) return false;
    struct tm utc;
    gmtime_r(&now, &utc);
    char timestamp[11];
    strftime(timestamp, sizeof(timestamp), "%Y%m%d%H", &utc);
    snprintf(s_client_id, sizeof(s_client_id), "%s_0_1_%s", cfg->iotda_device_id, timestamp);
    unsigned char digest[32];
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!info || mbedtls_md_hmac(info, (const unsigned char *)timestamp, strlen(timestamp),
        (const unsigned char *)cfg->iotda_password, strlen(cfg->iotda_password), digest) != 0) return false;
    for (int i = 0; i < 32; ++i) snprintf(s_password + i * 2, 3, "%02x", digest[i]);
    s_password[64] = '\0';
    return true;
}

static void fill_mqtt_config(const gateway_config_t *cfg,
    esp_mqtt_client_config_t *config)
{
    memset(config, 0, sizeof(*config));
    *config = (esp_mqtt_client_config_t) {
        .broker.address.uri = cfg->iotda_broker_uri,
        .broker.verification.crt_bundle_attach = esp_crt_bundle_attach,
        .credentials.client_id = s_client_id,
        .credentials.username = cfg->iotda_device_id,
        .credentials.authentication.password = s_password,
        .session.keepalive = 60,
        .network.reconnect_timeout_ms = 3000,
    };
}

static bool copy_string(cJSON *root, const char *name, char *dest, size_t size)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(root, name);
    if (!cJSON_IsString(item) || strlen(item->valuestring) >= size) return false;
    strlcpy(dest, item->valuestring, size); return true;
}

static bool parse_value_text(const char *text, gateway_command_t *cmd)
{
    if (!text) { cmd->value_type = VALUE_NONE; return true; }
    cJSON *value = cJSON_Parse(text); if (!value) return false;
    if (cJSON_IsString(value) && strlen(value->valuestring) < sizeof(cmd->string_value)) {
        cmd->value_type = VALUE_STRING; strlcpy(cmd->string_value, value->valuestring, sizeof(cmd->string_value));
    } else if (cJSON_IsNumber(value)) { cmd->value_type = VALUE_NUMBER; cmd->number_value = value->valuedouble; }
    else if (cJSON_IsBool(value)) { cmd->value_type = VALUE_BOOL; cmd->bool_value = cJSON_IsTrue(value); }
    else { cJSON_Delete(value); return false; }
    cJSON_Delete(value); return true;
}

static bool parse_cloud_command(const char *json, gateway_command_t *cmd)
{
    cJSON *root = cJSON_Parse(json); if (!root) return false;
    cJSON *paras = cJSON_GetObjectItemCaseSensitive(root, "paras");
    cJSON *name = cJSON_GetObjectItemCaseSensitive(root, "command_name");
    cJSON *cmd_id = paras ? cJSON_GetObjectItemCaseSensitive(paras, "CmdId") : NULL;
    cJSON *seq = paras ? cJSON_GetObjectItemCaseSensitive(paras, "Seq") : NULL;
    memset(cmd, 0, sizeof(*cmd));
    bool ok = cJSON_IsObject(paras) && cJSON_IsString(name) && !strcmp(name->valuestring, "SetDeviceStatus") &&
        cJSON_IsNumber(cmd_id) && cJSON_IsNumber(seq) &&
        copy_string(paras, "RequestId", cmd->request_id, sizeof(cmd->request_id)) &&
        copy_string(paras, "TargetDevice", cmd->target, sizeof(cmd->target)) &&
        copy_string(paras, "Action", cmd->action, sizeof(cmd->action)) &&
        copy_string(paras, "Timestamp", cmd->timestamp, sizeof(cmd->timestamp)) &&
        copy_string(paras, "Nonce", cmd->nonce, sizeof(cmd->nonce)) && copy_string(paras, "Alg", cmd->alg, sizeof(cmd->alg)) &&
        copy_string(paras, "KeyId", cmd->key_id, sizeof(cmd->key_id)) && copy_string(paras, "Sign", cmd->sign, sizeof(cmd->sign));
    if (ok) { cmd->cmd_id = cmd_id->valueint; cmd->seq = seq->valueint; cJSON *value = cJSON_GetObjectItemCaseSensitive(paras, "Value");
        ok = parse_value_text(cJSON_IsString(value) ? value->valuestring : NULL, cmd); }
    cJSON_Delete(root); return ok && cmd->cmd_id == 3001 && cmd->seq >= 0;
}

static void publish_response(const char *incoming_topic, const gateway_command_t *cmd, const gateway_ack_t *ack)
{
    const char *request = strstr(incoming_topic, "request_id="); request = request ? request + strlen("request_id=") : cmd->request_id;
    char topic[384]; snprintf(topic, sizeof(topic), "$oc/devices/%s/sys/commands/response/request_id=%s", gateway_config_get()->iotda_device_id, request);
    cJSON *root = cJSON_CreateObject(); cJSON_AddNumberToObject(root, "result_code", ack->result_code);
    cJSON_AddStringToObject(root, "response_name", "SetDeviceStatusResponse"); cJSON *paras = cJSON_AddObjectToObject(root, "paras");
    cJSON_AddStringToObject(paras, "RequestId", cmd->request_id); cJSON_AddNumberToObject(paras, "ResultCode", ack->result_code);
    cJSON_AddStringToObject(paras, "Message", ack->message); char *json = cJSON_PrintUnformatted(root);
    esp_mqtt_client_publish(s_client, topic, json, 0, 1, 0); free(json); cJSON_Delete(root);
}

void cloud_iotda_report_now(void)
{
    if (!s_client || !s_connected) return;
    /* Keep the 32-device report snapshot out of the MQTT report task stack.
     * This is the same bounded inventory used by LAN discovery and belongs in
     * the board's PSRAM, especially once cloud reporting is enabled. */
    device_state_t *devices = heap_caps_calloc(YAOCORE_MAX_DEVICES,
        sizeof(device_state_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (devices == NULL) {
        ESP_LOGE(TAG, "unable to allocate cloud inventory snapshot in PSRAM");
        return;
    }
    size_t count = device_router_snapshot(devices, YAOCORE_MAX_DEVICES);
    cJSON *root = cJSON_CreateObject(), *services = cJSON_AddArrayToObject(root, "services"), *service = cJSON_CreateObject();
    cJSON_AddStringToObject(service, "service_id", YAOCORE_SERVICE_ID); cJSON *properties = cJSON_AddObjectToObject(service, "properties");
    bool door_online = false, light_online = false, sensor_online = false,
        presence_online = false, ac_online = false;
    /* Dynamic inventory is the multi-device source of truth. The fixed
     * properties below remain for compatibility with the original profile. */
    /* Keep every JSON string comfortably below the IoTDA profile limit while
     * preserving all 32 unique devices. The App merges these pages by ID. */
    cJSON *inventory_pages[4] = { cJSON_CreateArray(), cJSON_CreateArray(),
        cJSON_CreateArray(), cJSON_CreateArray() };
    for (size_t i = 0; i < count; ++i) {
        device_state_t *d = &devices[i];
        cJSON *inventory = inventory_pages[i / 8];
        if (inventory) {
            cJSON *item = cJSON_CreateObject();
            if (item) {
                cJSON_AddStringToObject(item, "device_id", d->device_id);
                cJSON_AddStringToObject(item, "device_name", d->name);
                cJSON_AddStringToObject(item, "room_name", d->room);
                cJSON_AddStringToObject(item, "device_type",
                    cloud_type_name(d->type));
                if (d->brand[0]) cJSON_AddStringToObject(item, "brand", d->brand);
                cJSON_AddStringToObject(item, "protocol",
                    d->protocol[0] ? d->protocol : "direct");
                if (d->external) {
                    cJSON_AddBoolToObject(item, "external", true);
                    cJSON_AddStringToObject(item, "module_id", d->module_id);
                }
                cJSON_AddBoolToObject(item, "online", d->online);
                if (d->type == DEVICE_DOOR && d->online &&
                    (d->external || gateway_config_get()->door_feedback_gpio >= 0)) {
                    cJSON_AddBoolToObject(item, "open", d->open);
                } else if (d->type == DEVICE_LIGHT && d->online) {
                    cJSON_AddBoolToObject(item, "power", d->power);
                    cJSON_AddNumberToObject(item, "brightness", d->brightness);
                    if (d->has_color) cJSON_AddStringToObject(item, "color", d->color);
                } else if (d->type == DEVICE_SENSOR && d->online) {
                    if (d->has_environment) {
                        cJSON_AddNumberToObject(item, "temperature", d->temperature);
                        cJSON_AddNumberToObject(item, "humidity", d->humidity);
                    }
                    if (d->has_presence) cJSON_AddBoolToObject(item, "presence", d->presence);
                } else if (d->type == DEVICE_AC && d->online) {
                    cJSON_AddBoolToObject(item, "power", d->power);
                    cJSON_AddNumberToObject(item, "target_temperature", d->target_temperature);
                    cJSON_AddStringToObject(item, "mode", d->mode);
                } else if (d->type == DEVICE_SWITCH && d->online) {
                    cJSON_AddBoolToObject(item, "power", d->power);
                } else if (d->type == DEVICE_CURTAIN && d->online) {
                    cJSON_AddNumberToObject(item, "position", d->position);
                } else if (d->type == DEVICE_FAN && d->online) {
                    cJSON_AddBoolToObject(item, "power", d->power);
                    cJSON_AddNumberToObject(item, "speed", d->speed);
                } else if (d->type == DEVICE_SPEAKER && d->online) {
                    cJSON_AddBoolToObject(item, "power", d->power);
                    cJSON_AddNumberToObject(item, "volume", d->volume);
                }
                if (d->has_last_command) {
                    cJSON_AddStringToObject(item, "last_request_id", d->last_request_id);
                    cJSON_AddNumberToObject(item, "last_seq", d->last_seq);
                }
                if (d->state_source[0]) cJSON_AddStringToObject(item, "state_source", d->state_source);
                if (d->trigger_device_id[0]) cJSON_AddStringToObject(item, "trigger_device_id", d->trigger_device_id);
                if (d->automation_id[0]) cJSON_AddStringToObject(item, "automation_id", d->automation_id);
                cJSON_AddItemToArray(inventory, item);
            }
        }
        if (!strcmp(d->device_id, "Door_01") && d->type == DEVICE_DOOR) {
            door_online = d->online;
            if (d->online && (d->external ||
                gateway_config_get()->door_feedback_gpio >= 0)) cJSON_AddStringToObject(properties, "Door_01_Status",
                d->open ? "OPEN" : "CLOSED");
            if (d->has_last_command) {
                cJSON_AddStringToObject(properties, "Door_01_LastRequestId", d->last_request_id);
                cJSON_AddNumberToObject(properties, "Door_01_LastSeq", d->last_seq);
            }
            if (d->state_source[0]) cJSON_AddStringToObject(properties,
                "Door_01_StateSource", d->state_source);
        } else if (!strcmp(d->device_id, "Light_01") &&
            d->type == DEVICE_LIGHT) {
            light_online = d->online;
            if (d->online) {
                cJSON_AddStringToObject(properties, "Light_01_Status", d->power ? "ON" : "OFF");
                cJSON_AddNumberToObject(properties, "Light_01_Brightness", d->brightness);
                if (d->has_color) cJSON_AddStringToObject(properties,
                    "Light_01_Color", d->color);
            }
            if (d->has_last_command) {
                cJSON_AddStringToObject(properties, "Light_01_LastRequestId", d->last_request_id);
                cJSON_AddNumberToObject(properties, "Light_01_LastSeq", d->last_seq);
            }
            if (d->state_source[0]) cJSON_AddStringToObject(properties,
                "Light_01_StateSource", d->state_source);
            if (d->trigger_device_id[0]) cJSON_AddStringToObject(properties,
                "Light_01_TriggerDeviceId", d->trigger_device_id);
            if (d->automation_id[0]) cJSON_AddStringToObject(properties,
                "Light_01_AutomationId", d->automation_id);
        } else if (!strcmp(d->device_id, "Sensor_01")) {
            sensor_online = d->online;
            if (d->online) {
                cJSON_AddNumberToObject(properties, "Room_01_Temperature", d->temperature);
                cJSON_AddNumberToObject(properties, "Room_01_Humidity", d->humidity);
            }
        } else if (!strcmp(d->device_id, "Presence_01")) {
            presence_online = d->online;
            if (d->online) cJSON_AddBoolToObject(properties,
                "Presence_01_Detected", d->presence);
        } else if (!strcmp(d->device_id, "AC_01") && d->type == DEVICE_AC) {
            ac_online = d->online;
            if (d->online) {
                cJSON_AddStringToObject(properties, "AC_01_Status", d->power ? "ON" : "OFF");
                cJSON_AddNumberToObject(properties, "AC_01_TargetTemp", d->target_temperature);
                cJSON_AddStringToObject(properties, "AC_01_Mode", d->mode);
            }
            if (d->has_last_command) {
                cJSON_AddStringToObject(properties, "AC_01_LastRequestId", d->last_request_id);
                cJSON_AddNumberToObject(properties, "AC_01_LastSeq", d->last_seq);
            }
            if (d->state_source[0]) cJSON_AddStringToObject(properties,
                "AC_01_StateSource", d->state_source);
            if (d->trigger_device_id[0]) cJSON_AddStringToObject(properties,
                "AC_01_TriggerDeviceId", d->trigger_device_id);
            if (d->automation_id[0]) cJSON_AddStringToObject(properties,
                "AC_01_AutomationId", d->automation_id);
        }
    }
    cJSON_AddBoolToObject(properties, "Door_01_Online", door_online);
    cJSON_AddBoolToObject(properties, "Light_01_Online", light_online);
    cJSON_AddBoolToObject(properties, "Sensor_01_Online", sensor_online);
    cJSON_AddBoolToObject(properties, "Presence_01_Online", presence_online);
    cJSON_AddBoolToObject(properties, "AC_01_Online", ac_online);
    for (size_t page = 0; page < 4; ++page) {
        if (!inventory_pages[page]) continue;
        if (cJSON_GetArraySize(inventory_pages[page]) > 0) {
            char *inventory_json = cJSON_PrintUnformatted(inventory_pages[page]);
            if (inventory_json) {
                const char *names[] = { "DeviceInventoryJson",
                    "DeviceInventoryJson2", "DeviceInventoryJson3",
                    "DeviceInventoryJson4" };
                cJSON_AddStringToObject(properties, names[page], inventory_json);
                free(inventory_json);
            }
        }
        cJSON_Delete(inventory_pages[page]);
    }
    cJSON_AddBoolToObject(properties, "Gateway_Online", true);
    wifi_ap_record_t access_point;
    int gateway_rssi = -127; /* explicit unavailable sentinel allowed by schema */
    esp_err_t rssi_result = esp_wifi_sta_get_ap_info(&access_point);
    if (rssi_result == ESP_OK) gateway_rssi = access_point.rssi;
    else ESP_LOGW(TAG, "cannot read current Wi-Fi RSSI: %s",
        esp_err_to_name(rssi_result));
    cJSON_AddNumberToObject(properties, "Gateway_RSSI", gateway_rssi);
    char event_time[32]; time_t now = time(NULL); struct tm utc; gmtime_r(&now, &utc); strftime(event_time, sizeof(event_time), "%Y%m%dT%H%M%SZ", &utc);
    cJSON_AddStringToObject(service, "event_time", event_time); cJSON_AddItemToArray(services, service); char *json = cJSON_PrintUnformatted(root);
    int message_id = esp_mqtt_client_publish(s_client, s_report_topic, json, 0, 1, 0);
    if (message_id < 0) ESP_LOGW(TAG, "state report enqueue failed");
    free(json); cJSON_Delete(root); heap_caps_free(devices);
}

static void state_changed(const device_state_t *state, void *context)
{
    (void)state; (void)context;
    if (s_report_task) xTaskNotifyGive(s_report_task);
}

static void report_task(void *arg)
{
    (void)arg;
    const gateway_config_t *config = gateway_config_get();
    TickType_t interval = pdMS_TO_TICKS(config->iotda_report_interval_seconds * 1000);
    while (true) {
        ulTaskNotifyTake(pdTRUE, interval);
        cloud_iotda_report_now();
    }
}

static void clear_fragment(void)
{
    free(s_rx_topic); s_rx_topic = NULL;
    free(s_rx_payload); s_rx_payload = NULL;
    s_rx_total = 0;
}

static void process_cloud_command(const char *topic, const char *payload)
{
    gateway_command_t cmd;
    gateway_ack_t ack;
    memset(&ack, 0, sizeof(ack));
    if (!parse_cloud_command(payload, &cmd)) {
        ESP_LOGW(TAG, "discarding cloud command with invalid schema");
        return;
    }
    if (gateway_security_get_cached(&cmd, &ack)) {}
    else if (gateway_security_verify(&cmd, &ack)) {
        strlcpy(cmd.source, "app.cloud", sizeof(cmd.source));
        device_router_execute(&cmd, &ack);
        gateway_security_cache_result(&cmd, &ack);
    }
    publish_response(topic, &cmd, &ack);
}

static void receive_cloud_fragment(esp_mqtt_event_handle_t event)
{
    if (event->current_data_offset == 0) {
        clear_fragment();
        if (event->total_data_len <= 0 || event->total_data_len > 4096 ||
            !event->topic || event->topic_len <= 0) {
            ESP_LOGW(TAG, "rejecting oversized or topicless MQTT command");
            return;
        }
        s_rx_topic = strndup(event->topic, event->topic_len);
        s_rx_payload = calloc(1, event->total_data_len + 1);
        s_rx_total = event->total_data_len;
        if (!s_rx_topic || !s_rx_payload) { clear_fragment(); return; }
    }
    if (!s_rx_payload || event->current_data_offset < 0 || event->data_len < 0 ||
        event->current_data_offset + event->data_len > s_rx_total) {
        clear_fragment();
        return;
    }
    memcpy(s_rx_payload + event->current_data_offset, event->data, event->data_len);
    if (event->current_data_offset + event->data_len == s_rx_total) {
        process_cloud_command(s_rx_topic, s_rx_payload);
        clear_fragment();
    }
}

static void mqtt_event(void *args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    (void)args; (void)base;
    esp_mqtt_event_handle_t event = event_data;
    if (event_id == MQTT_EVENT_BEFORE_CONNECT) {
        const gateway_config_t *config = gateway_config_get();
        if (build_credentials(config)) {
            esp_mqtt_client_config_t refreshed;
            fill_mqtt_config(config, &refreshed);
            esp_err_t err = esp_mqtt_set_config(s_client, &refreshed);
            if (err != ESP_OK) ESP_LOGE(TAG, "MQTT credential refresh failed: %s",
                esp_err_to_name(err));
        } else ESP_LOGE(TAG, "clock invalid while refreshing MQTT credentials");
    } else if (event_id == MQTT_EVENT_CONNECTED) {
        s_connected = true;
        char topic[320]; snprintf(topic, sizeof(topic), "$oc/devices/%s/sys/commands/#", gateway_config_get()->iotda_device_id);
        esp_mqtt_client_subscribe(s_client, topic, 1);
        if (s_report_task) xTaskNotifyGive(s_report_task);
        ESP_LOGI(TAG, "IoTDA connected");
    } else if (event_id == MQTT_EVENT_DATA) {
        receive_cloud_fragment(event);
    } else if (event_id == MQTT_EVENT_DISCONNECTED) {
        s_connected = false;
        clear_fragment();
        ESP_LOGW(TAG, "IoTDA disconnected; client will reconnect");
    }
}

esp_err_t cloud_iotda_start(void)
{
    const gateway_config_t *cfg = gateway_config_get(); if (!cfg->iotda_enabled) return ESP_OK;
    if (strncmp(cfg->iotda_broker_uri, "mqtts://", 8)) {
        ESP_LOGE(TAG, "refusing non-TLS MQTT broker URI");
        return ESP_ERR_INVALID_ARG;
    }
    if (!build_credentials(cfg)) { ESP_LOGE(TAG, "cannot derive IoTDA credentials before clock sync"); return ESP_ERR_INVALID_STATE; }
    snprintf(s_report_topic, sizeof(s_report_topic), "$oc/devices/%s/sys/properties/report", cfg->iotda_device_id);
    esp_mqtt_client_config_t config;
    fill_mqtt_config(cfg, &config);
    s_client = esp_mqtt_client_init(&config); if (!s_client) return ESP_ERR_NO_MEM;
    if (xTaskCreate(report_task, "iotda_report", 8192, NULL, 4, &s_report_task) != pdPASS) {
        esp_mqtt_client_destroy(s_client); s_client = NULL; return ESP_ERR_NO_MEM;
    }
    esp_err_t err = esp_mqtt_client_register_event(s_client, ESP_EVENT_ANY_ID,
        mqtt_event, NULL);
    if (err != ESP_OK) {
        vTaskDelete(s_report_task); s_report_task = NULL;
        esp_mqtt_client_destroy(s_client); s_client = NULL;
        return err;
    }
    device_router_set_state_callback(state_changed, NULL);
    err = esp_mqtt_client_start(s_client);
    if (err != ESP_OK) {
        device_router_set_state_callback(NULL, NULL);
        vTaskDelete(s_report_task); s_report_task = NULL;
        esp_mqtt_client_destroy(s_client); s_client = NULL;
    }
    return err;
}
