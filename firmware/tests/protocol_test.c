#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "distance_protocol.h"

int main(void)
{
    const uint8_t golden[] = {1,1,0x34,0x12,0x78,0x56,0x34,0x12,0xC2,1,0,0};
    uint8_t out[DISTANCE_FRAME_SIZE];
    distance_encode(out, 0x1234, 0x12345678, 450, 0, false);
    assert(memcmp(out, golden, sizeof(golden)) == 0);
    distance_encode(out, 0, 0, 0, 0, true);
    assert(out[1] == 2 && out[8] == 255 && out[9] == 255 && out[10] == 1);
    distance_encode(out, 65535, UINT32_MAX, 4000, 0, true);
    assert(out[1] == 3 && out[2] == 255 && out[3] == 255 && out[8] == 0xA0 && out[9] == 0x0F);
    distance_encode(out, 1, 1, 300, 2, false);
    assert(out[1] == 0 && out[10] == 2 && out[8] == 255 && out[9] == 255);
    puts("C protocol golden-frame and validity tests passed");
    return 0;
}
