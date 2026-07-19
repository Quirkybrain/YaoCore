idf_component_register(
    SRCS
        "app_main.c"
        "gateway_config.c"
        "gateway_security.c"
        "hardware_drivers.c"
        "automation_engine.c"
        "external_module.c"
        "device_router.c"
        "network_manager.c"
        "local_server.c"
        "cloud_iotda.c"
        "board_display.c"
    INCLUDE_DIRS "."
    REQUIRES nvs_flash esp_wifi esp_event esp_netif esp_http_server esp_http_client mdns json mbedtls mqtt esp_timer driver esp_lcd wifi_provisioning bt
)
