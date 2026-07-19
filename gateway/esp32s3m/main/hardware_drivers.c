/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "hardware_drivers.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cJSON.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "driver/ledc.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gateway_config.h"

static const char *TAG = "hardware";
static hardware_event_callback_t s_callback;
static void *s_callback_context;
static bool s_light_ready;
static bool s_door_ready;
static bool s_ac_ready;
static uint8_t s_light_percent;
static uint32_t s_ledc_max_duty;
static SemaphoreHandle_t s_light_lock;
static SemaphoreHandle_t s_door_lock;
static SemaphoreHandle_t s_ac_lock;
static SemaphoreHandle_t s_ac_command_lock;
static bool s_ac_handshake_confirmed;
static bool s_door_feedback_online;
static bool s_door_last_reported_open;

static void emit_event(const hardware_event_t *event)
{
    hardware_event_callback_t callback = s_callback;
    if (callback) callback(event, s_callback_context);
}

static esp_err_t set_light_locked(uint8_t percent)
{
    if (!s_light_ready) return ESP_ERR_INVALID_STATE;
    const gateway_config_t *cfg = gateway_config_get();
    uint32_t duty = (uint32_t)(((uint64_t)s_ledc_max_duty * percent + 50U) / 100U);
    if (cfg->light_pwm_active_low) duty = s_ledc_max_duty - duty;
    esp_err_t err = ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, duty);
    if (err == ESP_OK) err = ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
    if (err == ESP_OK) {
        s_light_percent = percent;
    }
    return err;
}

void hardware_light_transaction_begin(void)
{
    xSemaphoreTake(s_light_lock, portMAX_DELAY);
}

void hardware_light_transaction_end(void)
{
    xSemaphoreGive(s_light_lock);
}

esp_err_t hardware_light_set_percent_locked(uint8_t percent)
{
    if (percent > 100) return ESP_ERR_INVALID_ARG;
    return set_light_locked(percent);
}

static esp_err_t init_light(void)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (cfg->light_gpio < 0) return ESP_ERR_NOT_SUPPORTED;
    ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_10_BIT,
        .timer_num = LEDC_TIMER_0,
        .freq_hz = cfg->light_pwm_frequency_hz,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    esp_err_t err = ledc_timer_config(&timer);
    if (err != ESP_OK) return err;
    ledc_channel_config_t channel = {
        .gpio_num = cfg->light_gpio,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_0,
        .intr_type = LEDC_INTR_DISABLE,
        .timer_sel = LEDC_TIMER_0,
        .duty = cfg->light_pwm_active_low ? 1023 : 0,
        .hpoint = 0,
    };
    err = ledc_channel_config(&channel);
    if (err != ESP_OK) return err;
    s_ledc_max_duty = 1023;
    s_light_ready = true;
    s_light_percent = 0;
    ESP_LOGI(TAG, "light PWM ready: GPIO%d, %d Hz", cfg->light_gpio,
        cfg->light_pwm_frequency_hz);
    return ESP_OK;
}

static uint8_t sht30_crc(const uint8_t *data, size_t length)
{
    uint8_t crc = 0xFF;
    for (size_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; ++bit) crc = (crc & 0x80) ?
            (uint8_t)((crc << 1) ^ 0x31) : (uint8_t)(crc << 1);
    }
    return crc;
}

