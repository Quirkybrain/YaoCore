/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "local_server.h"
#include <errno.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <time.h>
#include <unistd.h>
#include "cJSON.h"
#include "esp_http_server.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_random.h"
#include "mdns.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "device_router.h"
#include "gateway_config.h"
#include "gateway_security.h"
#include "gateway_types.h"
#include "external_module.h"

static const char *TAG = "local_server";
static httpd_handle_t s_httpd;

/* Authentication responses contain several small integrity headers.  On
 * networks with delayed ACKs, Nagle coalescing can hold those headers long
 * enough for a phone to time out even though the gateway is reachable.  A
 * mains-powered gateway favours deterministic LAN latency over saving a few
 * packets, so disable Nagle for every accepted HTTP connection. */
static esp_err_t configure_client_socket(httpd_handle_t server, int socket_fd)
{
    (void)server;
    int enabled = 1;
    if (setsockopt(socket_fd, IPPROTO_TCP, TCP_NODELAY, &enabled,
                   sizeof(enabled)) < 0) {
        ESP_LOGW(TAG, "unable to enable TCP_NODELAY for socket %d: errno=%d",
                 socket_fd, errno);
    }
    return ESP_OK;
}

bool local_server_is_started(void)
{
    return s_httpd != NULL;
}

static esp_err_t send_conflict(httpd_req_t *req, const char *message)
{
    httpd_resp_set_status(req, "409 Conflict");
    httpd_resp_set_type(req, "text/plain");
    return httpd_resp_sendstr(req, message);
}

static bool is_lower_hex_challenge(const char *value)
{
    if (!value || strlen(value) != 32) return false;
    for (size_t i = 0; i < 32; ++i) {
        if (!((value[i] >= '0' && value[i] <= '9') ||
            (value[i] >= 'a' && value[i] <= 'f'))) return false;
    }
    return true;
}

static bool read_discovery_challenge(httpd_req_t *req, char challenge[33])
{
    if (httpd_req_get_hdr_value_len(req, "X-YaoCore-Challenge") != 32) {
        return false;
    }
    if (httpd_req_get_hdr_value_str(req, "X-YaoCore-Challenge", challenge,
        33) != ESP_OK) return false;
    return is_lower_hex_challenge(challenge);
}

static esp_err_t set_authenticated_response_headers(httpd_req_t *req,
    const char *kind, const char *correlation, const char *body,
    char signature[65])
{
    if (!gateway_security_sign_response(kind, correlation, body, signature)) {
        ESP_LOGE(TAG, "unable to sign %s response", kind);
        return ESP_FAIL;
    }
    esp_err_t err = httpd_resp_set_hdr(req, "X-YaoCore-Response-Alg",
        YAOCORE_ALGORITHM);
    if (err == ESP_OK) err = httpd_resp_set_hdr(req, "X-YaoCore-Key-Id",
        YAOCORE_KEY_ID);
    if (err == ESP_OK) err = httpd_resp_set_hdr(req,
        "X-YaoCore-Response-Correlation", correlation);
    if (err == ESP_OK) err = httpd_resp_set_hdr(req,
        "X-YaoCore-Response-Sign", signature);
    return err;
}

static const char *type_name(device_type_t type)
{
    const char *names[] = {"door", "light", "sensor", "ac", "switch", "camera",
        "gateway", "curtain", "fan", "speaker"};
    return type <= DEVICE_SPEAKER ? names[type] : "switch";
}

static void format_timestamp(char output[17])
{
    time_t now = time(NULL); struct tm utc; gmtime_r(&now, &utc);
    strftime(output, 17, "%Y%m%dT%H%M%SZ", &utc);
}

static void format_state_timestamp(int64_t updated_monotonic_ms, char output[17])
{
    time_t wall_now = time(NULL);
    int64_t monotonic_now_ms = esp_timer_get_time() / 1000;
    int64_t age_seconds = updated_monotonic_ms > 0 &&
        monotonic_now_ms > updated_monotonic_ms ?
        (monotonic_now_ms - updated_monotonic_ms) / 1000 : 0;
    time_t wall_updated = wall_now - (time_t)age_seconds;
    struct tm utc;
    gmtime_r(&wall_updated, &utc);
    strftime(output, 17, "%Y%m%dT%H%M%SZ", &utc);
}

static cJSON *state_json(const device_state_t *d)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "deviceId", d->device_id); cJSON_AddStringToObject(j, "deviceName", d->name);
    cJSON_AddStringToObject(j, "roomName", d->room); cJSON_AddStringToObject(j, "deviceType", type_name(d->type));
    if (d->brand[0]) cJSON_AddStringToObject(j, "brand", d->brand);
    cJSON_AddStringToObject(j, "protocol", d->protocol[0] ? d->protocol : "direct");
    if (d->external) {
        cJSON_AddBoolToObject(j, "external", true);
        cJSON_AddStringToObject(j, "moduleId", d->module_id);
    }
    cJSON_AddBoolToObject(j, "online", d->online);
    if (d->type == DEVICE_DOOR && d->online &&
        (d->external || gateway_config_get()->door_feedback_gpio >= 0))
        cJSON_AddBoolToObject(j, "open", d->open);
    if ((d->type == DEVICE_LIGHT || d->type == DEVICE_SWITCH || d->type == DEVICE_AC) && d->online) cJSON_AddBoolToObject(j, "power", d->power);
    if (d->type == DEVICE_LIGHT && d->online) cJSON_AddNumberToObject(j, "brightness", d->brightness);
    if (d->type == DEVICE_LIGHT && d->online && d->has_color)
        cJSON_AddStringToObject(j, "color", d->color);
    if (d->has_environment && d->online) { cJSON_AddNumberToObject(j, "temperature", d->temperature); cJSON_AddNumberToObject(j, "humidity", d->humidity); }
    if (d->has_presence && d->online) cJSON_AddBoolToObject(j, "presence", d->presence);
    if (d->type == DEVICE_AC && d->online) { cJSON_AddNumberToObject(j, "targetTemp", d->target_temperature); cJSON_AddStringToObject(j, "mode", d->mode); }
    if (d->type == DEVICE_CURTAIN && d->online) cJSON_AddNumberToObject(j, "position", d->position);
    if (d->type == DEVICE_FAN && d->online) cJSON_AddNumberToObject(j, "speed", d->speed);
    if (d->type == DEVICE_SPEAKER && d->online) cJSON_AddNumberToObject(j, "volume", d->volume);
    if (d->has_last_command) { cJSON_AddStringToObject(j, "lastRequestId", d->last_request_id); cJSON_AddNumberToObject(j, "lastSeq", d->last_seq); }
    if (d->state_source[0]) cJSON_AddStringToObject(j, "stateSource", d->state_source);
    if (d->trigger_device_id[0]) cJSON_AddStringToObject(j, "triggerDeviceId", d->trigger_device_id);
    if (d->automation_id[0]) cJSON_AddStringToObject(j, "automationId", d->automation_id);
    char timestamp[17]; format_state_timestamp(d->updated_at_ms, timestamp); cJSON_AddStringToObject(j, "updatedAt", timestamp); return j;
}

