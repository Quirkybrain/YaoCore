/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "gateway_security.h"
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include "cJSON.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mbedtls/md.h"
#include "mbedtls/platform_util.h"
#include "gateway_config.h"

#define REPLAY_CACHE_SIZE 32
#define FRESHNESS_SECONDS 120
#define NONCE_TTL_SECONDS 300
#define AUTH_TIME_MIN_EPOCH 1704067200LL /* 2024-01-01T00:00:00Z */
#define AUTH_TIME_MAX_EPOCH 4102444800LL /* 2100-01-01T00:00:00Z */
#define SECURITY_NVS_NAMESPACE "yaocore_sec"
#define SECURITY_NVS_EPOCH_KEY "last_auth_epoch"
#define COMMAND_CANONICAL_MAX 1024

typedef struct {
    bool used;
    int64_t stored_at_us;
    char key_id[64];
    char nonce[65];
    char request_id[128];
    int32_t seq;
    char sign[65];
    char canonical[COMMAND_CANONICAL_MAX];
    gateway_ack_t ack;
} replay_entry_t;

typedef struct {
    bool used;
    int64_t stored_at_us;
    char key_id[64];
    char nonce[65];
} discovery_replay_entry_t;

static const char *TAG = "security";
static replay_entry_t s_cache[REPLAY_CACHE_SIZE];
static discovery_replay_entry_t s_discovery_cache[REPLAY_CACHE_SIZE];
static discovery_replay_entry_t s_module_cache[REPLAY_CACHE_SIZE];
static SemaphoreHandle_t s_lock;
static nvs_handle_t s_nvs;
static int64_t s_boot_epoch_floor;
static int64_t s_last_authenticated_epoch;
static bool s_persistence_healthy;

static void set_error(gateway_ack_t *ack, int code, const char *error, const char *message)
{
    memset(ack, 0, sizeof(*ack));
    ack->result_code = code;
    strlcpy(ack->error_code, error, sizeof(ack->error_code));
    strlcpy(ack->message, message, sizeof(ack->message));
}

static bool value_text(const gateway_command_t *cmd, char *output, size_t size)
{
    if (!cmd || !output || size == 0) return false;
    output[0] = '\0';
    if (cmd->value_type == VALUE_STRING) {
        cJSON *value = cJSON_CreateString(cmd->string_value);
        if (!value) return false;
        char *serialized = cJSON_PrintUnformatted(value);
        cJSON_Delete(value);
        if (!serialized) return false;
        size_t length = strlen(serialized);
        if (length >= size) { free(serialized); return false; }
        memcpy(output, serialized, length + 1);
        free(serialized);
    }
    else if (cmd->value_type == VALUE_BOOL) strlcpy(output, cmd->bool_value ? "true" : "false", size);
    else if (cmd->value_type == VALUE_NUMBER) {
        if (!isfinite(cmd->number_value)) return false;
        int written;
        if (isfinite(cmd->number_value) && floor(cmd->number_value) == cmd->number_value)
            written = snprintf(output, size, "%.0f", cmd->number_value);
        else written = snprintf(output, size, "%.15g", cmd->number_value);
        if (written < 0 || (size_t)written >= size) return false;
    }
    else if (cmd->value_type != VALUE_NONE) return false;
    return true;
}

bool gateway_security_format_canonical(const gateway_command_t *cmd, char *output, size_t size)
{
    if (!cmd || !output || size == 0) return false;
    char value[384];
    if (!value_text(cmd, value, sizeof(value))) return false;
    int written = snprintf(output, size, "%s\n%d\n%d\n%s\n%s\n%s\n%s\n%s\n%s\n%s",
        cmd->request_id, (int)cmd->cmd_id, (int)cmd->seq, cmd->target, cmd->action, value,
        cmd->timestamp, cmd->nonce, cmd->alg, cmd->key_id);
    return written > 0 && (size_t)written < size;
}

