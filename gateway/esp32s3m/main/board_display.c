/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

#include "board_display.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_check.h"
#include "esp_lcd_panel_commands.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#define LCD_HOST SPI2_HOST
#define LCD_WIDTH 160
#define LCD_HEIGHT 80
#define LCD_MOSI GPIO_NUM_11
#define LCD_SCLK GPIO_NUM_12
#define LCD_DC GPIO_NUM_40
#define LCD_CS GPIO_NUM_39
#define LCD_RST GPIO_NUM_38
#define LCD_BL GPIO_NUM_41

#define RGB565(r, g, b) (uint16_t)((((r) & 0xf8) << 8) | (((g) & 0xfc) << 3) | ((b) >> 3))
#define COLOR_BG RGB565(0, 0, 0)
#define COLOR_TITLE RGB565(0, 220, 255)
#define COLOR_TEXT RGB565(255, 255, 255)
#define COLOR_OK RGB565(40, 255, 110)
#define COLOR_ERROR RGB565(255, 80, 80)
#define COLOR_WAIT RGB565(255, 210, 0)
#define COLOR_MUTED RGB565(155, 170, 180)

static const char *TAG = "display";
static esp_lcd_panel_handle_t s_panel;
static SemaphoreHandle_t s_lock;
static uint16_t s_frame[LCD_WIDTH * LCD_HEIGHT];
static bool s_ready;
static char s_ip[16] = "0.0.0.0";

typedef struct {
    uint8_t command;
    uint8_t data[16];
    uint8_t data_length;
    uint16_t delay_ms;
} st7735s_init_command_t;

/* Exact initialization table from the Alientek DNESP32S3M 0.96-inch LCD
 * example.  The panel has an ST7735S controller with a 132x162 GRAM; only the
 * 160x80 window beginning at (1,26) is physically visible in landscape mode. */
static const st7735s_init_command_t ST7735S_INIT[] = {
    {0x11, {0}, 0, 120},
    {0x21, {0}, 0, 120},
    {0xB1, {0x05, 0x3A, 0x3A}, 3, 0},
    {0xB2, {0x05, 0x3A, 0x3A}, 3, 0},
    {0xB3, {0x05, 0x3A, 0x3A, 0x05, 0x3A, 0x3A}, 6, 0},
    {0xB4, {0x03}, 1, 0},
    {0xC0, {0x62, 0x02, 0x04}, 3, 0},
    {0xC1, {0xC0}, 1, 0},
    {0xC2, {0x0D, 0x00}, 2, 0},
    {0xC3, {0x8D, 0x6A}, 2, 0},
    {0xC4, {0x8D, 0xEE}, 2, 0},
    {0xC5, {0x0E}, 1, 0},
    {0xE0, {0x10, 0x0E, 0x02, 0x03, 0x0E, 0x07, 0x02, 0x07,
            0x0A, 0x12, 0x27, 0x37, 0x00, 0x0D, 0x0E, 0x10}, 16, 0},
    {0xE1, {0x10, 0x0E, 0x03, 0x03, 0x0F, 0x06, 0x02, 0x08,
            0x0A, 0x13, 0x26, 0x36, 0x00, 0x0D, 0x0E, 0x10}, 16, 0},
    {0x3A, {0x05}, 1, 0},       /* 16-bit RGB565 */
    {0x36, {0xA8}, 1, 0},       /* landscape, BGR scan order */
    {0x29, {0}, 0, 120},
};

static esp_err_t st7735s_initialize(esp_lcd_panel_io_handle_t io)
{
    for (size_t i = 0; i < sizeof(ST7735S_INIT) / sizeof(ST7735S_INIT[0]); ++i) {
        const st7735s_init_command_t *entry = &ST7735S_INIT[i];
        esp_err_t err = esp_lcd_panel_io_tx_param(io, entry->command,
            entry->data_length == 0 ? NULL : entry->data, entry->data_length);
        if (err != ESP_OK) return err;
        if (entry->delay_ms > 0) vTaskDelay(pdMS_TO_TICKS(entry->delay_ms));
    }
    return ESP_OK;
}

/* Five columns, seven rows.  Upper- and lower-case glyphs are kept distinct:
 * the provisioning PoP is case-sensitive, so changing its visual case would
 * tell the user to enter a value that the Security1 server will reject. */
