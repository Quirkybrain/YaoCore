/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "device_router.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "automation_engine.h"
#include "gateway_config.h"
#include "hardware_drivers.h"
#include "external_module.h"

static const char *TAG = "device_router";
/* Legacy firmware returned "air-conditioner IR driver not configured" here.
 * The real implementation below uses a southbound UART bridge and confirmed ACK. */
static device_state_t s_devices[YAOCORE_MAX_DEVICES];
static size_t s_count;
static SemaphoreHandle_t s_lock;
static SemaphoreHandle_t s_ac_state_lock;
static bool s_gateway_led;
static device_router_state_callback_t s_state_callback;
static void *s_state_callback_context;
static bool s_light_event_seen;
static bool s_door_event_seen;
static bool s_presence_event_seen;
static unsigned s_ac_health_failures;
static nvs_handle_t s_metadata_nvs;

#define DEVICE_METADATA_MAGIC 0x594D4554UL
#define DEVICE_METADATA_VERSION 1
#define DEVICE_METADATA_NAMESPACE "device_meta"
#define DEVICE_METADATA_KEY "overrides"

typedef struct {
    bool used;
    char device_id[YAOCORE_MAX_ID];
    char name[64];
    char room[32];
} device_metadata_entry_t;

typedef struct {
    uint32_t magic;
    uint32_t version;
    device_metadata_entry_t entries[YAOCORE_MAX_DEVICES];
    uint32_t checksum;
} device_metadata_store_t;

static device_metadata_store_t s_metadata;

static int64_t now_ms(void) { return esp_timer_get_time() / 1000; }

static uint32_t metadata_checksum(const device_metadata_store_t *store)
{
    const uint8_t *data = (const uint8_t *)store;
    size_t length = offsetof(device_metadata_store_t, checksum);
    uint32_t hash = 2166136261UL;
    for (size_t i = 0; i < length; ++i) {
        hash ^= data[i];
        hash *= 16777619UL;
    }
    return hash;
}

static esp_err_t metadata_init(void)
{
    esp_err_t err = nvs_open(DEVICE_METADATA_NAMESPACE, NVS_READWRITE,
        &s_metadata_nvs);
    if (err != ESP_OK) return err;
    size_t size = sizeof(s_metadata);
    err = nvs_get_blob(s_metadata_nvs, DEVICE_METADATA_KEY, &s_metadata, &size);
    bool valid = err == ESP_OK && size == sizeof(s_metadata) &&
        s_metadata.magic == DEVICE_METADATA_MAGIC &&
        s_metadata.version == DEVICE_METADATA_VERSION &&
        s_metadata.checksum == metadata_checksum(&s_metadata);
    if (!valid) {
        memset(&s_metadata, 0, sizeof(s_metadata));
        s_metadata.magic = DEVICE_METADATA_MAGIC;
        s_metadata.version = DEVICE_METADATA_VERSION;
        s_metadata.checksum = metadata_checksum(&s_metadata);
        if (err != ESP_ERR_NVS_NOT_FOUND && err != ESP_OK)
            ESP_LOGW(TAG, "discarding invalid metadata store: %s",
                esp_err_to_name(err));
    }
    return ESP_OK;
}

static device_metadata_entry_t *find_metadata(const char *device_id)
{
    for (size_t i = 0; i < YAOCORE_MAX_DEVICES; ++i)
        if (s_metadata.entries[i].used &&
            !strcmp(s_metadata.entries[i].device_id, device_id))
            return &s_metadata.entries[i];
    return NULL;
}

static void apply_metadata(device_state_t *device)
{
    device_metadata_entry_t *entry = find_metadata(device->device_id);
    if (!entry) return;
    if (entry->name[0]) strlcpy(device->name, entry->name,
        sizeof(device->name));
    if (entry->room[0]) strlcpy(device->room, entry->room,
        sizeof(device->room));
}

static esp_err_t persist_metadata_value(device_state_t *device,
    const char *name, const char *room)
{
    device_metadata_store_t before = s_metadata;
    device_metadata_entry_t *entry = find_metadata(device->device_id);
    if (!entry) {
        for (size_t i = 0; i < YAOCORE_MAX_DEVICES; ++i) {
            if (!s_metadata.entries[i].used) {
                entry = &s_metadata.entries[i];
                memset(entry, 0, sizeof(*entry));
                entry->used = true;
                strlcpy(entry->device_id, device->device_id,
                    sizeof(entry->device_id));
                break;
            }
        }
    }
    if (!entry) return ESP_ERR_NO_MEM;
    if (name) strlcpy(entry->name, name, sizeof(entry->name));
    if (room) strlcpy(entry->room, room, sizeof(entry->room));
    s_metadata.checksum = metadata_checksum(&s_metadata);
    esp_err_t err = nvs_set_blob(s_metadata_nvs, DEVICE_METADATA_KEY,
        &s_metadata, sizeof(s_metadata));
    if (err == ESP_OK) err = nvs_commit(s_metadata_nvs);
    if (err != ESP_OK) {
        s_metadata = before;
        return err;
    }
    if (name) strlcpy(device->name, name, sizeof(device->name));
    if (room) strlcpy(device->room, room, sizeof(device->room));
    return ESP_OK;
}