bool gateway_security_sign_response(const char *kind, const char *correlation,
    const char *response_body, char signature[65])
{
    if (!kind || (strcmp(kind, "discover") && strcmp(kind, "control")) ||
        !correlation || correlation[0] == '\0' || !response_body || !signature) {
        return false;
    }
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!info) return false;
    unsigned char body_digest[32];
    if (mbedtls_md(info, (const unsigned char *)response_body,
        strlen(response_body), body_digest) != 0) return false;
    char body_hash[65];
    for (int i = 0; i < 32; ++i) snprintf(body_hash + i * 2, 3, "%02x",
        body_digest[i]);
    body_hash[64] = '\0';
    char canonical[320];
    int written = snprintf(canonical, sizeof(canonical),
        "YAOCORE-RESPONSE-V1\n%s\n%s\n%s", kind, correlation, body_hash);
    if (written <= 0 || (size_t)written >= sizeof(canonical)) return false;
    const gateway_config_t *config = gateway_config_get();
    unsigned char response_digest[32];
    if (mbedtls_md_hmac(info, (const unsigned char *)config->command_secret,
        strlen(config->command_secret), (const unsigned char *)canonical,
        strlen(canonical), response_digest) != 0) return false;
    for (int i = 0; i < 32; ++i) snprintf(signature + i * 2, 3, "%02x",
        response_digest[i]);
    signature[64] = '\0';
    return true;
}

static bool parse_utc(const char *text, time_t *result);
static bool is_lower_hex_exact(const char *value, size_t length);

static bool constant_time_equal(const char *a, const char *b)
{
    size_t alen = strlen(a), blen = strlen(b);
    unsigned char diff = (unsigned char)(alen ^ blen);
    size_t max = alen > blen ? alen : blen;
    for (size_t i = 0; i < max; ++i) diff |= (i < alen ? a[i] : 0) ^ (i < blen ? b[i] : 0);
    return diff == 0;
}

static bool valid_module_kind(const char *kind)
{
    return kind && (!strcmp(kind, "register") || !strcmp(kind, "state") ||
        !strcmp(kind, "heartbeat") || !strcmp(kind, "command") ||
        !strcmp(kind, "command_ack") || !strcmp(kind, "gateway_ack"));
}

static bool derive_module_key(const char *module_id, unsigned char key[32])
{
    const gateway_config_t *config = gateway_config_get();
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!info || !module_id || !module_id[0]) return false;
    char context[YAOCORE_MAX_ID + 24];
    int written = snprintf(context, sizeof(context),
        "YAOCORE-MODULE-KEY-V1\n%s", module_id);
    return written > 0 && (size_t)written < sizeof(context) &&
        mbedtls_md_hmac(info,
            (const unsigned char *)config->command_secret,
            strlen(config->command_secret), (const unsigned char *)context,
            strlen(context), key) == 0;
}

bool gateway_security_sign_module_message(const char *kind,
    const char *module_id, const char *timestamp, const char *nonce,
    const char *body, char signature[65])
{
    if (!valid_module_kind(kind) || !module_id || !module_id[0] ||
        strlen(module_id) >= YAOCORE_MAX_ID || !timestamp ||
        strlen(timestamp) != 16 || !is_lower_hex_exact(nonce, 64) ||
        !body || !signature) return false;
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!info) return false;
    unsigned char body_digest[32];
    if (mbedtls_md(info, (const unsigned char *)body, strlen(body),
        body_digest) != 0) return false;
    char body_hash[65];
    for (int i = 0; i < 32; ++i) snprintf(body_hash + i * 2, 3, "%02x",
        body_digest[i]);
    body_hash[64] = '\0';
    char canonical[384];
    int written = snprintf(canonical, sizeof(canonical),
        "YAOCORE-MODULE-V1\n%s\n%s\n%s\n%s\n%s\n%s\n%s", kind,
        module_id, timestamp, nonce, YAOCORE_ALGORITHM, YAOCORE_KEY_ID,
        body_hash);
    if (written <= 0 || (size_t)written >= sizeof(canonical)) return false;
    unsigned char digest[32], module_key[32];
    if (!derive_module_key(module_id, module_key) ||
        mbedtls_md_hmac(info, module_key, sizeof(module_key),
            (const unsigned char *)canonical, strlen(canonical), digest) != 0) {
        mbedtls_platform_zeroize(module_key, sizeof(module_key));
        return false;
    }
    mbedtls_platform_zeroize(module_key, sizeof(module_key));
    for (int i = 0; i < 32; ++i) snprintf(signature + i * 2, 3, "%02x",
        digest[i]);
    signature[64] = '\0';
    return true;
}

