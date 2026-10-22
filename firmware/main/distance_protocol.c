#include "distance_protocol.h"

void distance_encode(uint8_t out[DISTANCE_FRAME_SIZE], uint16_t sequence,
                     uint32_t uptime_ms, uint16_t distance_mm, uint8_t status, bool simulated)
{
    bool valid = status == 0 && distance_mm >= 40 && distance_mm <= 4000;
    if (!valid) {
        distance_mm = UINT16_MAX;
        if (status == 0) status = 1;
    }
    out[0] = 1;
    out[1] = (valid ? 1 : 0) | (simulated ? 2 : 0);
    out[2] = sequence; out[3] = sequence >> 8;
    out[4] = uptime_ms; out[5] = uptime_ms >> 8;
    out[6] = uptime_ms >> 16; out[7] = uptime_ms >> 24;
    out[8] = distance_mm; out[9] = distance_mm >> 8;
    out[10] = valid ? 0 : status;
    out[11] = 0;
}