static esp_err_t read_sht30(float *temperature, float *humidity)
{
    const gateway_config_t *cfg = gateway_config_get();
    uint8_t command[] = {0x24, 0x00}; /* high repeatability, no clock stretching */
    esp_err_t err = i2c_master_write_to_device((i2c_port_t)cfg->sht30_i2c_port,
        cfg->sht30_address, command, sizeof(command), pdMS_TO_TICKS(100));
    if (err != ESP_OK) return err;
    vTaskDelay(pdMS_TO_TICKS(20));
    uint8_t data[6];
    err = i2c_master_read_from_device((i2c_port_t)cfg->sht30_i2c_port,
        cfg->sht30_address, data, sizeof(data), pdMS_TO_TICKS(100));
    if (err != ESP_OK) return err;
    if (sht30_crc(data, 2) != data[2] || sht30_crc(data + 3, 2) != data[5]) {
        return ESP_ERR_INVALID_CRC;
    }
    uint16_t raw_temperature = ((uint16_t)data[0] << 8) | data[1];
    uint16_t raw_humidity = ((uint16_t)data[3] << 8) | data[4];
    *temperature = -45.0f + 175.0f * (float)raw_temperature / 65535.0f;
    *humidity = 100.0f * (float)raw_humidity / 65535.0f;
    if (*temperature < -40.0f || *temperature > 125.0f ||
        *humidity < 0.0f || *humidity > 100.0f) return ESP_ERR_INVALID_RESPONSE;
    return ESP_OK;
}

static void sht30_task(void *arg)
{
    (void)arg;
    const gateway_config_t *cfg = gateway_config_get();
    unsigned consecutive_failures = 0;
    bool previously_online = false;
    while (true) {
        float temperature = 0.0f, humidity = 0.0f;
        esp_err_t err = read_sht30(&temperature, &humidity);
        if (err == ESP_OK) {
            consecutive_failures = 0;
            previously_online = true;
            hardware_event_t event = {
                .kind = HARDWARE_EVENT_SENSOR,
                .online = true,
                .temperature = temperature,
                .humidity = humidity,
            };
            emit_event(&event);
        } else {
            ++consecutive_failures;
            ESP_LOGW(TAG, "SHT30 read failed (%u): %s", consecutive_failures,
                esp_err_to_name(err));
            if (previously_online && consecutive_failures >= 3) {
                previously_online = false;
                hardware_event_t event = {
                    .kind = HARDWARE_EVENT_SENSOR,
                    .online = false,
                };
                emit_event(&event);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(cfg->sht30_sample_interval_ms));
    }
}

static esp_err_t init_sht30(void)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (!cfg->sht30_enabled) return ESP_ERR_NOT_SUPPORTED;
    i2c_config_t config = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = cfg->sht30_sda_gpio,
        .scl_io_num = cfg->sht30_scl_gpio,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = cfg->sht30_i2c_frequency_hz,
    };
    esp_err_t err = i2c_param_config((i2c_port_t)cfg->sht30_i2c_port, &config);
    if (err != ESP_OK) return err;
    err = i2c_driver_install((i2c_port_t)cfg->sht30_i2c_port,
        I2C_MODE_MASTER, 0, 0, 0);
    if (err != ESP_OK) return err;
    if (xTaskCreate(sht30_task, "sht30", 4096, NULL, 5, NULL) != pdPASS) {
        i2c_driver_delete((i2c_port_t)cfg->sht30_i2c_port);
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "SHT30 acquisition started on I2C%d address 0x%02x",
        cfg->sht30_i2c_port, cfg->sht30_address);
    return ESP_OK;
}