static esp_err_t add_device(const char *id, const char *name, const char *room,
    const char *brand, device_type_t type)
{
    if (!id || !name || !room || !brand || id[0] == '\0' ||
        strlen(id) >= sizeof(s_devices[0].device_id)) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_count >= YAOCORE_MAX_DEVICES) {
        ESP_LOGE(TAG, "device registry full; rejected %s", id);
        return ESP_ERR_NO_MEM;
    }
    for (size_t i = 0; i < s_count; ++i) {
        if (!strcmp(s_devices[i].device_id, id)) {
            ESP_LOGE(TAG, "duplicate device id rejected: %s", id);
            return ESP_ERR_INVALID_STATE;
        }
    }
    device_state_t *device = &s_devices[s_count++];
    memset(device, 0, sizeof(*device));
    strlcpy(device->device_id, id, sizeof(device->device_id));
    strlcpy(device->name, name, sizeof(device->name));
    strlcpy(device->room, room, sizeof(device->room));
    strlcpy(device->brand, brand, sizeof(device->brand));
    device->type = type;
    strlcpy(device->protocol, "direct", sizeof(device->protocol));
    device->online = false;
    device->updated_at_ms = now_ms();
    apply_metadata(device);
    return ESP_OK;
}

static device_state_t *find_device(const char *id)
{
    for (size_t i = 0; i < s_count; ++i) {
        if (!strcmp(s_devices[i].device_id, id)) return &s_devices[i];
    }
    return NULL;
}

static bool read_device_state(const char *id, device_state_t *output)
{
    if (!id || !output) return false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *device = find_device(id);
    if (device) *output = *device;
    xSemaphoreGive(s_lock);
    return device != NULL;
}

static void set_provenance(device_state_t *device, const char *source,
    const char *trigger_device_id, const char *automation_id)
{
    strlcpy(device->state_source, source ? source : "unknown",
        sizeof(device->state_source));
    strlcpy(device->trigger_device_id, trigger_device_id ? trigger_device_id : "",
        sizeof(device->trigger_device_id));
    strlcpy(device->automation_id, automation_id ? automation_id : "",
        sizeof(device->automation_id));
}

static void set_command_provenance(device_state_t *device,
    const gateway_command_t *command)
{
    set_provenance(device, command->source[0] ? command->source : "gateway.command",
        command->trigger_device_id, command->automation_id);
}

/* Always called after releasing s_lock: cloud reporting takes a router snapshot. */
static void notify_state(const device_state_t *state)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_router_state_callback_t callback = s_state_callback;
    void *context = s_state_callback_context;
    xSemaphoreGive(s_lock);
    if (callback) callback(state, context);
}

static float absolute_float(float value) { return value < 0.0f ? -value : value; }

static void hardware_event(const hardware_event_t *event, void *context)
{
    (void)context;
    device_state_t changed_state;
    bool changed = false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    const char *device_id = event->kind == HARDWARE_EVENT_SENSOR ? "Sensor_01" :
        event->kind == HARDWARE_EVENT_PRESENCE ? "Presence_01" :
        event->kind == HARDWARE_EVENT_DOOR ? "Door_01" : "Light_01";
    device_state_t *device = find_device(device_id);
    if (device) {
        if (event->kind == HARDWARE_EVENT_LIGHT) s_light_event_seen = true;
        if (event->kind == HARDWARE_EVENT_DOOR) s_door_event_seen = true;
        if (event->kind == HARDWARE_EVENT_PRESENCE) s_presence_event_seen = true;
        changed = device->online != event->online;
        device->online = event->online;
        if (event->kind == HARDWARE_EVENT_DOOR && event->online) {
            changed = changed || device->open != event->open;
            device->open = event->open;
        } else if (event->kind == HARDWARE_EVENT_LIGHT && event->online) {
            changed = changed || device->brightness != event->brightness;
            device->brightness = event->brightness;
            device->power = event->brightness > 0;
        } else if (event->kind == HARDWARE_EVENT_SENSOR && event->online) {
            changed = changed || absolute_float(device->temperature - event->temperature) >= 0.1f ||
                absolute_float(device->humidity - event->humidity) >= 0.5f;
            device->temperature = event->temperature;
            device->humidity = event->humidity;
        } else if (event->kind == HARDWARE_EVENT_PRESENCE && event->online) {
            changed = changed || device->presence != event->presence;
            device->presence = event->presence;
        }
        set_provenance(device, "sensor.physical", "", "");
        device->updated_at_ms = now_ms();
        changed_state = *device;
    }
    xSemaphoreGive(s_lock);
    if (changed && device) notify_state(&changed_state);
    if (device && (event->kind == HARDWARE_EVENT_SENSOR ||
        event->kind == HARDWARE_EVENT_PRESENCE)) {
        /* Runs after router state commit and outside s_lock. The automation
         * executor returns through device_router_execute(), preserving the
         * exact same physical ACK and state-reporting path as phone control. */
        automation_engine_on_sensor_state(&changed_state);
    }
}

