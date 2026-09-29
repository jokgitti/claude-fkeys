// Native contract test for qmk/keymaps/fkeys/fkeys_leds.c.
//
// Runs one scenario per process invocation (argv[1] selects it) so every
// scenario starts from fkeys_leds.c's true initial static state, with no
// reset hook added to the production file just for tests.
//
// Byte payloads for the "mixed"/"window"/"pulse" scenarios are the real
// SET_PALETTE/SET_STATES reports fkeysd printed for a known tab/session
// fixture (see run.sh) — not hand-typed literals — so a mismatch here is
// either an fkeys_leds.c bug or a Swift/C wire-format disagreement, not a
// disagreement with this file's own assumptions about the format.
//
// The "malformed" and "short" scenarios are the exception: fkeysd never
// emits a bad command byte or an undersized report, so there is no real
// encoder output to capture. Those two hand-craft the bad bytes on purpose,
// to test robustness fkeysd's own output can never exercise.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>

#include "fkeys_leds.h"

// ---- stubs for the two functions fkeys_leds.c is allowed to call ----

typedef struct { uint8_t index, r, g, b; } paint_call_t;

#define MAX_CALLS 256
static paint_call_t g_calls[MAX_CALLS];
static int g_call_count = 0;
static uint32_t g_mock_time = 0;

// Signature matches QMK's real quantum/rgb_matrix/rgb_matrix.h declaration
// (index is `int`, not `uint8_t` — see fkeys_leds.h). Recorded LED indices
// are always small (<98, see fkey_led), so narrowing back to uint8_t for
// storage changes no behaviour.
void rgb_matrix_set_color(int index, uint8_t r, uint8_t g, uint8_t b) {
    if (g_call_count < MAX_CALLS) {
        g_calls[g_call_count++] = (paint_call_t){(uint8_t)index, r, g, b};
    }
}

uint32_t timer_read32(void) {
    return g_mock_time;
}

static void reset_calls(void) { g_call_count = 0; }

// ---- test bookkeeping ----

static int g_failures = 0;

static void fail(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    printf("FAIL  ");
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
    g_failures++;
}

static void ok(const char *what) {
    printf("ok    %s\n", what);
}

// ---- hex parsing ----

// Parses whitespace-separated hex byte tokens (as fkeysd prints them) into
// `out`. Returns the number of bytes parsed.
static int parse_hex(const char *str, uint8_t *out, int max_len) {
    int n = 0;
    const char *p = str;
    while (*p && n < max_len) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        unsigned int byte;
        if (sscanf(p, "%2x", &byte) != 1) break;
        out[n++] = (uint8_t)byte;
        p += 2;
    }
    return n;
}

static const uint8_t expected_led[FKEYS_COUNT] = {
    6, 12, 18, 23, 28, 34, 39, 44, 50, 56, 61, 66
};

// Independent literal copies of the brief's contract values (task-8-brief.md:
// 10000ms watchdog, 1500ms pulse period, pulse floor 51, command 0x01) rather
// than fkeys_leds.h's own macros: if a future edit to that header drifted
// from the contract, deriving expectations from the same macro under test
// would hide the drift instead of catching it.
#define EXPECT_TIMEOUT_MS      10000
// Defaults when no SET_PULSE has been received (user-chosen: 700 ms, floor 0).
#define EXPECT_DEFAULT_PULSE_MS    700
#define EXPECT_DEFAULT_PULSE_FLOOR   0
// The fixture pulse from run.sh's palette.json ("period_ms": 900, "floor": 30),
// distinct from the defaults so a decoder ignoring the report cannot pass.
#define EXPECT_FIXTURE_PULSE_MS    900
#define EXPECT_FIXTURE_PULSE_FLOOR  30
#define EXPECT_CMD_SET_STATES   0x01
#define EXPECT_CMD_SET_PULSE    0x03

// Finds the final recorded call for `index` (the colour QMK ends up with, since
// a later rgb_matrix_set_color overwrites an earlier one), or NULL if that
// index was never painted. fkeys_paint paints black first and F-keys on top,
// so an F-row index has two calls and the last one is the one that counts.
static paint_call_t *find_call(uint8_t index) {
    for (int i = g_call_count - 1; i >= 0; i--) {
        if (g_calls[i].index == index) return &g_calls[i];
    }
    return NULL;
}

