/*
 * YaoCore (爻构) - authenticated southbound module protocol
 * Copyright (c) 2026 Zhang HaoXuan
 * SPDX-License-Identifier: Apache-2.0
 */

#include "external_module.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <time.h>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include "cJSON.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gateway_security.h"

typedef struct {
    bool used;
    char module_id[YAOCORE_MAX_ID];
    char device_id[YAOCORE_MAX_ID];
    char host[48];
    uint16_t port;
    char path[64];
    uint32_t heartbeat_seconds;
    int64_t last_sequence;
    int64_t last_seen_ms;
} module_route_t;

typedef struct {
    char *body;
    size_t body_size;
    size_t used;
    char timestamp[17];
    char nonce[65];
    char signature[65];
    char module_id[YAOCORE_MAX_ID];
} response_capture_t;

#define MODULE_CONNECTION_CACHE_SIZE 4

typedef struct {
    bool used;
    char module_id[YAOCORE_MAX_ID];
    char host[48];
    uint16_t port;
    int socket_fd;
    int64_t last_used_ms;
} module_connection_t;

static const char *TAG = "external_module";
static module_route_t s_routes[YAOCORE_MAX_MODULES];
static SemaphoreHandle_t s_lock;
static SemaphoreHandle_t s_transport_lock;
static module_connection_t s_connections[MODULE_CONNECTION_CACHE_SIZE];
static external_module_offline_callback_t s_offline_callback;

static void close_module_connection(module_connection_t *connection);
static void invalidate_module_connections(const char *module_id);

static int64_t now_ms(void) { return esp_timer_get_time() / 1000; }

static module_route_t *find_route_locked(const char *module_id,
    const char *device_id)
{
    for (size_t i = 0; i < YAOCORE_MAX_MODULES; ++i) {
        if (s_routes[i].used && !strcmp(s_routes[i].module_id, module_id) &&
            (!device_id || !strcmp(s_routes[i].device_id, device_id))) return &s_routes[i];
    }
    return NULL;
}

static module_route_t *find_device_locked(const char *device_id)
{
    for (size_t i = 0; i < YAOCORE_MAX_MODULES; ++i) {
        if (s_routes[i].used && !strcmp(s_routes[i].device_id, device_id)) return &s_routes[i];
    }
    return NULL;
}

static int64_t module_last_sequence_locked(const char *module_id)
{
    int64_t latest = -1;
    for (size_t i = 0; i < YAOCORE_MAX_MODULES; ++i) {
        if (s_routes[i].used && !strcmp(s_routes[i].module_id, module_id) &&
            s_routes[i].last_sequence > latest) latest = s_routes[i].last_sequence;
    }
    return latest;
}

static void offline_task(void *arg)
{
    (void)arg;
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(2000));
        char expired[YAOCORE_MAX_MODULES][YAOCORE_MAX_ID];
        size_t count = 0;
        int64_t current = now_ms();
        xSemaphoreTake(s_lock, portMAX_DELAY);
        for (size_t i = 0; i < YAOCORE_MAX_MODULES; ++i) {
            module_route_t *route = &s_routes[i];
            if (!route->used || route->last_seen_ms <= 0) continue;
            int64_t timeout = (int64_t)route->heartbeat_seconds * 3000;
            if (current - route->last_seen_ms > timeout) {
                strlcpy(expired[count++], route->device_id, YAOCORE_MAX_ID);
                route->last_seen_ms = 0; /* notify once until the module returns */
            }
        }
        xSemaphoreGive(s_lock);
        for (size_t i = 0; i < count; ++i) {
            ESP_LOGW(TAG, "module device timed out: %s", expired[i]);
            if (s_offline_callback) s_offline_callback(expired[i]);
        }
    }
}