static void pir_task(void *arg)
{
    (void)arg;
    const gateway_config_t *cfg = gateway_config_get();
    bool reported_presence = gpio_get_level(cfg->pir_gpio) == cfg->pir_active_level;
    int64_t last_motion_ms = 0;
    hardware_event_t initial = {
        .kind = HARDWARE_EVENT_PRESENCE,
        .online = true,
        .presence = reported_presence,
    };
    if (reported_presence) last_motion_ms = esp_timer_get_time() / 1000;
    emit_event(&initial);
    while (true) {
        bool active = gpio_get_level(cfg->pir_gpio) == cfg->pir_active_level;
        int64_t now_ms = esp_timer_get_time() / 1000;
        if (active) last_motion_ms = now_ms;
        if (active && !reported_presence) {
            reported_presence = true;
            hardware_event_t event = {
                .kind = HARDWARE_EVENT_PRESENCE,
                .online = true,
                .presence = true,
            };
            emit_event(&event);
        }
        if (!active && reported_presence && last_motion_ms > 0 &&
            now_ms - last_motion_ms >= (int64_t)cfg->pir_timeout_seconds * 1000) {
            reported_presence = false;
            hardware_event_t event = {
                .kind = HARDWARE_EVENT_PRESENCE,
                .online = true,
                .presence = false,
            };
            emit_event(&event);
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

static esp_err_t init_pir(void)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (cfg->pir_gpio < 0) return ESP_ERR_NOT_SUPPORTED;
    gpio_config_t input = {
        .pin_bit_mask = 1ULL << cfg->pir_gpio,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&input);
    if (err != ESP_OK) return err;
    if (xTaskCreate(pir_task, "pir_automation", 3072, NULL, 6, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "PIR presence sensor ready: GPIO%d, no-motion timeout %d s", cfg->pir_gpio,
        cfg->pir_timeout_seconds);
    return ESP_OK;
}

static bool read_door_feedback(bool *open)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (!open || cfg->door_feedback_gpio < 0) return false;
    int level = gpio_get_level(cfg->door_feedback_gpio);
    if (level != 0 && level != 1) return false;
    *open = level == cfg->door_feedback_open_level;
    return true;
}

static void door_feedback_task(void *arg)
{
    (void)arg;
    const gateway_config_t *cfg = gateway_config_get();
    bool candidate = s_door_last_reported_open;
    int64_t candidate_since_ms = esp_timer_get_time() / 1000;
    unsigned consecutive_read_failures = 0;
    while (true) {
        bool observed = candidate;
        int64_t now_ms = esp_timer_get_time() / 1000;
        if (!read_door_feedback(&observed)) {
            candidate_since_ms = now_ms;
            if (++consecutive_read_failures >= 3) {
                xSemaphoreTake(s_door_lock, portMAX_DELAY);
                if (s_door_feedback_online) {
                    s_door_feedback_online = false;
                    hardware_event_t event = {
                        .kind = HARDWARE_EVENT_DOOR,
                        .online = false,
                        .open = s_door_last_reported_open,
                    };
                    emit_event(&event);
                }
                xSemaphoreGive(s_door_lock);
            }
        } else {
            consecutive_read_failures = 0;
            if (observed != candidate) {
                candidate = observed;
                candidate_since_ms = now_ms;
            }
            if (now_ms - candidate_since_ms >= cfg->door_feedback_debounce_ms) {
                xSemaphoreTake(s_door_lock, portMAX_DELAY);
                bool confirmed = false;
                if (read_door_feedback(&confirmed) && confirmed == candidate &&
                    (!s_door_feedback_online ||
                     candidate != s_door_last_reported_open)) {
                    s_door_feedback_online = true;
                    s_door_last_reported_open = candidate;
                    hardware_event_t event = {
                        .kind = HARDWARE_EVENT_DOOR,
                        .online = true,
                        .open = candidate,
                    };
                    emit_event(&event);
                }
                xSemaphoreGive(s_door_lock);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(cfg->door_feedback_poll_interval_ms));
    }
}

void hardware_door_transaction_begin(void)
{
    xSemaphoreTake(s_door_lock, portMAX_DELAY);
}

void hardware_door_transaction_end(void)
{
    xSemaphoreGive(s_door_lock);
}

static esp_err_t init_door(bool *initial_open)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (cfg->door_gpio < 0) return ESP_ERR_NOT_SUPPORTED;
    gpio_config_t output = {
        .pin_bit_mask = 1ULL << cfg->door_gpio,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&output);
    if (err != ESP_OK) return err;
    err = gpio_set_level(cfg->door_gpio,
        cfg->door_open_level ? 0 : 1); /* safe closed */
    if (err != ESP_OK) return err;
    *initial_open = false;
    if (cfg->door_feedback_gpio >= 0) {
        gpio_config_t feedback = {
            .pin_bit_mask = 1ULL << cfg->door_feedback_gpio,
            .mode = GPIO_MODE_INPUT,
            .pull_up_en = cfg->door_feedback_pullup ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE,
            .pull_down_en = GPIO_PULLDOWN_DISABLE,
            .intr_type = GPIO_INTR_DISABLE,
        };
        err = gpio_config(&feedback);
        if (err != ESP_OK) return err;
        if (!read_door_feedback(initial_open)) return ESP_ERR_INVALID_RESPONSE;
    }
    s_door_ready = true;
    s_door_feedback_online = cfg->door_feedback_gpio >= 0;
    s_door_last_reported_open = *initial_open;
    if (cfg->door_feedback_gpio >= 0 &&
        xTaskCreate(door_feedback_task, "door_feedback", 3072, NULL, 5,
            NULL) != pdPASS) {
        s_door_ready = false;
        s_door_feedback_online = false;
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "door actuator ready: GPIO%d%s", cfg->door_gpio,
        cfg->door_feedback_gpio >= 0 ? " with feedback" : " without feedback");
    return ESP_OK;
}

esp_err_t hardware_door_set_locked(bool open, bool *confirmed_open,
    bool *feedback_confirmed)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (!s_door_ready || !confirmed_open || !feedback_confirmed) {
        return ESP_ERR_INVALID_STATE;
    }
    *feedback_confirmed = false;
    esp_err_t err = gpio_set_level(cfg->door_gpio,
        open ? cfg->door_open_level : !cfg->door_open_level);
    if (err != ESP_OK) { s_door_feedback_online = false; return err; }
    if (cfg->door_feedback_gpio < 0) {
        *confirmed_open = open;
        s_door_feedback_online = false;
        return ESP_OK;
    }
    int64_t deadline = esp_timer_get_time() +
        (int64_t)cfg->door_feedback_timeout_ms * 1000;
    while (esp_timer_get_time() < deadline) {
        bool observed = false;
        if (read_door_feedback(&observed) && observed == open) {
            *confirmed_open = observed;
            *feedback_confirmed = true;
            s_door_feedback_online = true;
            s_door_last_reported_open = observed;
            return ESP_OK;
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    if (!read_door_feedback(confirmed_open)) *confirmed_open =
        s_door_last_reported_open;
    s_door_feedback_online = false;
    return ESP_ERR_TIMEOUT;
}

static bool valid_ac_mode(const char *mode)
{
    const char *modes[] = {"AUTO", "COOL", "HEAT", "DRY", "FAN", "ECO", "SLEEP"};
    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); ++i) {
        if (!strcmp(mode, modes[i])) return true;
    }
    return false;
}

static bool parse_ac_ack(const char *line, const char *request_id,
    device_state_t *state, bool *matched, bool *accepted,
    char *message, size_t message_size)
{
    *matched = false;
    *accepted = false;
    cJSON *root = cJSON_Parse(line);
    if (!root) return false;
    cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "version");
    cJSON *id = cJSON_GetObjectItemCaseSensitive(root, "requestId");
    cJSON *target = cJSON_GetObjectItemCaseSensitive(root, "target");
    cJSON *code = cJSON_GetObjectItemCaseSensitive(root, "resultCode");
    bool envelope_ok = cJSON_IsString(version) && !strcmp(version->valuestring, "1.0") &&
        cJSON_IsString(id) && cJSON_IsString(target) &&
        cJSON_IsNumber(code) && !strcmp(target->valuestring, "AC_01");
    if (!envelope_ok || strcmp(id->valuestring, request_id)) {
        cJSON_Delete(root);
        return envelope_ok;
    }
    *matched = true;
    cJSON *remote_message = cJSON_GetObjectItemCaseSensitive(root, "message");
    if (cJSON_IsString(remote_message)) strlcpy(message, remote_message->valuestring,
        message_size);
    if (code->valueint != 0) {
        cJSON_Delete(root);
        return true;
    }
    cJSON *snapshot = cJSON_GetObjectItemCaseSensitive(root, "state");
    cJSON *power = snapshot ? cJSON_GetObjectItemCaseSensitive(snapshot, "power") : NULL;
    cJSON *temperature = snapshot ? cJSON_GetObjectItemCaseSensitive(snapshot,
        "targetTemperature") : NULL;
    cJSON *mode = snapshot ? cJSON_GetObjectItemCaseSensitive(snapshot, "mode") : NULL;
    if (!cJSON_IsObject(snapshot) || !cJSON_IsBool(power) ||
        !cJSON_IsNumber(temperature) || temperature->valuedouble < 16 ||
        temperature->valuedouble > 30 || !cJSON_IsString(mode) ||
        !valid_ac_mode(mode->valuestring)) {
        strlcpy(message, "malformed AC state in ACK", message_size);
        cJSON_Delete(root);
        return false;
    }
    memset(state, 0, sizeof(*state));
    strlcpy(state->device_id, "AC_01", sizeof(state->device_id));
    strlcpy(state->brand, gateway_config_get()->ac_brand, sizeof(state->brand));
    state->type = DEVICE_AC;
    state->online = true;
    state->power = cJSON_IsTrue(power);
    state->target_temperature = (float)temperature->valuedouble;
    strlcpy(state->mode, mode->valuestring, sizeof(state->mode));
    state->updated_at_ms = esp_timer_get_time() / 1000;
    *accepted = true;
    cJSON_Delete(root);
    return true;
}

