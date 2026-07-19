/* Copy to config.h, provision one physical product, and never commit secrets. */
#pragma once

/* Manufacturing identity: stable and unique for every physical product. */
#define YAOCORE_MODULE_ID "module.standard.rgb.01"
#define YAOCORE_DEVICE_ID "StandardRgbLight_01"
#define YAOCORE_MODULE_KEY_HEX "PASTE_64_LOWERCASE_HEX_DERIVED_MODULE_KEY"

/* Development network only. Production devices must use their vendor's
 * commissioning flow or a standard such as Matter instead of these values. */
#define YAOCORE_WIFI_SSID "TEST_NETWORK_SSID"
#define YAOCORE_WIFI_PASSWORD "TEST_NETWORK_PASSWORD"
#define YAOCORE_EXPECTED_GATEWAY_ID "gateway_01"

#define YAOCORE_DEVICE_BRAND "YaoCore"
#define YAOCORE_PRODUCT_MODEL "YaoCore UNO R4 RGB Light"

/* Common-cathode RGB LED: D3/D5/D6 through one resistor per channel. */
#define YAOCORE_RED_PIN 3
#define YAOCORE_GREEN_PIN 5
#define YAOCORE_BLUE_PIN 6
#define YAOCORE_COMMON_ANODE 0

/* 270-degree three-wire potentiometer: VCC=5V, GND=GND, OUT=A1. */
#define YAOCORE_COLOR_KNOB_PIN A1
#define YAOCORE_COLOR_KNOB_ADC_MIN 80
#define YAOCORE_COLOR_KNOB_ADC_MAX 4015

#define YAOCORE_STATUS_LED LED_BUILTIN
