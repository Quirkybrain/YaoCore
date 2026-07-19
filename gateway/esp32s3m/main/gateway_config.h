/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <stdbool.h>

typedef struct {
    const char *provisioning_pop;
    const char *gateway_id;
    const char *gateway_name;
    const char *command_secret;
    int local_port;
    int udp_port;
    int board_led_gpio;
    bool board_led_active_low;
    int door_gpio;
    int door_open_level;
    int door_feedback_gpio;
    int door_feedback_open_level;
    bool door_feedback_pullup;
    int door_feedback_timeout_ms;
    int door_feedback_poll_interval_ms;
    int door_feedback_debounce_ms;
    int light_gpio;
    bool light_pwm_active_low;
    int light_pwm_frequency_hz;
    int light_default_brightness;
    bool sht30_enabled;
    int sht30_i2c_port;
    int sht30_sda_gpio;
    int sht30_scl_gpio;
    int sht30_i2c_frequency_hz;
    int sht30_address;
    int sht30_sample_interval_ms;
    int pir_gpio;
    int pir_active_level;
    int pir_timeout_seconds;
    int pir_light_brightness;
    bool presence_light_automation_enabled;
    const char *presence_light_target_id;
    bool temperature_ac_automation_enabled;
    int temperature_ac_on_threshold;
    int temperature_ac_off_threshold;
    int ac_uart_port;
    int ac_uart_tx_gpio;
    int ac_uart_rx_gpio;
    int ac_uart_baud_rate;
    int ac_ack_timeout_ms;
    int ac_health_interval_seconds;
    int ac_health_failure_threshold;
    const char *ac_brand;
    bool iotda_enabled;
    const char *iotda_broker_uri;
    const char *iotda_device_id;
    const char *iotda_password;
    int iotda_report_interval_seconds;
} gateway_config_t;

const gateway_config_t *gateway_config_get(void);
bool gateway_config_validate(void);