static cJSON *reported_state_json(const device_state_t *d)
{
    cJSON *j = cJSON_CreateObject(); cJSON_AddStringToObject(j, "deviceId", d->device_id);
    cJSON_AddStringToObject(j, "deviceName", d->name);
    cJSON_AddStringToObject(j, "roomName", d->room);
    cJSON_AddStringToObject(j, "deviceType", type_name(d->type));
    if (d->brand[0]) cJSON_AddStringToObject(j, "brand", d->brand);
    cJSON_AddStringToObject(j, "protocol", d->protocol[0] ? d->protocol : "direct");
    if (d->external) cJSON_AddStringToObject(j, "moduleId", d->module_id);
    cJSON_AddBoolToObject(j, "online", d->online);
    if (d->type == DEVICE_DOOR && d->online &&
        (d->external || gateway_config_get()->door_feedback_gpio >= 0))
        cJSON_AddBoolToObject(j, "open", d->open);
    if ((d->type == DEVICE_LIGHT || d->type == DEVICE_SWITCH || d->type == DEVICE_AC) && d->online) cJSON_AddBoolToObject(j, "power", d->power);
    if (d->type == DEVICE_LIGHT && d->online) cJSON_AddNumberToObject(j, "brightness", d->brightness);
    if (d->type == DEVICE_LIGHT && d->online && d->has_color)
        cJSON_AddStringToObject(j, "color", d->color);
    if (d->has_environment && d->online) { cJSON_AddNumberToObject(j, "temperature", d->temperature); cJSON_AddNumberToObject(j, "humidity", d->humidity); }
    if (d->has_presence && d->online) cJSON_AddBoolToObject(j, "presence", d->presence);
    if (d->type == DEVICE_AC && d->online) { cJSON_AddNumberToObject(j, "targetTemp", d->target_temperature); cJSON_AddStringToObject(j, "mode", d->mode); }
    if (d->type == DEVICE_CURTAIN && d->online) cJSON_AddNumberToObject(j, "position", d->position);
    if (d->type == DEVICE_FAN && d->online) cJSON_AddNumberToObject(j, "speed", d->speed);
    if (d->type == DEVICE_SPEAKER && d->online) cJSON_AddNumberToObject(j, "volume", d->volume);
    if (d->has_last_command) { cJSON_AddStringToObject(j, "lastRequestId", d->last_request_id); cJSON_AddNumberToObject(j, "lastSeq", d->last_seq); }
    if (d->state_source[0]) cJSON_AddStringToObject(j, "stateSource", d->state_source);
    if (d->trigger_device_id[0]) cJSON_AddStringToObject(j, "triggerDeviceId", d->trigger_device_id);
    if (d->automation_id[0]) cJSON_AddStringToObject(j, "automationId", d->automation_id);
    char timestamp[17]; format_state_timestamp(d->updated_at_ms, timestamp); cJSON_AddStringToObject(j, "updatedAt", timestamp); return j;
}