static esp_err_t ac_exchange(const char *request_id, const char *action,
    command_value_type_t value_type, bool bool_value, double number_value,
    const char *string_value, device_state_t *state, bool *received_ack,
    char *message, size_t message_size)
{
    const gateway_config_t *cfg = gateway_config_get();
    *received_ack = false;
    if (message_size) message[0] = '\0';
    cJSON *root = cJSON_CreateObject();
    if (!root) return ESP_ERR_NO_MEM;
    cJSON_AddStringToObject(root, "version", "1.0");
    cJSON_AddStringToObject(root, "requestId", request_id);
    cJSON_AddStringToObject(root, "target", "AC_01");
    cJSON_AddStringToObject(root, "brand", cfg->ac_brand);
    cJSON_AddStringToObject(root, "action", action);
    if (value_type == VALUE_BOOL) cJSON_AddBoolToObject(root, "value", bool_value);
    else if (value_type == VALUE_NUMBER) cJSON_AddNumberToObject(root, "value", number_value);
    else if (value_type == VALUE_STRING) cJSON_AddStringToObject(root, "value", string_value);
    else cJSON_AddNullToObject(root, "value");
    char *json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (!json) return ESP_ERR_NO_MEM;
    size_t json_len = strlen(json);
    char *frame = malloc(json_len + 2);
    if (!frame) { free(json); return ESP_ERR_NO_MEM; }
    memcpy(frame, json, json_len);
    frame[json_len] = '\n';
    frame[json_len + 1] = '\0';
    free(json);

    xSemaphoreTake(s_ac_lock, portMAX_DELAY);
    uart_flush_input((uart_port_t)cfg->ac_uart_port);
    int written = uart_write_bytes((uart_port_t)cfg->ac_uart_port, frame,
        json_len + 1);
    free(frame);
    if (written != (int)json_len + 1 ||
        uart_wait_tx_done((uart_port_t)cfg->ac_uart_port,
            pdMS_TO_TICKS(cfg->ac_ack_timeout_ms)) != ESP_OK) {
        xSemaphoreGive(s_ac_lock);
        return ESP_FAIL;
    }
    int64_t deadline = esp_timer_get_time() + (int64_t)cfg->ac_ack_timeout_ms * 1000;
    char line[512];
    size_t used = 0;
    bool frame_overflow = false;
    esp_err_t result = ESP_ERR_TIMEOUT;
    while (esp_timer_get_time() < deadline) {
        uint8_t byte;
        int count = uart_read_bytes((uart_port_t)cfg->ac_uart_port, &byte, 1,
            pdMS_TO_TICKS(50));
        if (count <= 0) continue;
        if (byte == '\r') continue;
        if (byte != '\n') {
            if (!frame_overflow && used + 1 < sizeof(line)) line[used++] = (char)byte;
            else frame_overflow = true;
            continue;
        }
        if (frame_overflow) { used = 0; frame_overflow = false; continue; }
        if (used == 0) continue;
        line[used] = '\0';
        used = 0;
        bool matched = false, accepted = false;
        bool valid = parse_ac_ack(line, request_id, state, &matched, &accepted,
            message, message_size);
        if (!matched) continue; /* stale/unrelated frame */
        *received_ack = true;
        result = valid && accepted ? ESP_OK : ESP_ERR_INVALID_RESPONSE;
        break;
    }
    xSemaphoreGive(s_ac_lock);
    return result;
}