static bool is_fkey_led(int index) {
    for (int i = 0; i < FKEYS_COUNT; i++) {
        if (expected_led[i] == index) return true;
    }
    return false;
}

// Literal copy of the board's LED count (98 entries in gmmk/pro/rev1/ansi
// keyboard.json), independent of FKEYS_LED_COUNT for the same reason as EXPECT_*.
#define EXPECT_LED_COUNT 98

// Asserts every index in [lo, hi) that is not an F-row LED has final colour
// black, and that nothing at or beyond EXPECT_LED_COUNT was painted.
static void assert_non_fkeys_black(const char *label, int lo, int hi) {
    int bad = 0;
    for (int index = lo; index < hi && index < EXPECT_LED_COUNT; index++) {
        if (is_fkey_led(index)) continue;
        paint_call_t *c = find_call((uint8_t)index);
        if (!c) {
            fail("%s: index %d was not painted, want black", label, index);
            bad++;
        } else if (c->r || c->g || c->b) {
            fail("%s: index %d got rgb(%d,%d,%d), want black", label, index, c->r, c->g, c->b);
            bad++;
        }
    }
    for (int i = 0; i < g_call_count; i++) {
        if (g_calls[i].index >= EXPECT_LED_COUNT) {
            fail("%s: painted index %d, board has only %d LEDs", label, g_calls[i].index, EXPECT_LED_COUNT);
            bad++;
        }
    }
    if (!bad) ok(label);
}

// Asserts the whole board [0, EXPECT_LED_COUNT) is black and exactly one call
// was made per LED.
static void assert_all_dark(const char *label) {
    assert_non_fkeys_black(label, 0, EXPECT_LED_COUNT);
    for (int i = 0; i < FKEYS_COUNT; i++) {
        paint_call_t *c = find_call(expected_led[i]);
        if (!c) fail("%s: F-row index %d was not painted, want black", label, expected_led[i]);
        else if (c->r || c->g || c->b) fail("%s: F-row index %d got rgb(%d,%d,%d), want black", label, expected_led[i], c->r, c->g, c->b);
    }
    if (g_call_count != EXPECT_LED_COUNT) fail("%s: expected %d calls, got %d", label, EXPECT_LED_COUNT, g_call_count);
    else ok(label);
}

static void assert_painted(const char *label, uint8_t index, uint8_t r, uint8_t g, uint8_t b) {
    paint_call_t *c = find_call(index);
    if (!c) {
        fail("%s: index %d was not painted at all", label, index);
        return;
    }
    if (c->r != r || c->g != g || c->b != b) {
        fail("%s: index %d got rgb(%d,%d,%d), want rgb(%d,%d,%d)", label, index, c->r, c->g, c->b, r, g, b);
        return;
    }
    ok(label);
}

static void assert_not_painted(const char *label, uint8_t index) {
    paint_call_t *c = find_call(index);
    if (c) {
        fail("%s: index %d was painted rgb(%d,%d,%d), want no call", label, index, c->r, c->g, c->b);
        return;
    }
    ok(label);
}

// ---- scenarios ----

// Tab/session fixture (see run.sh): one window, 4 tabs. Tab 0 (F1) working,
// tab 1 (F2) idle, tab 2 (F3) waiting, tab 3 (F4) a plain tab with no
// session (-> off); tabs 4-11 (F5-F12) don't exist in the window (-> off).
// Palette is the custom fixture in run.sh, not fkeys_leds.c's built-in
// defaults, so a test passing by coincidence against defaults is ruled out.
enum {
    LED_F1 = 6,   // working
    LED_F2 = 12,  // idle
    LED_F3 = 18,  // waiting
    LED_F4 = 23,  // off (tab with no session)
    LED_F5 = 28,  // off (no tab)
    LED_F6 = 34,
    LED_F7 = 39,
    LED_F8 = 44,
    LED_F9 = 50,
    LED_F10 = 56,
    LED_F11 = 61,
    LED_F12 = 66,
};