char *local_server_create_discovery_json(void)
{
    const gateway_config_t *cfg = gateway_config_get();
    cJSON *root = cJSON_CreateObject(); cJSON_AddStringToObject(root, "protocolVersion", YAOCORE_PROTOCOL_VERSION);
    cJSON_AddStringToObject(root, "gatewayId", cfg->gateway_id); cJSON_AddStringToObject(root, "gatewayName", cfg->gateway_name);
    cJSON_AddStringToObject(root, "serviceId", YAOCORE_SERVICE_ID); char now[17]; format_timestamp(now); cJSON_AddStringToObject(root, "generatedAt", now);
    cJSON *security = cJSON_AddObjectToObject(root, "security"); cJSON_AddStringToObject(security, "alg", YAOCORE_ALGORITHM);
    cJSON_AddStringToObject(security, "keyId", YAOCORE_KEY_ID); cJSON_AddNumberToObject(security, "timeWindowSeconds", 120);
    cJSON_AddNumberToObject(security, "nonceTtlSeconds", 300); cJSON *devices = cJSON_AddArrayToObject(root, "devices");

    /* A full 32-device snapshot is much larger than the HTTP task's stack.
     * Keeping it as a local array corrupted the scheduler stack on every
     * authenticated /discover request, rebooting the gateway at App progress
     * 96%.  Place this bounded, short-lived snapshot in the board's PSRAM. */
    device_state_t *snapshot = heap_caps_calloc(YAOCORE_MAX_DEVICES,
        sizeof(device_state_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (snapshot == NULL) {
        ESP_LOGE(TAG, "unable to allocate discovery snapshot in PSRAM");
        cJSON_Delete(root);
        return NULL;
    }
    size_t count = device_router_snapshot(snapshot, YAOCORE_MAX_DEVICES);
    for (size_t i = 0; i < count; ++i) {
        cJSON *state = state_json(&snapshot[i]);
        if (state == NULL) {
            heap_caps_free(snapshot);
            cJSON_Delete(root);
            return NULL;
        }
        cJSON_AddItemToArray(devices, state);
    }
    heap_caps_free(snapshot);
    char *json = cJSON_PrintUnformatted(root); cJSON_Delete(root); return json;
}

static char *create_udp_candidate_json(void)
{
    const gateway_config_t *config = gateway_config_get();
    cJSON *root = cJSON_CreateObject();
    if (!root) return NULL;
    cJSON_AddStringToObject(root, "protocolVersion", YAOCORE_PROTOCOL_VERSION);
    cJSON_AddStringToObject(root, "gatewayId", config->gateway_id);
    cJSON_AddStringToObject(root, "gatewayName", config->gateway_name);
    cJSON_AddStringToObject(root, "serviceId", YAOCORE_SERVICE_ID);
    cJSON_AddNumberToObject(root, "port", config->local_port);
    char *json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return json;
}

static esp_err_t discover_handler(httpd_req_t *req)
{
    char challenge[33];
    if (!read_discovery_challenge(req, challenge)) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST,
            "missing or invalid X-YaoCore-Challenge");
    }
    size_t algorithm_length = httpd_req_get_hdr_value_len(req,
        "X-YaoCore-Request-Alg");
    size_t key_id_length = httpd_req_get_hdr_value_len(req,
        "X-YaoCore-Key-Id");
    size_t signature_length = httpd_req_get_hdr_value_len(req,
        "X-YaoCore-Request-Sign");
    size_t timestamp_length = httpd_req_get_hdr_value_len(req,
        "X-YaoCore-Request-Timestamp");
    size_t nonce_length = httpd_req_get_hdr_value_len(req,
        "X-YaoCore-Request-Nonce");
    if (algorithm_length == 0 || key_id_length == 0 || signature_length == 0 ||
        timestamp_length == 0 || nonce_length == 0) {
        return httpd_resp_send_err(req, HTTPD_401_UNAUTHORIZED,
            "discovery request authentication required");
    }
    char timestamp[17], nonce[33], algorithm[32], key_id[64], request_signature[65];
    if (algorithm_length >= sizeof(algorithm) || key_id_length >= sizeof(key_id) ||
        signature_length != 64 || timestamp_length != 16 || nonce_length != 32 ||
        httpd_req_get_hdr_value_str(req, "X-YaoCore-Request-Timestamp",
            timestamp, sizeof(timestamp)) != ESP_OK ||
        httpd_req_get_hdr_value_str(req, "X-YaoCore-Request-Nonce", nonce,
            sizeof(nonce)) != ESP_OK ||
        httpd_req_get_hdr_value_str(req, "X-YaoCore-Request-Alg", algorithm,
            sizeof(algorithm)) != ESP_OK ||
        httpd_req_get_hdr_value_str(req, "X-YaoCore-Key-Id", key_id,
            sizeof(key_id)) != ESP_OK ||
        httpd_req_get_hdr_value_str(req, "X-YaoCore-Request-Sign",
            request_signature, sizeof(request_signature)) != ESP_OK ||
        !gateway_security_verify_discovery_request(challenge, timestamp, nonce,
            algorithm, key_id, request_signature)) {
        return httpd_resp_send_err(req, HTTPD_403_FORBIDDEN,
            "invalid discovery request authentication");
    }
    char *json = local_server_create_discovery_json(); if (!json) return ESP_ERR_NO_MEM;
    httpd_resp_set_type(req, "application/json"); httpd_resp_set_hdr(req, "X-YaoCore-Protocol", "2");
    char signature[65];
    if (set_authenticated_response_headers(req, "discover", challenge, json,
        signature) != ESP_OK) {
        free(json);
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
            "response authentication unavailable");
    }
    esp_err_t result = httpd_resp_sendstr(req, json);
    if (result != ESP_OK) {
        ESP_LOGW(TAG, "authenticated discovery response send failed: %s",
                 esp_err_to_name(result));
    }
    free(json);
    return result;
}

static bool copy_string(cJSON *root, const char *name, char *dest, size_t size)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(root, name);
    if (!cJSON_IsString(item) || !item->valuestring || strlen(item->valuestring) >= size) return false;
    strlcpy(dest, item->valuestring, size); return true;
}

static bool parse_command(const char *body, gateway_command_t *cmd)
{
    cJSON *root = cJSON_Parse(body); if (!root) return false; memset(cmd, 0, sizeof(*cmd));
    cJSON *cmd_id = cJSON_GetObjectItemCaseSensitive(root, "cmd_id"), *seq = cJSON_GetObjectItemCaseSensitive(root, "seq");
    cJSON *payload = cJSON_GetObjectItemCaseSensitive(root, "payload");
    bool ok = cJSON_IsNumber(cmd_id) && cJSON_IsNumber(seq) && cJSON_IsObject(payload) &&
        copy_string(root, "request_id", cmd->request_id, sizeof(cmd->request_id)) &&
        copy_string(root, "target", cmd->target, sizeof(cmd->target)) &&
        copy_string(root, "timestamp", cmd->timestamp, sizeof(cmd->timestamp)) &&
        copy_string(root, "nonce", cmd->nonce, sizeof(cmd->nonce)) && copy_string(root, "alg", cmd->alg, sizeof(cmd->alg)) &&
        copy_string(root, "key_id", cmd->key_id, sizeof(cmd->key_id)) && copy_string(root, "sign", cmd->sign, sizeof(cmd->sign)) &&
        copy_string(payload, "action", cmd->action, sizeof(cmd->action));
    if (ok) { cmd->cmd_id = cmd_id->valueint; cmd->seq = seq->valueint; cJSON *value = cJSON_GetObjectItemCaseSensitive(payload, "value");
        if (!value) cmd->value_type = VALUE_NONE;
        else if (cJSON_IsBool(value)) { cmd->value_type = VALUE_BOOL; cmd->bool_value = cJSON_IsTrue(value); }
        else if (cJSON_IsNumber(value)) { cmd->value_type = VALUE_NUMBER; cmd->number_value = value->valuedouble; }
        else if (cJSON_IsString(value) && strlen(value->valuestring) < sizeof(cmd->string_value)) {
            cmd->value_type = VALUE_STRING; strlcpy(cmd->string_value, value->valuestring, sizeof(cmd->string_value));
        } else ok = false;
    }
    cJSON_Delete(root); return ok && cmd->cmd_id == 2001 && cmd->seq >= 0;
}

static char *ack_json(const gateway_command_t *cmd, const gateway_ack_t *ack)
{
    cJSON *root = cJSON_CreateObject(); cJSON_AddStringToObject(root, "request_id", cmd->request_id); cJSON_AddNumberToObject(root, "seq", cmd->seq);
    cJSON_AddNumberToObject(root, "result_code", ack->result_code); cJSON_AddStringToObject(root, "message", ack->message);
    if (ack->error_code[0]) cJSON_AddStringToObject(root, "error_code", ack->error_code);
    char server_time[17]; format_timestamp(server_time); cJSON_AddStringToObject(root, "server_time", server_time);
    if (ack->has_reported_state) cJSON_AddItemToObject(root, "reported_state", reported_state_json(&ack->reported_state));
    else if (ack->result_code == 0) { cJSON *gateway = cJSON_AddObjectToObject(root, "reported_state");
        cJSON_AddStringToObject(gateway, "gatewayId", gateway_config_get()->gateway_id); cJSON_AddBoolToObject(gateway, "online", true);
        cJSON_AddBoolToObject(gateway, "boardLed", device_router_gateway_led_state()); cJSON_AddStringToObject(gateway, "updatedAt", server_time); }
    if (ack->idempotent_replay) cJSON_AddBoolToObject(root, "idempotent_replay", true);
    char *json = cJSON_PrintUnformatted(root); cJSON_Delete(root); return json;
}