static esp_err_t init_ac(device_state_t *state)
{
    const gateway_config_t *cfg = gateway_config_get();
    if (cfg->ac_uart_tx_gpio < 0 || cfg->ac_uart_rx_gpio < 0) {
        return ESP_ERR_NOT_SUPPORTED;
    }
    uart_config_t uart_config = {
        .baud_rate = cfg->ac_uart_baud_rate,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    esp_err_t err = uart_param_config((uart_port_t)cfg->ac_uart_port,
        &uart_config);
    if (err != ESP_OK) return err;
    err = uart_set_pin((uart_port_t)cfg->ac_uart_port, cfg->ac_uart_tx_gpio,
        cfg->ac_uart_rx_gpio, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (err != ESP_OK) return err;
    err = uart_driver_install((uart_port_t)cfg->ac_uart_port, 2048, 0, 0,
        NULL, 0);
    if (err != ESP_OK) return err;
    s_ac_ready = true;
    s_ac_handshake_confirmed = false;
    char request_id[64];
    snprintf(request_id, sizeof(request_id), "boot-%lld",
        (long long)(esp_timer_get_time() / 1000));
    bool received_ack = false;
    char message[96];
    err = ac_exchange(request_id, "HANDSHAKE", VALUE_NONE, false, 0, NULL,
        state, &received_ack, message, sizeof(message));
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "AC bridge handshake failed: %s", received_ack ?
            message : "no matching ACK");
        ESP_LOGW(TAG, "UART remains available so a later command can retry the bridge");
        return err;
    }
    s_ac_handshake_confirmed = true;
    ESP_LOGI(TAG, "AC UART bridge ready: UART%d, %s", cfg->ac_uart_port,
        cfg->ac_brand);
    return ESP_OK;
}

