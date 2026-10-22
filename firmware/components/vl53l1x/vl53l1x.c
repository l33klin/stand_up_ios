// I²C port and bounded ranging flow for the ST VL53L1X default configuration.
// See default_configuration.h and NOTICE.md for upstream license and provenance.
#include "vl53l1x.h"
#include "default_configuration.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

#define TRY(call) do { esp_err_t vl53l1x_error_code = (call); if (vl53l1x_error_code != ESP_OK) return vl53l1x_error_code; } while (0)

static esp_err_t read_bytes(vl53l1x_t *s, uint16_t reg, uint8_t *out, size_t size)
{
    uint8_t address[] = {reg >> 8, reg};
    return i2c_master_transmit_receive(s->device, address, 2, out, size, 100);
}

static esp_err_t write_bytes(vl53l1x_t *s, uint16_t reg, const uint8_t *data, size_t size)
{
    uint8_t buffer[94];
    if (size > sizeof(buffer) - 2) return ESP_ERR_INVALID_SIZE;
    buffer[0] = reg >> 8; buffer[1] = reg;
    memcpy(buffer + 2, data, size);
    return i2c_master_transmit(s->device, buffer, size + 2, 100);
}

static esp_err_t write8(vl53l1x_t *s, uint16_t reg, uint8_t value) { return write_bytes(s, reg, &value, 1); }
static esp_err_t write16(vl53l1x_t *s, uint16_t reg, uint16_t value)
{
    uint8_t b[] = {value >> 8, value};
    return write_bytes(s, reg, b, 2);
}

static esp_err_t wait_ready(vl53l1x_t *s, int timeout_ms)
{
    uint8_t polarity;
    TRY(read_bytes(s, 0x0030, &polarity, 1));
    uint8_t expected = (polarity & 0x10) ? 0 : 1;
    int64_t deadline = esp_timer_get_time() + timeout_ms * 1000LL;
    while (esp_timer_get_time() < deadline) {
        uint8_t ready;
        TRY(read_bytes(s, 0x0031, &ready, 1));
        if ((ready & 1) == expected) return ESP_OK;
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    return ESP_ERR_TIMEOUT;
}

esp_err_t vl53l1x_init(vl53l1x_t *s, int sda_gpio, int scl_gpio)
{
    if (sda_gpio == scl_gpio) return ESP_ERR_INVALID_ARG;
    if (!s->bus) {
        i2c_master_bus_config_t bus = {
            .i2c_port = I2C_NUM_0, .sda_io_num = sda_gpio, .scl_io_num = scl_gpio,
            .clk_source = I2C_CLK_SRC_DEFAULT, .glitch_ignore_cnt = 7,
            .flags.enable_internal_pullup = true,
        };
        TRY(i2c_new_master_bus(&bus, &s->bus));
    }
    if (!s->device) {
        i2c_device_config_t device = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = 0x29, .scl_speed_hz = 100000};
        TRY(i2c_master_bus_add_device(s->bus, &device, &s->device));
    }
    TRY(i2c_master_probe(s->bus, 0x29, 100));
    // A soft reset also recovers after unplug/replug without reallocating the bus.
    TRY(write8(s, 0x0000, 0));
    vTaskDelay(pdMS_TO_TICKS(10));
    TRY(write8(s, 0x0000, 1));
    vTaskDelay(pdMS_TO_TICKS(100));
    int64_t deadline = esp_timer_get_time() + 1000000;
    uint8_t boot = 0;
    do {
        TRY(read_bytes(s, 0x00E5, &boot, 1));
        if (boot & 1) break;
        vTaskDelay(pdMS_TO_TICKS(10));
    } while (esp_timer_get_time() < deadline);
    if (!(boot & 1)) return ESP_ERR_TIMEOUT;
    uint8_t id[2];
    TRY(read_bytes(s, 0x010F, id, 2));
    if (id[0] != 0xEA || id[1] != 0xCC) return ESP_ERR_NOT_FOUND;
    TRY(write_bytes(s, 0x002D, vl53l1x_defaults, sizeof(vl53l1x_defaults)));
    TRY(write8(s, 0x0087, 0x40));
    TRY(wait_ready(s, 1000));
    TRY(write8(s, 0x0086, 1));
    TRY(write8(s, 0x0087, 0));
    TRY(write8(s, 0x0008, 9));
    TRY(write8(s, 0x000B, 0));
    // Long distance mode, 100ms timing budget, 200ms intermeasurement period.
    TRY(write8(s, 0x004B, 0x0A));
    TRY(write8(s, 0x0060, 0x0F));
    TRY(write8(s, 0x0063, 0x0D));
    TRY(write8(s, 0x0069, 0xB8));
    TRY(write16(s, 0x0078, 0x0F0D));
    TRY(write16(s, 0x007A, 0x0E0E));
    TRY(write16(s, 0x005E, 0x01CC));
    TRY(write16(s, 0x0061, 0x01EA));
    uint8_t pll_bytes[2];
    TRY(read_bytes(s, 0x00DE, pll_bytes, 2));
    uint16_t pll = ((uint16_t)pll_bytes[0] << 8 | pll_bytes[1]) & 0x3FF;
    if (!pll) return ESP_ERR_INVALID_RESPONSE;
    uint32_t period = (uint32_t)(pll * 200 * 1.075);
    uint8_t period_bytes[] = {period >> 24, period >> 16, period >> 8, period};
    TRY(write_bytes(s, 0x006C, period_bytes, 4));
    TRY(write8(s, 0x0086, 1));
    return write8(s, 0x0087, 0x40);
}

esp_err_t vl53l1x_read(vl53l1x_t *s, uint16_t *distance_mm, bool *valid)
{
    *valid = false;
    *distance_mm = UINT16_MAX;
    TRY(wait_ready(s, 180));
    // Read one coherent result block before clearing its interrupt.
    uint8_t result[15];
    TRY(read_bytes(s, 0x0089, result, sizeof(result)));
    TRY(write8(s, 0x0086, 1));
    uint8_t raw_status = result[0] & 0x1F;
    uint16_t mm = (uint16_t)result[13] << 8 | result[14];
    // ST ULD maps raw status 9 to range-valid (0). Reject partial/wrapped results.
    *valid = raw_status == 9 && mm >= 40 && mm <= 4000;
    if (*valid) *distance_mm = mm;
    return ESP_OK;
}
