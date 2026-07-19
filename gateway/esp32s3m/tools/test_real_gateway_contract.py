# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

import hashlib
import hmac
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class RealGatewayContractTests(unittest.TestCase):
    def source(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_component_registers_physical_driver_layer(self):
        cmake = self.source("main/CMakeLists.txt")
        self.assertIn('"hardware_drivers.c"', cmake)

    def test_light_uses_real_percentage_pwm(self):
        driver = self.source("main/hardware_drivers.c")
        router = self.source("main/device_router.c")
        self.assertIn("ledc_set_duty", driver)
        self.assertIn("ledc_update_duty", driver)
        self.assertIn("s_ledc_max_duty * percent", driver)
        self.assertNotIn("brightness = 50", router)
        self.assertNotIn("gpio_set_level(cfg->light_gpio", router)

    def test_sht30_requires_crc_valid_real_samples(self):
        driver = self.source("main/hardware_drivers.c")
        for marker in (
            "i2c_master_write_to_device",
            "i2c_master_read_from_device",
            "sht30_crc(data, 2)",
            "consecutive_failures >= 3",
            "HARDWARE_EVENT_SENSOR",
        ):
            self.assertIn(marker, driver)

    def test_sensor_events_drive_confirmed_local_automation_with_manual_override(self):
        driver = self.source("main/hardware_drivers.c")
        automation = self.source("main/automation_engine.c")
        router = self.source("main/device_router.c")
        for marker in (
            "pir_task",
            "cfg->pir_timeout_seconds",
            "HARDWARE_EVENT_PRESENCE",
            ".presence = true",
            ".presence = false",
        ):
            self.assertIn(marker, driver)
        for marker in (
            "PRESENCE_LIGHT_RULE",
            "TEMPERATURE_AC_RULE",
            "config->pir_light_brightness",
            "s_presence_owns_light",
            "s_temperature_owns_ac",
            "automation_engine_note_external_command",
            "ack.has_reported_state",
        ):
            self.assertIn(marker, automation)
        self.assertIn("automation_engine_on_sensor_state", router)
        self.assertNotIn("set_light_locked((uint8_t)cfg->pir_light_brightness", driver)

    def test_door_feedback_gates_success(self):
        driver = self.source("main/hardware_drivers.c")
        router = self.source("main/device_router.c")
        self.assertIn("cfg->door_feedback_gpio", driver)
        self.assertIn("observed == open", driver)
        self.assertIn("ESP_ERR_TIMEOUT", driver)
        self.assertIn("ACTUATION_UNCONFIRMED", router)
        self.assertIn("ACTUATION_ACCEPTED_UNCONFIRMED", router)
        for marker in (
            "door_feedback_task",
            "door_feedback_poll_interval_ms",
            "door_feedback_debounce_ms",
            "HARDWARE_EVENT_DOOR",
            "candidate != s_door_last_reported_open",
        ):
            self.assertIn(marker, driver + router)

    def test_door_and_light_transactions_cover_driver_and_state_commit(self):
        driver = self.source("main/hardware_drivers.c")
        router = self.source("main/device_router.c")
        self.assertIn("s_door_lock = xSemaphoreCreateMutex()", driver)
        self.assertIn("s_light_lock = xSemaphoreCreateMutex()", driver)
        door = router.split("static esp_err_t execute_door", 1)[1].split(
            "static esp_err_t execute_light", 1)[0]
        light = router.split("static esp_err_t execute_light", 1)[1].split(
            "static esp_err_t execute_ac", 1)[0]
        self.assertLess(door.index("hardware_door_transaction_begin"),
                        door.index("hardware_door_set_locked"))
        self.assertLess(door.index("hardware_door_set_locked"),
                        door.index("door->updated_at_ms"))
        self.assertLess(door.index("door->updated_at_ms"),
                        door.index("hardware_door_transaction_end"))
        self.assertLess(light.index("hardware_light_transaction_begin"),
                        light.index("hardware_light_set_percent_locked"))
        self.assertLess(light.index("hardware_light_set_percent_locked"),
                        light.index("light->updated_at_ms"))
        self.assertLess(light.index("light->updated_at_ms"),
                        light.index("hardware_light_transaction_end"))
        route = router.split("bool ac_power", 1)[1].split(
            "fail(ack, 2002", 1)[0]
        self.assertLess(route.index("xSemaphoreTake(s_ac_state_lock"),
                        route.index("execute_ac"))
        self.assertLess(route.index("execute_ac"),
                        route.index("xSemaphoreGive(s_ac_state_lock"))

    def test_successful_commands_publish_exact_correlation_provenance(self):
        types = self.source("main/gateway_types.h")
        router = self.source("main/device_router.c")
        local = self.source("main/local_server.c")
        cloud = self.source("main/cloud_iotda.c")
        for marker in ("has_last_command", "last_request_id", "last_seq"):
            self.assertIn(marker, types)
        self.assertGreaterEqual(router.count("has_last_command = true"), 3)
        self.assertIn('"lastRequestId"', local)
        self.assertIn('"lastSeq"', local)
        for prefix in ("Door_01", "Light_01", "AC_01"):
            self.assertIn(f'"{prefix}_LastRequestId"', cloud)
            self.assertIn(f'"{prefix}_LastSeq"', cloud)

    def test_ac_state_requires_matching_structured_ack(self):
        driver = self.source("main/hardware_drivers.c")
        router = self.source("main/device_router.c")
        for marker in (
            '"requestId"',
            '"brand"',
            '"target"',
            '"action"',
            '"resultCode"',
            '"targetTemperature"',
            '"HANDSHAKE"',
        ):
            self.assertIn(marker, driver)
        self.assertIn("DOWNSTREAM_NO_ACK", router)
        self.assertIn("southbound AC ACK confirmed", router)

    def test_ac_health_monitor_serializes_uart_and_reports_transitions(self):
        driver = self.source("main/hardware_drivers.c")
        router = self.source("main/device_router.c")
        cloud = self.source("main/cloud_iotda.c")
        readme = self.source("README.md")

        query = driver.split("esp_err_t hardware_ac_health_query", 1)[1].split(
            "esp_err_t hardware_drivers_init", 1)[0]
        execute = driver.split("esp_err_t hardware_ac_execute", 1)[1].split(
            "esp_err_t hardware_ac_health_query", 1)[0]
        self.assertIn("xSemaphoreTake(s_ac_command_lock", query)
        self.assertIn("xSemaphoreGive(s_ac_command_lock)", query)
        self.assertIn("xSemaphoreTake(s_ac_command_lock", execute)
        self.assertIn('"STATUS_QUERY"', query)
        self.assertIn('"HANDSHAKE"', query)
        self.assertIn("s_ac_handshake_confirmed = result == ESP_OK", query)

        task = router.split("static void ac_health_task", 1)[1].split(
            "static esp_err_t configure_board_led", 1)[0]
        self.assertLess(task.index("xSemaphoreTake(s_ac_state_lock"),
                        task.index("hardware_ac_health_query(&observed"))
        self.assertLess(task.index("hardware_ac_health_query(&observed"),
                        task.index("ac->online = false"))
        self.assertLess(task.index("ac->online = false"),
                        task.index("xSemaphoreGive(s_ac_state_lock"))
        for marker in (
            "s_ac_health_failures",
            "ac_health_failure_threshold",
            "ac_health_interval_seconds",
            "ac->online = true",
            "ac->online = false",
            "notify_state(&changed_state)",
            'xTaskCreate(ac_health_task, "ac_health"',
        ):
            self.assertIn(marker, router)
        self.assertIn("xTaskNotifyGive(s_report_task)", cloud)
        self.assertIn("主动推送空调遥控器变化属于后续协议扩展", readme)
        self.assertIn("周期 `STATUS_QUERY`", readme)

        # Failure threshold is consecutive; one valid full-state response
        # restores online immediately instead of waiting for another command.
        def transitions(results, threshold=3):
            online, failures, observed = True, 0, []
            for success in results:
                if success:
                    failures, online = 0, True
                else:
                    failures = min(failures + 1, threshold)
                    if failures >= threshold:
                        online = False
                observed.append(online)
            return observed

        self.assertEqual([True, True, False, True],
                         transitions([False, False, False, True]))

    def test_online_state_is_earned_and_changes_are_observable(self):
        router = self.source("main/device_router.c")
        self.assertIn("device->online = false", router)
        self.assertIn("initial.ac_online", router)
        self.assertIn("device_router_set_state_callback", router)
        self.assertIn("after releasing s_lock", router)

    def test_cloud_reports_real_connectivity_and_all_online_flags(self):
        cloud = self.source("main/cloud_iotda.c")
        config = self.source("main/gateway_config.c")
        for marker in (
            "Door_01_Online",
            "Light_01_Online",
            "Sensor_01_Online",
            "Presence_01_Online",
            "AC_01_Online",
            "esp_wifi_sta_get_ap_info",
            "int gateway_rssi = -127",
            'cJSON_AddNumberToObject(properties, "Gateway_RSSI", gateway_rssi)',
            "iotda_report_interval_seconds",
            "xTaskNotifyGive",
            '"mqtts://"',
        ):
            self.assertIn(marker, cloud + config)
        self.assertNotIn("Gateway_RSSI\", -50", cloud)

    def test_http_and_mqtt_fragmented_payloads_are_accumulated(self):
        local = self.source("main/local_server.c")
        cloud = self.source("main/cloud_iotda.c")
        self.assertIn("while (received < (size_t)req->content_len)", local)
        self.assertIn("current_data_offset", cloud)
        self.assertIn("total_data_len", cloud)

    def test_local_http_responses_are_body_bound_and_authenticated(self):
        security = self.source("main/gateway_security.c")
        local = self.source("main/local_server.c")
        for marker in (
            "gateway_security_sign_response",
            "mbedtls_md(info",
            '"YAOCORE-RESPONSE-V1\\n%s\\n%s\\n%s"',
            "mbedtls_md_hmac",
        ):
            self.assertIn(marker, security)
        for header in (
            "X-YaoCore-Response-Alg",
            "X-YaoCore-Key-Id",
            "X-YaoCore-Response-Correlation",
            "X-YaoCore-Response-Sign",
        ):
            self.assertIn(header, local)
        self.assertIn('httpd_req_get_hdr_value_len(req, "X-YaoCore-Challenge") != 32', local)
        self.assertIn("value[i] >= 'a' && value[i] <= 'f'", local)
        self.assertIn('snprintf(correlation, sizeof(correlation), "%s:%d"', local)

        discover = local.split("static esp_err_t discover_handler", 1)[1].split(
            "static bool copy_string", 1)[0]
        control = local.split("static esp_err_t control_handler", 1)[1].split(
            "static void udp_task", 1)[0]
        self.assertLess(discover.index("set_authenticated_response_headers"),
                        discover.index("httpd_resp_sendstr"))
        self.assertLess(control.index("set_authenticated_response_headers"),
                        control.index("httpd_resp_sendstr"))
        self.assertIn("HTTPD_500_INTERNAL_SERVER_ERROR", discover)
        self.assertIn("HTTPD_500_INTERNAL_SERVER_ERROR", control)

        secret = b"0123456789abcdef"
        body = '{"ok":true}'
        correlation = "0123456789abcdef0123456789abcdef"
        body_hash = hashlib.sha256(body.encode("utf-8")).hexdigest()
        canonical = f"YAOCORE-RESPONSE-V1\ndiscover\n{correlation}\n{body_hash}"
        signature = hmac.new(secret, canonical.encode("utf-8"), hashlib.sha256).hexdigest()
        self.assertEqual("4062edaf750fb8074e7e83e0c9028c94e32468a8b6f1614774328ef045150f93",
                         body_hash)
        self.assertEqual("af96f10fe296e578bdcb757ca005de952f849cf423258cffcc0d6b0e00946ae4",
                         signature)

    def test_discovery_request_is_authenticated_before_full_snapshot(self):
        security = self.source("main/gateway_security.c")
        local = self.source("main/local_server.c")
        for marker in (
            "gateway_security_verify_discovery_request",
            '"YAOCORE-DISCOVER-V2\\n%s\\n%s\\n%s\\n%s\\n%s"',
            "constant_time_equal(expected, signature)",
            "X-YaoCore-Request-Timestamp",
            "X-YaoCore-Request-Nonce",
            "X-YaoCore-Request-Alg",
            "X-YaoCore-Request-Sign",
            "HTTPD_401_UNAUTHORIZED",
            "HTTPD_403_FORBIDDEN",
        ):
            self.assertIn(marker, security + local)
        discover = local.split("static esp_err_t discover_handler", 1)[1].split(
            "static bool copy_string", 1)[0]
        self.assertLess(discover.index("gateway_security_verify_discovery_request"),
                        discover.index("local_server_create_discovery_json"))
        challenge = "0123456789abcdef0123456789abcdef"
        timestamp = "20260716T120000Z"
        nonce = "fedcba98765432100123456789abcdef"
        canonical = (f"YAOCORE-DISCOVER-V2\n{challenge}\n{timestamp}\n{nonce}\n"
                     "HMAC-SHA256\napp-key-v1")
        signature = hmac.new(b"0123456789abcdef", canonical.encode("utf-8"),
                             hashlib.sha256).hexdigest()
        self.assertEqual("97efb70951b827c43a2596a354a591081e50a0239b2f03f697228dcdbfbf664e",
                         signature)
        for marker in (
            "FRESHNESS_SECONDS",
            "s_discovery_cache",
            "NONCE_TTL_SECONDS",
            "now - signed_time",
            "strcmp(s_discovery_cache[i].nonce, nonce)",
        ):
            self.assertIn(marker, security)

    def test_udp_discovery_exposes_candidate_identity_only(self):
        local = self.source("main/local_server.c")
        candidate = local.split("static char *create_udp_candidate_json", 1)[1].split(
            "static esp_err_t discover_handler", 1)[0]
        for field in ("protocolVersion", "gatewayId", "gatewayName", "serviceId", "port"):
            self.assertIn(f'"{field}"', candidate)
        self.assertNotIn('"devices"', candidate)
        self.assertNotIn("device_router_snapshot", candidate)
        udp = local.split("static void udp_task", 1)[1].split(
            "esp_err_t local_server_start", 1)[0]
        self.assertIn("create_udp_candidate_json", udp)
        self.assertNotIn("local_server_create_discovery_json", udp)

    def test_command_string_canonical_matches_json_stringify_controls(self):
        security = self.source("main/gateway_security.c")
        self.assertIn("cJSON_CreateString", security)
        self.assertIn("cJSON_PrintUnformatted", security)
        self.assertIn("COMMAND_CANONICAL_MAX 1024", security)
        self.assertNotIn("char value[96]", security)
        value = 'quote" slash\\ newline\n tab\t back\b form\f return\r ctrl\x01'
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        canonical = "\n".join([
            "req-special", "2001", "7", "AC_01", "SET_MODE", encoded,
            "20260716T120000Z", "0123456789abcdef0123456789abcdef",
            "HMAC-SHA256", "app-key-v1"
        ])
        signature = hmac.new(b"0123456789abcdef", canonical.encode("utf-8"),
                             hashlib.sha256).hexdigest()
        self.assertEqual('"quote\\" slash\\\\ newline\\n tab\\t back\\b form\\f return\\r ctrl\\u0001"',
                         encoded)
        self.assertEqual("ef311a9842b2395e51e8bd02b20b0c974dfce4747b190ceb47578a721aef7651",
                         signature)

    def test_offline_cold_boot_uses_authenticated_persistent_time_barrier(self):
        security = self.source("main/gateway_security.c")
        app_main = self.source("main/app_main.c")
        for marker in (
            "SECURITY_NVS_EPOCH_KEY",
            "nvs_get_i64",
            "nvs_set_i64",
            "nvs_commit",
            "s_boot_epoch_floor",
            "PERSISTENT_REPLAY",
            "settimeofday",
            "AUTH_TIME_MIN_EPOCH",
            "AUTH_TIME_MAX_EPOCH",
        ):
            self.assertIn(marker, security)
        # HMAC verification must happen before any signed timestamp can set time.
        verify_body = security.split(
            "bool gateway_security_verify(const gateway_command_t *cmd", 1
        )[1]
        self.assertLess(verify_body.index("signature_matches"),
                        verify_body.index("settimeofday"))
        # LAN starts as soon as DHCP succeeds; trusted cloud still waits for SNTP.
        self.assertLess(app_main.index("local_server_start"),
                        app_main.index("NETWORK_TIME_READY_BIT"))
        self.assertNotIn("nvs_flash_erase", app_main)

        # Logical replay model: every prior-boot timestamp is blocked, while two
        # distinct current-boot commands may share the same second above floor.
        persisted_floor = 1_750_000_000
        accepted_after_reboot = lambda timestamp: timestamp > persisted_floor
        self.assertFalse(accepted_after_reboot(persisted_floor))
        self.assertFalse(accepted_after_reboot(persisted_floor - 1))
        current_second = persisted_floor + 1
        self.assertTrue(accepted_after_reboot(current_second))
        self.assertTrue(accepted_after_reboot(current_second))

    def test_menuconfig_exposes_all_real_hardware_parameters(self):
        kconfig = self.source("main/Kconfig.projbuild")
        for option in (
            "YAOCORE_DOOR_FEEDBACK_GPIO",
            "YAOCORE_DOOR_FEEDBACK_POLL_INTERVAL_MS",
            "YAOCORE_DOOR_FEEDBACK_DEBOUNCE_MS",
            "YAOCORE_LIGHT_PWM_FREQUENCY_HZ",
            "YAOCORE_SHT30_ENABLE",
            "YAOCORE_PIR_GPIO",
            "YAOCORE_AC_UART_TX_GPIO",
            "YAOCORE_AC_HEALTH_INTERVAL_SECONDS",
            "YAOCORE_AC_HEALTH_FAILURE_THRESHOLD",
            "YAOCORE_AC_BRAND",
            "YAOCORE_IOTDA_REPORT_INTERVAL_SECONDS",
        ):
            self.assertIn(option, kconfig)


if __name__ == "__main__":
    unittest.main()