esp_err_t hardware_ac_execute(const gateway_command_t *command,
    device_state_t *reported_state, bool *state_confirmed, bool *received_ack,
    char *remote_message, size_t remote_message_size)
{
    if (received_ack) *received_ack = false;
    if (state_confirmed) *state_confirmed = false;
    if (!command || !reported_state || !state_confirmed || !received_ack ||
        !s_ac_ready) {
        return ESP_ERR_INVALID_STATE;
    }
    xSemaphoreTake(s_ac_command_lock, portMAX_DELAY);
    if (!s_ac_handshake_confirmed) {
        char handshake_id[64];
        snprintf(handshake_id, sizeof(handshake_id), "retry-%lld",
            (long long)(esp_timer_get_time() / 1000));
        device_state_t handshake_state;
        esp_err_t handshake = ac_exchange(handshake_id, "HANDSHAKE", VALUE_NONE,
            false, 0, NULL, &handshake_state, received_ack, remote_message,
            remote_message_size);
        if (handshake != ESP_OK) {
            xSemaphoreGive(s_ac_command_lock);
            return handshake;
        }
        *reported_state = handshake_state;
        *state_confirmed = true;
        s_ac_handshake_confirmed = true;
    }
    esp_err_t result = ac_exchange(command->request_id, command->action, command->value_type,
        command->bool_value, command->number_value, command->string_value,
        reported_state, received_ack, remote_message, remote_message_size);
    if (result == ESP_OK) *state_confirmed = true;
    if (result != ESP_OK && !*received_ack) s_ac_handshake_confirmed = false;
    xSemaphoreGive(s_ac_command_lock);
    return result;
}