static void glyph5x7(char c, uint8_t columns[5])
{
    const uint8_t *shape = NULL;
    switch (c) {
    case 'A': { static const uint8_t v[5]={0x7e,0x11,0x11,0x11,0x7e}; shape=v; break; }
    case 'B': { static const uint8_t v[5]={0x7f,0x49,0x49,0x49,0x36}; shape=v; break; }
    case 'C': { static const uint8_t v[5]={0x3e,0x41,0x41,0x41,0x22}; shape=v; break; }
    case 'D': { static const uint8_t v[5]={0x7f,0x41,0x41,0x22,0x1c}; shape=v; break; }
    case 'E': { static const uint8_t v[5]={0x7f,0x49,0x49,0x49,0x41}; shape=v; break; }
    case 'F': { static const uint8_t v[5]={0x7f,0x09,0x09,0x09,0x01}; shape=v; break; }
    case 'G': { static const uint8_t v[5]={0x3e,0x41,0x49,0x49,0x7a}; shape=v; break; }
    case 'H': { static const uint8_t v[5]={0x7f,0x08,0x08,0x08,0x7f}; shape=v; break; }
    case 'I': { static const uint8_t v[5]={0x00,0x41,0x7f,0x41,0x00}; shape=v; break; }
    case 'J': { static const uint8_t v[5]={0x20,0x40,0x41,0x3f,0x01}; shape=v; break; }
    case 'K': { static const uint8_t v[5]={0x7f,0x08,0x14,0x22,0x41}; shape=v; break; }
    case 'L': { static const uint8_t v[5]={0x7f,0x40,0x40,0x40,0x40}; shape=v; break; }
    case 'M': { static const uint8_t v[5]={0x7f,0x02,0x0c,0x02,0x7f}; shape=v; break; }
    case 'N': { static const uint8_t v[5]={0x7f,0x04,0x08,0x10,0x7f}; shape=v; break; }
    case 'O': { static const uint8_t v[5]={0x3e,0x41,0x41,0x41,0x3e}; shape=v; break; }
    case 'P': { static const uint8_t v[5]={0x7f,0x09,0x09,0x09,0x06}; shape=v; break; }
    case 'Q': { static const uint8_t v[5]={0x3e,0x41,0x51,0x21,0x5e}; shape=v; break; }
    case 'R': { static const uint8_t v[5]={0x7f,0x09,0x19,0x29,0x46}; shape=v; break; }
    case 'S': { static const uint8_t v[5]={0x46,0x49,0x49,0x49,0x31}; shape=v; break; }
    case 'T': { static const uint8_t v[5]={0x01,0x01,0x7f,0x01,0x01}; shape=v; break; }
    case 'U': { static const uint8_t v[5]={0x3f,0x40,0x40,0x40,0x3f}; shape=v; break; }
    case 'V': { static const uint8_t v[5]={0x1f,0x20,0x40,0x20,0x1f}; shape=v; break; }
    case 'W': { static const uint8_t v[5]={0x3f,0x40,0x38,0x40,0x3f}; shape=v; break; }
    case 'X': { static const uint8_t v[5]={0x63,0x14,0x08,0x14,0x63}; shape=v; break; }
    case 'Y': { static const uint8_t v[5]={0x07,0x08,0x70,0x08,0x07}; shape=v; break; }
    case 'Z': { static const uint8_t v[5]={0x61,0x51,0x49,0x45,0x43}; shape=v; break; }
    case 'a': { static const uint8_t v[5]={0x20,0x54,0x54,0x54,0x78}; shape=v; break; }
    case 'b': { static const uint8_t v[5]={0x7f,0x48,0x44,0x44,0x38}; shape=v; break; }
    case 'c': { static const uint8_t v[5]={0x38,0x44,0x44,0x44,0x20}; shape=v; break; }
    case 'd': { static const uint8_t v[5]={0x38,0x44,0x44,0x48,0x7f}; shape=v; break; }
    case 'e': { static const uint8_t v[5]={0x38,0x54,0x54,0x54,0x18}; shape=v; break; }
    case 'f': { static const uint8_t v[5]={0x08,0x7e,0x09,0x01,0x02}; shape=v; break; }
    case 'g': { static const uint8_t v[5]={0x0c,0x52,0x52,0x52,0x3e}; shape=v; break; }
    case 'h': { static const uint8_t v[5]={0x7f,0x08,0x04,0x04,0x78}; shape=v; break; }
    case 'i': { static const uint8_t v[5]={0x00,0x44,0x7d,0x40,0x00}; shape=v; break; }
    case 'j': { static const uint8_t v[5]={0x20,0x40,0x44,0x3d,0x00}; shape=v; break; }
    case 'k': { static const uint8_t v[5]={0x7f,0x10,0x28,0x44,0x00}; shape=v; break; }
    case 'l': { static const uint8_t v[5]={0x00,0x41,0x7f,0x40,0x00}; shape=v; break; }
    case 'm': { static const uint8_t v[5]={0x7c,0x04,0x18,0x04,0x78}; shape=v; break; }
    case 'n': { static const uint8_t v[5]={0x7c,0x08,0x04,0x04,0x78}; shape=v; break; }
    case 'o': { static const uint8_t v[5]={0x38,0x44,0x44,0x44,0x38}; shape=v; break; }
    case 'p': { static const uint8_t v[5]={0x7c,0x14,0x14,0x14,0x08}; shape=v; break; }
    case 'q': { static const uint8_t v[5]={0x08,0x14,0x14,0x18,0x7c}; shape=v; break; }
    case 'r': { static const uint8_t v[5]={0x7c,0x08,0x04,0x04,0x08}; shape=v; break; }
    case 's': { static const uint8_t v[5]={0x48,0x54,0x54,0x54,0x20}; shape=v; break; }
    case 't': { static const uint8_t v[5]={0x04,0x3f,0x44,0x40,0x20}; shape=v; break; }
    case 'u': { static const uint8_t v[5]={0x3c,0x40,0x40,0x20,0x7c}; shape=v; break; }
    case 'v': { static const uint8_t v[5]={0x1c,0x20,0x40,0x20,0x1c}; shape=v; break; }
    case 'w': { static const uint8_t v[5]={0x3c,0x40,0x30,0x40,0x3c}; shape=v; break; }
    case 'x': { static const uint8_t v[5]={0x44,0x28,0x10,0x28,0x44}; shape=v; break; }
    case 'y': { static const uint8_t v[5]={0x0c,0x50,0x50,0x50,0x3c}; shape=v; break; }
    case 'z': { static const uint8_t v[5]={0x44,0x64,0x54,0x4c,0x44}; shape=v; break; }
    case '0': { static const uint8_t v[5]={0x3e,0x51,0x49,0x45,0x3e}; shape=v; break; }
    case '1': { static const uint8_t v[5]={0x00,0x42,0x7f,0x40,0x00}; shape=v; break; }
    case '2': { static const uint8_t v[5]={0x42,0x61,0x51,0x49,0x46}; shape=v; break; }
    case '3': { static const uint8_t v[5]={0x21,0x41,0x45,0x4b,0x31}; shape=v; break; }
    case '4': { static const uint8_t v[5]={0x18,0x14,0x12,0x7f,0x10}; shape=v; break; }
    case '5': { static const uint8_t v[5]={0x27,0x45,0x45,0x45,0x39}; shape=v; break; }
    case '6': { static const uint8_t v[5]={0x3c,0x4a,0x49,0x49,0x30}; shape=v; break; }
    case '7': { static const uint8_t v[5]={0x01,0x71,0x09,0x05,0x03}; shape=v; break; }
    case '8': { static const uint8_t v[5]={0x36,0x49,0x49,0x49,0x36}; shape=v; break; }
    case '9': { static const uint8_t v[5]={0x06,0x49,0x49,0x29,0x1e}; shape=v; break; }
    case '.': { static const uint8_t v[5]={0x00,0x60,0x60,0x00,0x00}; shape=v; break; }
    case ':': { static const uint8_t v[5]={0x00,0x36,0x36,0x00,0x00}; shape=v; break; }
    case '-': { static const uint8_t v[5]={0x08,0x08,0x08,0x08,0x08}; shape=v; break; }
    case '/': { static const uint8_t v[5]={0x20,0x10,0x08,0x04,0x02}; shape=v; break; }
    default: { static const uint8_t blank[5]={0,0,0,0,0}; shape=blank; break; }
    }
    memcpy(columns, shape, 5);
}

