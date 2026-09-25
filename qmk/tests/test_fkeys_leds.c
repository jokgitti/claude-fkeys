// Native contract test for qmk/keymaps/fkeys/fkeys_leds.c.
//
// Runs one scenario per process invocation (argv[1] selects it) so every
// scenario starts from fkeys_leds.c's true initial static state, with no
// reset hook added to the production file just for tests.
//
// Byte payloads for the "mixed"/"window"/"pulse" scenarios are the real
// SET_PALETTE/SET_STATES reports fkeysd printed for a known registry+state
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

void rgb_matrix_set_color(uint8_t index, uint8_t r, uint8_t g, uint8_t b) {
    if (g_call_count < MAX_CALLS) {
        g_calls[g_call_count++] = (paint_call_t){index, r, g, b};
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
#define EXPECT_PULSE_MS         1500
#define EXPECT_PULSE_FLOOR        51
#define EXPECT_CMD_SET_STATES   0x01

// Finds the recorded call for `index`, or NULL if that index was never painted.
static paint_call_t *find_call(uint8_t index) {
    for (int i = 0; i < g_call_count; i++) {
        if (g_calls[i].index == index) return &g_calls[i];
    }
    return NULL;
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

// Registry fixture (see run.sh): key1..key4 bound, key1=working, key2=idle,
// key3=waiting, key4 registered but no state file (-> off); keys 5-12 unbound
// (-> off). Palette is the custom fixture in run.sh, not fkeys_leds.c's
// built-in defaults, so a test passing by coincidence against defaults is
// ruled out.
enum {
    LED_F1 = 6,   // working
    LED_F2 = 12,  // idle
    LED_F3 = 18,  // waiting
    LED_F4 = 23,  // off (ghost registry entry)
    LED_F5 = 28,  // off (unbound)
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

static void feed(const char *hex, int max_len) {
    uint8_t buf[64];
    int n = parse_hex(hex, buf, max_len < 64 ? max_len : 64);
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

    // t=750 is exactly half of FKEYS_PULSE_MS: the triangle wave peaks at
    // 255 there, so the waiting LED reads as the unscaled palette colour
    // and every index can be asserted with a single exact RGB, including
    // the pulsing one.
    g_mock_time = 750;
    bool r = fkeys_paint(0, 255);
    if (!r) fail("mixed: fkeys_paint returned false");

    assert_painted("mixed: F1 working",  LED_F1,  PAL_WORKING.r, PAL_WORKING.g, PAL_WORKING.b);
    assert_painted("mixed: F2 idle",     LED_F2,  PAL_IDLE.r,    PAL_IDLE.g,    PAL_IDLE.b);
    assert_painted("mixed: F3 waiting (pulse peak)", LED_F3, PAL_WAITING.r, PAL_WAITING.g, PAL_WAITING.b);
    assert_painted("mixed: F4 off (ghost registry entry)", LED_F4, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F5 off (unbound)",  LED_F5,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F6 off (unbound)",  LED_F6,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F7 off (unbound)",  LED_F7,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F8 off (unbound)",  LED_F8,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F9 off (unbound)",  LED_F9,  PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F10 off (unbound)", LED_F10, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F11 off (unbound)", LED_F11, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);
    assert_painted("mixed: F12 off (unbound)", LED_F12, PAL_OFF.r, PAL_OFF.g, PAL_OFF.b);

    if (g_call_count != FKEYS_COUNT) {
        fail("mixed: expected exactly %d rgb_matrix_set_color calls, got %d", FKEYS_COUNT, g_call_count);
    } else {
        ok("mixed: exactly 12 calls, nothing painted at any other index");
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

    g_mock_time = 750; // pulse peak, see scenario_mixed
    fkeys_paint(0, 255);

    assert_painted("defaults: F1 working",  LED_F1,  DEFAULT_WORKING.r, DEFAULT_WORKING.g, DEFAULT_WORKING.b);
    assert_painted("defaults: F2 idle",     LED_F2,  DEFAULT_IDLE.r,    DEFAULT_IDLE.g,    DEFAULT_IDLE.b);
    assert_painted("defaults: F3 waiting (pulse peak)", LED_F3, DEFAULT_WAITING.r, DEFAULT_WAITING.g, DEFAULT_WAITING.b);
    assert_painted("defaults: F4 off (ghost registry entry)", LED_F4, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F5 off (unbound)",  LED_F5,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F6 off (unbound)",  LED_F6,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F7 off (unbound)",  LED_F7,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F8 off (unbound)",  LED_F8,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F9 off (unbound)",  LED_F9,  DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F10 off (unbound)", LED_F10, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F11 off (unbound)", LED_F11, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);
    assert_painted("defaults: F12 off (unbound)", LED_F12, DEFAULT_OFF.r, DEFAULT_OFF.g, DEFAULT_OFF.b);

    if (g_call_count != FKEYS_COUNT) {
        fail("defaults: expected exactly %d rgb_matrix_set_color calls, got %d", FKEYS_COUNT, g_call_count);
    } else {
        ok("defaults: exactly 12 calls, nothing painted at any other index");
    }
}

static void scenario_window(const char *palette_hex, const char *states_hex, int led_min, int led_max) {
    reset_calls();
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 750; // pulse peak, see scenario_mixed
    fkeys_paint((uint8_t)led_min, (uint8_t)led_max);

    int expect_count = 0;
    for (int i = 0; i < FKEYS_COUNT; i++) {
        uint8_t idx = expected_led[i];
        char label[64];
        if (idx >= led_min && idx < led_max) {
            expect_count++;
            snprintf(label, sizeof label, "window[%d,%d): index %d inside window is painted", led_min, led_max, idx);
            paint_call_t *c = find_call(idx);
            if (!c) fail("%s", label); else ok(label);
        } else {
            snprintf(label, sizeof label, "window[%d,%d): index %d outside window is untouched", led_min, led_max, idx);
            assert_not_painted(label, idx);
        }
    }
    if (g_call_count != expect_count) {
        fail("window[%d,%d): expected %d calls total, got %d", led_min, led_max, expect_count, g_call_count);
    } else {
        ok("window: call count matches indices inside the window");
    }
}

static void scenario_watchdog_none(void) {
    reset_calls();
    g_mock_time = 12345;
    bool r = fkeys_paint(0, 255);
    if (!r) fail("watchdog-none: fkeys_paint returned false");
    if (g_call_count != 0) {
        fail("watchdog-none: expected 0 calls with no report ever received, got %d", g_call_count);
    } else {
        ok("watchdog-none: no report received -> nothing painted");
    }
}

static void scenario_watchdog_stale(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = 1000;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 1000 + EXPECT_TIMEOUT_MS + 1; // just over the watchdog window
    fkeys_paint(0, 255);
    if (g_call_count != 0) {
        fail("watchdog-stale: expected 0 calls once report is older than %dms, got %d", EXPECT_TIMEOUT_MS, g_call_count);
    } else {
        ok("watchdog-stale: report older than timeout -> nothing painted");
    }
}

static void scenario_watchdog_fresh(const char *palette_hex, const char *states_hex) {
    reset_calls();
    g_mock_time = 1000;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    g_mock_time = 1000 + EXPECT_TIMEOUT_MS - 1; // just under the watchdog window
    fkeys_paint(0, 255);
    if (g_call_count != FKEYS_COUNT) {
        fail("watchdog-fresh: expected %d calls with a fresh report, got %d", FKEYS_COUNT, g_call_count);
    } else {
        ok("watchdog-fresh: report within timeout -> painting resumes");
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
    if (g_call_count != FKEYS_COUNT) {
        fail("watchdog-boundary: expected %d calls at elapsed == timeout exactly, got %d", FKEYS_COUNT, g_call_count);
    } else {
        ok("watchdog-boundary: elapsed == timeout exactly still paints");
    }
}

static void scenario_pulse(const char *palette_hex, const char *states_hex) {
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    int floor_r = (PAL_WAITING.r * EXPECT_PULSE_FLOOR) / 255;
    int floor_g = (PAL_WAITING.g * EXPECT_PULSE_FLOOR) / 255;
    int floor_b = (PAL_WAITING.b * EXPECT_PULSE_FLOOR) / 255;

    int min_r = 256, min_g = 256, min_b = 256;
    int max_r = -1, max_g = -1, max_b = -1;
    bool any_zero = false;
    bool waiting_varied = false;
    paint_call_t first_working = {0}, first_idle = {0}, first_off = {0};
    bool working_varied = false, idle_varied = false, off_varied = false;
    bool have_first = false;

    for (int t = 0; t < EXPECT_PULSE_MS; t += 10) {
        reset_calls();
        g_mock_time = (uint32_t)t;
        fkeys_paint(0, 255);

        paint_call_t *w = find_call(LED_F3); // waiting
        paint_call_t *k = find_call(LED_F1); // working
        paint_call_t *i = find_call(LED_F2); // idle
        paint_call_t *o = find_call(LED_F4); // off
        if (!w || !k || !i || !o) { fail("pulse: expected all four sampled indices painted at t=%d", t); continue; }

        if (w->r < min_r) min_r = w->r; if (w->r > max_r) max_r = w->r;
        if (w->g < min_g) min_g = w->g; if (w->g > max_g) max_g = w->g;
        if (w->b < min_b) min_b = w->b; if (w->b > max_b) max_b = w->b;
        if (w->r == 0 && PAL_WAITING.r != 0) any_zero = true;
        if (w->g == 0 && PAL_WAITING.g != 0) any_zero = true;
        if (w->b == 0 && PAL_WAITING.b != 0) any_zero = true;

        if (!have_first) {
            first_working = *k; first_idle = *i; first_off = *o;
            have_first = true;
        } else {
            if (k->r != first_working.r || k->g != first_working.g || k->b != first_working.b) working_varied = true;
            if (i->r != first_idle.r || i->g != first_idle.g || i->b != first_idle.b) idle_varied = true;
            if (o->r != first_off.r || o->g != first_off.g || o->b != first_off.b) off_varied = true;
        }
        if (t > 0 && (min_r != max_r || min_g != max_g || min_b != max_b)) waiting_varied = true;
    }

    if (any_zero) fail("pulse: waiting LED hit exactly 0 on a nonzero channel, floor should prevent that");
    else ok("pulse: waiting LED never goes fully dark");

    if (min_r < floor_r || min_g < floor_g || min_b < floor_b) {
        fail("pulse: waiting LED dipped below the 20%% floor (%d,%d,%d), got min (%d,%d,%d)", floor_r, floor_g, floor_b, min_r, min_g, min_b);
    } else {
        ok("pulse: waiting LED never dips below the 20% floor");
    }

    if (max_r > PAL_WAITING.r || max_g > PAL_WAITING.g || max_b > PAL_WAITING.b) {
        fail("pulse: waiting LED exceeded 100%% of configured colour (%d,%d,%d), got max (%d,%d,%d)",
             PAL_WAITING.r, PAL_WAITING.g, PAL_WAITING.b, max_r, max_g, max_b);
    } else {
        ok("pulse: waiting LED never exceeds the configured colour");
    }

    // Confirm the sampled range actually reaches close to both ends, so this
    // isn't trivially satisfied by a pulse that barely moves.
    if (max_r < PAL_WAITING.r - 2 && PAL_WAITING.r > floor_r + 2) {
        fail("pulse: sampled max_r=%d never got near the configured %d", max_r, PAL_WAITING.r);
    } else {
        ok("pulse: sampled range reaches near the configured colour");
    }
    if (min_r > floor_r + 2 && PAL_WAITING.r > floor_r + 2) {
        fail("pulse: sampled min_r=%d never got near the floor %d", min_r, floor_r);
    } else {
        ok("pulse: sampled range reaches near the floor");
    }

    if (!waiting_varied) fail("pulse: waiting LED colour did not vary across the sampled period");
    else ok("pulse: waiting LED colour varies over time");

    if (working_varied) fail("pulse: working LED colour varied over time, it should be constant");
    else ok("pulse: working LED colour is constant over time");
    if (idle_varied) fail("pulse: idle LED colour varied over time, it should be constant");
    else ok("pulse: idle LED colour is constant over time");
    if (off_varied) fail("pulse: off LED colour varied over time, it should be constant");
    else ok("pulse: off LED colour is constant over time");
}

// Hand-crafted: fkeysd never emits an unknown command byte. Uses the real
// states_hex as a known-good baseline, then a synthetic bad report.
static void scenario_malformed(const char *palette_hex, const char *states_hex) {
    g_mock_time = 0;
    feed(palette_hex, 32);
    feed(states_hex, 32);

    reset_calls();
    g_mock_time = 750;
    fkeys_paint(0, 255);
    paint_call_t before[FKEYS_COUNT];
    memcpy(before, g_calls, sizeof before);

    uint8_t bogus[32] = {0};
    bogus[0] = 0x7F; // unknown command
    for (int i = 1; i < 32; i++) bogus[i] = (uint8_t)(i * 7); // noise, must be ignored
    fkeys_receive(bogus, sizeof bogus);

    reset_calls();
    g_mock_time = 750;
    fkeys_paint(0, 255);

    bool same = (g_call_count == FKEYS_COUNT);
    for (int i = 0; same && i < FKEYS_COUNT; i++) {
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
    g_mock_time = 750;
    fkeys_paint(0, 255);
    paint_call_t before[FKEYS_COUNT];
    memcpy(before, g_calls, sizeof before);

    uint8_t shortReport[12] = { EXPECT_CMD_SET_STATES, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 }; // length 12 < 13
    fkeys_receive(shortReport, sizeof shortReport);

    reset_calls();
    g_mock_time = 750;
    fkeys_paint(0, 255);

    bool same = (g_call_count == FKEYS_COUNT);
    for (int i = 0; same && i < FKEYS_COUNT; i++) {
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
    } else if (strcmp(scenario, "pulse") == 0 && argc == 4) {
        scenario_pulse(argv[2], argv[3]);
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
