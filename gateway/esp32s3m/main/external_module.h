/*
 * YaoCore (爻构) - authenticated southbound module protocol
 * Copyright (c) 2026 Zhang HaoXuan
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "gateway_types.h"

#define YAOCORE_MODULE_PROTOCOL "1.0"
#define YAOCORE_MAX_MODULES 24

typedef struct {
    bool has_online;
    bool online;
    bool has_power;
    bool power;
    bool has_open;
    bool open;
    bool has_brightness;
    int brightness;
    bool has_color;
    char color[YAOCORE_COLOR_HEX_SIZE];
    bool has_environment;
    float temperature;
    float humidity;
    bool has_presence;
    bool presence;
    bool has_target_temperature;
    float target_temperature;
    bool has_mode;
    char mode[YAOCORE_MAX_MODE];
    bool has_position;
    int position;
    bool has_speed;
    int speed;
    bool has_volume;
    int volume;
} external_state_patch_t;

typedef struct {
    char module_id[YAOCORE_MAX_ID];
    char device_id[YAOCORE_MAX_ID];
    char name[64];
    char room[32];
    char brand[32];
    char protocol[32];
    device_type_t type;
    uint16_t command_port;
    char command_path[64];
    uint32_t heartbeat_seconds;
    int64_t sequence;
    external_state_patch_t initial_state;
} external_device_registration_t;

typedef void (*external_module_offline_callback_t)(const char *device_id);

esp_err_t external_module_init(external_module_offline_callback_t offline_callback);
esp_err_t external_module_register(const external_device_registration_t *registration,
    const char *peer_ip);
void external_module_unregister(const char *module_id, const char *device_id);
esp_err_t external_module_touch(const char *module_id, int64_t sequence);
bool external_module_accept_sequence(const char *module_id, const char *device_id,
    int64_t sequence);
void external_module_note_response(const char *module_id, const char *device_id);
esp_err_t external_module_execute(const gateway_command_t *command,
    device_type_t expected_type, external_state_patch_t *reported_state,
    int *result_code, char *message, size_t message_size);