// Fixture palette from run.sh's config/palette.json-alike, decoded by hand
// once here for the expected-value tables. (This is the *expected* value;
// the actual palette bytes fed to the C code still come from fkeysd's own
// SET_PALETTE report, parsed at runtime — this struct is not itself an
// input to fkeys_leds.c.)
typedef struct { uint8_t r, g, b; } rgb_t;
static const rgb_t PAL_OFF     = {0x11, 0x22, 0x33};
static const rgb_t PAL_WORKING = {0x44, 0x55, 0x66};
static const rgb_t PAL_IDLE    = {0x77, 0x88, 0x99};
static const rgb_t PAL_WAITING = {0xAA, 0xBB, 0xCC};

// The last SET_STATES fed, replayed by waiting_at() as a keepalive so long
// sampling spans do not trip the 10 s watchdog.
static uint8_t g_states_report[64];
static int g_states_report_len = 0;

static void feed(const char *hex, int max_len) {
    uint8_t buf[64];
    int n = parse_hex(hex, buf, max_len < 64 ? max_len : 64);
    if (n > 0 && buf[0] == EXPECT_CMD_SET_STATES) {
        memcpy(g_states_report, buf, (size_t)n);
        g_states_report_len = n;
    }
    fkeys_receive(buf, (uint8_t)n);
}

// Literal copies of the spec's default palette (config/palette.json /
// fkeys_leds.c's compiled-in initialiser), independent of fkeys_leds.c's own
// table for the same reason as EXPECT_* above: comparing against a copy of
// the table under test would hide a regression in that table, not catch it.
static const rgb_t DEFAULT_OFF     = {0x00, 0x00, 0x00};
static const rgb_t DEFAULT_WORKING = {0xFF, 0x95, 0x00};
static const rgb_t DEFAULT_IDLE    = {0x00, 0xD7, 0x5F};
static const rgb_t DEFAULT_WAITING = {0xFF, 0x00, 0xAA};

static void scenario_mixed(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    // t=350 is exactly half of the default 700 ms pulse period: the triangle wave peaks at
    // 255 there, so the waiting LED reads as the unscaled palette colour
    // and every index can be asserted with a single exact RGB, including
    // the pulsing one.
    g_mock_time = 350;
    bool r = fkeys_paint(0, 255);
    if (!r) fail("mixed: fkeys_paint returned false");

    assert_painted("mixed: F1 working",  LED_F1,  PAL_WORKING.r, PAL_WORKING.g, PAL_WORKING.b);
    assert_painted("mixed: F2 idle",     LED_F2,  PAL_IDLE.r,    PAL_IDLE.g,    PAL_IDLE.b);
    assert_painted("mixed: F3 waiting (pulse peak)", LED_F3, PAL_WAITING.r, PAL_WAITING.g, PAL_WAITING.b);
    assert_painted("mixed: F4 off (tab with no session)", LED_F4, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F5 off (unbound)",  LED_F5,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F6 off (unbound)",  LED_F6,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F7 off (unbound)",  LED_F7,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F8 off (unbound)",  LED_F8,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F9 off (unbound)",  LED_F9,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F10 off (unbound)", LED_F10, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F11 off (unbound)", LED_F11, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F12 off (unbound)", LED_F12, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);

    assert_non_fkeys_black("mixed: every non-F-row LED is black", 0, 255);
    if (g_call_count != EXPECT_LED_COUNT + FKEYS_COUNT) {
        fail("mixed: expected %d calls (98 black + 12 F-row), got %d", EXPECT_LED_COUNT + FKEYS_COUNT, g_call_count);
    } else {
        ok("mixed: 98 black calls + 12 F-row calls, nothing beyond the board");
    }
}

