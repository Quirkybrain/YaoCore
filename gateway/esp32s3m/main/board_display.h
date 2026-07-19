/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include "esp_err.h"

/* Status display for the on-board 160x80 ST7735S LCD.  All
 * functions are safe to call when LCD initialization failed. */
esp_err_t board_display_init(void);
void board_display_show_starting(void);
void board_display_show_config_error(void);
void board_display_show_ble_error(void);
/* Shows the complete PoP only while the gateway is accepting BLE provisioning.
 * The next network-state screen clears it from the LCD. */
void board_display_show_provisioning(const char *service_name, const char *pop);
void board_display_show_connecting(void);
void board_display_show_connected(const char *ipv4);
void board_display_show_ready(const char *ipv4, int port);
void board_display_show_reconnecting(void);
void board_display_show_reset_countdown(int seconds_remaining);
void board_display_show_wifi_cleared(void);
void board_display_show_reset_failed(void);
void board_display_show_restarting(void);
