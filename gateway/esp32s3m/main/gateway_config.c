/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "gateway_config.h"
#include <string.h>
#include "esp_log.h"
#include "driver/gpio.h"
#include "sdkconfig.h"

static const char *TAG = "gateway_config";

static const gateway_config_t CONFIG = {
    .provisioning_pop = CONFIG_YAOCORE_PROV_POP,
    .gateway_id = CONFIG_YAOCORE_GATEWAY_ID,
    .gateway_name = CONFIG_YAOCORE_GATEWAY_NAME,
    .command_secret = CONFIG_YAOCORE_COMMAND_SECRET,
    .local_port = CONFIG_YAOCORE_LOCAL_PORT,
    .udp_port = CONFIG_YAOCORE_DISCOVERY_UDP_PORT,
    .board_led_gpio = CONFIG_YAOCORE_BOARD_LED_GPIO,
#ifdef CONFIG_YAOCORE_BOARD_LED_ACTIVE_LOW
    .board_led_active_low = true,
#else
    .board_led_active_low = false,
#endif
    .door_gpio = CONFIG_YAOCORE_DOOR_GPIO,
    .door_open_level = CONFIG_YAOCORE_DOOR_OPEN_LEVEL,
    .door_feedback_gpio = CONFIG_YAOCORE_DOOR_FEEDBACK_GPIO,
    .door_feedback_open_level = CONFIG_YAOCORE_DOOR_FEEDBACK_OPEN_LEVEL,
#ifdef CONFIG_YAOCORE_DOOR_FEEDBACK_PULLUP
    .door_feedback_pullup = true,
#else
    .door_feedback_pullup = false,
#endif
    .door_feedback_timeout_ms = CONFIG_YAOCORE_DOOR_FEEDBACK_TIMEOUT_MS,
    .door_feedback_poll_interval_ms = CONFIG_YAOCORE_DOOR_FEEDBACK_POLL_INTERVAL_MS,
    .door_feedback_debounce_ms = CONFIG_YAOCORE_DOOR_FEEDBACK_DEBOUNCE_MS,
    .light_gpio = CONFIG_YAOCORE_LIGHT_GPIO,
#ifdef CONFIG_YAOCORE_LIGHT_PWM_ACTIVE_LOW
    .light_pwm_active_low = true,
#else
    .light_pwm_active_low = false,
#endif
    .light_pwm_frequency_hz = CONFIG_YAOCORE_LIGHT_PWM_FREQUENCY_HZ,
    .light_default_brightness = CONFIG_YAOCORE_LIGHT_DEFAULT_BRIGHTNESS,
#ifdef CONFIG_YAOCORE_SHT30_ENABLE
    .sht30_enabled = true,
    .sht30_i2c_port = CONFIG_YAOCORE_SHT30_I2C_PORT,
    .sht30_sda_gpio = CONFIG_YAOCORE_SHT30_SDA_GPIO,
    .sht30_scl_gpio = CONFIG_YAOCORE_SHT30_SCL_GPIO,
    .sht30_i2c_frequency_hz = CONFIG_YAOCORE_SHT30_I2C_FREQUENCY_HZ,
    .sht30_address = CONFIG_YAOCORE_SHT30_ADDRESS,
    .sht30_sample_interval_ms = CONFIG_YAOCORE_SHT30_SAMPLE_INTERVAL_MS,
#else
    .sht30_enabled = false,
    .sht30_i2c_port = 0,
    .sht30_sda_gpio = -1,
    .sht30_scl_gpio = -1,
    .sht30_i2c_frequency_hz = 100000,
    .sht30_address = 0x44,
    .sht30_sample_interval_ms = 5000,
#endif
    .pir_gpio = CONFIG_YAOCORE_PIR_GPIO,
    .pir_active_level = CONFIG_YAOCORE_PIR_ACTIVE_LEVEL,
    .pir_timeout_seconds = CONFIG_YAOCORE_PIR_TIMEOUT_SECONDS,
    .pir_light_brightness = CONFIG_YAOCORE_PIR_LIGHT_BRIGHTNESS,
#ifdef CONFIG_YAOCORE_PRESENCE_LIGHT_AUTOMATION_ENABLE
    .presence_light_automation_enabled = true,
#else
    .presence_light_automation_enabled = false,
#endif
    .presence_light_target_id = CONFIG_YAOCORE_PRESENCE_LIGHT_TARGET_ID,
#ifdef CONFIG_YAOCORE_TEMPERATURE_AC_AUTOMATION_ENABLE
    .temperature_ac_automation_enabled = true,
    .temperature_ac_on_threshold = CONFIG_YAOCORE_TEMPERATURE_AC_ON_THRESHOLD,
    .temperature_ac_off_threshold = CONFIG_YAOCORE_TEMPERATURE_AC_OFF_THRESHOLD,
#else
    .temperature_ac_automation_enabled = false,
    .temperature_ac_on_threshold = 28,
    .temperature_ac_off_threshold = 26,
#endif
    .ac_uart_port = CONFIG_YAOCORE_AC_UART_PORT,
    .ac_uart_tx_gpio = CONFIG_YAOCORE_AC_UART_TX_GPIO,
    .ac_uart_rx_gpio = CONFIG_YAOCORE_AC_UART_RX_GPIO,
    .ac_uart_baud_rate = CONFIG_YAOCORE_AC_UART_BAUD_RATE,
    .ac_ack_timeout_ms = CONFIG_YAOCORE_AC_ACK_TIMEOUT_MS,
    .ac_health_interval_seconds = CONFIG_YAOCORE_AC_HEALTH_INTERVAL_SECONDS,
    .ac_health_failure_threshold = CONFIG_YAOCORE_AC_HEALTH_FAILURE_THRESHOLD,
    .ac_brand = CONFIG_YAOCORE_AC_BRAND,
#ifdef CONFIG_YAOCORE_IOTDA_ENABLE
    .iotda_enabled = true,
    .iotda_broker_uri = CONFIG_YAOCORE_IOTDA_BROKER_URI,
    .iotda_device_id = CONFIG_YAOCORE_IOTDA_DEVICE_ID,
    .iotda_password = CONFIG_YAOCORE_IOTDA_PASSWORD,
#else
    .iotda_enabled = false,
    .iotda_broker_uri = "",
    .iotda_device_id = "",
    .iotda_password = "",
#endif
    .iotda_report_interval_seconds = CONFIG_YAOCORE_IOTDA_REPORT_INTERVAL_SECONDS,
};

