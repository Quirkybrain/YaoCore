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
#include <stdint.h>
#include "esp_err.h"

#define YAOCORE_PROTOCOL_VERSION "2.0"
#define YAOCORE_SERVICE_ID "SmartHomeService"
#define YAOCORE_ALGORITHM "HMAC-SHA256"
#define YAOCORE_KEY_ID "app-key-v1"
#define YAOCORE_MAX_DEVICES 32
#define YAOCORE_MAX_ID 64
#define YAOCORE_MAX_MODE 16
#define YAOCORE_COLOR_HEX_SIZE 8
#define YAOCORE_MAX_REQUEST_ID 128
#define YAOCORE_MAX_STATE_SOURCE 32
#define YAOCORE_MAX_AUTOMATION_ID 64

typedef enum {
    DEVICE_DOOR,
    DEVICE_LIGHT,
    DEVICE_SENSOR,
    DEVICE_AC,
    DEVICE_SWITCH,
    DEVICE_CAMERA,
    DEVICE_GATEWAY,
    DEVICE_CURTAIN,
    DEVICE_FAN,
    DEVICE_SPEAKER,
} device_type_t;

typedef struct {
    char device_id[YAOCORE_MAX_ID];
    char name[64];
    char room[32];
    char brand[32];
    device_type_t type;
    bool online;
    bool power;
    bool open;
    int brightness;
    bool has_color;
    char color[YAOCORE_COLOR_HEX_SIZE];
    float temperature;
    float humidity;
    float target_temperature;
    char mode[YAOCORE_MAX_MODE];
    int position;
    int speed;
    int volume;
    bool has_environment;
    bool has_presence;
    bool presence;
    bool has_last_command;
    char last_request_id[YAOCORE_MAX_REQUEST_ID];
    int32_t last_seq;
    /* Provenance is state, not presentation-only metadata.  It lets LAN/cloud
     * consumers distinguish a physical sensor update, a phone command and a
     * gateway-local automation without guessing from the resulting value. */
    char state_source[YAOCORE_MAX_STATE_SOURCE];
    char trigger_device_id[YAOCORE_MAX_ID];
    char automation_id[YAOCORE_MAX_AUTOMATION_ID];
    /* External devices are owned by a separately powered southbound module.
     * module_id is stable across reconnects; protocol identifies its adapter. */
    bool external;
    char module_id[YAOCORE_MAX_ID];
    char protocol[32];
    int64_t updated_at_ms;
} device_state_t;

typedef enum { VALUE_NONE, VALUE_BOOL, VALUE_NUMBER, VALUE_STRING } command_value_type_t;

typedef struct {
    char request_id[YAOCORE_MAX_REQUEST_ID];
    int32_t cmd_id;
    int32_t seq;
    char target[YAOCORE_MAX_ID];
    char action[48];
    command_value_type_t value_type;
    bool bool_value;
    double number_value;
    char string_value[64];
    char timestamp[17];
    char nonce[65];
    char alg[32];
    char key_id[64];
    char sign[65];
    /* Internal provenance. These fields are assigned only after transport
     * authentication, or by the local automation engine itself. */
    char source[YAOCORE_MAX_STATE_SOURCE];
    char trigger_device_id[YAOCORE_MAX_ID];
    char automation_id[YAOCORE_MAX_AUTOMATION_ID];
} gateway_command_t;

typedef struct {
    int result_code;
    char error_code[48];
    char message[128];
    device_state_t reported_state;
    bool has_reported_state;
    bool idempotent_replay;
} gateway_ack_t;