static int status_for_ack(const gateway_ack_t *ack)
{
    if (ack->result_code == 0) return 200;
    if (ack->result_code == 1002) return 401;
    if (ack->result_code == 1003 || ack->result_code == 1004) return 403;
    if (ack->result_code == 1005) return 409;
    if (ack->result_code == 1006) return 503;
    return 422;
}

static esp_err_t control_handler(httpd_req_t *req)
{
    if (req->content_len <= 0 || req->content_len > 2048) return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body length");
    char *body = calloc(1, req->content_len + 1); if (!body) return ESP_ERR_NO_MEM;
    size_t received = 0;
    unsigned timeouts = 0;
    while (received < (size_t)req->content_len) {
        int chunk = httpd_req_recv(req, body + received, req->content_len - received);
        if (chunk == HTTPD_SOCK_ERR_TIMEOUT && ++timeouts <= 3) continue;
        if (chunk <= 0) {
            free(body);
            return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "incomplete body");
        }
        received += (size_t)chunk;
        timeouts = 0;
    }
    gateway_command_t cmd; gateway_ack_t ack;
    if (!parse_command(body, &cmd)) { free(body); return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid command schema"); } free(body);
    if (!gateway_security_get_cached(&cmd, &ack)) {
        if (gateway_security_verify(&cmd, &ack)) {
            strlcpy(cmd.source, "app.lan", sizeof(cmd.source));
            device_router_execute(&cmd, &ack);
            gateway_security_cache_result(&cmd, &ack);
        }
    }
    int status = status_for_ack(&ack);
    httpd_resp_set_status(req, status == 200 ? "200 OK" :
        status == 409 ? "409 Conflict" :
        status == 401 ? "401 Unauthorized" :
        status == 403 ? "403 Forbidden" :
        status == 503 ? "503 Service Unavailable" :
        "422 Unprocessable Entity");
    char *json = ack_json(&cmd, &ack);
    if (!json) return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
        "ACK serialization failed");
    char correlation[160];
    char signature[65];
    int correlation_length = snprintf(correlation, sizeof(correlation), "%s:%d",
        cmd.request_id, (int)cmd.seq);
    if (correlation_length <= 0 || (size_t)correlation_length >= sizeof(correlation) ||
        set_authenticated_response_headers(req, "control", correlation, json,
            signature) != ESP_OK) {
        free(json);
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
            "response authentication unavailable");
    }
    httpd_resp_set_type(req, "application/json");
    esp_err_t result = httpd_resp_sendstr(req, json); free(json); return result;
}

static esp_err_t read_json_body(httpd_req_t *req, char **output)
{
    if (!req || !output || req->content_len <= 0 || req->content_len > 4096)
        return ESP_ERR_INVALID_SIZE;
    char *body = calloc(1, req->content_len + 1);
    if (!body) return ESP_ERR_NO_MEM;
    size_t received = 0; unsigned timeouts = 0;
    while (received < (size_t)req->content_len) {
        int count = httpd_req_recv(req, body + received,
            req->content_len - received);
        if (count == HTTPD_SOCK_ERR_TIMEOUT && ++timeouts <= 3) continue;
        if (count <= 0) { free(body); return ESP_FAIL; }
        received += (size_t)count; timeouts = 0;
    }
    body[received] = '\0'; *output = body; return ESP_OK;
}

static bool header_exact(httpd_req_t *req, const char *name,
    char *output, size_t output_size)
{
    size_t length = httpd_req_get_hdr_value_len(req, name);
    return length > 0 && length < output_size &&
        httpd_req_get_hdr_value_str(req, name, output, output_size) == ESP_OK;
}

static bool verify_module_request(httpd_req_t *req, const char *kind,
    const char *module_id, const char *body)
{
    char algorithm[32], key_id[64], header_module[YAOCORE_MAX_ID];
    char timestamp[17], nonce[65], signature[65];
    if (!header_exact(req, "X-YaoCore-Alg", algorithm, sizeof(algorithm)) ||
        !header_exact(req, "X-YaoCore-Key-Id", key_id, sizeof(key_id)) ||
        !header_exact(req, "X-YaoCore-Module-Id", header_module,
            sizeof(header_module)) ||
        !header_exact(req, "X-YaoCore-Timestamp", timestamp,
            sizeof(timestamp)) ||
        !header_exact(req, "X-YaoCore-Nonce", nonce, sizeof(nonce)) ||
        !header_exact(req, "X-YaoCore-Sign", signature, sizeof(signature)) ||
        strcmp(algorithm, YAOCORE_ALGORITHM) || strcmp(key_id, YAOCORE_KEY_ID) ||
        strcmp(header_module, module_id)) return false;
    return gateway_security_verify_module_message(kind, module_id, timestamp,
        nonce, signature, body);
}

static void module_timestamp(char output[17])
{
    time_t now = time(NULL); struct tm utc; gmtime_r(&now, &utc);
    strftime(output, 17, "%Y%m%dT%H%M%SZ", &utc);
}

static void module_nonce(char output[65])
{
    uint8_t bytes[32]; esp_fill_random(bytes, sizeof(bytes));
    for (size_t i = 0; i < sizeof(bytes); ++i) snprintf(output + i * 2, 3,
        "%02x", bytes[i]);
    output[64] = '\0';
}