const gateway_config_t *gateway_config_get(void) { return &CONFIG; }

static bool validate_gpio_capabilities(void)
{
    bool ok = true;
    const int output_pins[] = { CONFIG.board_led_gpio, CONFIG.door_gpio,
        CONFIG.light_gpio, CONFIG.ac_uart_tx_gpio };
    for (size_t i = 0; i < sizeof(output_pins) / sizeof(output_pins[0]); ++i) {
        if (output_pins[i] >= 0 && !GPIO_IS_VALID_OUTPUT_GPIO(output_pins[i])) {
            ESP_LOGE(TAG, "GPIO%d is not output-capable", output_pins[i]); ok = false;
        }
    }
    const int input_pins[] = { CONFIG.door_feedback_gpio, CONFIG.pir_gpio,
        CONFIG.ac_uart_rx_gpio };
    for (size_t i = 0; i < sizeof(input_pins) / sizeof(input_pins[0]); ++i) {
        if (input_pins[i] >= 0 && !GPIO_IS_VALID_GPIO(input_pins[i])) {
            ESP_LOGE(TAG, "GPIO%d is not a valid input", input_pins[i]); ok = false;
        }
    }
    if (CONFIG.sht30_enabled &&
        (!GPIO_IS_VALID_OUTPUT_GPIO(CONFIG.sht30_sda_gpio) ||
         !GPIO_IS_VALID_OUTPUT_GPIO(CONFIG.sht30_scl_gpio))) {
        ESP_LOGE(TAG, "SHT30 SDA/SCL must be output-capable GPIOs"); ok = false;
    }
    return ok;
}

