#!/bin/sh
# Contract harness for qmk/keymaps/fkeys/fkeys_leds.c.
#
# Compiles fkeys_leds.c natively with clang, feeds it the exact bytes the
# real Swift binary (fkeysd --dry-run) produces for a known registry/state
# fixture, and asserts the LED indices and RGB values fkeys_leds.c paints.
# This is the only way to check the Swift encoder and the C decoder agree
# without a keyboard.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FW="$ROOT/qmk/keymaps/fkeys"
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STATE_DIR="$TMP/state"
REGISTRY="$TMP/registry.json"
PALETTE="$TMP/palette.json"
mkdir -p "$STATE_DIR"

# --- fixture: a deliberately mixed registry ---
# key1 -> working, key2 -> idle, key3 -> waiting, key4 -> registered but no
# state file (off), keys 5-12 unbound (off). Exercises every KeyState and
# both ways a key ends up "off".
UUID_WORKING="11111111-1111-1111-1111-111111111111"
UUID_IDLE="22222222-2222-2222-2222-222222222222"
UUID_WAITING="33333333-3333-3333-3333-333333333333"
UUID_GHOST="44444444-4444-4444-4444-444444444444"

cat > "$REGISTRY" <<EOF
{
  "1": "$UUID_WORKING",
  "2": "$UUID_IDLE",
  "3": "$UUID_WAITING",
  "4": "$UUID_GHOST"
}
EOF

cat > "$STATE_DIR/$UUID_WORKING.json" <<'EOF'
{"state":"working","ts":1,"claude_session_id":"s1"}
EOF
cat > "$STATE_DIR/$UUID_IDLE.json" <<'EOF'
{"state":"idle","ts":1,"claude_session_id":"s2"}
EOF
cat > "$STATE_DIR/$UUID_WAITING.json" <<'EOF'
{"state":"waiting","ts":1,"claude_session_id":"s3"}
EOF
# Deliberately no state file for UUID_GHOST: registered but stale.

# Custom palette, distinct from fkeys_leds.c's built-in defaults, so a test
# that only happens to match the defaults can't hide a real bug.
cat > "$PALETTE" <<'EOF'
{
  "off": "#112233",
  "working": "#445566",
  "idle": "#778899",
  "waiting": "#aabbcc"
}
EOF

echo "== building fkeysd (debug) =="
(cd "$ROOT" && swift build) >&2

FKEYSD="$ROOT/.build/debug/fkeysd"

echo "== running fkeysd --dry-run against the fixture =="
DRYRUN=$(FKEYS_STATE_DIR="$STATE_DIR" FKEYS_REGISTRY="$REGISTRY" FKEYS_PALETTE="$PALETTE" "$FKEYSD" --dry-run)
echo "$DRYRUN" >&2

PALETTE_HEX=$(echo "$DRYRUN" | awk '/^SET_PALETTE/ { $1=""; print }')
STATES_HEX=$(echo "$DRYRUN" | awk '/^SET_STATES/ { $1=""; print }')

if [ -z "$PALETTE_HEX" ] || [ -z "$STATES_HEX" ]; then
    echo "FAIL  could not parse fkeysd --dry-run output" >&2
    exit 1
fi

echo "== compiling the native C harness =="
CBIN="$TMP/test_fkeys_leds"
cc -std=c11 -Wall -Wextra -Werror -I "$FW" -o "$CBIN" \
    "$ROOT/qmk/tests/test_fkeys_leds.c" "$FW/fkeys_leds.c"

run_case() {
    label="$1"; shift
    echo "-- $label --"
    if ! "$CBIN" "$@"; then
        FAIL=1
    fi
}

run_case "mixed registry"        mixed          "$PALETTE_HEX" "$STATES_HEX"
run_case "led_min/led_max window" window        "$PALETTE_HEX" "$STATES_HEX" 20 45
run_case "watchdog: no report ever" watchdog_none
run_case "watchdog: stale report" watchdog_stale "$PALETTE_HEX" "$STATES_HEX"
run_case "watchdog: fresh report" watchdog_fresh "$PALETTE_HEX" "$STATES_HEX"
run_case "watchdog: exact boundary" watchdog_boundary "$PALETTE_HEX" "$STATES_HEX"
run_case "pulse sampled over one period" pulse   "$PALETTE_HEX" "$STATES_HEX"
run_case "malformed command byte"        malformed "$PALETTE_HEX" "$STATES_HEX"
run_case "short report (length < 13)"    short     "$PALETTE_HEX" "$STATES_HEX"

if [ "$FAIL" = "0" ]; then
    echo "== firmware contract harness: all scenarios passed =="
else
    echo "== firmware contract harness: FAILURES ABOVE ==" >&2
fi
exit "$FAIL"
