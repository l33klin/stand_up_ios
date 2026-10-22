#pragma once
#include <stdbool.h>
#include "driver/i2c_master.h"
#include "esp_err.h"

typedef struct {
    i2c_master_bus_handle_t bus;
    i2c_master_dev_handle_t device;
} vl53l1x_t;

// Initialize with {0}. Calls are serialized by the sampling task.
esp_err_t vl53l1x_init(vl53l1x_t *sensor, int sda_gpio, int scl_gpio);
esp_err_t vl53l1x_read(vl53l1x_t *sensor, uint16_t *distance_mm, bool *valid);