static esp_err_t send_module_ack(httpd_req_t *req, const char *module_id,
    int result_code, const char *message)
{
    cJSON *root = cJSON_CreateObject();
    if (!root) return ESP_ERR_NO_MEM;
    cJSON_AddStringToObject(root, "protocolVersion", YAOCORE_MODULE_PROTOCOL);
    cJSON_AddNumberToObject(root, "resultCode", result_code);
    cJSON_AddStringToObject(root, "message", message ? message : "");
    char *body = cJSON_PrintUnformatted(root); cJSON_Delete(root);
    if (!body) return ESP_ERR_NO_MEM;
    char timestamp[17], nonce[65], signature[65];
    module_timestamp(timestamp); module_nonce(nonce);
    if (!gateway_security_sign_module_message("gateway_ack", module_id,
        timestamp, nonce, body, signature)) { free(body); return ESP_FAIL; }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "X-YaoCore-Alg", YAOCORE_ALGORITHM);
    httpd_resp_set_hdr(req, "X-YaoCore-Key-Id", YAOCORE_KEY_ID);
    httpd_resp_set_hdr(req, "X-YaoCore-Module-Id", module_id);
    httpd_resp_set_hdr(req, "X-YaoCore-Timestamp", timestamp);
    httpd_resp_set_hdr(req, "X-YaoCore-Nonce", nonce);
    httpd_resp_set_hdr(req, "X-YaoCore-Sign", signature);
    esp_err_t result = httpd_resp_sendstr(req, body); free(body); return result;
}

static bool json_string(cJSON *object, const char *name, char *output,
    size_t output_size)
{
    cJSON *value = cJSON_GetObjectItemCaseSensitive(object, name);
    if (!cJSON_IsString(value) || !value->valuestring ||
        strlen(value->valuestring) >= output_size) return false;
    strlcpy(output, value->valuestring, output_size); return true;
}

static bool module_identifier(const char *value)
{
    if (!value || !value[0] || strlen(value) >= YAOCORE_MAX_ID) return false;
    for (size_t i = 0; value[i]; ++i) {
        bool alpha_numeric = (value[i] >= '0' && value[i] <= '9') ||
            (value[i] >= 'A' && value[i] <= 'Z') ||
            (value[i] >= 'a' && value[i] <= 'z');
        bool separator = value[i] == '_' || value[i] == '-' ||
            value[i] == '.' || value[i] == ':';
        if ((!alpha_numeric && !separator) || (i == 0 && !alpha_numeric))
            return false;
    }
    return true;
}

static bool module_type(const char *name, device_type_t *type)
{
    if (!name || !type) return false;
    const char *names[] = {"door", "light", "sensor", "ac", "switch", "camera",
        "gateway", "curtain", "fan", "speaker"};
    for (size_t i = 0; i <= DEVICE_SPEAKER; ++i) {
        if (!strcmp(name, names[i])) { *type = (device_type_t)i; return true; }
    }
    return false;
}

static bool module_mode(const char *mode)
{
    const char *modes[] = { "AUTO", "COOL", "HEAT", "DRY", "FAN", "ECO",
        "SLEEP" };
    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); ++i) {
        if (!strcmp(mode, modes[i])) return true;
    }
    return false;
}

static bool module_color(const char *color)
{
    if (!color || strlen(color) != 7 || color[0] != '#') return false;
    for (size_t i = 1; i < 7; ++i) {
        bool digit = color[i] >= '0' && color[i] <= '9';
        bool upper = color[i] >= 'A' && color[i] <= 'F';
        if (!digit && !upper) return false;
    }
    return true;
}

static bool module_command_path(const char *path)
{
    if (!path || path[0] != '/' || strlen(path) >= 64) return false;
    for (size_t i = 0; path[i]; ++i) {
        bool alpha_numeric = (path[i] >= '0' && path[i] <= '9') ||
            (path[i] >= 'A' && path[i] <= 'Z') ||
            (path[i] >= 'a' && path[i] <= 'z');
        if (!alpha_numeric && path[i] != '/' && path[i] != '_' &&
            path[i] != '-' && path[i] != '.') return false;
    }
    return true;
}

static bool module_state_patch(cJSON *state, external_state_patch_t *patch)
{
    if (!cJSON_IsObject(state) || !patch) return false;
    memset(patch, 0, sizeof(*patch));
    cJSON *value = cJSON_GetObjectItemCaseSensitive(state, "online");
    if (cJSON_IsBool(value)) { patch->has_online = true; patch->online = cJSON_IsTrue(value); }
    value = cJSON_GetObjectItemCaseSensitive(state, "power");
    if (cJSON_IsBool(value)) { patch->has_power = true; patch->power = cJSON_IsTrue(value); }
    value = cJSON_GetObjectItemCaseSensitive(state, "open");
    if (cJSON_IsBool(value)) { patch->has_open = true; patch->open = cJSON_IsTrue(value); }
    value = cJSON_GetObjectItemCaseSensitive(state, "brightness");
    if (cJSON_IsNumber(value) && value->valueint >= 0 && value->valueint <= 100) {
        patch->has_brightness = true; patch->brightness = value->valueint;
    }
    value = cJSON_GetObjectItemCaseSensitive(state, "color");
    if (cJSON_IsString(value) && module_color(value->valuestring)) {
        patch->has_color = true;
        strlcpy(patch->color, value->valuestring, sizeof(patch->color));
    }
    cJSON *temperature = cJSON_GetObjectItemCaseSensitive(state, "temperature");
    cJSON *humidity = cJSON_GetObjectItemCaseSensitive(state, "humidity");
    if (cJSON_IsNumber(temperature) && temperature->valuedouble >= -50 &&
        temperature->valuedouble <= 100 && cJSON_IsNumber(humidity) &&
        humidity->valuedouble >= 0 && humidity->valuedouble <= 100) {
        patch->has_environment = true; patch->temperature = temperature->valuedouble;
        patch->humidity = humidity->valuedouble;
    }
    value = cJSON_GetObjectItemCaseSensitive(state, "presence");
    if (cJSON_IsBool(value)) { patch->has_presence = true; patch->presence = cJSON_IsTrue(value); }
    value = cJSON_GetObjectItemCaseSensitive(state, "targetTemperature");
    if (cJSON_IsNumber(value) && value->valuedouble >= 16 && value->valuedouble <= 30) {
        patch->has_target_temperature = true;
        patch->target_temperature = value->valuedouble;
    }
    value = cJSON_GetObjectItemCaseSensitive(state, "mode");
    if (cJSON_IsString(value) && module_mode(value->valuestring)) {
        patch->has_mode = true; strlcpy(patch->mode, value->valuestring,
            sizeof(patch->mode));
    }
#define PARSE_PERCENT(field, flag, output) do { value = \
    cJSON_GetObjectItemCaseSensitive(state, field); if (cJSON_IsNumber(value) && \
    value->valueint >= 0 && value->valueint <= 100) { patch->flag = true; \
    patch->output = value->valueint; } } while (0)
    PARSE_PERCENT("position", has_position, position);
    PARSE_PERCENT("speed", has_speed, speed);
    PARSE_PERCENT("volume", has_volume, volume);