static bool validate_pin_conflicts(void)
{
    struct pin_use { int gpio; const char *name; } pins[9];
    size_t count = 0;
#define ADD_PIN(value, label) do { if ((value) >= 0) pins[count++] = \
    (struct pin_use){ (value), (label) }; } while (0)
    ADD_PIN(CONFIG.board_led_gpio, "board LED");
    ADD_PIN(CONFIG.door_gpio, "door actuator");
    ADD_PIN(CONFIG.door_feedback_gpio, "door feedback");
    ADD_PIN(CONFIG.light_gpio, "light PWM");
    ADD_PIN(CONFIG.pir_gpio, "PIR");
    ADD_PIN(CONFIG.ac_uart_tx_gpio, "AC UART TX");
    ADD_PIN(CONFIG.ac_uart_rx_gpio, "AC UART RX");
    if (CONFIG.sht30_enabled) {
        ADD_PIN(CONFIG.sht30_sda_gpio, "SHT30 SDA");
        ADD_PIN(CONFIG.sht30_scl_gpio, "SHT30 SCL");
    }
#undef ADD_PIN
    bool ok = true;
    for (size_t i = 0; i < count; ++i) {
        if (pins[i].gpio == 0) {
            ESP_LOGE(TAG, "%s cannot use reserved BOOT/provision-reset GPIO0",
                pins[i].name); ok = false;
        }
        if (pins[i].gpio == 11 || pins[i].gpio == 12 || pins[i].gpio == 38 ||
            pins[i].gpio == 39 || pins[i].gpio == 40 || pins[i].gpio == 41) {
            ESP_LOGE(TAG, "%s cannot use GPIO%d reserved by the onboard LCD",
                pins[i].name, pins[i].gpio);
            ok = false;
        }
        for (size_t j = i + 1; j < count; ++j) {
            if (pins[i].gpio == pins[j].gpio) {
                ESP_LOGE(TAG, "GPIO%d conflict between %s and %s", pins[i].gpio,
                    pins[i].name, pins[j].name); ok = false;
            }
        }
    }
    return ok;
}