static void ac_health_task(void *arg)
{
    (void)arg;
    const gateway_config_t *cfg = gateway_config_get();
    TickType_t interval = pdMS_TO_TICKS(cfg->ac_health_interval_seconds * 1000);
    while (true) {
        /* The boot HANDSHAKE already provides the initial state. */
        vTaskDelay(interval);

        device_state_t observed;
        memset(&observed, 0, sizeof(observed));
        bool received_ack = false;
        char remote_message[96] = {0};
        bool changed = false;
        device_state_t changed_state;

        /* Keep the UART query and router commit in the same transaction used
         * by HTTP/MQTT AC commands. hardware_ac_health_query() additionally
         * takes the shared southbound command mutex. */
        xSemaphoreTake(s_ac_state_lock, portMAX_DELAY);
        esp_err_t err = hardware_ac_health_query(&observed, &received_ack,
            remote_message, sizeof(remote_message));
        xSemaphoreTake(s_lock, portMAX_DELAY);
        device_state_t *ac = find_device("AC_01");
        if (err == ESP_OK) {
            s_ac_health_failures = 0;
            changed = !ac->online || ac->power != observed.power ||
                absolute_float(ac->target_temperature -
                    observed.target_temperature) >= 0.01f ||
                strcmp(ac->mode, observed.mode);
            ac->online = true;
            ac->power = observed.power;
            ac->target_temperature = observed.target_temperature;
            strlcpy(ac->mode, observed.mode, sizeof(ac->mode));
            ac->updated_at_ms = observed.updated_at_ms;
            if (changed) set_provenance(ac, "device.feedback", "", "");
        } else {
            if (s_ac_health_failures < (unsigned)cfg->ac_health_failure_threshold) {
                ++s_ac_health_failures;
            }
            ESP_LOGW(TAG, "AC health query failed (%u/%d): %s",
                s_ac_health_failures, cfg->ac_health_failure_threshold,
                received_ack && remote_message[0] ? remote_message :
                    esp_err_to_name(err));
            if (s_ac_health_failures >=
                (unsigned)cfg->ac_health_failure_threshold && ac->online) {
                ac->online = false;
                ac->updated_at_ms = now_ms();
                changed = true;
            }
        }
        changed_state = *ac;
        xSemaphoreGive(s_lock);
        xSemaphoreGive(s_ac_state_lock);

        /* cloud_iotda's registered callback wakes its report task; the same
         * state is immediately visible to LAN discovery and reconciliation. */
        if (changed) notify_state(&changed_state);
    }
}

static esp_err_t configure_board_led(const gateway_config_t *config)
{
    if (config->board_led_gpio < 0) return ESP_OK;
    gpio_config_t output = {
        .pin_bit_mask = 1ULL << config->board_led_gpio,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&output);
    if (err == ESP_OK) err = gpio_set_level(config->board_led_gpio,
        config->board_led_active_low ? 1 : 0);
    return err;
}