#undef PARSE_PERCENT
    return patch->has_online || patch->has_power || patch->has_open ||
        patch->has_brightness || patch->has_color || patch->has_environment || patch->has_presence ||
        patch->has_target_temperature || patch->has_mode || patch->has_position ||
        patch->has_speed || patch->has_volume;
}

static bool peer_ipv4(httpd_req_t *req, char output[48])
{
    int socket_fd = httpd_req_to_sockfd(req);
    struct sockaddr_storage address; socklen_t length = sizeof(address);
    if (socket_fd < 0 || getpeername(socket_fd, (struct sockaddr *)&address,
        &length) != 0) return false;
    if (address.ss_family == AF_INET) {
        struct sockaddr_in *ipv4 = (struct sockaddr_in *)&address;
        return inet_ntop(AF_INET, &ipv4->sin_addr, output, 48) != NULL;
    }
#if CONFIG_LWIP_IPV6
    if (address.ss_family == AF_INET6) {
        /* ESP-IDF/lwIP may expose an IPv4 peer accepted by a dual-stack HTTP
         * listener as ::ffff:a.b.c.d. Preserve the IPv4-only module routing
         * contract while accepting that equivalent socket representation. */
        const uint8_t *bytes =
            ((const struct sockaddr_in6 *)&address)->sin6_addr.s6_addr;
        bool mapped = true;
        for (size_t i = 0; i < 10; ++i) mapped = mapped && bytes[i] == 0;
        mapped = mapped && bytes[10] == 0xff && bytes[11] == 0xff;
        if (!mapped) return false;
        struct in_addr ipv4;
        memcpy(&ipv4, bytes + 12, sizeof(ipv4));
        return inet_ntop(AF_INET, &ipv4, output, 48) != NULL;
    }
#endif
    return false;
}

static esp_err_t module_register_handler(httpd_req_t *req)
{
    char *body = NULL;
    if (read_json_body(req, &body) != ESP_OK)
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body");
    cJSON *root = cJSON_Parse(body);
    external_device_registration_t registration; memset(&registration, 0,
        sizeof(registration));
    cJSON *device = root ? cJSON_GetObjectItemCaseSensitive(root, "device") : NULL;
    cJSON *version = root ? cJSON_GetObjectItemCaseSensitive(root,
        "protocolVersion") : NULL;
    cJSON *port = root ? cJSON_GetObjectItemCaseSensitive(root, "commandPort") : NULL;
    cJSON *heartbeat = root ? cJSON_GetObjectItemCaseSensitive(root,
        "heartbeatSeconds") : NULL;
    cJSON *sequence = root ? cJSON_GetObjectItemCaseSensitive(root, "sequence") : NULL;
    char type[24];
    bool valid = cJSON_IsString(version) &&
        !strcmp(version->valuestring, YAOCORE_MODULE_PROTOCOL) &&
        cJSON_IsObject(device) && json_string(root, "moduleId",
            registration.module_id, sizeof(registration.module_id)) &&
        json_string(device, "deviceId", registration.device_id,
            sizeof(registration.device_id)) &&
        module_identifier(registration.module_id) &&
        module_identifier(registration.device_id) &&
        json_string(device, "name", registration.name, sizeof(registration.name)) &&
        json_string(device, "room", registration.room, sizeof(registration.room)) &&
        json_string(device, "brand", registration.brand, sizeof(registration.brand)) &&
        json_string(device, "protocol", registration.protocol,
            sizeof(registration.protocol)) &&
        json_string(device, "deviceType", type, sizeof(type)) &&
        module_type(type, &registration.type) &&
        registration.type != DEVICE_GATEWAY &&
        json_string(root, "commandPath", registration.command_path,
            sizeof(registration.command_path)) &&
        module_command_path(registration.command_path) && cJSON_IsNumber(port) &&
        port->valueint > 0 && port->valueint <= 65535 &&
        cJSON_IsNumber(heartbeat) && heartbeat->valueint >= 5 &&
        heartbeat->valueint <= 300 && cJSON_IsNumber(sequence) &&
        sequence->valuedouble >= 0;
    registration.command_port = valid ? (uint16_t)port->valueint : 0;
    registration.heartbeat_seconds = valid ? heartbeat->valueint : 0;
    registration.sequence = valid ? (int64_t)sequence->valuedouble : -1;
    cJSON *state = root ? cJSON_GetObjectItemCaseSensitive(root, "state") : NULL;
    if (valid && state && !module_state_patch(state, &registration.initial_state))
        valid = false;
    if (!valid) { cJSON_Delete(root); free(body); return httpd_resp_send_err(req,
        HTTPD_400_BAD_REQUEST, "invalid module registration schema"); }
    if (!verify_module_request(req, "register", registration.module_id, body)) {
        cJSON_Delete(root); free(body); return httpd_resp_send_err(req,
            HTTPD_403_FORBIDDEN, "module authentication failed");
    }
    char peer[48];
    if (!peer_ipv4(req, peer)) { cJSON_Delete(root); free(body); return
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "IPv4 module required"); }
    esp_err_t route = external_module_register(&registration, peer);
    esp_err_t registry = route == ESP_OK ?
        device_router_register_external(&registration) : route;
    cJSON_Delete(root); free(body);
    if (route == ESP_OK && registry != ESP_OK) {
        external_module_unregister(registration.module_id,
            registration.device_id);
    }
    if (registry != ESP_OK) return send_conflict(req,
        "module or device identity conflict");
    return send_module_ack(req, registration.module_id, 0,
        "module device registered");
}