// Exercises fkeys_leds.c's compiled-in default palette. Every other scenario
// sends a SET_PALETTE report before ever painting, so the defaults are
// overwritten before they're read -- nothing else in this file would catch a
// wrong default. Those defaults are live on hardware whenever a SET_STATES
// report arrives with no preceding SET_PALETTE: a daemon that crashed
// between the two writes, or a future tool that only ever sends states.
// Reuses the real states_hex from run.sh's fixture (see scenario_mixed) --
// only the SET_PALETTE report is withheld, still no hand-typed states bytes.
static void scenario_defaults(const char *states_hex) {
    reset_calls();
    g_mock_time = 0;
    feed(states_hex, 32); // SET_STATES only; SET_PALETTE deliberately never sent.

    g_mock_time = 350; // pulse peak, see scenario_mixed
    fkeys_paint(0, 255);

    assert_painted("defaults: F1 working",  LED_F1,  DEFAULT_WORKING.r, DEFAULT_WORKING.g, DEFAULT_WORKING.b);
    assert_painted("defaults: F2 idle",     LED_F2,  DEFAULT_IDLE.r,    DEFAULT_IDLE.g,    DEFAULT_IDLE.b);
    assert_painted("defaults: F3 waiting (pulse peak)", LED_F3, DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b);
    assert_painted("defaults: F4 off (tab with no session)", LED_F4, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F5 off (unbound)",  LED_F5,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F6 off (unbound)",  LED_F6,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F7 off (unbound)",  LED_F7,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F8 off (unbound)",  LED_F8,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F9 off (unbound)",  LED_F9,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F10 off (unbound)", LED_F10, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F11 off (unbound)", LED_F11, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F12 off (unbound)", LED_F12, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);

    assert_non_fkeys_black("defaults: every non-F-row LED is black", 0, 255);
    if (g_call_count != EXPECT_LED_COUNT + FKEYS_COUNT) {
        fail("defaults: expected %d calls (98 black + 12 F-row), got %d", EXPECT_LED_COUNT + FKEYS_COUNT, g_call_count);
    } else {
        ok("defaults: 98 black calls + 12 F-row calls, nothing beyond the board");
    }
}

static void scenario_window(const char *palette_hex, const char *states_hex, int led_min, int led_max) {
    reset_calls();
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 350; // pulse peak, see scenario_mixed
    fkeys_paint((uint8_t)led_min, (uint8_t)led_max);

    // Inside the window: F-row LEDs carry a state colour (any painted colour;
    // exact colours are pinned by "mixed"), every other LED is black.
    // Outside the window: no call at all, for every LED on the board.
    int expect_count = 0;
    for (int idx = 0; idx < EXPECT_LED_COUNT; idx++) {
        char label[80];
        bool inside = idx >= led_min && idx < led_max;
        if (inside) {
            expect_count++;
            if (is_fkey_led(idx)) expect_count++;
            continue;
        }
        snprintf(label, sizeof label, "window[%d,%d): index %d outside window is untouched", led_min, led_max, idx);
        assert_not_painted(label, (uint8_t)idx);
    }
    assert_non_fkeys_black("window: non-F-row LEDs inside the window are black", led_min, led_max);
    for (int i = 0; i < FKEYS_COUNT; i++) {
        uint8_t idx = expected_led[i];
        if (idx < led_min || idx >= led_max) continue;
        char label[80];
        snprintf(label, sizeof label, "window[%d,%d): F%d inside window has its state colour", led_min, led_max, i + 1);
        rgb_t want = (i == 0) ? PAL_WORKING : (i == 1) ? PAL_IDLE : (i == 2) ? PAL_WAITING : PAL_OFF;
        assert_painted(label, idx, want.r, want.g, want.b);
    }
    if (g_call_count != expect_count) {
        fail("window[%d,%d): expected %d calls total, got %d", led_min, led_max, expect_count, g_call_count);
    } else {
        ok("window: call count matches LEDs inside the window plus their F-row overpaints");
    }
}

static void scenario_watchdog_none(void) {
    reset_calls();
    g_mock_time = 12345;
    bool r = fkeys_paint(0, 255);
    if (!r) fail("watchdog-none: fkeys_paint returned false");
    assert_all_dark("watchdog-none: no report received -> whole board black");
}

static void scenario_watchdog_stale(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = 1000;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 1000 + EXPECT_TIMEOUT_MS + 1; // just over the watchdog window
    fkeys_paint(0, 255);
    assert_all_dark("watchdog-stale: report older than timeout -> whole board black");
}