esp_err_t external_module_init(external_module_offline_callback_t callback)
{
    memset(s_routes, 0, sizeof(s_routes));
    memset(s_connections, 0, sizeof(s_connections));
    for (size_t i = 0; i < MODULE_CONNECTION_CACHE_SIZE; ++i)
        s_connections[i].socket_fd = -1;
    s_lock = xSemaphoreCreateMutex();
    s_transport_lock = xSemaphoreCreateMutex();
    if (!s_lock || !s_transport_lock) return ESP_ERR_NO_MEM;
    s_offline_callback = callback;
    if (xTaskCreate(offline_task, "module_watch", 3072, NULL, 5, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "authenticated external module transport ready");
    return ESP_OK;
}

esp_err_t external_module_register(const external_device_registration_t *reg,
    const char *peer_ip)
{
    if (!reg || !peer_ip || !reg->module_id[0] || !reg->device_id[0] ||
        !reg->command_path[0] || reg->command_path[0] != '/' ||
        reg->command_port == 0) return ESP_ERR_INVALID_ARG;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    module_route_t *route = find_device_locked(reg->device_id);
    if (route && strcmp(route->module_id, reg->module_id)) {
        xSemaphoreGive(s_lock);
        return ESP_ERR_INVALID_STATE;
    }
    int64_t module_latest = module_last_sequence_locked(reg->module_id);
    if (module_latest >= 0 && reg->sequence <= module_latest) {
        xSemaphoreGive(s_lock);
        return ESP_ERR_INVALID_STATE;
    }
    if (!route) {
        for (size_t i = 0; i < YAOCORE_MAX_MODULES; ++i) {
            if (!s_routes[i].used) { route = &s_routes[i]; break; }
        }
    }
    if (!route) { xSemaphoreGive(s_lock); return ESP_ERR_NO_MEM; }
    memset(route, 0, sizeof(*route));
    route->used = true;
    strlcpy(route->module_id, reg->module_id, sizeof(route->module_id));
    strlcpy(route->device_id, reg->device_id, sizeof(route->device_id));
    strlcpy(route->host, peer_ip, sizeof(route->host));
    strlcpy(route->path, reg->command_path, sizeof(route->path));
    route->port = reg->command_port;
    route->heartbeat_seconds = reg->heartbeat_seconds < 5 ? 5 :
        (reg->heartbeat_seconds > 300 ? 300 : reg->heartbeat_seconds);
    route->last_sequence = reg->sequence;
    route->last_seen_ms = now_ms();
    xSemaphoreGive(s_lock);
    /* A module can re-register with the same identity after reboot or DHCP
     * renewal.  Never reuse the TCP stream that points at its previous
     * process/endpoint, even when the IP and port happen to be unchanged. */
    invalidate_module_connections(reg->module_id);
    ESP_LOGI(TAG, "module=%s device=%s endpoint=http://%s:%u%s", reg->module_id,
        reg->device_id, peer_ip, reg->command_port, reg->command_path);
    return ESP_OK;
}

void external_module_unregister(const char *module_id, const char *device_id)
{
    if (!module_id || !device_id || !s_lock) return;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    module_route_t *route = find_route_locked(module_id, device_id);
    if (route) memset(route, 0, sizeof(*route));
    xSemaphoreGive(s_lock);
    invalidate_module_connections(module_id);
}

esp_err_t external_module_touch(const char *module_id, int64_t sequence)
{
    if (!module_id || sequence < 0) return ESP_ERR_INVALID_ARG;
    bool found = false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int64_t latest = module_last_sequence_locked(module_id);
    if (latest >= 0 && sequence <= latest) {
        xSemaphoreGive(s_lock);
        return ESP_ERR_INVALID_STATE;
    }
    for (size_t i = 0; i < YAOCORE_MAX_MODULES; ++i) {
        module_route_t *route = &s_routes[i];
        if (!route->used || strcmp(route->module_id, module_id)) continue;
        found = true;
        route->last_sequence = sequence;
        route->last_seen_ms = now_ms();
    }
    xSemaphoreGive(s_lock);
    return found ? ESP_OK : ESP_ERR_NOT_FOUND;
}

bool external_module_accept_sequence(const char *module_id, const char *device_id,
    int64_t sequence)
{
    if (!module_id || !device_id || sequence < 0) return false;
    bool accepted = false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    module_route_t *route = find_route_locked(module_id, device_id);
    int64_t latest = module_last_sequence_locked(module_id);
    if (route && sequence > latest) {
        route->last_sequence = sequence;
        route->last_seen_ms = now_ms();
        accepted = true;
    }
    xSemaphoreGive(s_lock);
    return accepted;
}

void external_module_note_response(const char *module_id, const char *device_id)
{
    if (!module_id || !device_id || !s_lock) return;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    module_route_t *route = find_route_locked(module_id, device_id);
    if (route) route->last_seen_ms = now_ms();
    xSemaphoreGive(s_lock);
}

static void timestamp_now(char output[17])
{
    time_t now = time(NULL); struct tm utc; gmtime_r(&now, &utc);
    strftime(output, 17, "%Y%m%dT%H%M%SZ", &utc);
}

static void random_nonce(char output[65])
{
    uint8_t bytes[32]; esp_fill_random(bytes, sizeof(bytes));
    for (size_t i = 0; i < sizeof(bytes); ++i) snprintf(output + i * 2, 3,
        "%02x", bytes[i]);
    output[64] = '\0';
}

static void copy_header_value(char *destination, size_t destination_size,
    const char *value, size_t value_length)
{
    if (!destination || destination_size == 0) return;
    while (value_length > 0 && (*value == ' ' || *value == '\t')) {
        ++value;
        --value_length;
    }
    while (value_length > 0 &&
        (value[value_length - 1] == ' ' || value[value_length - 1] == '\t')) {
        --value_length;
    }
    size_t copy_length = value_length < destination_size - 1 ?
        value_length : destination_size - 1;
    memcpy(destination, value, copy_length);
    destination[copy_length] = '\0';
}

static void capture_response_header(response_capture_t *capture,
    const char *line, size_t length, size_t *content_length)
{
    const char *colon = memchr(line, ':', length);
    if (!colon) return;
    size_t name_length = (size_t)(colon - line);
    const char *value = colon + 1;
    size_t value_length = length - name_length - 1;
    if (name_length == strlen("X-YaoCore-Timestamp") &&
        !strncasecmp(line, "X-YaoCore-Timestamp", name_length)) {
        copy_header_value(capture->timestamp, sizeof(capture->timestamp),
            value, value_length);
    } else if (name_length == strlen("X-YaoCore-Nonce") &&
        !strncasecmp(line, "X-YaoCore-Nonce", name_length)) {
        copy_header_value(capture->nonce, sizeof(capture->nonce), value,
            value_length);
    } else if (name_length == strlen("X-YaoCore-Sign") &&
        !strncasecmp(line, "X-YaoCore-Sign", name_length)) {
        copy_header_value(capture->signature, sizeof(capture->signature),
            value, value_length);
    } else if (name_length == strlen("X-YaoCore-Module-Id") &&
        !strncasecmp(line, "X-YaoCore-Module-Id", name_length)) {
        copy_header_value(capture->module_id, sizeof(capture->module_id),
            value, value_length);
    } else if (content_length && name_length == strlen("Content-Length") &&
        !strncasecmp(line, "Content-Length", name_length)) {
        char number[16];
        copy_header_value(number, sizeof(number), value, value_length);
        char *end = NULL;
        unsigned long parsed = strtoul(number, &end, 10);
        if (end != number && *end == '\0') *content_length = parsed;
    }
}

static bool send_all(int socket_fd, const char *data, size_t length)
{
    size_t sent = 0;
    while (sent < length) {
        int result = send(socket_fd, data + sent, length - sent, 0);
        if (result <= 0) return false;
        sent += (size_t)result;
    }
    return true;
}

static void close_module_connection(module_connection_t *connection)
{
    if (!connection) return;
    if (connection->socket_fd >= 0) {
        struct linger no_wait = { .l_onoff = 1, .l_linger = 0 };
        setsockopt(connection->socket_fd, SOL_SOCKET, SO_LINGER, &no_wait,
            sizeof(no_wait));
        close(connection->socket_fd);
    }
    memset(connection, 0, sizeof(*connection));
    connection->socket_fd = -1;
}

static void invalidate_module_connections(const char *module_id)
{
    if (!module_id || !module_id[0] || !s_transport_lock) return;
    xSemaphoreTake(s_transport_lock, portMAX_DELAY);
    for (size_t i = 0; i < MODULE_CONNECTION_CACHE_SIZE; ++i) {
        module_connection_t *connection = &s_connections[i];
        if (connection->used && !strcmp(connection->module_id, module_id))
            close_module_connection(connection);
    }
    xSemaphoreGive(s_transport_lock);
}

static module_connection_t *connection_for_route(const module_route_t *route)
{
    module_connection_t *free_slot = NULL;
    module_connection_t *oldest = &s_connections[0];
    for (size_t i = 0; i < MODULE_CONNECTION_CACHE_SIZE; ++i) {
        module_connection_t *connection = &s_connections[i];
        if (connection->used && !strcmp(connection->module_id,
            route->module_id) && !strcmp(connection->host, route->host) &&
            connection->port == route->port) return connection;
        if (!connection->used && !free_slot) free_slot = connection;
        if (connection->last_used_ms < oldest->last_used_ms) oldest = connection;
    }
    module_connection_t *selected = free_slot ? free_slot : oldest;
    close_module_connection(selected);
    selected->used = true;
    selected->socket_fd = -1;
    selected->port = route->port;
    selected->last_used_ms = now_ms();
    strlcpy(selected->module_id, route->module_id,
        sizeof(selected->module_id));
    strlcpy(selected->host, route->host, sizeof(selected->host));
    return selected;
}

static esp_err_t connect_module_socket(module_connection_t *connection)
{
    if (connection->socket_fd >= 0) return ESP_OK;
    struct sockaddr_in address = {
        .sin_family = AF_INET,
        .sin_port = htons(connection->port),
    };
    if (inet_pton(AF_INET, connection->host, &address.sin_addr) != 1)
        return ESP_ERR_INVALID_ARG;
    int socket_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
    if (socket_fd < 0) return ESP_FAIL;
    int enabled = 1;
    setsockopt(socket_fd, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled));
    struct timeval timeout = { .tv_sec = 3, .tv_usec = 500000 };
    setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(socket_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    if (connect(socket_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(socket_fd);
        return errno == EAGAIN || errno == ETIMEDOUT ? ESP_ERR_TIMEOUT :
            ESP_FAIL;
    }
    connection->socket_fd = socket_fd;
    connection->last_used_ms = now_ms();
    return ESP_OK;
}

/* WiFiS3 spends a substantial part of every command waiting for a fragmented
 * HTTP request. Build the complete request and issue it through one TCP send,
 * with Nagle disabled. The response remains ordinary signed HTTP/1.1, so this
 * is an on-wire optimization rather than a second device protocol. */
static esp_err_t perform_module_http(const module_route_t *route,
    const char *body, const char *timestamp, const char *nonce,
    const char *signature, response_capture_t *capture, int *status)
{
    if (!route || !body || !capture || !status) return ESP_ERR_INVALID_ARG;
    xSemaphoreTake(s_transport_lock, portMAX_DELAY);
    module_connection_t *connection = connection_for_route(route);
    esp_err_t result = connect_module_socket(connection);
    if (result != ESP_OK) {
        close_module_connection(connection);
        xSemaphoreGive(s_transport_lock);
        return result;
    }
    int socket_fd = connection->socket_fd;

    const char *format =
        "POST %s HTTP/1.1\r\n"
        "Host: %s:%u\r\n"
        "Connection: keep-alive\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %u\r\n"
        "X-YaoCore-Alg: %s\r\n"
        "X-YaoCore-Key-Id: %s\r\n"
        "X-YaoCore-Module-Id: %s\r\n"
        "X-YaoCore-Timestamp: %s\r\n"
        "X-YaoCore-Nonce: %s\r\n"
        "X-YaoCore-Sign: %s\r\n\r\n%s";
    int request_length = snprintf(NULL, 0, format, route->path, route->host,
        route->port, (unsigned)strlen(body), YAOCORE_ALGORITHM, YAOCORE_KEY_ID,
        route->module_id, timestamp, nonce, signature, body);
    if (request_length <= 0 || request_length > 4096) {
        result = ESP_ERR_INVALID_SIZE;
        goto failed;
    }
    char *request = malloc((size_t)request_length + 1);
    if (!request) {
        result = ESP_ERR_NO_MEM;
        goto failed;
    }
    snprintf(request, (size_t)request_length + 1, format, route->path,
        route->host, route->port, (unsigned)strlen(body), YAOCORE_ALGORITHM,
        YAOCORE_KEY_ID, route->module_id, timestamp, nonce, signature, body);
    bool sent = send_all(socket_fd, request, (size_t)request_length);
    free(request);
    if (!sent) {
        result = ESP_FAIL;
        goto failed;
    }

    size_t response_capacity = capture->body_size + 1024;
    char *raw = malloc(response_capacity);
    if (!raw) {
        result = ESP_ERR_NO_MEM;
        goto failed;
    }
    size_t received = 0;
    size_t expected_response_size = SIZE_MAX;
    bool peer_closed = false;
    while (received + 1 < response_capacity) {
        int count = recv(socket_fd, raw + received,
            response_capacity - received - 1, 0);
        if (count == 0) { peer_closed = true; break; }
        if (count < 0) {
            if (errno == EINTR) continue;
            break;
        }
        received += (size_t)count;
        raw[received] = '\0';

        /* Do not wait for the peer's TCP FIN after a complete HTTP response.
         * WiFiS3 occasionally keeps the socket in its modem close path for the
         * full receive timeout even though the signed ACK is already present.
         * Content-Length is mandatory in the module protocol, so the complete
         * frame can be consumed immediately and the next slider sample can be
         * forwarded without a multi-second outlier. */
        if (expected_response_size == SIZE_MAX) {
            char *complete_header = strstr(raw, "\r\n\r\n");
            if (complete_header) {
                size_t declared_length = SIZE_MAX;
                char *header_line = strstr(raw, "\r\n");
                header_line = header_line ? header_line + 2 : complete_header;
                while (header_line < complete_header) {
                    char *line_end = strstr(header_line, "\r\n");
                    if (!line_end || line_end > complete_header) break;
                    capture_response_header(capture, header_line,
                        (size_t)(line_end - header_line), &declared_length);
                    header_line = line_end + 2;
                }
                size_t header_size = (size_t)(complete_header + 4 - raw);
                if (declared_length != SIZE_MAX &&
                    declared_length < capture->body_size &&
                    header_size + declared_length < response_capacity) {
                    expected_response_size = header_size + declared_length;
                }
            }
        }
        if (expected_response_size != SIZE_MAX &&
            received >= expected_response_size) break;
    }
    raw[received] = '\0';
    char *header_end = strstr(raw, "\r\n\r\n");
    if (!header_end || sscanf(raw, "HTTP/%*u.%*u %d", status) != 1) {
        free(raw);
        result = ESP_ERR_INVALID_RESPONSE;
        goto failed;
    }
    size_t content_length = SIZE_MAX;
    char *line = strstr(raw, "\r\n");
    line = line ? line + 2 : header_end;
    while (line < header_end) {
        char *line_end = strstr(line, "\r\n");
        if (!line_end || line_end > header_end) break;
        capture_response_header(capture, line, (size_t)(line_end - line),
            &content_length);
        line = line_end + 2;
    }
    const char *response_body = header_end + 4;
    size_t available = received - (size_t)(response_body - raw);
    if (content_length == SIZE_MAX || content_length > available ||
        content_length >= capture->body_size) {
        free(raw);
        result = ESP_ERR_INVALID_SIZE;
        goto failed;
    }
    memcpy(capture->body, response_body, content_length);
    capture->body[content_length] = '\0';
    capture->used = content_length;
    free(raw);
    connection->last_used_ms = now_ms();
    if (peer_closed) close_module_connection(connection);
    xSemaphoreGive(s_transport_lock);
    return ESP_OK;

failed:
    close_module_connection(connection);
    xSemaphoreGive(s_transport_lock);
    return result;
}

static void add_command_value(cJSON *root, const gateway_command_t *command)
{
    if (command->value_type == VALUE_BOOL) cJSON_AddBoolToObject(root, "value",
        command->bool_value);
    else if (command->value_type == VALUE_NUMBER) cJSON_AddNumberToObject(root,
        "value", command->number_value);
    else if (command->value_type == VALUE_STRING) cJSON_AddStringToObject(root,
        "value", command->string_value);
    else cJSON_AddNullToObject(root, "value");
}

static bool valid_color_hex(const char *value)
{
    if (!value || strlen(value) != 7 || value[0] != '#') return false;
    for (size_t i = 1; i < 7; ++i) {
        bool digit = value[i] >= '0' && value[i] <= '9';
        bool upper = value[i] >= 'A' && value[i] <= 'F';
        if (!digit && !upper) return false;
    }
    return true;
}

static bool parse_reported_state(cJSON *state, device_type_t type,
    external_state_patch_t *patch)
{
    if (!cJSON_IsObject(state) || !patch) return false;
    memset(patch, 0, sizeof(*patch));
    cJSON *online = cJSON_GetObjectItemCaseSensitive(state, "online");
    if (cJSON_IsBool(online)) { patch->has_online = true; patch->online = cJSON_IsTrue(online); }
    cJSON *power = cJSON_GetObjectItemCaseSensitive(state, "power");
    if (cJSON_IsBool(power)) { patch->has_power = true; patch->power = cJSON_IsTrue(power); }
    cJSON *open = cJSON_GetObjectItemCaseSensitive(state, "open");
    if (cJSON_IsBool(open)) { patch->has_open = true; patch->open = cJSON_IsTrue(open); }
    cJSON *brightness = cJSON_GetObjectItemCaseSensitive(state, "brightness");
    if (cJSON_IsNumber(brightness) && brightness->valueint >= 0 && brightness->valueint <= 100) {
        patch->has_brightness = true; patch->brightness = brightness->valueint;
    }
    cJSON *color = cJSON_GetObjectItemCaseSensitive(state, "color");
    if (cJSON_IsString(color) && valid_color_hex(color->valuestring)) {
        patch->has_color = true;
        strlcpy(patch->color, color->valuestring, sizeof(patch->color));
    }
    cJSON *temperature = cJSON_GetObjectItemCaseSensitive(state, "temperature");
    cJSON *humidity = cJSON_GetObjectItemCaseSensitive(state, "humidity");
    if (cJSON_IsNumber(temperature) && cJSON_IsNumber(humidity)) {
        patch->has_environment = true; patch->temperature = temperature->valuedouble;
        patch->humidity = humidity->valuedouble;
    }
    cJSON *presence = cJSON_GetObjectItemCaseSensitive(state, "presence");
    if (cJSON_IsBool(presence)) { patch->has_presence = true; patch->presence = cJSON_IsTrue(presence); }
    cJSON *target = cJSON_GetObjectItemCaseSensitive(state, "targetTemperature");
    if (cJSON_IsNumber(target) && target->valuedouble >= 16 && target->valuedouble <= 30) {
        patch->has_target_temperature = true; patch->target_temperature = target->valuedouble;
    }
    cJSON *mode = cJSON_GetObjectItemCaseSensitive(state, "mode");
    if (cJSON_IsString(mode) && strlen(mode->valuestring) < sizeof(patch->mode)) {
        patch->has_mode = true; strlcpy(patch->mode, mode->valuestring, sizeof(patch->mode));
    }
    cJSON *position = cJSON_GetObjectItemCaseSensitive(state, "position");
    if (cJSON_IsNumber(position) && position->valueint >= 0 && position->valueint <= 100) {
        patch->has_position = true; patch->position = position->valueint;
    }
    cJSON *speed = cJSON_GetObjectItemCaseSensitive(state, "speed");
    if (cJSON_IsNumber(speed) && speed->valueint >= 0 && speed->valueint <= 100) {
        patch->has_speed = true; patch->speed = speed->valueint;
    }
    cJSON *volume = cJSON_GetObjectItemCaseSensitive(state, "volume");
    if (cJSON_IsNumber(volume) && volume->valueint >= 0 && volume->valueint <= 100) {
        patch->has_volume = true; patch->volume = volume->valueint;
    }
    if (type == DEVICE_DOOR) return patch->has_open;
    if (type == DEVICE_LIGHT) return patch->has_power && patch->has_brightness;
    if (type == DEVICE_SENSOR) return patch->has_environment || patch->has_presence;
    if (type == DEVICE_AC) return patch->has_power && patch->has_target_temperature && patch->has_mode;
    if (type == DEVICE_CURTAIN) return patch->has_position;
    if (type == DEVICE_FAN) return patch->has_power && patch->has_speed;
    if (type == DEVICE_SPEAKER) return patch->has_power && patch->has_volume;
    if (type == DEVICE_SWITCH) return patch->has_power;
    return patch->has_online;
}

static bool reported_effect_matches(const gateway_command_t *command,
    device_type_t type, const external_state_patch_t *state)
{
    if (!strcmp(command->action, "ON")) return state->has_power && state->power;
    if (!strcmp(command->action, "OFF")) return state->has_power && !state->power;
    if (type == DEVICE_DOOR && !strcmp(command->action, "OPEN"))
        return state->has_open && state->open;
    if (type == DEVICE_DOOR && !strcmp(command->action, "CLOSE"))
        return state->has_open && !state->open;
    if (type == DEVICE_CURTAIN && !strcmp(command->action, "OPEN"))
        return state->has_position && state->position == 100;
    if (type == DEVICE_CURTAIN && !strcmp(command->action, "CLOSE"))
        return state->has_position && state->position == 0;
    if (!strcmp(command->action, "STOP")) return type == DEVICE_CURTAIN &&
        state->has_position;
    if (!strcmp(command->action, "SET_BRIGHTNESS"))
        return state->has_brightness && fabs(state->brightness -
            command->number_value) < 0.51;
    if (!strcmp(command->action, "SET_COLOR"))
        return state->has_color && command->value_type == VALUE_STRING &&
            !strcmp(state->color, command->string_value);
    if (!strcmp(command->action, "SET_POSITION"))
        return state->has_position && fabs(state->position -
            command->number_value) < 0.51;
    if (!strcmp(command->action, "SET_SPEED"))
        return state->has_speed && fabs(state->speed -
            command->number_value) < 0.51;
    if (!strcmp(command->action, "SET_VOLUME"))
        return state->has_volume && fabs(state->volume -
            command->number_value) < 0.51;
    if (!strcmp(command->action, "SET_TARGET_TEMPERATURE"))
        return state->has_target_temperature && fabs(state->target_temperature -
            command->number_value) < 0.051;
    if (!strcmp(command->action, "SET_MODE")) return state->has_mode &&
        !strcmp(state->mode, command->string_value);
    return false;
}

esp_err_t external_module_execute(const gateway_command_t *command,
    device_type_t expected_type, external_state_patch_t *reported_state,
    int *result_code, char *message, size_t message_size)
{
    if (!command || !reported_state || !result_code || !message || message_size == 0)
        return ESP_ERR_INVALID_ARG;
    module_route_t route;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    module_route_t *found = find_device_locked(command->target);
    if (!found || found->last_seen_ms <= 0) {
        xSemaphoreGive(s_lock); return ESP_ERR_NOT_FOUND;
    }
    route = *found;
    xSemaphoreGive(s_lock);

    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "protocolVersion", YAOCORE_MODULE_PROTOCOL);
    cJSON_AddStringToObject(root, "requestId", command->request_id);
    cJSON_AddStringToObject(root, "targetDevice", command->target);
    cJSON_AddStringToObject(root, "action", command->action);
    add_command_value(root, command);
    cJSON_AddStringToObject(root, "source", command->source);
    if (command->trigger_device_id[0]) cJSON_AddStringToObject(root,
        "triggerDeviceId", command->trigger_device_id);
    if (command->automation_id[0]) cJSON_AddStringToObject(root,
        "automationId", command->automation_id);
    char *body = cJSON_PrintUnformatted(root); cJSON_Delete(root);
    if (!body) return ESP_ERR_NO_MEM;

    char timestamp[17], nonce[65], signature[65];
    timestamp_now(timestamp); random_nonce(nonce);
    if (!gateway_security_sign_module_message("command", route.module_id,
        timestamp, nonce, body, signature)) { free(body); return ESP_FAIL; }
    char response_body[1536] = {0};
    response_capture_t capture = { .body = response_body,
        .body_size = sizeof(response_body) };
    int status = 0;
    int64_t transport_started_ms = now_ms();
    esp_err_t err = perform_module_http(&route, body, timestamp, nonce,
        signature, &capture, &status);
    int64_t transport_finished_ms = now_ms();
    free(body);
    if (err != ESP_OK || status != 200 || !capture.used) {
        ESP_LOGW(TAG,
            "module command transport failed module=%s err=%s status=%d bytes=%u elapsed=%lldms",
            route.module_id, esp_err_to_name(err), status,
            (unsigned)capture.used,
            (long long)(transport_finished_ms - transport_started_ms));
        return err == ESP_OK ? ESP_FAIL : err;
    }
    if (strcmp(capture.module_id, route.module_id) ||
        !gateway_security_verify_module_message("command_ack", route.module_id,
            capture.timestamp, capture.nonce, capture.signature, response_body)) {
        ESP_LOGW(TAG, "module command ACK authentication failed module=%s transport=%lldms",
            route.module_id,
            (long long)(transport_finished_ms - transport_started_ms));
        return ESP_ERR_INVALID_CRC;
    }
    int64_t authenticated_ms = now_ms();
    cJSON *response = cJSON_Parse(response_body);
    if (!response) return ESP_ERR_INVALID_RESPONSE;
    cJSON *request_id = cJSON_GetObjectItemCaseSensitive(response, "requestId");
    cJSON *code = cJSON_GetObjectItemCaseSensitive(response, "resultCode");
    cJSON *text = cJSON_GetObjectItemCaseSensitive(response, "message");
    cJSON *state = cJSON_GetObjectItemCaseSensitive(response, "reportedState");
    bool envelope = cJSON_IsString(request_id) && !strcmp(request_id->valuestring,
        command->request_id) && cJSON_IsNumber(code) && cJSON_IsString(text);
    if (!envelope) { cJSON_Delete(response); return ESP_ERR_INVALID_RESPONSE; }
    *result_code = code->valueint;
    strlcpy(message, text->valuestring, message_size);
    bool state_ok = parse_reported_state(state, expected_type, reported_state);
    cJSON_Delete(response);
    if (!state_ok || *result_code != 0 ||
        !reported_effect_matches(command, expected_type, reported_state))
        return ESP_ERR_INVALID_RESPONSE;
    /* A command ACK proves liveness but is not a module-originated state
     * sequence. Advancing the inbound sequence here would reject the
     * module's next legitimate heartbeat/state event. */
    external_module_note_response(route.module_id, route.device_id);
    if (authenticated_ms - transport_started_ms > 1000) {
        ESP_LOGW(TAG,
            "slow module command module=%s transport=%lldms auth=%lldms",
            route.module_id,
            (long long)(transport_finished_ms - transport_started_ms),
            (long long)(authenticated_ms - transport_finished_ms));
    }
    return ESP_OK;
}
