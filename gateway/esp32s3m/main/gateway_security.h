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
#include "gateway_types.h"

esp_err_t gateway_security_init(void);
bool gateway_security_verify(const gateway_command_t *command, gateway_ack_t *error_ack);
bool gateway_security_get_cached(const gateway_command_t *command, gateway_ack_t *ack);
void gateway_security_cache_result(const gateway_command_t *command, const gateway_ack_t *ack);
bool gateway_security_format_canonical(const gateway_command_t *command, char *output, size_t output_size);
bool gateway_security_sign_response(const char *kind, const char *correlation,
    const char *response_body, char signature[65]);
bool gateway_security_verify_discovery_request(const char *challenge,
    const char *timestamp, const char *nonce, const char *algorithm,
    const char *key_id, const char *signature);
bool gateway_security_sign_module_message(const char *kind, const char *module_id,
    const char *timestamp, const char *nonce, const char *body,
    char signature[65]);
bool gateway_security_verify_module_message(const char *kind,
    const char *module_id, const char *timestamp, const char *nonce,
    const char *signature, const char *body);