static void scenario_watchdog_fresh(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = 1000;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 1000 + EXPECT_TIMEOUT_MS - 1; // just under the watchdog window
    fkeys_paint(0, 255);
    assert_painted("watchdog-fresh: F1 shows its state colour", LED_F1, PAL_WORKING.r, PAL_WORKING.g, PAL_WORKING.b);
    assert_painted("watchdog-fresh: F2 shows its state colour", LED_F2, PAL_IDLE.r, PAL_IDLE.g, PAL_IDLE.b);
    assert_non_fkeys_black("watchdog-fresh: non-F-row LEDs black", 0, 255);
    if (g_call_count != EXPECT_LED_COUNT + FKEYS_COUNT) {
        fail("watchdog-fresh: expected %d calls with a fresh report, got %d", EXPECT_LED_COUNT + FKEYS_COUNT, g_call_count);
    } else {
        ok("watchdog-fresh: report within timeout -> F-row painted over black");
    }
}

// Elapsed == the threshold exactly (not < and not >) must still paint: the
// brief specifies "older than 10000ms" as the cutoff, so equality is inside
// the window. Pins the boundary so a `>=` vs `>` off-by-one is caught.
static void scenario_watchdog_boundary(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = 1000;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 1000 + EXPECT_TIMEOUT_MS; // elapsed exactly equals the threshold
    fkeys_paint(0, 255);
    assert_painted("watchdog-boundary: F1 still shows its state colour", LED_F1, PAL_WORKING.r, PAL_WORKING.g, PAL_WORKING.b);
    if (g_call_count != EXPECT_LED_COUNT + FKEYS_COUNT) {
        fail("watchdog-boundary: expected %d calls at elapsed == timeout exactly, got %d", EXPECT_LED_COUNT + FKEYS_COUNT, g_call_count);
    } else {
        ok("watchdog-boundary: elapsed == timeout exactly still paints");
    }
}

// timer_read32() wraps every ~49 days of uptime. fkeys_leds.c's watchdog
// check, `(uint32_t)(timer_read32() - fkey_last_report) > FKEYS_TIMEOUT_MS`,
// relies on unsigned subtraction already wrapping modulo 2^32 (matching
// QMK's own timer_elapsed32/TIMER_DIFF_32) rather than a naive
// `timer_read32() > fkey_last_report + FKEYS_TIMEOUT_MS`, which would
// misfire once fkey_last_report + FKEYS_TIMEOUT_MS itself overflows. That
// was verified by hand; this converts the proof into a regression test.
static void scenario_watchdog_wraparound(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = (uint32_t)(UINT32_MAX - 500); // last report just before the clock wraps
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 200; // clock has wrapped past UINT32_MAX; ~701ms really elapsed
    fkeys_paint(0, 255);
    assert_painted("watchdog-wraparound: F1 still shows its state colour", LED_F1, PAL_WORKING.r, PAL_WORKING.g, PAL_WORKING.b);
    if (g_call_count != EXPECT_LED_COUNT + FKEYS_COUNT) {
        fail("watchdog-wraparound: expected %d calls once the clock wraps past UINT32_MAX with a fresh report, got %d",
             EXPECT_LED_COUNT + FKEYS_COUNT, g_call_count);
    } else {
        ok("watchdog-wraparound: elapsed survives a timer_read32() wraparound");
    }
}

// Waiting-key colour at time t, all channels.
static paint_call_t waiting_at(uint32_t t) {
    reset_calls();
    g_mock_time = t;
    fkeys_receive(g_states_report, (uint8_t)g_states_report_len);
    fkeys_paint(0, 255);
    paint_call_t *w = find_call(LED_F3);
    if (!w) { fail("pulse: F3 not painted at t=%u", (unsigned)t); return (paint_call_t){0}; }
    return *w;
}

static bool same_rgb(paint_call_t a, paint_call_t b) {
    return a.r == b.r && a.g == b.g && a.b == b.b;
}