bool gateway_security_verify_module_message(const char *kind,
    const char *module_id, const char *timestamp, const char *nonce,
    const char *signature, const char *body)
{
    if (!signature || !is_lower_hex_exact(signature, 64)) return false;
    char expected[65];
    if (!gateway_security_sign_module_message(kind, module_id, timestamp,
        nonce, body, expected) || !constant_time_equal(expected, signature)) {
        return false;
    }
    time_t signed_time;
    if (!parse_utc(timestamp, &signed_time) ||
        (int64_t)signed_time < AUTH_TIME_MIN_EPOCH ||
        (int64_t)signed_time > AUTH_TIME_MAX_EPOCH) return false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    time_t now = time(NULL);
    bool clock_valid = (int64_t)now >= AUTH_TIME_MIN_EPOCH &&
        (int64_t)now <= AUTH_TIME_MAX_EPOCH;
    if (clock_valid && llabs((long long)(now - signed_time)) >
        FRESHNESS_SECONDS) { xSemaphoreGive(s_lock); return false; }
    if (!clock_valid) {
        struct timeval authenticated_time = { .tv_sec = signed_time, .tv_usec = 0 };
        if (settimeofday(&authenticated_time, NULL) != 0) {
            xSemaphoreGive(s_lock); return false;
        }
    }
    int64_t current_us = esp_timer_get_time();
    int free_slot = -1, oldest_slot = 0;
    for (int i = 0; i < REPLAY_CACHE_SIZE; ++i) {
        bool alive = s_module_cache[i].used && current_us -
            s_module_cache[i].stored_at_us <= NONCE_TTL_SECONDS * 1000000LL;
        if (!alive) {
            s_module_cache[i].used = false;
            if (free_slot < 0) free_slot = i;
            continue;
        }
        if (!strcmp(s_module_cache[i].key_id, module_id) &&
            !strcmp(s_module_cache[i].nonce, nonce)) {
            xSemaphoreGive(s_lock); return false;
        }
        if (s_module_cache[i].stored_at_us <
            s_module_cache[oldest_slot].stored_at_us) oldest_slot = i;
    }
    int slot = free_slot >= 0 ? free_slot : oldest_slot;
    discovery_replay_entry_t *entry = &s_module_cache[slot];
    memset(entry, 0, sizeof(*entry));
    entry->used = true; entry->stored_at_us = current_us;
    strlcpy(entry->key_id, module_id, sizeof(entry->key_id));
    strlcpy(entry->nonce, nonce, sizeof(entry->nonce));
    xSemaphoreGive(s_lock);
    return true;
}

static bool parse_utc(const char *text, time_t *result);

static bool is_lower_hex_exact(const char *value, size_t length)
{
    if (!value || strlen(value) != length) return false;
    for (size_t i = 0; i < length; ++i) {
        if (!((value[i] >= '0' && value[i] <= '9') ||
            (value[i] >= 'a' && value[i] <= 'f'))) return false;
    }
    return true;
}