static esp_err_t module_state_handler(httpd_req_t *req)
{
    char *body = NULL;
    if (read_json_body(req, &body) != ESP_OK)
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body");
    cJSON *root = cJSON_Parse(body); char module_id[YAOCORE_MAX_ID];
    char device_id[YAOCORE_MAX_ID]; external_state_patch_t patch;
    cJSON *version = root ? cJSON_GetObjectItemCaseSensitive(root,
        "protocolVersion") : NULL;
    cJSON *sequence = root ? cJSON_GetObjectItemCaseSensitive(root, "sequence") : NULL;
    cJSON *state = root ? cJSON_GetObjectItemCaseSensitive(root, "state") : NULL;
    bool valid = cJSON_IsString(version) &&
        !strcmp(version->valuestring, YAOCORE_MODULE_PROTOCOL) &&
        json_string(root, "moduleId", module_id, sizeof(module_id)) &&
        json_string(root, "deviceId", device_id, sizeof(device_id)) &&
        cJSON_IsNumber(sequence) && sequence->valuedouble >= 0 &&
        module_state_patch(state, &patch);
    if (!valid) { cJSON_Delete(root); free(body); return httpd_resp_send_err(req,
        HTTPD_400_BAD_REQUEST, "invalid state schema"); }
    if (!verify_module_request(req, "state", module_id, body)) {
        cJSON_Delete(root); free(body); return httpd_resp_send_err(req,
            HTTPD_403_FORBIDDEN, "module authentication failed");
    }
    if (!external_module_accept_sequence(module_id, device_id,
        (int64_t)sequence->valuedouble)) {
        cJSON_Delete(root); free(body); return send_conflict(req,
            "stale or unknown module sequence");
    }
    esp_err_t result = device_router_report_external(module_id, device_id, &patch);
    cJSON_Delete(root); free(body);
    if (result != ESP_OK) return httpd_resp_send_err(req, HTTPD_404_NOT_FOUND,
        "module device not registered");
    return send_module_ack(req, module_id, 0, "state accepted");
}

static esp_err_t module_heartbeat_handler(httpd_req_t *req)
{
    char *body = NULL;
    if (read_json_body(req, &body) != ESP_OK)
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "invalid body");
    cJSON *root = cJSON_Parse(body); char module_id[YAOCORE_MAX_ID];
    cJSON *version = root ? cJSON_GetObjectItemCaseSensitive(root,
        "protocolVersion") : NULL;
    cJSON *sequence = root ? cJSON_GetObjectItemCaseSensitive(root, "sequence") : NULL;
    bool valid = cJSON_IsString(version) &&
        !strcmp(version->valuestring, YAOCORE_MODULE_PROTOCOL) &&
        json_string(root, "moduleId", module_id, sizeof(module_id)) &&
        cJSON_IsNumber(sequence) && sequence->valuedouble >= 0;
    if (!valid) { cJSON_Delete(root); free(body); return httpd_resp_send_err(req,
        HTTPD_400_BAD_REQUEST, "invalid heartbeat schema"); }
    if (!verify_module_request(req, "heartbeat", module_id, body)) {
        cJSON_Delete(root); free(body); return httpd_resp_send_err(req,
            HTTPD_403_FORBIDDEN, "module authentication failed");
    }
    esp_err_t result = external_module_touch(module_id,
        (int64_t)sequence->valuedouble);
    cJSON_Delete(root); free(body);
    if (result == ESP_ERR_INVALID_STATE) return send_conflict(req,
        "stale heartbeat sequence");
    if (result != ESP_OK) return httpd_resp_send_err(req, HTTPD_404_NOT_FOUND,
        "module not registered");
    return send_module_ack(req, module_id, 0, "heartbeat accepted");
}

static void udp_nonce(char output[65])
{
    for (size_t i = 0; i < 32; ++i) {
        uint8_t value = (uint8_t)esp_random();
        snprintf(output + i * 2, 3, "%02x", value);
    }
    output[64] = '\0';
}

static void send_module_udp_ack(int sock, const struct sockaddr *destination,
    socklen_t destination_length, const char *module_id, int64_t sequence,
    int result_code)
{
    cJSON *body_root = cJSON_CreateObject();
    if (!body_root) return;
    cJSON_AddStringToObject(body_root, "protocolVersion", YAOCORE_MODULE_PROTOCOL);
    cJSON_AddNumberToObject(body_root, "resultCode", result_code);
    cJSON_AddNumberToObject(body_root, "sequence", (double)sequence);
    char *body = cJSON_PrintUnformatted(body_root);
    cJSON_Delete(body_root);
    if (!body) return;
    char timestamp[17], nonce[65], signature[65];
    format_timestamp(timestamp); udp_nonce(nonce);
    if (!gateway_security_sign_module_message("gateway_ack", module_id,
        timestamp, nonce, body, signature)) { free(body); return; }
    cJSON *envelope = cJSON_CreateObject();
    if (!envelope) { free(body); return; }
    cJSON_AddStringToObject(envelope, "type", "YAOCORE_MODULE_ACK");
    cJSON_AddStringToObject(envelope, "moduleId", module_id);
    cJSON_AddStringToObject(envelope, "timestamp", timestamp);
    cJSON_AddStringToObject(envelope, "nonce", nonce);
    cJSON_AddStringToObject(envelope, "signature", signature);
    cJSON_AddStringToObject(envelope, "body", body);
    char *packet = cJSON_PrintUnformatted(envelope);
    cJSON_Delete(envelope); free(body);
    if (packet) {
        sendto(sock, packet, strlen(packet), 0, destination,
            destination_length);
        free(packet);
    }
}

/* Telemetry is a signed UDP event so the WiFiS3 coprocessor never blocks the
 * R4 command server while it waits for an HTTP heartbeat/state ACK. Commands
 * and physical execution ACKs remain reliable, Content-Length framed TCP. */