// Checks a pulse of `period` ms and `floor` (0-255) against PAL_WAITING:
// trough at t=0 scaled by floor/255, peak at t=period/2 unscaled, periodic,
// monotone up then down, bounded, and not periodic at half the period.
static void check_pulse(const char *tag, uint32_t period, int floor_scale, rgb_t colour) {
    char label[96];
    int want_min_r = colour.r * floor_scale / 255;
    int want_min_g = colour.g * floor_scale / 255;
    int want_min_b = colour.b * floor_scale / 255;

    paint_call_t trough = waiting_at(0);
    snprintf(label, sizeof label, "%s: trough at t=0 is the colour scaled by floor %d", tag, floor_scale);
    if (trough.r != want_min_r || trough.g != want_min_g || trough.b != want_min_b) {
        fail("%s (got %d,%d,%d want %d,%d,%d)", label, trough.r, trough.g, trough.b, want_min_r, want_min_g, want_min_b);
    } else ok(label);

    paint_call_t peak = waiting_at(period / 2);
    snprintf(label, sizeof label, "%s: peak at t=period/2 is the full colour", tag);
    if (peak.r != colour.r || peak.g != colour.g || peak.b != colour.b) {
        fail("%s (got %d,%d,%d)", label, peak.r, peak.g, peak.b);
    } else ok(label);

    bool periodic = true, bounded = true, rising = true, falling = true;
    int prev = -1;
    bool past_peak = false;
    for (uint32_t t = 0; t <= period; t += (period / 60 ? period / 60 : 1)) {
        paint_call_t now = waiting_at(t);
        paint_call_t later = waiting_at(t + period);
        paint_call_t much_later = waiting_at(t + 5 * period);
        if (!same_rgb(now, later) || !same_rgb(now, much_later)) periodic = false;
        if (now.r < want_min_r || now.r > colour.r || now.g < want_min_g || now.g > colour.g ||
            now.b < want_min_b || now.b > colour.b) bounded = false;
        if (colour.r) {
            // The first sample past the midpoint may straddle the peak, so
            // it is exempt from the falling check.
            if (t <= period / 2 && prev > now.r) rising = false;
            if (t > period / 2 && past_peak && prev < now.r) falling = false;
            if (t > period / 2) past_peak = true;
            prev = now.r;
        }
    }
    snprintf(label, sizeof label, "%s: repeats every %u ms", tag, (unsigned)period);
    if (!periodic) fail("%s", label); else ok(label);
    snprintf(label, sizeof label, "%s: stays between the trough and the full colour", tag);
    if (!bounded) fail("%s", label); else ok(label);
    snprintf(label, sizeof label, "%s: rises to the midpoint then falls (triangle)", tag);
    if (!rising || !falling) fail("%s", label); else ok(label);

    if (floor_scale < 255) {
        snprintf(label, sizeof label, "%s: not periodic at half the period", tag);
        if (same_rgb(waiting_at(0), waiting_at(period / 2))) fail("%s", label); else ok(label);
    }
}

// Other states must not vary with time: only `waiting` pulses.
static void check_others_constant(const char *tag, uint32_t period) {
    char label[96];
    paint_call_t first_k = {0}, first_i = {0}, first_o = {0};
    bool kv = false, iv = false, ov = false, have = false;
    for (uint32_t t = 0; t < period; t += 7) {
        reset_calls();
        g_mock_time = t;
        fkeys_receive(g_states_report, (uint8_t)g_states_report_len);
        fkeys_paint(0, 255);
        paint_call_t *k = find_call(LED_F1), *i = find_call(LED_F2), *o = find_call(LED_F4);
        if (!k || !i || !o) { fail("%s: sampled indices not painted at t=%u", tag, (unsigned)t); return; }
        if (!have) { first_k = *k; first_i = *i; first_o = *o; have = true; }
        else {
            if (!same_rgb(*k, first_k)) kv = true;
            if (!same_rgb(*i, first_i)) iv = true;
            if (!same_rgb(*o, first_o)) ov = true;
        }
    }
    snprintf(label, sizeof label, "%s: working LED is constant over time", tag);
    if (kv) fail("%s", label); else ok(label);
    snprintf(label, sizeof label, "%s: idle LED is constant over time", tag);
    if (iv) fail("%s", label); else ok(label);
    snprintf(label, sizeof label, "%s: off LED is constant over time", tag);
    if (ov) fail("%s", label); else ok(label);
}

