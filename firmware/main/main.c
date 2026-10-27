#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sdkconfig.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "distance_protocol.h"
#include "vl53l1x.h"

static const char *TAG = "standup";
static const ble_uuid128_t service_uuid = BLE_UUID128_INIT(DISTANCE_SERVICE_UUID_BYTES);
static const ble_uuid128_t measurement_uuid = BLE_UUID128_INIT(DISTANCE_MEASUREMENT_UUID_BYTES);
static const ble_uuid128_t info_uuid = BLE_UUID128_INIT(DISTANCE_INFO_UUID_BYTES);
static QueueHandle_t sample_queue;
// Only the NimBLE host task accesses these connection/GATT variables.
static uint8_t latest_frame[DISTANCE_FRAME_SIZE];
static uint16_t connection = BLE_HS_CONN_HANDLE_NONE;
static uint16_t measurement_handle;
static bool subscribed;
static uint8_t own_address_type;
static struct ble_npl_callout notify_callout;

static void check_ble(int rc)
{
    if (rc != 0) { ESP_LOGE(TAG, "NimBLE initialization failed: %d", rc); abort(); }
}

#ifdef CONFIG_STANDUP_MOCK_SENSOR
static const char *firmware_info = "1.0.0;MOCK";
#else
static const char *firmware_info = "1.0.0;VL53L1X";
#endif

static void sample_task(void *arg)
{
    (void)arg;
    uint16_t sequence = 0;
#ifndef CONFIG_STANDUP_MOCK_SENSOR
    vl53l1x_t sensor = {0};
    bool initialized = false;
    int failures = 0;
    int64_t retry_at = 0;
    int64_t log_at = 0;
#endif
    for (;;) {
        uint16_t mm = UINT16_MAX;
        uint8_t status = 0;
        bool simulated = false;
#ifdef CONFIG_STANDUP_MOCK_SENSOR
        simulated = true;
        // Desk riser: 10cm seated / 45cm standing, ±2mm jitter.
        mm = ((esp_timer_get_time() / 15000000) % 2) ? 450 : 100;
        mm += (sequence % 5) - 2;
#else
        int64_t now = esp_timer_get_time();
        if (!initialized && now >= retry_at) {
            esp_err_t err = vl53l1x_init(&sensor, CONFIG_STANDUP_I2C_SDA, CONFIG_STANDUP_I2C_SCL);
            initialized = err == ESP_OK;
            retry_at = esp_timer_get_time() + 5000000;
            if (!initialized) ESP_LOGW(TAG, "VL53L1X init: %s; retry in 5s", esp_err_to_name(err));
            else ESP_LOGI(TAG, "VL53L1X ready (SDA=%d, SCL=%d, address=0x29)",
                          CONFIG_STANDUP_I2C_SDA, CONFIG_STANDUP_I2C_SCL);
        }
        if (initialized) {
            bool valid = false;
            esp_err_t err = vl53l1x_read(&sensor, &mm, &valid);
            status = err == ESP_ERR_TIMEOUT ? 3 : err != ESP_OK ? 2 : valid ? 0 : 1;
            if (err != ESP_OK) {
                failures++;
                if (failures >= 3) {
                    initialized = false;
                    failures = 0;
                    retry_at = esp_timer_get_time() + 5000000;
                }
            } else { failures = 0; }
        } else { status = 2; }
        // Keep hardware diagnostics readable without logging every BLE sample.
        if (esp_timer_get_time() >= log_at) {
            if (status == 0) ESP_LOGI(TAG, "VL53L1X distance: %u mm", (unsigned)mm);
            else ESP_LOGW(TAG, "VL53L1X sample invalid (status=%u)", (unsigned)status);
            log_at = esp_timer_get_time() + 5000000;
        }
#endif
        uint8_t frame[DISTANCE_FRAME_SIZE];
        distance_encode(frame, sequence++, (uint32_t)(esp_timer_get_time() / 1000), mm, status, simulated);
        xQueueOverwrite(sample_queue, frame);
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}

static int gatt_access(uint16_t conn_handle, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR) return BLE_ATT_ERR_READ_NOT_PERMITTED;
    int rc = arg ? os_mbuf_append(ctxt->om, firmware_info, strlen(firmware_info))
                 : os_mbuf_append(ctxt->om, latest_frame, sizeof(latest_frame));
    return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static const struct ble_gatt_svc_def services[] = {
    {.type = BLE_GATT_SVC_TYPE_PRIMARY, .uuid = &service_uuid.u,
     .characteristics = (struct ble_gatt_chr_def[]) {
        {.uuid = &measurement_uuid.u, .access_cb = gatt_access,
         .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY, .val_handle = &measurement_handle},
        {.uuid = &info_uuid.u, .access_cb = gatt_access, .arg = (void *)1, .flags = BLE_GATT_CHR_F_READ},
        {0}}},
    {0}
};

static int gap_event(struct ble_gap_event *event, void *arg);

static void advertise(void)
{
    // Legacy ADV fits 31 bytes: flags + complete 128-bit service UUID.
    // Put the local name in SCAN_RSP so iOS can scan with a service filter.
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = (ble_uuid128_t *)&service_uuid;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) { ESP_LOGE(TAG, "ADV fields: %d", rc); return; }
    struct ble_hs_adv_fields response = {0};
    const char *name = ble_svc_gap_device_name();
    response.name = (uint8_t *)name;
    response.name_len = strlen(name);
    response.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&response);
    if (rc != 0) { ESP_LOGE(TAG, "SCAN_RSP fields: %d", rc); return; }
    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(own_address_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL);
    if (rc != 0) ESP_LOGE(TAG, "ADV start: %d", rc);
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            connection = event->connect.conn_handle;
            subscribed = false;
            ESP_LOGI(TAG, "Phone connected");
        } else { advertise(); }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        connection = BLE_HS_CONN_HANDLE_NONE;
        subscribed = false;
        ESP_LOGI(TAG, "Disconnected; advertising again");
        advertise();
        break;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == measurement_handle) subscribed = event->subscribe.cur_notify;
        break;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        break;
    default:
        break;
    }
    return 0;
}

