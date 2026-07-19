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
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "gateway_types.h"

typedef enum {
    HARDWARE_EVENT_DOOR,
    HARDWARE_EVENT_LIGHT,
    HARDWARE_EVENT_SENSOR,
    HARDWARE_EVENT_PRESENCE,
} hardware_event_kind_t;

typedef struct {
    hardware_event_kind_t kind;
    bool online;
    bool open;
    int brightness;
    float temperature;
    float humidity;
    bool presence;
} hardware_event_t;

typedef void (*hardware_event_callback_t)(const hardware_event_t *event, void *context);

typedef struct {
    bool door_online;
    bool door_open;
    bool light_online;
    int light_brightness;
    bool presence_online;
    bool presence;
    bool ac_online;
    device_state_t ac_state;
} hardware_initial_state_t;

/*
 * Initialise only configured physical drivers.  A disabled or failed driver is
 * reported offline; it is never replaced by a logical/simulated device.
 */
esp_err_t hardware_drivers_init(hardware_event_callback_t callback, void *context,
    hardware_initial_state_t *initial);

/* Keep physical execution and router state commit in one per-device transaction. */
void hardware_light_transaction_begin(void);
void hardware_light_transaction_end(void);
esp_err_t hardware_light_set_percent_locked(uint8_t percent);

/* When feedback is configured, success is returned only after matching readback. */
void hardware_door_transaction_begin(void);
void hardware_door_transaction_end(void);
esp_err_t hardware_door_set_locked(bool open, bool *confirmed_open,
    bool *feedback_confirmed);

/*
 * Send a structured UART request to the southbound controller.  reported_state
 * changes only after a matching structured ACK containing a full state snapshot.
 * received_ack distinguishes a remote rejection from a transport timeout.
 */
esp_err_t hardware_ac_execute(const gateway_command_t *command,
    device_state_t *reported_state, bool *state_confirmed, bool *received_ack,
    char *remote_message, size_t remote_message_size);

/*
 * Query the southbound bridge without changing AC state.  This uses the same
 * transaction mutex as hardware_ac_execute(), and therefore cannot consume a
 * business command's ACK.  A full, matching state snapshot is mandatory.
 */
esp_err_t hardware_ac_health_query(device_state_t *reported_state,
    bool *received_ack, char *remote_message, size_t remote_message_size);