bool gateway_security_verify_discovery_request(const char *challenge,
    const char *timestamp, const char *nonce, const char *algorithm,
    const char *key_id, const char *signature)
{
    if (!is_lower_hex_exact(challenge, 32) || !timestamp || strlen(timestamp) != 16 ||
        !is_lower_hex_exact(nonce, 32) || !algorithm || !key_id ||
        !is_lower_hex_exact(signature, 64) ||
        strcmp(algorithm, YAOCORE_ALGORITHM) ||
        strcmp(key_id, YAOCORE_KEY_ID)) return false;
    char canonical[224];
    int written = snprintf(canonical, sizeof(canonical),
        "YAOCORE-DISCOVER-V2\n%s\n%s\n%s\n%s\n%s", challenge,
        timestamp, nonce, YAOCORE_ALGORITHM, YAOCORE_KEY_ID);
    if (written <= 0 || (size_t)written >= sizeof(canonical)) return false;
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    unsigned char digest[32];
    const gateway_config_t *config = gateway_config_get();
    if (!info || mbedtls_md_hmac(info,
        (const unsigned char *)config->command_secret,
        strlen(config->command_secret), (const unsigned char *)canonical,
        strlen(canonical), digest) != 0) return false;
    char expected[65];
    for (int i = 0; i < 32; ++i) snprintf(expected + i * 2, 3, "%02x",
        digest[i]);
    expected[64] = '\0';
    if (!constant_time_equal(expected, signature)) return false;

    /* Only authenticated timestamps reach the clock/freshness path. A discovery
     * request never executes a device action, but its nonce is still single-use
     * so a captured signed snapshot request cannot be replayed during its window. */
    time_t signed_time;
    if (!parse_utc(timestamp, &signed_time) ||
        (int64_t)signed_time < AUTH_TIME_MIN_EPOCH ||
        (int64_t)signed_time > AUTH_TIME_MAX_EPOCH) return false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    time_t now = time(NULL);
    bool clock_valid = (int64_t)now >= AUTH_TIME_MIN_EPOCH &&
        (int64_t)now <= AUTH_TIME_MAX_EPOCH;
    if (clock_valid && llabs((long long)(now - signed_time)) > FRESHNESS_SECONDS) {
        xSemaphoreGive(s_lock);
        return false;
    }
    if (!clock_valid) {
        struct timeval authenticated_time = { .tv_sec = signed_time, .tv_usec = 0 };
        if (settimeofday(&authenticated_time, NULL) != 0) {
            xSemaphoreGive(s_lock);
            return false;
        }
    }

    const int64_t now_us = esp_timer_get_time();
    int free_slot = -1;
    int oldest_slot = 0;
    for (int i = 0; i < REPLAY_CACHE_SIZE; ++i) {
        bool alive = s_discovery_cache[i].used &&
            now_us - s_discovery_cache[i].stored_at_us <= NONCE_TTL_SECONDS * 1000000LL;
        if (!alive) {
            s_discovery_cache[i].used = false;
            if (free_slot < 0) free_slot = i;
            continue;
        }
        if (!strcmp(s_discovery_cache[i].key_id, key_id) &&
            !strcmp(s_discovery_cache[i].nonce, nonce)) {
            xSemaphoreGive(s_lock);
            return false;
        }
        if (s_discovery_cache[i].stored_at_us <
            s_discovery_cache[oldest_slot].stored_at_us) oldest_slot = i;
    }
    int slot = free_slot >= 0 ? free_slot : oldest_slot;
    discovery_replay_entry_t *entry = &s_discovery_cache[slot];
    memset(entry, 0, sizeof(*entry));
    entry->used = true;
    entry->stored_at_us = now_us;
    strlcpy(entry->key_id, key_id, sizeof(entry->key_id));
    strlcpy(entry->nonce, nonce, sizeof(entry->nonce));
    xSemaphoreGive(s_lock);
    return true;
}

static bool parse_utc(const char *text, time_t *result)
{
    if (strlen(text) != 16 || text[8] != 'T' || text[15] != 'Z') return false;
    struct tm tm = {0};
    int y, mon, d, h, min, sec;
    if (sscanf(text, "%4d%2d%2dT%2d%2d%2dZ", &y, &mon, &d, &h, &min, &sec) != 6) return false;
    tm.tm_year = y - 1900; tm.tm_mon = mon - 1; tm.tm_mday = d;
    tm.tm_hour = h; tm.tm_min = min; tm.tm_sec = sec;
    *result = mktime(&tm);
    if (*result <= 0) return false;
    struct tm normalized;
    char round_trip[17];
    gmtime_r(result, &normalized);
    strftime(round_trip, sizeof(round_trip), "%Y%m%dT%H%M%SZ", &normalized);
    return !strcmp(text, round_trip);
}