esp_err_t device_router_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    s_ac_state_lock = xSemaphoreCreateMutex();
    if (!s_lock || !s_ac_state_lock) return ESP_ERR_NO_MEM;
    s_count = 0;
    s_gateway_led = false;
    s_light_event_seen = false;
    s_door_event_seen = false;
    s_presence_event_seen = false;
    s_ac_health_failures = 0;
    esp_err_t metadata = metadata_init();
    if (metadata != ESP_OK) return metadata;
    esp_err_t module_transport = external_module_init(
        device_router_mark_external_offline);
    if (module_transport != ESP_OK) return module_transport;
    const gateway_config_t *config = gateway_config_get();
    if (config->light_gpio < 0) ESP_LOGI(TAG, "light PWM driver is disabled");
    esp_err_t registry_err = ESP_OK;
    if (config->door_gpio >= 0) {
        registry_err = add_device("Door_01", "Smart Door", "Entrance", "GENERIC", DEVICE_DOOR);
        if (registry_err != ESP_OK) return registry_err;
    }
    if (config->light_gpio >= 0) {
        registry_err = add_device("Light_01", "PWM Main Light", "Living Room", "GENERIC", DEVICE_LIGHT);
        if (registry_err != ESP_OK) return registry_err;
    }
    if (config->sht30_enabled) {
        registry_err = add_device("Sensor_01", "SHT30 Temperature Humidity", "Living Room", "Sensirion",
            DEVICE_SENSOR);
        if (registry_err != ESP_OK) return registry_err;
        s_devices[s_count - 1].has_environment = true;
    }
    if (config->pir_gpio >= 0) {
        registry_err = add_device("Presence_01", "PIR Presence Sensor", "Living Room", "GENERIC",
            DEVICE_SENSOR);
        if (registry_err != ESP_OK) return registry_err;
        s_devices[s_count - 1].has_presence = true;
    }
    if (config->ac_uart_tx_gpio >= 0 && config->ac_uart_rx_gpio >= 0) {
        registry_err = add_device("AC_01", "Air Conditioner", "Living Room", config->ac_brand, DEVICE_AC);
        if (registry_err != ESP_OK) return registry_err;
    }

    esp_err_t automation = automation_engine_init(read_device_state,
        device_router_execute);
    if (automation != ESP_OK) return automation;

    esp_err_t board_led = configure_board_led(config);
    if (board_led != ESP_OK) ESP_LOGE(TAG, "board LED init failed: %s",
        esp_err_to_name(board_led));

    hardware_initial_state_t initial;
    esp_err_t err = hardware_drivers_init(hardware_event, NULL, &initial);
    if (err != ESP_OK) return err;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *door = find_device("Door_01");
    if (door && !s_door_event_seen) {
        door->online = initial.door_online;
        door->open = initial.door_open;
    }
    device_state_t *light = find_device("Light_01");
    if (light && !s_light_event_seen) {
        light->online = initial.light_online;
        light->brightness = initial.light_brightness;
        light->power = initial.light_brightness > 0;
    }
    device_state_t *ac = find_device("AC_01");
    if (ac && initial.ac_online) {
        ac->online = true;
        ac->power = initial.ac_state.power;
        ac->target_temperature = initial.ac_state.target_temperature;
        strlcpy(ac->mode, initial.ac_state.mode, sizeof(ac->mode));
        ac->updated_at_ms = initial.ac_state.updated_at_ms;
    }
    device_state_t *presence = find_device("Presence_01");
    if (presence && !s_presence_event_seen) {
        presence->online = initial.presence_online;
        presence->presence = initial.presence;
        if (presence->online) set_provenance(presence, "sensor.physical", "", "");
    }
    bool door_online = door && door->online, light_online = light && light->online,
        presence_online = presence && presence->online, ac_online = ac && ac->online;
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "physical registry: door=%s light=%s environment=pending-sample presence=%s ac=%s",
        door_online ? "online" : "offline", light_online ? "online" : "offline",
        presence_online ? "online" : "offline", ac_online ? "online" : "offline");
    if (presence && presence_online) automation_engine_on_sensor_state(presence);
    if (ac && config->ac_uart_tx_gpio >= 0 &&
        xTaskCreate(ac_health_task, "ac_health", 4096, NULL, 5, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

void device_router_set_state_callback(device_router_state_callback_t callback,
    void *context)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_state_callback = callback;
    s_state_callback_context = context;
    xSemaphoreGive(s_lock);
}

size_t device_router_snapshot(device_state_t *output, size_t capacity)
{
    if (!output || capacity == 0) return 0;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    size_t count = s_count < capacity ? s_count : capacity;
    memcpy(output, s_devices, count * sizeof(device_state_t));
    xSemaphoreGive(s_lock);
    return count;
}

static void apply_external_patch(device_state_t *device,
    const external_state_patch_t *patch)
{
    if (patch->has_online) device->online = patch->online;
    else device->online = true;
    if (patch->has_power) device->power = patch->power;
    if (patch->has_open) device->open = patch->open;
    if (patch->has_brightness) device->brightness = patch->brightness;
    if (patch->has_color) {
        device->has_color = true;
        strlcpy(device->color, patch->color, sizeof(device->color));
    }
    if (patch->has_environment) {
        device->has_environment = true;
        device->temperature = patch->temperature;
        device->humidity = patch->humidity;
    }
    if (patch->has_presence) {
        device->has_presence = true;
        device->presence = patch->presence;
    }
    if (patch->has_target_temperature)
        device->target_temperature = patch->target_temperature;
    if (patch->has_mode) strlcpy(device->mode, patch->mode,
        sizeof(device->mode));
    if (patch->has_position) device->position = patch->position;
    if (patch->has_speed) device->speed = patch->speed;
    if (patch->has_volume) device->volume = patch->volume;
    device->updated_at_ms = now_ms();
}

static bool external_patch_supported(device_type_t type,
    const external_state_patch_t *patch)
{
    bool any = patch->has_online || patch->has_power || patch->has_open ||
        patch->has_brightness || patch->has_color || patch->has_environment ||
        patch->has_presence || patch->has_target_temperature ||
        patch->has_mode || patch->has_position || patch->has_speed ||
        patch->has_volume;
    if (!any) return true; /* registration may omit its initial snapshot */
    bool common_only = patch->has_online;
    if (type == DEVICE_DOOR) return (common_only || patch->has_open) &&
        !patch->has_power && !patch->has_brightness && !patch->has_color &&
        !patch->has_environment && !patch->has_presence &&
        !patch->has_target_temperature && !patch->has_mode &&
        !patch->has_position && !patch->has_speed && !patch->has_volume;
    if (type == DEVICE_LIGHT) return (common_only || patch->has_power ||
        patch->has_brightness || patch->has_color) && !patch->has_open &&
        !patch->has_environment && !patch->has_presence &&
        !patch->has_target_temperature && !patch->has_mode &&
        !patch->has_position && !patch->has_speed && !patch->has_volume;
    if (type == DEVICE_SENSOR) return (common_only || patch->has_environment ||
        patch->has_presence) && !patch->has_power && !patch->has_open &&
        !patch->has_brightness && !patch->has_color && !patch->has_target_temperature &&
        !patch->has_mode && !patch->has_position && !patch->has_speed &&
        !patch->has_volume;
    if (type == DEVICE_AC) return (common_only || patch->has_power ||
        patch->has_target_temperature || patch->has_mode) && !patch->has_open &&
        !patch->has_brightness && !patch->has_color && !patch->has_environment &&
        !patch->has_presence && !patch->has_position && !patch->has_speed &&
        !patch->has_volume;
    if (type == DEVICE_SWITCH) return (common_only || patch->has_power) &&
        !patch->has_open && !patch->has_brightness && !patch->has_color &&
        !patch->has_environment && !patch->has_presence &&
        !patch->has_target_temperature && !patch->has_mode &&
        !patch->has_position && !patch->has_speed && !patch->has_volume;
    if (type == DEVICE_CURTAIN) return (common_only || patch->has_position) &&
        !patch->has_power && !patch->has_open && !patch->has_brightness && !patch->has_color &&
        !patch->has_environment && !patch->has_presence &&
        !patch->has_target_temperature && !patch->has_mode &&
        !patch->has_speed && !patch->has_volume;
    if (type == DEVICE_FAN) return (common_only || patch->has_power ||
        patch->has_speed) && !patch->has_open && !patch->has_brightness && !patch->has_color &&
        !patch->has_environment && !patch->has_presence &&
        !patch->has_target_temperature && !patch->has_mode &&
        !patch->has_position && !patch->has_volume;
    if (type == DEVICE_SPEAKER) return (common_only || patch->has_power ||
        patch->has_volume) && !patch->has_open && !patch->has_brightness && !patch->has_color &&
        !patch->has_environment && !patch->has_presence &&
        !patch->has_target_temperature && !patch->has_mode &&
        !patch->has_position && !patch->has_speed;
    return common_only && !patch->has_power && !patch->has_open &&
        !patch->has_brightness && !patch->has_color && !patch->has_environment &&
        !patch->has_presence && !patch->has_target_temperature &&
        !patch->has_mode && !patch->has_position && !patch->has_speed &&
        !patch->has_volume;
}

esp_err_t device_router_register_external(
    const external_device_registration_t *registration)
{
    if (!registration) return ESP_ERR_INVALID_ARG;
    if (!external_patch_supported(registration->type,
        &registration->initial_state)) return ESP_ERR_INVALID_ARG;
    device_state_t changed;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *device = find_device(registration->device_id);
    if (device && (!device->external || strcmp(device->module_id,
        registration->module_id))) {
        xSemaphoreGive(s_lock);
        return ESP_ERR_INVALID_STATE;
    }
    if (!device) {
        esp_err_t added = add_device(registration->device_id, registration->name,
            registration->room, registration->brand, registration->type);
        if (added != ESP_OK) { xSemaphoreGive(s_lock); return added; }
        device = find_device(registration->device_id);
    }
    strlcpy(device->name, registration->name, sizeof(device->name));
    strlcpy(device->room, registration->room, sizeof(device->room));
    strlcpy(device->brand, registration->brand, sizeof(device->brand));
    strlcpy(device->module_id, registration->module_id,
        sizeof(device->module_id));
    strlcpy(device->protocol, registration->protocol,
        sizeof(device->protocol));
    device->type = registration->type;
    device->external = true;
    apply_metadata(device);
    apply_external_patch(device, &registration->initial_state);
    set_provenance(device, "module.register", "", "");
    changed = *device;
    xSemaphoreGive(s_lock);
    notify_state(&changed);
    if (changed.type == DEVICE_SENSOR)
        automation_engine_on_sensor_state(&changed);
    return ESP_OK;
}

esp_err_t device_router_report_external(const char *module_id,
    const char *device_id, const external_state_patch_t *patch)
{
    if (!module_id || !device_id || !patch) return ESP_ERR_INVALID_ARG;
    device_state_t before, changed;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *device = find_device(device_id);
    if (!device || !device->external || strcmp(device->module_id, module_id)) {
        xSemaphoreGive(s_lock); return ESP_ERR_NOT_FOUND;
    }
    if (!external_patch_supported(device->type, patch)) {
        xSemaphoreGive(s_lock); return ESP_ERR_INVALID_ARG;
    }
    before = *device;
    apply_external_patch(device, patch);
    set_provenance(device, device->type == DEVICE_SENSOR ?
        "sensor.module" : "device.module", "", "");
    changed = *device;
    xSemaphoreGive(s_lock);
    if (memcmp(&before, &changed, sizeof(changed)) != 0) notify_state(&changed);
    if (changed.type == DEVICE_SENSOR)
        automation_engine_on_sensor_state(&changed);
    return ESP_OK;
}

void device_router_mark_external_offline(const char *device_id)
{
    if (!device_id || !s_lock) return;
    device_state_t changed;
    bool notify = false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *device = find_device(device_id);
    if (device && device->external && device->online) {
        device->online = false;
        device->updated_at_ms = now_ms();
        set_provenance(device, "module.timeout", "", "");
        changed = *device; notify = true;
    }
    xSemaphoreGive(s_lock);
    if (notify) notify_state(&changed);
}

static void fail(gateway_ack_t *ack, int code, const char *error,
    const char *message)
{
    memset(ack, 0, sizeof(*ack));
    ack->result_code = code;
    strlcpy(ack->error_code, error, sizeof(ack->error_code));
    strlcpy(ack->message, message, sizeof(ack->message));
}

static bool valid_mode(const char *mode)
{
    const char *modes[] = {"AUTO", "COOL", "HEAT", "DRY", "FAN", "ECO", "SLEEP"};
    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); ++i) {
        if (!strcmp(mode, modes[i])) return true;
    }
    return false;
}

