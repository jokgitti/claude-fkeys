// Decode and paint logic for the fkeys keymap, kept free of QMK headers so it
// can be compiled and tested natively (see qmk/tests). The only two
// functions it calls but does not define are declared below; keymap.c's QMK
// build links the real ones, the native test build links stubs.
#pragma once

#include <stdbool.h>
#include <stdint.h>

// Provided by QMK's rgb_matrix driver / timer subsystem in the firmware
// build, and by stubs in the native test build. Signatures must match QMK's
// own declarations exactly (quantum/rgb_matrix/rgb_matrix.h, quantum/timer.h)
// — QMK is the authority here, not this header.
void rgb_matrix_set_color(int index, uint8_t r, uint8_t g, uint8_t b);
uint32_t timer_read32(void);

enum fkeys_command {
    FKEYS_CMD_SET_STATES  = 0x01,
    FKEYS_CMD_SET_PALETTE = 0x02,
};

#define FKEYS_COUNT           12
#define FKEYS_PALETTE_SLOTS    4
#define FKEYS_TIMEOUT_MS   10000
#define FKEYS_PULSE_MS      1500
#define FKEYS_PULSE_FLOOR     51   // 20% of 255
#define FKEYS_STATE_WAITING    3

// LED indices for F1..F12 on gmmk/pro/rev1/ansi. Verified in step 7 (hardware
// only — see the task report for what qmk/tests does and does not prove
// about this table).
extern const uint8_t fkey_led[FKEYS_COUNT];

// Called from keymap.c's raw_hid_receive. Ignores anything shorter than a
// full report or with an unknown command byte, per the wire contract.
void fkeys_receive(const uint8_t *data, uint8_t length);

// Called from keymap.c's rgb_matrix_indicators_advanced_user. Paints the
// twelve F-row LEDs inside [led_min, led_max) from the last-received state,
// applying the watchdog and the waiting-state pulse. Always returns true,
// matching QMK's "indicators handled, don't fall through" convention.
bool fkeys_paint(uint8_t led_min, uint8_t led_max);