static bool signature_matches(const gateway_command_t *cmd, const char *canonical)
{
    unsigned char digest[32];
    const gateway_config_t *cfg = gateway_config_get();
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!info || mbedtls_md_hmac(info, (const unsigned char *)cfg->command_secret, strlen(cfg->command_secret),
        (const unsigned char *)canonical, strlen(canonical), digest) != 0) return false;
    char hex[65];
    for (int i = 0; i < 32; ++i) snprintf(hex + i * 2, 3, "%02x", digest[i]);
    hex[64] = '\0';
    return constant_time_equal(hex, cmd->sign);
}

esp_err_t gateway_security_init(void)
{
    memset(s_cache, 0, sizeof(s_cache));
    memset(s_discovery_cache, 0, sizeof(s_discovery_cache));
    memset(s_module_cache, 0, sizeof(s_module_cache));
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) return ESP_ERR_NO_MEM;
    esp_err_t err = nvs_open(SECURITY_NVS_NAMESPACE, NVS_READWRITE, &s_nvs);
    if (err != ESP_OK) return err;
    int64_t persisted = 0;
    err = nvs_get_i64(s_nvs, SECURITY_NVS_EPOCH_KEY, &persisted);
    if (err == ESP_ERR_NVS_NOT_FOUND) persisted = 0;
    else if (err != ESP_OK) { nvs_close(s_nvs); return err; }
    if (persisted < 0 || persisted > AUTH_TIME_MAX_EPOCH) {
        nvs_close(s_nvs);
        ESP_LOGE(TAG, "invalid persistent authentication epoch");
        return ESP_ERR_INVALID_STATE;
    }
    s_boot_epoch_floor = persisted;
    s_last_authenticated_epoch = persisted;
    s_persistence_healthy = true;
    ESP_LOGI(TAG, "persistent replay floor=%lld", (long long)s_boot_epoch_floor);
    return ESP_OK;
}

static bool entry_alive(const replay_entry_t *entry, int64_t now_us)
{
    return entry->used && now_us - entry->stored_at_us <= NONCE_TTL_SECONDS * 1000000LL;
}

bool gateway_security_get_cached(const gateway_command_t *cmd, gateway_ack_t *ack)
{
    char canonical[COMMAND_CANONICAL_MAX];
    if (!gateway_security_format_canonical(cmd, canonical, sizeof(canonical))) return false;
    int64_t now = esp_timer_get_time();
    xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < REPLAY_CACHE_SIZE; ++i) {
        if (!entry_alive(&s_cache[i], now)) { s_cache[i].used = false; continue; }
        if (strcmp(s_cache[i].key_id, cmd->key_id) == 0 && strcmp(s_cache[i].nonce, cmd->nonce) == 0) {
            if (strcmp(s_cache[i].canonical, canonical) == 0 && strcmp(s_cache[i].sign, cmd->sign) == 0) {
                *ack = s_cache[i].ack; ack->idempotent_replay = true;
            } else set_error(ack, 1005, "REPLAY", "nonce reused with different command");
            xSemaphoreGive(s_lock);
            return true;
        }
    }
    xSemaphoreGive(s_lock);
    return false;
}