static void notify_tick(struct ble_npl_event *event)
{
    (void)event;
    // Crossing tasks through a length-one queue keeps snapshots coherent.
    xQueuePeek(sample_queue, latest_frame, 0);
    if (connection != BLE_HS_CONN_HANDLE_NONE && subscribed) {
        struct os_mbuf *payload = ble_hs_mbuf_from_flat(latest_frame, sizeof(latest_frame));
        if (payload) {
            int rc = ble_gatts_notify_custom(connection, measurement_handle, payload);
            if (rc != 0 && rc != BLE_HS_ENOTCONN) ESP_LOGW(TAG, "Notify skipped: %d", rc);
        }
    }
    ble_npl_callout_reset(&notify_callout, ble_npl_time_ms_to_ticks32(250));
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    check_ble(rc);
    rc = ble_hs_id_infer_auto(0, &own_address_type);
    check_ble(rc);
    uint8_t address[6];
    rc = ble_hs_id_copy_addr(own_address_type, address, NULL);
    check_ble(rc);
    char name[20];
    snprintf(name, sizeof(name), "StandUp-%02X%02X", address[1], address[0]);
    rc = ble_svc_gap_device_name_set(name);
    check_ble(rc);
    advertise();
    ble_npl_callout_reset(&notify_callout, ble_npl_time_ms_to_ticks32(250));
    ESP_LOGI(TAG, "%s ready (%s)", name, firmware_info);
}

static void on_reset(int reason)
{
    connection = BLE_HS_CONN_HANDLE_NONE;
    subscribed = false;
    ble_npl_callout_stop(&notify_callout);
    ESP_LOGW(TAG, "BLE host reset: %d", reason);
}

static void host_task(void *arg)
{
    (void)arg;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void app_main(void)
{
    esp_err_t rc = nvs_flash_init();
    if (rc == ESP_ERR_NVS_NO_FREE_PAGES || rc == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        rc = nvs_flash_init();
    }
    ESP_ERROR_CHECK(rc);
    sample_queue = xQueueCreate(1, DISTANCE_FRAME_SIZE);
    if (!sample_queue) abort();
    distance_encode(latest_frame, 0, 0, UINT16_MAX, 3, false);
    xQueueOverwrite(sample_queue, latest_frame);
    ESP_ERROR_CHECK(nimble_port_init());
    ble_svc_gap_init();
    ble_svc_gatt_init();
    check_ble(ble_gatts_count_cfg(services));
    check_ble(ble_gatts_add_svcs(services));
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sm_bonding = 0;
    ble_npl_callout_init(&notify_callout, nimble_port_get_dflt_eventq(), notify_tick, NULL);
    if (xTaskCreate(sample_task, "distance", 4096, NULL, 5, NULL) != pdPASS) abort();
    nimble_port_freertos_init(host_task);
}