static bool valid_gateway_id(const char *value)
{
    size_t length = strlen(value);
    if (length == 0 || length >= 64) return false;
    for (size_t i = 0; i < length; ++i) {
        char ch = value[i];
        bool alpha_numeric = (ch >= '0' && ch <= '9') ||
            (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
        if (!alpha_numeric && (i == 0 ||
            (ch != '_' && ch != '.' && ch != ':' && ch != '-'))) return false;
    }
    return true;
}

bool gateway_config_validate(void)
{
    bool ok = true;
    size_t pop_len = strlen(CONFIG.provisioning_pop);
    if (pop_len < 8 || pop_len > 64) {
        ESP_LOGE(TAG, "BLE provisioning PoP must contain 8 to 64 bytes");
        ok = false;
    }
    if (strlen(CONFIG.command_secret) < 16) { ESP_LOGE(TAG, "HMAC secret must be at least 16 bytes"); ok = false; }
    if (!valid_gateway_id(CONFIG.gateway_id)) {
        ESP_LOGE(TAG, "gateway ID must match [A-Za-z0-9][A-Za-z0-9_.:-]{0,62}");
        ok = false;
    }
    if (strlen(CONFIG.gateway_name) == 0 || strlen(CONFIG.gateway_name) >= 64) {
        ESP_LOGE(TAG, "gateway name must contain 1 to 63 bytes");
        ok = false;
    }
    size_t gateway_name_len = strlen(CONFIG.gateway_name);
    if (gateway_name_len == 0 || gateway_name_len >= 64) {
        ESP_LOGE(TAG, "gateway name must contain 1 to 63 UTF-8 bytes");
        ok = false;
    }
    if (CONFIG.door_feedback_gpio >= 0 && CONFIG.door_gpio < 0) {
        ESP_LOGE(TAG, "door feedback cannot be enabled without a door actuator GPIO"); ok = false;
    }
    if (CONFIG.door_feedback_gpio >= 0 && CONFIG.door_feedback_gpio == CONFIG.door_gpio) {
        ESP_LOGE(TAG, "door actuator and feedback GPIO must differ"); ok = false;
    }
    if (CONFIG.door_feedback_gpio >= 0 &&
        CONFIG.door_feedback_debounce_ms < CONFIG.door_feedback_poll_interval_ms) {
        ESP_LOGE(TAG, "door feedback debounce must be at least one poll interval"); ok = false;
    }
    if (CONFIG.presence_light_automation_enabled &&
        !valid_gateway_id(CONFIG.presence_light_target_id)) {
        ESP_LOGE(TAG, "presence-light automation target must be a valid deviceId");
        ok = false;
    }
    if (CONFIG.presence_light_automation_enabled &&
        !strcmp(CONFIG.presence_light_target_id, "Light_01") &&
        CONFIG.light_gpio < 0) {
        ESP_LOGE(TAG, "Light_01 automation target requires a configured light PWM GPIO");
        ok = false;
    }
    if (CONFIG.sht30_enabled && (CONFIG.sht30_sda_gpio < 0 ||
        CONFIG.sht30_scl_gpio < 0 || CONFIG.sht30_sda_gpio == CONFIG.sht30_scl_gpio)) {
        ESP_LOGE(TAG, "SHT30 requires distinct SDA and SCL GPIOs"); ok = false;
    }
    bool ac_tx_set = CONFIG.ac_uart_tx_gpio >= 0;
    bool ac_rx_set = CONFIG.ac_uart_rx_gpio >= 0;
    if (ac_tx_set != ac_rx_set || (ac_tx_set &&
        CONFIG.ac_uart_tx_gpio == CONFIG.ac_uart_rx_gpio)) {
        ESP_LOGE(TAG, "AC UART requires distinct TX and RX GPIOs, or both disabled"); ok = false;
    }
    if (CONFIG.temperature_ac_automation_enabled &&
        (!CONFIG.sht30_enabled || !ac_tx_set)) {
        ESP_LOGE(TAG, "temperature-AC automation requires SHT30 and AC UART");
        ok = false;
    }
    if (CONFIG.temperature_ac_automation_enabled &&
        CONFIG.temperature_ac_off_threshold >= CONFIG.temperature_ac_on_threshold) {
        ESP_LOGE(TAG, "temperature-AC off threshold must be below on threshold");
        ok = false;
    }
    if (strcmp(CONFIG.ac_brand, "GREE") && strcmp(CONFIG.ac_brand, "MIDEA") &&
        strcmp(CONFIG.ac_brand, "HAIER") && strcmp(CONFIG.ac_brand, "GENERIC")) {
        ESP_LOGE(TAG, "AC brand must be GREE, MIDEA, HAIER, or GENERIC"); ok = false;
    }
    if (CONFIG.iotda_enabled && (strlen(CONFIG.iotda_device_id) == 0 || strlen(CONFIG.iotda_password) == 0)) {
        ESP_LOGE(TAG, "IoTDA credentials are incomplete"); ok = false;
    }
    if (CONFIG.iotda_enabled && strlen(CONFIG.iotda_device_id) > 230) {
        ESP_LOGE(TAG, "IoTDA device ID is too long for MQTT ClientId"); ok = false;
    }
    if (CONFIG.iotda_enabled && strncmp(CONFIG.iotda_broker_uri, "mqtts://", 8) != 0) {
        ESP_LOGE(TAG, "IoTDA broker URI must use mqtts:// TLS transport"); ok = false;
    }
    if (!validate_gpio_capabilities()) ok = false;
    if (!validate_pin_conflicts()) ok = false;
    return ok;
}
