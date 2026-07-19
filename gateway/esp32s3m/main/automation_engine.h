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
#include "gateway_types.h"

typedef bool (*automation_state_reader_t)(const char *device_id,
    device_state_t *state);
typedef esp_err_t (*automation_executor_t)(const gateway_command_t *command,
    gateway_ack_t *ack);

/* Rules run entirely on the gateway and therefore remain available without
 * Wi-Fi WAN/cloud access.  Their actions still travel through device_router,
 * so GPIO/UART confirmation and state reporting are identical to App control. */
esp_err_t automation_engine_init(automation_state_reader_t state_reader,
    automation_executor_t executor);
void automation_engine_on_sensor_state(const device_state_t *sensor_state);

/* A valid non-automation command releases rule ownership before actuation.
 * This establishes deterministic manual/scene/cloud precedence. */
void automation_engine_note_external_command(const gateway_command_t *command);