static bool valid_color(const char *color)
{
    if (!color || strlen(color) != 7 || color[0] != '#') return false;
    for (size_t i = 1; i < 7; ++i) {
        bool digit = color[i] >= '0' && color[i] <= '9';
        bool upper = color[i] >= 'A' && color[i] <= 'F';
        if (!digit && !upper) return false;
    }
    return true;
}

static void set_reported_success(gateway_ack_t *ack, const device_state_t *state,
    const char *message)
{
    ack->result_code = 0;
    strlcpy(ack->message, message, sizeof(ack->message));
    ack->reported_state = *state;
    ack->has_reported_state = true;
}

static bool external_action_supported(const device_state_t *device,
    const gateway_command_t *command)
{
    bool no_value = command->value_type == VALUE_NONE;
    bool percent = command->value_type == VALUE_NUMBER &&
        command->number_value >= 0 && command->number_value <= 100;
    if (device->type == DEVICE_DOOR) return no_value &&
        (!strcmp(command->action, "OPEN") || !strcmp(command->action, "CLOSE"));
    if (device->type == DEVICE_LIGHT) return (no_value &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF"))) ||
        (percent && !strcmp(command->action, "SET_BRIGHTNESS")) ||
        (device->has_color && command->value_type == VALUE_STRING &&
         !strcmp(command->action, "SET_COLOR") && valid_color(command->string_value));
    if (device->type == DEVICE_SWITCH) return no_value &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF"));
    if (device->type == DEVICE_CURTAIN) return (no_value &&
        (!strcmp(command->action, "OPEN") || !strcmp(command->action, "CLOSE") ||
         !strcmp(command->action, "STOP"))) ||
        (percent && !strcmp(command->action, "SET_POSITION"));
    if (device->type == DEVICE_FAN) return (no_value &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF"))) ||
        (percent && !strcmp(command->action, "SET_SPEED"));
    if (device->type == DEVICE_SPEAKER) return (no_value &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF"))) ||
        (percent && !strcmp(command->action, "SET_VOLUME"));
    if (device->type == DEVICE_AC) return (no_value &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF"))) ||
        (command->value_type == VALUE_NUMBER &&
         command->number_value >= 16 && command->number_value <= 30 &&
         !strcmp(command->action, "SET_TARGET_TEMPERATURE")) ||
        (command->value_type == VALUE_STRING &&
         !strcmp(command->action, "SET_MODE") && valid_mode(command->string_value));
    return false;
}

static esp_err_t execute_external(const gateway_command_t *command,
    gateway_ack_t *ack, const device_state_t *before)
{
    if (!before->online) {
        fail(ack, 2009, "MODULE_OFFLINE", "external device module is offline");
        return ESP_ERR_INVALID_STATE;
    }
    if (!external_action_supported(before, command)) {
        fail(ack, 2002, "ACTION_NOT_SUPPORTED",
            "action is not supported by this external device type");
        return ESP_ERR_NOT_SUPPORTED;
    }
    external_state_patch_t reported;
    int result_code = -1;
    char message[128] = {0};
    esp_err_t result = external_module_execute(command, before->type, &reported,
        &result_code, message, sizeof(message));
    if (result != ESP_OK || result_code != 0) {
        fail(ack, result == ESP_ERR_INVALID_CRC ? 2011 : 2010,
            result == ESP_ERR_INVALID_CRC ? "MODULE_AUTH_FAILED" :
            "MODULE_COMMAND_UNCONFIRMED", message[0] ? message :
            "external module did not return a valid confirmed state");
        return result;
    }
    device_state_t changed;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *device = find_device(command->target);
    if (!device || !device->external || strcmp(device->module_id,
        before->module_id)) {
        xSemaphoreGive(s_lock);
        fail(ack, 2001, "DEVICE_NOT_FOUND", "external device disappeared");
        return ESP_ERR_NOT_FOUND;
    }
    apply_external_patch(device, &reported);
    device->has_last_command = true;
    strlcpy(device->last_request_id, command->request_id,
        sizeof(device->last_request_id));
    device->last_seq = command->seq;
    set_command_provenance(device, command);
    changed = *device;
    xSemaphoreGive(s_lock);
    if (memcmp(&changed, before, sizeof(changed)) != 0) notify_state(&changed);
    automation_engine_note_external_command(command);
    set_reported_success(ack, &changed, message[0] ? message :
        "external module state confirmed");
    return ESP_OK;
}

static esp_err_t execute_door(const gateway_command_t *command, gateway_ack_t *ack,
    const device_state_t *before)
{
    (void)before;
    hardware_door_transaction_begin();
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t serialized_before = *find_device(command->target);
    xSemaphoreGive(s_lock);
    bool requested_open = !strcmp(command->action, "OPEN");
    bool confirmed_open = serialized_before.open;
    bool feedback_confirmed = false;
    esp_err_t err = hardware_door_set_locked(requested_open, &confirmed_open,
        &feedback_confirmed);
    device_state_t changed;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *door = find_device(command->target);
    if (err == ESP_OK && feedback_confirmed) {
        door->online = true;
        door->open = confirmed_open;
        door->has_last_command = true;
        strlcpy(door->last_request_id, command->request_id,
            sizeof(door->last_request_id));
        door->last_seq = command->seq;
        set_command_provenance(door, command);
    } else {
        door->online = false; /* physical state is no longer trustworthy */
    }
    door->updated_at_ms = now_ms();
    changed = *door;
    xSemaphoreGive(s_lock);
    hardware_door_transaction_end();
    if (memcmp(&changed, &serialized_before, sizeof(changed)) != 0) notify_state(&changed);
    if (err != ESP_OK) {
        fail(ack, 2004, "ACTUATION_UNCONFIRMED",
            "door output changed but feedback did not confirm requested state");
        ack->reported_state = changed;
        ack->has_reported_state = true;
        return err;
    }
    if (!feedback_confirmed) {
        fail(ack, 2008, "ACTUATION_ACCEPTED_UNCONFIRMED",
            "door output accepted but position feedback is not configured");
        ack->reported_state = changed;
        ack->has_reported_state = true;
        return ESP_ERR_INVALID_STATE;
    }
    set_reported_success(ack, &changed, "door position confirmed by feedback");
    return ESP_OK;
}

static esp_err_t execute_light(const gateway_command_t *command, gateway_ack_t *ack,
    const device_state_t *before)
{
    (void)before;
    const gateway_config_t *cfg = gateway_config_get();
    /* Defensive invariant: this helper may be reused independently later. */
    if (cfg->light_gpio < 0) {
        fail(ack, 2003, "DRIVER_NOT_CONFIGURED", "light PWM GPIO not configured");
        return ESP_ERR_INVALID_STATE;
    }
    hardware_light_transaction_begin();
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t serialized_before = *find_device(command->target);
    xSemaphoreGive(s_lock);
    int percent;
    if (!strcmp(command->action, "OFF")) percent = 0;
    else if (!strcmp(command->action, "ON")) percent = serialized_before.brightness > 0 ?
        serialized_before.brightness : cfg->light_default_brightness;
    else percent = (int)(command->number_value + 0.5);
    esp_err_t err = hardware_light_set_percent_locked((uint8_t)percent);
    device_state_t changed;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *light = find_device(command->target);
    light->online = err == ESP_OK;
    if (err == ESP_OK) {
        light->brightness = percent;
        light->power = percent > 0;
        light->has_last_command = true;
        strlcpy(light->last_request_id, command->request_id,
            sizeof(light->last_request_id));
        light->last_seq = command->seq;
        set_command_provenance(light, command);
    }
    light->updated_at_ms = now_ms();
    changed = *light;
    xSemaphoreGive(s_lock);
    hardware_light_transaction_end();
    if (memcmp(&changed, &serialized_before, sizeof(changed)) != 0) notify_state(&changed);
    if (err != ESP_OK) {
        fail(ack, 2005, "PWM_DRIVER_FAILURE", "LEDC rejected the requested duty");
        ack->reported_state = changed;
        ack->has_reported_state = true;
        return err;
    }
    set_reported_success(ack, &changed, "PWM duty applied");
    return ESP_OK;
}

static esp_err_t execute_ac(const gateway_command_t *command, gateway_ack_t *ack,
    const device_state_t *before)
{
    device_state_t downstream;
    memset(&downstream, 0, sizeof(downstream));
    bool state_confirmed = false;
    bool received_ack = false;
    char remote_message[96];
    esp_err_t err = hardware_ac_execute(command, &downstream, &state_confirmed,
        &received_ack,
        remote_message, sizeof(remote_message));
    device_state_t changed = *before;
    bool notify = false;
    if (err == ESP_OK) {
        s_ac_health_failures = 0;
        xSemaphoreTake(s_lock, portMAX_DELAY);
        device_state_t *ac = find_device(command->target);
        ac->online = true;
        ac->power = downstream.power;
        ac->target_temperature = downstream.target_temperature;
        strlcpy(ac->mode, downstream.mode, sizeof(ac->mode));
        ac->has_last_command = true;
        strlcpy(ac->last_request_id, command->request_id,
            sizeof(ac->last_request_id));
        ac->last_seq = command->seq;
        set_command_provenance(ac, command);
        ac->updated_at_ms = now_ms();
        changed = *ac;
        xSemaphoreGive(s_lock);
        notify = memcmp(&changed, before, sizeof(changed)) != 0;
        if (notify) notify_state(&changed);
        set_reported_success(ack, &changed, "southbound AC ACK confirmed");
        return ESP_OK;
    }
    if (!received_ack) {
        xSemaphoreTake(s_lock, portMAX_DELAY);
        device_state_t *ac = find_device(command->target);
        ac->online = false;
        ac->updated_at_ms = now_ms();
        changed = *ac;
        xSemaphoreGive(s_lock);
        if (memcmp(&changed, before, sizeof(changed)) != 0) notify_state(&changed);
        fail(ack, 2006, "DOWNSTREAM_NO_ACK",
            "air-conditioner bridge did not return a matching ACK");
        ack->reported_state = changed;
        ack->has_reported_state = true;
    } else {
        if (state_confirmed) {
            s_ac_health_failures = 0;
            xSemaphoreTake(s_lock, portMAX_DELAY);
            device_state_t *ac = find_device(command->target);
            ac->online = true;
            ac->power = downstream.power;
            ac->target_temperature = downstream.target_temperature;
            strlcpy(ac->mode, downstream.mode, sizeof(ac->mode));
            ac->updated_at_ms = now_ms();
            changed = *ac;
            xSemaphoreGive(s_lock);
            if (memcmp(&changed, before, sizeof(changed)) != 0) notify_state(&changed);
        }
        fail(ack, 2007, "DOWNSTREAM_REJECTED", remote_message[0] ?
            remote_message : "air-conditioner bridge rejected or malformed the command");
        if (state_confirmed) {
            ack->reported_state = changed;
            ack->has_reported_state = true;
        }
    }
    return err;
}

esp_err_t device_router_execute(const gateway_command_t *command,
    gateway_ack_t *ack)
{
    if (!command || !ack) return ESP_ERR_INVALID_ARG;
    const gateway_config_t *config = gateway_config_get();
    memset(ack, 0, sizeof(*ack));
    if (!strcmp(command->target, config->gateway_id)) {
        if (!strcmp(command->action, "PING")) {
            ack->result_code = 0;
            strlcpy(ack->message, "pong", sizeof(ack->message));
            return ESP_OK;
        }
        if (!strcmp(command->action, "BOARD_LED_ON")) {
            if (config->board_led_gpio < 0) {
                fail(ack, 2003, "DRIVER_NOT_CONFIGURED",
                    "board LED GPIO not configured");
                return ESP_ERR_INVALID_STATE;
            }
            esp_err_t led = gpio_set_level(config->board_led_gpio,
                config->board_led_active_low ? 0 : 1);
            if (led != ESP_OK) {
                fail(ack, 2004, "ACTUATION_UNCONFIRMED",
                    "board LED output write failed");
                return led;
            }
            s_gateway_led = true;
            ack->result_code = 0;
            strlcpy(ack->message, "board LED enabled", sizeof(ack->message));
            return ESP_OK;
        }
        fail(ack, 2002, "ACTION_NOT_SUPPORTED", "unsupported gateway action");
        return ESP_ERR_NOT_SUPPORTED;
    }

    xSemaphoreTake(s_lock, portMAX_DELAY);
    device_state_t *device = find_device(command->target);
    if (!device) {
        xSemaphoreGive(s_lock);
        fail(ack, 2001, "DEVICE_NOT_FOUND", "target device not registered");
        return ESP_ERR_NOT_FOUND;
    }
    device_state_t before = *device;
    xSemaphoreGive(s_lock);

    bool set_name = !strcmp(command->action, "SET_DEVICE_NAME");
    bool set_room = !strcmp(command->action, "SET_DEVICE_ROOM");
    if (set_name || set_room) {
        size_t value_length = strlen(command->string_value);
        size_t capacity = set_name ? sizeof(before.name) : sizeof(before.room);
        if (command->value_type != VALUE_STRING || value_length == 0 ||
            value_length >= capacity) {
            fail(ack, 2010, "INVALID_METADATA",
                set_name ? "device name must contain 1 to 63 UTF-8 bytes" :
                "room name must contain 1 to 31 UTF-8 bytes");
            return ESP_ERR_INVALID_ARG;
        }
        device_state_t changed;
        xSemaphoreTake(s_lock, portMAX_DELAY);
        device = find_device(command->target);
        esp_err_t saved = device ? persist_metadata_value(device,
            set_name ? command->string_value : NULL,
            set_room ? command->string_value : NULL) : ESP_ERR_NOT_FOUND;
        if (saved == ESP_OK) {
            set_command_provenance(device, command);
            device->updated_at_ms = now_ms();
            changed = *device;
        }
        xSemaphoreGive(s_lock);
        if (saved != ESP_OK) {
            fail(ack, 2011, "METADATA_PERSIST_FAILED",
                "gateway could not persist device metadata");
            return saved;
        }
        notify_state(&changed);
        set_reported_success(ack, &changed,
            set_name ? "device name saved by gateway" :
            "device room saved by gateway");
        return ESP_OK;
    }

    if (before.external) return execute_external(command, ack, &before);

    const gateway_config_t *cfg = config;
    if (before.type == DEVICE_DOOR && cfg->door_gpio < 0) {
        fail(ack, 2003, "DRIVER_NOT_CONFIGURED", "door actuator GPIO not configured");
        return ESP_ERR_INVALID_STATE;
    }
    if (before.type == DEVICE_LIGHT && cfg->light_gpio < 0) {
        fail(ack, 2003, "DRIVER_NOT_CONFIGURED", "light PWM GPIO not configured");
        return ESP_ERR_INVALID_STATE;
    }
    if (before.type == DEVICE_AC &&
        (cfg->ac_uart_tx_gpio < 0 || cfg->ac_uart_rx_gpio < 0)) {
        fail(ack, 2003, "DRIVER_NOT_CONFIGURED", "air-conditioner UART bridge not configured");
        return ESP_ERR_INVALID_STATE;
    }

    if (before.type == DEVICE_DOOR &&
        (!strcmp(command->action, "OPEN") || !strcmp(command->action, "CLOSE")) &&
        command->value_type == VALUE_NONE) {
        automation_engine_note_external_command(command);
        return execute_door(command, ack, &before);
    }
    bool light_on_off = before.type == DEVICE_LIGHT &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF")) &&
        command->value_type == VALUE_NONE;
    bool light_brightness = before.type == DEVICE_LIGHT &&
        !strcmp(command->action, "SET_BRIGHTNESS") &&
        command->value_type == VALUE_NUMBER && command->number_value >= 0 &&
        command->number_value <= 100;
    if (light_on_off || light_brightness) {
        automation_engine_note_external_command(command);
        return execute_light(command, ack, &before);
    }

    bool ac_power = before.type == DEVICE_AC &&
        (!strcmp(command->action, "ON") || !strcmp(command->action, "OFF")) &&
        command->value_type == VALUE_NONE;
    bool ac_temperature = before.type == DEVICE_AC &&
        !strcmp(command->action, "SET_TARGET_TEMPERATURE") &&
        command->value_type == VALUE_NUMBER && command->number_value >= 16 &&
        command->number_value <= 30;
    bool ac_mode = before.type == DEVICE_AC && !strcmp(command->action, "SET_MODE") &&
        command->value_type == VALUE_STRING && valid_mode(command->string_value);
    if (ac_power || ac_temperature || ac_mode) {
        automation_engine_note_external_command(command);
        xSemaphoreTake(s_ac_state_lock, portMAX_DELAY);
        xSemaphoreTake(s_lock, portMAX_DELAY);
        device_state_t serialized_before = *find_device(command->target);
        xSemaphoreGive(s_lock);
        esp_err_t result = execute_ac(command, ack, &serialized_before);
        xSemaphoreGive(s_ac_state_lock);
        return result;
    }

    fail(ack, 2002, "ACTION_NOT_SUPPORTED", "action or value not supported");
    return ESP_ERR_NOT_SUPPORTED;
}

bool device_router_gateway_led_state(void) { return s_gateway_led; }
