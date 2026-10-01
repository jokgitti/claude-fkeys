#include "fkeys_leds.h"

const uint8_t fkey_led[FKEYS_COUNT] = {
    6, 12, 18, 23, 28, 34, 39, 44, 50, 56, 61, 66
};

static uint8_t  fkey_state[FKEYS_COUNT] = {0};
static uint8_t  fkey_palette[FKEYS_PALETTE_SLOTS][3] = {
    {  0,   0,   0},   // off
    {255, 149,   0},   // working
    {  0, 215,  95},   // idle
    {255,   0, 170},   // waiting
};
static uint16_t fkey_pulse_ms    = FKEYS_PULSE_MS;
static uint8_t  fkey_pulse_floor = FKEYS_PULSE_FLOOR;
static uint32_t fkey_last_report  = 0;
static bool     fkey_have_report  = false;

void fkeys_receive(const uint8_t *data, uint8_t length) {
    if (length < 13) return;

    switch (data[0]) {
        case FKEYS_CMD_SET_STATES:
            for (uint8_t i = 0; i < FKEYS_COUNT; i++) {
                uint8_t s = data[1 + i];
                fkey_state[i] = (s < FKEYS_PALETTE_SLOTS) ? s : 0;
            }
            break;

        case FKEYS_CMD_SET_PALETTE:
            for (uint8_t i = 0; i < FKEYS_PALETTE_SLOTS; i++) {
                fkey_palette[i][0] = data[1 + i * 3];
                fkey_palette[i][1] = data[2 + i * 3];
                fkey_palette[i][2] = data[3 + i * 3];
            }
            break;

        case FKEYS_CMD_SET_PULSE: {
            uint16_t period = (uint16_t)(data[1] | (data[2] << 8));
            if (period < FKEYS_PULSE_MIN_MS) return;
            fkey_pulse_ms    = period;
            fkey_pulse_floor = data[3];
            break;
        }

        default:
            return;
    }

    fkey_last_report = timer_read32();
    fkey_have_report = true;
}

// Triangle wave over fkey_pulse_ms, from fkey_pulse_floor to 255.
static uint8_t fkey_pulse(void) {
    uint16_t half  = fkey_pulse_ms / 2;
    uint16_t phase = timer_read32() % fkey_pulse_ms;
    uint16_t tri   = (phase < half) ? phase : (fkey_pulse_ms - phase);
    // An odd period gives half + 1 at phase == half, which would overflow 255.
    if (tri > half) tri = half;
    return fkey_pulse_floor + (uint32_t)tri * (255 - fkey_pulse_floor) / half;
}

bool fkeys_paint(uint8_t led_min, uint8_t led_max) {
    // The whole board is dark unless a fresh report binds an F-key. This runs
    // before the watchdog so it also applies when no report has ever arrived.
    uint8_t end = (led_max < FKEYS_LED_COUNT) ? led_max : FKEYS_LED_COUNT;
    for (uint8_t index = led_min; index < end; index++) {
        rgb_matrix_set_color(index, 0, 0, 0);
    }

    if (!fkey_have_report) return true;
    if ((uint32_t)(timer_read32() - fkey_last_report) > FKEYS_TIMEOUT_MS) return true;

    uint8_t pulse = fkey_pulse();

    for (uint8_t i = 0; i < FKEYS_COUNT; i++) {
        uint8_t index = fkey_led[i];
        if (index < led_min || index >= led_max) continue;

        uint8_t s = fkey_state[i];
        uint8_t r = fkey_palette[s][0];
        uint8_t g = fkey_palette[s][1];
        uint8_t b = fkey_palette[s][2];

        if (s == FKEYS_STATE_WAITING) {
            r = (uint16_t)r * pulse / 255;
            g = (uint16_t)g * pulse / 255;
            b = (uint16_t)b * pulse / 255;
        }

        rgb_matrix_set_color(index, r, g, b);
    }

    return true;
}