static void fill(uint16_t color)
{
    for (size_t i = 0; i < LCD_WIDTH * LCD_HEIGHT; ++i) s_frame[i] = color;
}

static void pixel(int x, int y, uint16_t color)
{
    if (x >= 0 && x < LCD_WIDTH && y >= 0 && y < LCD_HEIGHT) {
        s_frame[y * LCD_WIDTH + x] = color;
    }
}

static void text(int x, int y, const char *value, uint16_t color, int scale)
{
    if (value == NULL) return;
    while (*value && x + 5 * scale <= LCD_WIDTH) {
        uint8_t columns[5];
        glyph5x7(*value++, columns);
        for (int col = 0; col < 5; ++col) {
            for (int row = 0; row < 7; ++row) {
                if ((columns[col] & (1U << row)) == 0) continue;
                for (int dy = 0; dy < scale; ++dy) {
                    for (int dx = 0; dx < scale; ++dx) pixel(x + col * scale + dx, y + row * scale + dy, color);
                }
            }
        }
        x += 6 * scale;
    }
}

static void render(const char *state, const char *detail, uint16_t state_color)
{
    if (!s_ready || xPortInIsrContext()) return;
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(250)) != pdTRUE) return;
    fill(COLOR_BG);
    text(4, 2, "YAOCORE", COLOR_TITLE, 1);
    for (int x = 4; x < 156; ++x) pixel(x, 12, COLOR_TITLE);
    /* The current state is the visual focus on every page. All state labels
     * fit the 160 px panel at 2x; supporting information stays at 1x. */
    text(4, 17, state, state_color, 2);
    text(4, 36, detail, COLOR_TEXT, 1);
    text(4, 50, "IP:", COLOR_TITLE, 1);
    text(28, 50, s_ip, COLOR_TEXT, 1);
    text(4, 68, "ESP32S3M GATEWAY", COLOR_MUTED, 1);
    esp_err_t err = esp_lcd_panel_draw_bitmap(s_panel, 0, 0, LCD_WIDTH, LCD_HEIGHT, s_frame);
    if (err != ESP_OK) ESP_LOGW(TAG, "LCD refresh failed: %s", esp_err_to_name(err));
    xSemaphoreGive(s_lock);
}

