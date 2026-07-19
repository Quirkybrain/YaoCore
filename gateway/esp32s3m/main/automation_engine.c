/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "automation_engine.h"

#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "gateway_config.h"

#define AUTOMATION_SOURCE "automation.local"
#define PRESENCE_LIGHT_RULE "presence-light-v1"
#define TEMPERATURE_AC_RULE "temperature-ac-v1"

static const char *TAG = "automation";
static SemaphoreHandle_t s_lock;
static QueueHandle_t s_sensor_queue;
static automation_state_reader_t s_state_reader;
static automation_executor_t s_executor;
static bool s_presence_owns_light;
static bool s_temperature_owns_ac;
static int32_t s_sequence = 40000;

static void automation_task(void *arg);

static bool is_automation_command(const gateway_command_t *command)
{
    return command && !strcmp(command->source, AUTOMATION_SOURCE);
}

static void build_command(gateway_command_t *command, const char *rule_id,
    const char *trigger_id, const char *target, const char *action)
{
    memset(command, 0, sizeof(*command));
    ++s_sequence;
    if (s_sequence < 40000) s_sequence = 40000;
    snprintf(command->request_id, sizeof(command->request_id), "auto:%s:%lld:%ld",
        rule_id, (long long)(esp_timer_get_time() / 1000), (long)s_sequence);
    command->cmd_id = 4001;
    command->seq = s_sequence;
    strlcpy(command->target, target, sizeof(command->target));
    strlcpy(command->action, action, sizeof(command->action));
    command->value_type = VALUE_NONE;
    strlcpy(command->source, AUTOMATION_SOURCE, sizeof(command->source));
    strlcpy(command->trigger_device_id, trigger_id,
        sizeof(command->trigger_device_id));
    strlcpy(command->automation_id, rule_id, sizeof(command->automation_id));
}

static bool execute_rule(gateway_command_t *command)
{
    gateway_ack_t ack;
    memset(&ack, 0, sizeof(ack));
    esp_err_t result = s_executor(command, &ack);
    if (result != ESP_OK || ack.result_code != 0 || !ack.has_reported_state) {
        ESP_LOGW(TAG, "rule=%s trigger=%s target=%s action=%s failed: %s (%d)",
            command->automation_id, command->trigger_device_id, command->target,
            command->action, ack.message[0] ? ack.message : esp_err_to_name(result),
            ack.result_code);
        return false;
    }
    ESP_LOGI(TAG, "rule=%s trigger=%s target=%s action=%s confirmed",
        command->automation_id, command->trigger_device_id, command->target,
        command->action);
    return true;
}

static void run_presence_light(const device_state_t *sensor)
{
    const gateway_config_t *config = gateway_config_get();
    if (!config->presence_light_automation_enabled || !sensor->online ||
        !sensor->has_presence) return;

    device_state_t target;
    const char *target_id = config->presence_light_target_id;
    if (!target_id || !target_id[0] || !s_state_reader(target_id, &target) ||
        !target.online || target.type != DEVICE_LIGHT) return;

    gateway_command_t command;
    if (sensor->presence) {
        /* Do not take ownership of a light that was already enabled manually. */
        if (target.power || s_presence_owns_light) return;
        build_command(&command, PRESENCE_LIGHT_RULE, sensor->device_id,
            target_id, "SET_BRIGHTNESS");
        command.value_type = VALUE_NUMBER;
        command.number_value = config->pir_light_brightness;
        s_presence_owns_light = execute_rule(&command);
    } else if (s_presence_owns_light) {
        if (!target.power) {
            s_presence_owns_light = false;
            return;
        }
        build_command(&command, PRESENCE_LIGHT_RULE, sensor->device_id,
            target_id, "OFF");
        if (execute_rule(&command)) s_presence_owns_light = false;
    }
}

static void run_temperature_ac(const device_state_t *sensor)
{
    const gateway_config_t *config = gateway_config_get();
    if (!config->temperature_ac_automation_enabled || !sensor->online ||
        !sensor->has_environment) return;

    device_state_t target;
    if (!s_state_reader("AC_01", &target) || !target.online) return;

    gateway_command_t command;
    if (sensor->temperature >= config->temperature_ac_on_threshold) {
        /* Existing manual AC operation is observed but never claimed. */
        if (target.power || s_temperature_owns_ac) return;
        build_command(&command, TEMPERATURE_AC_RULE, sensor->device_id,
            "AC_01", "ON");
        s_temperature_owns_ac = execute_rule(&command);
    } else if (sensor->temperature <= config->temperature_ac_off_threshold &&
        s_temperature_owns_ac) {
        if (!target.power) {
            s_temperature_owns_ac = false;
            return;
        }
        build_command(&command, TEMPERATURE_AC_RULE, sensor->device_id,
            "AC_01", "OFF");
        if (execute_rule(&command)) s_temperature_owns_ac = false;
    }
}

esp_err_t automation_engine_init(automation_state_reader_t state_reader,
    automation_executor_t executor)
{
    if (!state_reader || !executor) return ESP_ERR_INVALID_ARG;
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) return ESP_ERR_NO_MEM;
    s_sensor_queue = xQueueCreate(8, sizeof(device_state_t));
    if (!s_sensor_queue) return ESP_ERR_NO_MEM;
    s_state_reader = state_reader;
    s_executor = executor;
    s_presence_owns_light = false;
    s_temperature_owns_ac = false;
    if (xTaskCreate(automation_task, "automation", 6144, NULL, 5, NULL) !=
        pdPASS) return ESP_ERR_NO_MEM;
    ESP_LOGI(TAG, "local rules ready: presence-light=%s temperature-AC=%s",
        gateway_config_get()->presence_light_automation_enabled ? "enabled" : "disabled",
        gateway_config_get()->temperature_ac_automation_enabled ? "enabled" : "disabled");
    return ESP_OK;
}

void automation_engine_on_sensor_state(const device_state_t *sensor_state)
{
    if (!sensor_state || !s_sensor_queue) return;
    if (xQueueSend(s_sensor_queue, sensor_state, 0) != pdTRUE) {
        ESP_LOGW(TAG, "sensor automation queue full; dropped state from %s",
            sensor_state->device_id);
    }
}

static void automation_task(void *arg)
{
    (void)arg;
    device_state_t sensor;
    while (true) {
        if (xQueueReceive(s_sensor_queue, &sensor, portMAX_DELAY) != pdTRUE)
            continue;
        xSemaphoreTake(s_lock, portMAX_DELAY);
        /* Capabilities, rather than a vendor-specific sensor ID, select
         * rules. Running outside the HTTP handler also prevents a sensor
         * module from deadlocking while the gateway calls an actuator on the
         * same southbound module. */
        if (sensor.has_presence) run_presence_light(&sensor);
        if (sensor.has_environment) run_temperature_ac(&sensor);
        xSemaphoreGive(s_lock);
    }
}

void automation_engine_note_external_command(const gateway_command_t *command)
{
    if (!command || !s_lock || is_automation_command(command)) return;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    const char *light_target = gateway_config_get()->presence_light_target_id;
    if (light_target && !strcmp(command->target, light_target))
        s_presence_owns_light = false;
    if (!strcmp(command->target, "AC_01")) s_temperature_owns_ac = false;
    xSemaphoreGive(s_lock);
}