// SET_PULSE bytes come from fkeysd --dry-run for the fixture config.
static void scenario_pulse(const char *palette_hex, const char *states_hex, const char *pulse_hex) {
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(pulse_hex, 32);
    feed(states_hex, 32);
    check_pulse("pulse(fixture 900 ms, floor 30)", EXPECT_FIXTURE_PULSE_MS, EXPECT_FIXTURE_PULSE_FLOOR, PAL_WAITING);
    check_others_constant("pulse(fixture)", EXPECT_FIXTURE_PULSE_MS);
}

// No SET_PULSE ever sent: compiled-in defaults, 700 ms and floor 0, so the
// key goes fully dark at the trough.
static void scenario_pulse_defaults(const char *states_hex) {
    g_mock_time = 0;
    feed(states_hex, 32);
    check_pulse("pulse(defaults 700 ms, floor 0)", EXPECT_DEFAULT_PULSE_MS, EXPECT_DEFAULT_PULSE_FLOOR,
                (rgb_t){DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b});
    paint_call_t dark = waiting_at(0);
    if (dark.r || dark.g || dark.b) fail("pulse-defaults: waiting key not fully dark at the trough");
    else ok("pulse-defaults: waiting key is fully dark at the trough");
    check_others_constant("pulse(defaults)", EXPECT_DEFAULT_PULSE_MS);
}

static void send_pulse(uint8_t lo, uint8_t hi, uint8_t floor_byte) {
    uint8_t report[32] = {0};
    report[0] = EXPECT_CMD_SET_PULSE;
    report[1] = lo;
    report[2] = hi;
    report[3] = floor_byte;
    fkeys_receive(report, sizeof report);
}

// Hand-crafted: pins byte order and the reject rule independently of fkeysd.
static void scenario_pulse_raw(const char *states_hex) {
    g_mock_time = 0;
    feed(states_hex, 32);

    // 0x0100 = 256 ms sent low byte first. Big-endian decoding would read
    // 0x0001 = 1 ms and be rejected; a swapped read of 0x0001 would differ.
    send_pulse(0x00, 0x01, 0);
    check_pulse("pulse-raw(256 ms, little-endian)", 256, 0,
                (rgb_t){DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b});

    // A period of 0 (would divide by zero) and 1 (half-period 0) are rejected
    // and leave the 256 ms pulse in force.
    send_pulse(0x00, 0x00, 0);
    check_pulse("pulse-raw(period 0 rejected, still 256 ms)", 256, 0,
                (rgb_t){DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b});
    send_pulse(0x01, 0x00, 0);
    check_pulse("pulse-raw(period 1 rejected, still 256 ms)", 256, 0,
                (rgb_t){DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b});

    // The smallest accepted period is 2 ms; paint must not fault.
    g_mock_time = 0;
    send_pulse(0x02, 0x00, 0);
    reset_calls();
    g_mock_time = 5;
    fkeys_paint(0, 255);
    if (g_call_count != EXPECT_LED_COUNT + FKEYS_COUNT) fail("pulse-raw: period 2 painted %d calls", g_call_count);
    else ok("pulse-raw: period 2 is accepted and paints normally");

    // Longest period, 0xFFFF, with a mid floor.
    send_pulse(0xFF, 0xFF, 128);
    check_pulse("pulse-raw(65535 ms, floor 128)", 65535, 128,
                (rgb_t){DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b});

    // Floor is a full byte: 255 means no dimming at all.
    send_pulse(0xBC, 0x02, 255);
    reset_calls();
    bool flat = true;
    for (uint32_t t = 0; t < 700; t += 13) {
        paint_call_t w = waiting_at(t);
        if (w.r != DEFAULT_WAITING.r || w.g != DEFAULT_WAITING.g || w.b != DEFAULT_WAITING.b) flat = false;
    }
    if (!flat) fail("pulse-raw: floor 255 should not dim"); else ok("pulse-raw: floor 255 does not dim");
}

