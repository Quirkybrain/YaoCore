/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <stddef.h>
#include "external_module.h"
#include "gateway_types.h"

typedef void (*device_router_state_callback_t)(const device_state_t *state,
    void *context);

esp_err_t device_router_init(void);
void device_router_set_state_callback(device_router_state_callback_t callback,
    void *context);
size_t device_router_snapshot(device_state_t *output, size_t capacity);
esp_err_t device_router_execute(const gateway_command_t *command, gateway_ack_t *ack);
bool device_router_gateway_led_state(void);
esp_err_t device_router_register_external(
    const external_device_registration_t *registration);
esp_err_t device_router_report_external(const char *module_id,
    const char *device_id, const external_state_patch_t *patch);
void device_router_mark_external_offline(const char *device_id);
