/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

#define NETWORK_CONNECTED_BIT BIT0
#define NETWORK_TIME_READY_BIT BIT1
#define NETWORK_PROVISIONING_BIT BIT2

void network_manager_start(void);
EventGroupHandle_t network_manager_events(void);