// Hand-crafted: fkeysd never emits an unknown command byte. Uses the real
// states_hex as a known-good baseline, then a synthetic bad report.
static void scenario_malformed(const char *palette_hex, const char *states_hex) {
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    reset_calls();
    g_mock_time = 350;
    fkeys_paint(0, 255);
    static paint_call_t before[MAX_CALLS];
    int before_count = g_call_count;
    memcpy(before, g_calls, sizeof before);

    uint8_t bogus[32] = {0};
    bogus[0] = 0x7F; // unknown command
    for (int i = 1; i < 32; i++) bogus[i] = (uint8_t)(i * 7); // noise, must be ignored
    fkeys_receive(bogus, sizeof bogus);

    reset_calls();
    g_mock_time = 350;
    fkeys_paint(0, 255);

    bool same = (g_call_count == before_count && before_count == EXPECT_LED_COUNT + FKEYS_COUNT);
    for (int i = 0; same && i < before_count; i++) {
        if (g_calls[i].index != before[i].index || g_calls[i].r != before[i].r ||
            g_calls[i].g != before[i].g || g_calls[i].b != before[i].b) {
            same = false;
        }
    }
    if (!same) fail("malformed: state changed after an unknown command byte");
    else ok("malformed: unknown command byte leaves prior state untouched");
}

// Hand-crafted: fkeysd never emits a report shorter than 13 bytes.
static void scenario_short(const char *palette_hex, const char *states_hex) {
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    reset_calls();
    g_mock_time = 350;
    fkeys_paint(0, 255);
    static paint_call_t before[MAX_CALLS];
    int before_count = g_call_count;
    memcpy(before, g_calls, sizeof before);

    uint8_t shortReport[12] = { EXPECT_CMD_SET_STATES, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 }; // length 12 < 13
    fkeys_receive(shortReport, sizeof shortReport);

    reset_calls();
    g_mock_time = 350;
    fkeys_paint(0, 255);

    bool same = (g_call_count == before_count && before_count == EXPECT_LED_COUNT + FKEYS_COUNT);
    for (int i = 0; same && i < before_count; i++) {
        if (g_calls[i].index != before[i].index || g_calls[i].r != before[i].r ||
            g_calls[i].g != before[i].g || g_calls[i].b != before[i].b) {
            same = false;
        }
    }
    if (!same) fail("short: state changed after a length-12 report");
    else ok("short: report shorter than 13 bytes is rejected");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <scenario> [args...]\n", argv[0]);
        return 2;
    }
    const char *scenario = argv[1];

    if (strcmp(scenario, "mixed") == 0 && argc == 4) {
        scenario_mixed(argv[2], argv[3]);
    } else if (strcmp(scenario, "defaults") == 0 && argc == 3) {
        scenario_defaults(argv[2]);
    } else if (strcmp(scenario, "window") == 0 && argc == 6) {
        scenario_window(argv[2], argv[3], atoi(argv[4]), atoi(argv[5]));
    } else if (strcmp(scenario, "watchdog_none") == 0 && argc == 2) {
        scenario_watchdog_none();
    } else if (strcmp(scenario, "watchdog_stale") == 0 && argc == 4) {
        scenario_watchdog_stale(argv[2], argv[3]);
    } else if (strcmp(scenario, "watchdog_fresh") == 0 && argc == 4) {
        scenario_watchdog_fresh(argv[2], argv[3]);
    } else if (strcmp(scenario, "watchdog_boundary") == 0 && argc == 4) {
        scenario_watchdog_boundary(argv[2], argv[3]);
    } else if (strcmp(scenario, "watchdog_wraparound") == 0 && argc == 4) {
        scenario_watchdog_wraparound(argv[2], argv[3]);
    } else if (strcmp(scenario, "pulse") == 0 && argc == 5) {
        scenario_pulse(argv[2], argv[3], argv[4]);
    } else if (strcmp(scenario, "pulse_defaults") == 0 && argc == 3) {
        scenario_pulse_defaults(argv[2]);
    } else if (strcmp(scenario, "pulse_raw") == 0 && argc == 3) {
        scenario_pulse_raw(argv[2]);
    } else if (strcmp(scenario, "malformed") == 0 && argc == 4) {
        scenario_malformed(argv[2], argv[3]);
    } else if (strcmp(scenario, "short") == 0 && argc == 4) {
        scenario_short(argv[2], argv[3]);
    } else {
        fprintf(stderr, "unknown scenario or wrong arg count: %s\n", scenario);
        return 2;
    }

    printf("%d failure(s)\n", g_failures);
    return g_failures == 0 ? 0 : 1;
}