esp_err_t board_display_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) return ESP_ERR_NO_MEM;
    spi_bus_config_t bus = {
        .mosi_io_num = LCD_MOSI, .miso_io_num = GPIO_NUM_NC, .sclk_io_num = LCD_SCLK,
        .quadwp_io_num = GPIO_NUM_NC, .quadhd_io_num = GPIO_NUM_NC,
        .max_transfer_sz = sizeof(s_frame),
    };
    esp_err_t err = spi_bus_initialize(LCD_HOST, &bus, SPI_DMA_CH_AUTO);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) return err;
    esp_lcd_panel_io_handle_t io = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .cs_gpio_num = LCD_CS, .dc_gpio_num = LCD_DC, .spi_mode = 0,
        .pclk_hz = 40 * 1000 * 1000, .trans_queue_depth = 7,
        .lcd_cmd_bits = 8, .lcd_param_bits = 8,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST,
        &io_config, &io), TAG, "create panel IO");
    gpio_config_t backlight = {
        .pin_bit_mask = 1ULL << LCD_BL, .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE, .pull_down_en = GPIO_PULLDOWN_ENABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&backlight), TAG, "configure backlight");
    ESP_RETURN_ON_ERROR(gpio_set_level(LCD_BL, 0), TAG, "disable backlight during init");

    /* ESP-IDF 5.2 has no built-in ST7735 panel object.  The ST7789 panel
     * object is used only for its SPI RGB565 draw_bitmap implementation; its
     * generic initialization is deliberately not called. */
    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = LCD_RST,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_BGR,
        .data_endian = LCD_RGB_DATA_ENDIAN_BIG,
        .bits_per_pixel = 16,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_st7789(io, &panel_config, &s_panel), TAG, "create panel");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_reset(s_panel), TAG, "reset panel");
    ESP_RETURN_ON_ERROR(st7735s_initialize(io), TAG, "initialize ST7735S");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_set_gap(s_panel, 1, 26), TAG, "set panel gap");
    ESP_RETURN_ON_ERROR(gpio_set_level(LCD_BL, 1), TAG, "enable backlight");
    s_ready = true;
    ESP_LOGI(TAG, "Alientek DNESP32S3M ST7735S 160x80 LCD ready");
    board_display_show_starting();
    return ESP_OK;
}