esp_err_t hardware_ac_health_query(device_state_t *reported_state,
    bool *received_ack, char *remote_message, size_t remote_message_size)
{
    if (received_ack) *received_ack = false;
    if (!reported_state || !received_ack || !remote_message ||
        remote_message_size == 0 || !s_ac_ready) {
        return ESP_ERR_INVALID_STATE;
    }

    xSemaphoreTake(s_ac_command_lock, portMAX_DELAY);
    char request_id[64];
    snprintf(request_id, sizeof(request_id), "health-%lld",
        (long long)(esp_timer_get_time() / 1000));
    /* A failed query invalidates the session.  The next health cycle or user
     * command performs a full HANDSHAKE before trusting the bridge again. */
    const char *action = s_ac_handshake_confirmed ? "STATUS_QUERY" : "HANDSHAKE";
    esp_err_t result = ac_exchange(request_id, action, VALUE_NONE, false, 0,
        NULL, reported_state, received_ack, remote_message,
        remote_message_size);
    s_ac_handshake_confirmed = result == ESP_OK;
    xSemaphoreGive(s_ac_command_lock);
    return result;
}

esp_err_t hardware_drivers_init(hardware_event_callback_t callback, void *context,
    hardware_initial_state_t *initial)
{
    if (!initial) return ESP_ERR_INVALID_ARG;
    memset(initial, 0, sizeof(*initial));
    s_callback = callback;
    s_callback_context = context;
    s_light_lock = xSemaphoreCreateMutex();
    s_door_lock = xSemaphoreCreateMutex();
    s_ac_lock = xSemaphoreCreateMutex();
    s_ac_command_lock = xSemaphoreCreateMutex();
    if (!s_light_lock || !s_door_lock || !s_ac_lock || !s_ac_command_lock) {
        return ESP_ERR_NO_MEM;
    }

    esp_err_t err = init_light();
    initial->light_online = err == ESP_OK;
    initial->light_brightness = 0;
    if (err != ESP_OK && err != ESP_ERR_NOT_SUPPORTED) {
        ESP_LOGE(TAG, "light driver init failed: %s", esp_err_to_name(err));
    }
    err = init_door(&initial->door_open);
    /* Door online means a closed feedback loop, not merely a writable relay. */
    initial->door_online = err == ESP_OK &&
        gateway_config_get()->door_feedback_gpio >= 0;
    if (err != ESP_OK && err != ESP_ERR_NOT_SUPPORTED) {
        ESP_LOGE(TAG, "door driver init failed: %s", esp_err_to_name(err));
    }
    err = init_sht30();
    if (err != ESP_OK && err != ESP_ERR_NOT_SUPPORTED) {
        ESP_LOGE(TAG, "SHT30 init failed: %s", esp_err_to_name(err));
    }
    err = init_pir();
    initial->presence_online = err == ESP_OK;
    initial->presence = err == ESP_OK &&
        gpio_get_level(gateway_config_get()->pir_gpio) ==
            gateway_config_get()->pir_active_level;
    if (err != ESP_OK && err != ESP_ERR_NOT_SUPPORTED) {
        ESP_LOGE(TAG, "PIR init failed: %s", esp_err_to_name(err));
    }
    err = init_ac(&initial->ac_state);
    initial->ac_online = err == ESP_OK;
    return ESP_OK;
}