static void handle_module_udp_event(int sock, const char *packet,
    const struct sockaddr *source, socklen_t source_length)
{
    cJSON *envelope = cJSON_Parse(packet);
    char type[32], kind[16], module_id[YAOCORE_MAX_ID], timestamp[17];
    char nonce[65], signature[65];
    cJSON *body_item = envelope ? cJSON_GetObjectItemCaseSensitive(envelope,
        "body") : NULL;
    bool valid = envelope && json_string(envelope, "type", type, sizeof(type)) &&
        !strcmp(type, "YAOCORE_MODULE_EVENT") &&
        json_string(envelope, "kind", kind, sizeof(kind)) &&
        (!strcmp(kind, "state") || !strcmp(kind, "heartbeat")) &&
        json_string(envelope, "moduleId", module_id, sizeof(module_id)) &&
        json_string(envelope, "timestamp", timestamp, sizeof(timestamp)) &&
        json_string(envelope, "nonce", nonce, sizeof(nonce)) &&
        json_string(envelope, "signature", signature, sizeof(signature)) &&
        cJSON_IsString(body_item) && body_item->valuestring;
    if (!valid || !gateway_security_verify_module_message(kind, module_id,
        timestamp, nonce, signature, body_item->valuestring)) {
        cJSON_Delete(envelope); return;
    }
    cJSON *body = cJSON_Parse(body_item->valuestring);
    cJSON *version = body ? cJSON_GetObjectItemCaseSensitive(body,
        "protocolVersion") : NULL;
    cJSON *sequence_item = body ? cJSON_GetObjectItemCaseSensitive(body,
        "sequence") : NULL;
    char body_module_id[YAOCORE_MAX_ID];
    bool body_valid = cJSON_IsString(version) &&
        !strcmp(version->valuestring, YAOCORE_MODULE_PROTOCOL) &&
        json_string(body, "moduleId", body_module_id, sizeof(body_module_id)) &&
        !strcmp(body_module_id, module_id) && cJSON_IsNumber(sequence_item) &&
        sequence_item->valuedouble >= 0;
    int64_t sequence = body_valid ? (int64_t)sequence_item->valuedouble : -1;
    int result_code = 40;
    if (body_valid && !strcmp(kind, "heartbeat")) {
        esp_err_t result = external_module_touch(module_id, sequence);
        result_code = result == ESP_OK ? 0 :
            (result == ESP_ERR_NOT_FOUND ? 44 : 45);
    } else if (body_valid) {
        char device_id[YAOCORE_MAX_ID]; external_state_patch_t patch;
        cJSON *state = cJSON_GetObjectItemCaseSensitive(body, "state");
        if (json_string(body, "deviceId", device_id, sizeof(device_id)) &&
            module_state_patch(state, &patch)) {
            if (!external_module_accept_sequence(module_id, device_id,
                sequence)) result_code = 44;
            else result_code = device_router_report_external(module_id,
                device_id, &patch) == ESP_OK ? 0 : 44;
        }
    }
    send_module_udp_ack(sock, source, source_length, module_id, sequence,
        result_code);
    cJSON_Delete(body); cJSON_Delete(envelope);
}

static void udp_task(void *arg)
{
    (void)arg;
    const gateway_config_t *cfg = gateway_config_get(); int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (sock < 0) { ESP_LOGE(TAG, "UDP socket creation failed: %d", errno); vTaskDelete(NULL); return; }
    int broadcast = 1; setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast));
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_port = htons(cfg->udp_port), .sin_addr.s_addr = htonl(INADDR_ANY) };
    if (bind(sock, (struct sockaddr *)&address, sizeof(address)) < 0) { ESP_LOGE(TAG, "UDP bind failed: %d", errno); close(sock); vTaskDelete(NULL); return; }
    char buffer[1536];
    while (true) { struct sockaddr_storage source; socklen_t length = sizeof(source); int len = recvfrom(sock, buffer, sizeof(buffer) - 1, 0, (struct sockaddr *)&source, &length);
        if (len <= 0) continue;
        buffer[len] = '\0';
        if (strstr(buffer, "YAOCORE_DISCOVER") != NULL) { char *json = create_udp_candidate_json(); if (json) { sendto(sock, json, strlen(json), 0, (struct sockaddr *)&source, length); free(json); } }
        else if (strstr(buffer, "YAOCORE_MODULE_EVENT") != NULL)
            handle_module_udp_event(sock, buffer, (struct sockaddr *)&source,
                length);
    }
}

esp_err_t local_server_start(void)
{
    const gateway_config_t *cfg = gateway_config_get(); httpd_config_t config = HTTPD_DEFAULT_CONFIG(); config.server_port = cfg->local_port;
    config.stack_size = 10240; config.max_uri_handlers = 10;
    /* The gateway also owns UDP discovery, mDNS, SNTP and southbound module
     * sockets. Keep the HTTP client pool bounded and evict an abandoned
     * session instead of exhausting lwIP after a phone changes networks. */
    config.max_open_sockets = 5;
    config.lru_purge_enable = true;
    config.open_fn = configure_client_socket;
    config.recv_wait_timeout = 8;
    config.send_wait_timeout = 8;
    ESP_RETURN_ON_ERROR(httpd_start(&s_httpd, &config), TAG, "HTTP server start failed");
    httpd_uri_t discover = { .uri = "/discover", .method = HTTP_GET, .handler = discover_handler };
    httpd_uri_t control = { .uri = "/control", .method = HTTP_POST, .handler = control_handler };
    httpd_uri_t module_register = { .uri = "/module/v1/register", .method = HTTP_POST, .handler = module_register_handler };
    httpd_uri_t module_state = { .uri = "/module/v1/state", .method = HTTP_POST, .handler = module_state_handler };
    httpd_uri_t module_heartbeat = { .uri = "/module/v1/heartbeat", .method = HTTP_POST, .handler = module_heartbeat_handler };
    ESP_ERROR_CHECK(httpd_register_uri_handler(s_httpd, &discover)); ESP_ERROR_CHECK(httpd_register_uri_handler(s_httpd, &control));
    ESP_ERROR_CHECK(httpd_register_uri_handler(s_httpd, &module_register));
    ESP_ERROR_CHECK(httpd_register_uri_handler(s_httpd, &module_state));
    ESP_ERROR_CHECK(httpd_register_uri_handler(s_httpd, &module_heartbeat));
    ESP_ERROR_CHECK(mdns_init()); mdns_hostname_set("yaocore-gateway"); mdns_instance_name_set(cfg->gateway_name);
    mdns_service_add(cfg->gateway_name, "_yaocore", "_tcp", cfg->local_port, NULL, 0);
    mdns_txt_item_t txt[] = {{"protocol", "2.0"}, {"service", YAOCORE_SERVICE_ID}, {"secure", "hmac-sha256"}};
    mdns_service_txt_set("_yaocore", "_tcp", txt, 3);
    /* Signed module datagrams perform JSON parsing and HMAC verification in
     * this task; 4 KiB was sufficient for locator-only discovery but can
     * overflow on the first authenticated heartbeat. */
    BaseType_t udp_created = xTaskCreate(udp_task, "yaocore_udp", 8192,
        NULL, 5, NULL);
    ESP_RETURN_ON_FALSE(udp_created == pdPASS, ESP_ERR_NO_MEM, TAG,
        "UDP discovery/telemetry task creation failed");
    ESP_LOGI(TAG, "local gateway ready on port %d", cfg->local_port); return ESP_OK;
}