void board_display_show_starting(void) { render("STARTING", "SYSTEM BOOT", COLOR_WAIT); }
void board_display_show_config_error(void) { render("CONFIG ERROR", "CHECK SERIAL", COLOR_ERROR); }
void board_display_show_ble_error(void) { render("BLE ERROR", "CHECK SERIAL", COLOR_ERROR); }

void board_display_show_provisioning(const char *name, const char *pop)
{
    if (!s_ready || xPortInIsrContext()) return;
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(250)) != pdTRUE) return;

    fill(COLOR_BG);
    text(4, 2, "YAOCORE", COLOR_TITLE, 1);
    for (int x = 4; x < 156; ++x) pixel(x, 12, COLOR_TITLE);
    text(4, 17, "BLE SETUP", COLOR_WAIT, 2);
    text(4, 36, "POP:", COLOR_TITLE, 1);

    /* Start the value on the same row as "POP:". The first row has room for
     * 22 value characters and the two continuation rows hold 25 each, which
     * covers the configured maximum of 64 bytes. */
    const char *value = pop == NULL ? "" : pop;
    size_t value_length = strlen(value);
    size_t offset = 0;
    if (value_length > 0) {
        char first[23];
        size_t count = value_length > 22 ? 22 : value_length;
        memcpy(first, value, count);
        first[count] = '\0';
        text(28, 36, first, COLOR_TEXT, 1);
        offset = count;
    } else {
        text(28, 36, "NOT CONFIGURED", COLOR_WAIT, 1);
    }
    for (size_t row = 0; row < 2 && offset < value_length; ++row) {
        char chunk[26];
        size_t remaining = value_length - offset;
        size_t count = remaining > 25 ? 25 : remaining;
        memcpy(chunk, value + offset, count);
        chunk[count] = '\0';
        text(4, 47 + (int)row * 11, chunk, COLOR_TEXT, 1);
        offset += count;
    }

    text(4, 70, name == NULL ? "YAOCORE-GW" : name, COLOR_MUTED, 1);
    esp_err_t err = esp_lcd_panel_draw_bitmap(s_panel, 0, 0, LCD_WIDTH, LCD_HEIGHT, s_frame);
    if (err != ESP_OK) ESP_LOGW(TAG, "LCD PoP refresh failed: %s", esp_err_to_name(err));
    xSemaphoreGive(s_lock);
}
void board_display_show_connecting(void) { render("WIFI CONNECT", "WAIT FOR ROUTER", COLOR_WAIT); }
void board_display_show_connected(const char *ip)
{
    if (ip != NULL) snprintf(s_ip, sizeof(s_ip), "%s", ip);
    render("WIFI ONLINE", "STARTING LAN", COLOR_OK);
}
void board_display_show_ready(const char *ip, int port)
{
    if (ip != NULL) snprintf(s_ip, sizeof(s_ip), "%s", ip);
    char detail[24]; snprintf(detail, sizeof(detail), "LAN READY PORT %d", port);
    render("ONLINE", detail, COLOR_OK);
}
void board_display_show_reconnecting(void) { render("RECONNECT", "CHECK ROUTER", COLOR_WAIT); }
void board_display_show_reset_countdown(int seconds_remaining)
{
    char detail[24];
    snprintf(detail, sizeof(detail), "KEEP HOLDING %d SEC", seconds_remaining);
    render("RESET WIFI", detail, COLOR_WAIT);
}
void board_display_show_wifi_cleared(void) { render("WIFI CLEARED", "RELEASE BOOT", COLOR_OK); }
void board_display_show_reset_failed(void) { render("RESET FAILED", "CHECK SERIAL", COLOR_ERROR); }
void board_display_show_restarting(void) { render("RESTARTING", "BLE SETUP NEXT", COLOR_WAIT); }