bool gateway_security_verify(const gateway_command_t *cmd, gateway_ack_t *error_ack)
{
    if (strcmp(cmd->alg, YAOCORE_ALGORITHM) || strcmp(cmd->key_id, YAOCORE_KEY_ID)) {
        set_error(error_ack, 1003, "UNSUPPORTED_KEY", "unsupported algorithm or key id"); return false;
    }
    char canonical[COMMAND_CANONICAL_MAX];
    if (!gateway_security_format_canonical(cmd, canonical, sizeof(canonical)) || !signature_matches(cmd, canonical)) {
        set_error(error_ack, 1004, "BAD_SIGNATURE", "signature verification failed"); return false;
    }
    time_t timestamp;
    if (!parse_utc(cmd->timestamp, &timestamp) ||
        (int64_t)timestamp < AUTH_TIME_MIN_EPOCH ||
        (int64_t)timestamp > AUTH_TIME_MAX_EPOCH) {
        set_error(error_ack, 1002, "STALE_TIMESTAMP", "signed timestamp is outside the sane UTC range");
        return false;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (!s_persistence_healthy) {
        xSemaphoreGive(s_lock);
        set_error(error_ack, 1006, "SECURITY_STORAGE_FAILURE",
            "persistent replay protection is unavailable");
        return false;
    }
    if ((int64_t)timestamp <= s_boot_epoch_floor) {
        xSemaphoreGive(s_lock);
        set_error(error_ack, 1005, "PERSISTENT_REPLAY",
            "timestamp does not advance the persisted reboot replay floor");
        return false;
    }
    time_t now = time(NULL);
    bool clock_valid = (int64_t)now >= AUTH_TIME_MIN_EPOCH &&
        (int64_t)now <= AUTH_TIME_MAX_EPOCH;
    if (clock_valid && llabs((long long)(now - timestamp)) > FRESHNESS_SECONDS) {
        xSemaphoreGive(s_lock);
        set_error(error_ack, 1002, "STALE_TIMESTAMP", "timestamp outside allowed window");
        return false;
    }
    if (!clock_valid) {
        struct timeval authenticated_time = { .tv_sec = timestamp, .tv_usec = 0 };
        if (settimeofday(&authenticated_time, NULL) != 0) {
            xSemaphoreGive(s_lock);
            set_error(error_ack, 1006, "CLOCK_SET_FAILED",
                "unable to apply authenticated application time");
            return false;
        }
        ESP_LOGW(TAG, "system time bootstrapped from authenticated command: %s",
            cmd->timestamp);
    }
    xSemaphoreGive(s_lock);
    return true;
}

static void persist_authenticated_epoch(time_t timestamp)
{
    if ((int64_t)timestamp <= s_last_authenticated_epoch) return;
    esp_err_t err = nvs_set_i64(s_nvs, SECURITY_NVS_EPOCH_KEY,
        (int64_t)timestamp);
    if (err == ESP_OK) err = nvs_commit(s_nvs);
    if (err == ESP_OK) s_last_authenticated_epoch = (int64_t)timestamp;
    else {
        s_persistence_healthy = false;
        ESP_LOGE(TAG, "failed to persist replay floor: %s", esp_err_to_name(err));
    }
}

void gateway_security_cache_result(const gateway_command_t *cmd, const gateway_ack_t *ack)
{
    char canonical[COMMAND_CANONICAL_MAX];
    if (!gateway_security_format_canonical(cmd, canonical, sizeof(canonical))) return;
    int64_t now = esp_timer_get_time();
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int slot = 0;
    for (int i = 0; i < REPLAY_CACHE_SIZE; ++i) {
        if (!entry_alive(&s_cache[i], now)) { slot = i; break; }
        if (s_cache[i].stored_at_us < s_cache[slot].stored_at_us) slot = i;
    }
    replay_entry_t *entry = &s_cache[slot];
    memset(entry, 0, sizeof(*entry)); entry->used = true; entry->stored_at_us = now;
    strlcpy(entry->key_id, cmd->key_id, sizeof(entry->key_id));
    strlcpy(entry->nonce, cmd->nonce, sizeof(entry->nonce));
    strlcpy(entry->request_id, cmd->request_id, sizeof(entry->request_id));
    strlcpy(entry->sign, cmd->sign, sizeof(entry->sign));
    strlcpy(entry->canonical, canonical, sizeof(entry->canonical));
    entry->seq = cmd->seq; entry->ack = *ack;
    time_t authenticated_timestamp;
    if (parse_utc(cmd->timestamp, &authenticated_timestamp)) {
        persist_authenticated_epoch(authenticated_timestamp);
    }
    xSemaphoreGive(s_lock);
    ESP_LOGD(TAG, "cached request %s", cmd->request_id);
}
