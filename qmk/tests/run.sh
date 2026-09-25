#!/bin/sh
# Contract harness for qmk/keymaps/fkeys/fkeys_leds.c.
#
# Compiles fkeys_leds.c natively with clang, feeds it the exact bytes the
# real Swift binary (fkeysd --dry-run) produces for a known iTerm-tab/state
# fixture, and asserts the LED indices and RGB values fkeys_leds.c paints.
# This is the only way to check the Swift encoder and the C decoder agree
# without a keyboard.
#
# The fixture is a fake `it2` (see build_it2_stub below), pointed at via
# FKEYS_IT2: fkeysd's tab-index derivation genuinely runs against it, so this
# exercises the real derivation path end to end instead of bypassing it with
# a hand-written registry file (the pre-tab-index-binding design).
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FW="$ROOT/qmk/keymaps/fkeys"
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STATE_DIR="$TMP/state"
PALETTE="$TMP/palette.json"
IT2_STUB="$TMP/it2-stub.sh"
mkdir -p "$STATE_DIR"

# --- fixture: a deliberately mixed window ---
# tab 0 -> working, tab 1 -> idle, tab 2 -> waiting, tab 3 -> a plain
# (non-Claude) tab with no session at all (off), tabs 4-11 don't exist in
# the window (also off). Exercises every KeyState and both ways a key ends
# up "off".
UUID_WORKING="11111111-1111-1111-1111-111111111111"
UUID_IDLE="22222222-2222-2222-2222-222222222222"
UUID_WAITING="33333333-3333-3333-3333-333333333333"

WINDOW_ID="pty-STUB0000-0000-0000-0000-000000000000"
TAB_ID_0="10"
TAB_ID_1="11"
TAB_ID_2="12"
TAB_ID_3="13"

cat > "$STATE_DIR/$UUID_WORKING.json" <<'EOF'
{"state":"working","ts":1,"claude_session_id":"s1"}
EOF
cat > "$STATE_DIR/$UUID_IDLE.json" <<'EOF'
{"state":"idle","ts":1,"claude_session_id":"s2"}
EOF
cat > "$STATE_DIR/$UUID_WAITING.json" <<'EOF'
{"state":"waiting","ts":1,"claude_session_id":"s3"}
EOF
# Deliberately no state file, and no session get-var mapping, for tab 3:
# it's a plain shell tab, not a Claude session.

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

# Fakes the handful of `it2` subcommands fkeysd's tab-index derivation and
# reconcile() call, so the harness can exercise the real derivation path
# without a live iTerm. Answers exactly the calls in Sources/fkeysd/ITermCLI.swift;
# anything else fails loudly rather than returning empty, since empty output
# is deliberately read as "unknown, change nothing" and would pass for the
# wrong reason.
cat > "$IT2_STUB" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "window list")
    cat <<JSON
[
  { "id": "$WINDOW_ID" }
]
JSON
    ;;
  "tab list")
    cat <<JSON
[
  { "index": 0, "id": "$TAB_ID_0", "window_id": "$WINDOW_ID", "is_active": true,  "sessions": 1 },
  { "index": 1, "id": "$TAB_ID_1", "window_id": "$WINDOW_ID", "is_active": false, "sessions": 1 },
  { "index": 2, "id": "$TAB_ID_2", "window_id": "$WINDOW_ID", "is_active": false, "sessions": 1 },
  { "index": 3, "id": "$TAB_ID_3", "window_id": "$WINDOW_ID", "is_active": false, "sessions": 1 }
]
JSON
    ;;
  "session get-var")
    # arguments: session get-var tab.id -s <uuid> -- uuid is \$5.
    case "\$5" in
      "$UUID_WORKING") echo "\"$TAB_ID_0\"" ;;
      "$UUID_IDLE")    echo "\"$TAB_ID_1\"" ;;
      "$UUID_WAITING") echo "\"$TAB_ID_2\"" ;;
      *) ;; # unknown session: empty output, same as the real it2's "no such session"
    esac
    ;;
  "session list")
    printf '%s\tchat (claude)\tchat (claude)\t364x93\t/dev/ttys000\n' "$UUID_WORKING"
    printf '%s\tchat (claude)\tchat (claude)\t364x93\t/dev/ttys001\n' "$UUID_IDLE"
    printf '%s\tchat (claude)\tchat (claude)\t364x93\t/dev/ttys002\n' "$UUID_WAITING"
    ;;
  "tab goto")
    ;;
  *)
    echo "it2-stub: unhandled arguments: \$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$IT2_STUB"

echo "== building fkeysd (debug) =="
(cd "$ROOT" && swift build) >&2

FKEYSD="$ROOT/.build/debug/fkeysd"

# An empty string is not the same as unset for a plain environment lookup:
# `FKEYS_STATE_DIR=""` used to resolve to the process's cwd instead of
# falling back to the default (see main.swift's envOverride). Compares two
# live invocations against whatever the real ~/.claude/~/.config/real it2
# happen to hold rather than asserting fixed bytes, since that ambient state
# isn't ours to fix -- but a wrapper script or plist that exports one of
# these four blank must behave exactly as if it hadn't, and this is
# read-only (--dry-run never writes, and never calls `tab goto` since there
# is no keypress to react to).
echo "== verifying an empty FKEYS_* override is treated as unset =="
BASELINE=$(env -u FKEYS_STATE_DIR -u FKEYS_IT2 -u FKEYS_PALETTE "$FKEYSD" --dry-run)
EMPTY_OVERRIDE=$(FKEYS_STATE_DIR= FKEYS_IT2= FKEYS_PALETTE= "$FKEYSD" --dry-run)
if [ "$BASELINE" = "$EMPTY_OVERRIDE" ]; then
    echo "ok    empty FKEYS_* vars behave as unset (match the real defaults)"
else
    echo "FAIL  empty FKEYS_* vars diverged from unset:"
    echo "  unset: $BASELINE"
    echo "  empty: $EMPTY_OVERRIDE"
    FAIL=1
fi

echo "== running fkeysd --dry-run against the fixture =="
DRYRUN=$(FKEYS_STATE_DIR="$STATE_DIR" FKEYS_IT2="$IT2_STUB" FKEYS_PALETTE="$PALETTE" "$FKEYSD" --dry-run)
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

run_case "mixed tabs"            mixed          "$PALETTE_HEX" "$STATES_HEX"
run_case "compiled-in default palette (no SET_PALETTE sent)" defaults "$STATES_HEX"
# [23, 44) pins both edges on real LED indices rather than landing in a gap
# between them: 23 is F4's own index (must be included, F3 at 18 excluded)
# and 44 is F8's own index (must be excluded, F7 at 39 included). A window
# like [20, 45) never touches an actual index and can't catch an off-by-one
# in the bound check.
run_case "led_min/led_max window" window        "$PALETTE_HEX" "$STATES_HEX" 23 44
run_case "watchdog: no report ever" watchdog_none
run_case "watchdog: stale report" watchdog_stale "$PALETTE_HEX" "$STATES_HEX"
run_case "watchdog: fresh report" watchdog_fresh "$PALETTE_HEX" "$STATES_HEX"
run_case "watchdog: exact boundary" watchdog_boundary "$PALETTE_HEX" "$STATES_HEX"
run_case "watchdog: timer_read32 wraparound" watchdog_wraparound "$PALETTE_HEX" "$STATES_HEX"
run_case "pulse sampled over one period" pulse   "$PALETTE_HEX" "$STATES_HEX"
run_case "malformed command byte"        malformed "$PALETTE_HEX" "$STATES_HEX"
run_case "short report (length < 13)"    short     "$PALETTE_HEX" "$STATES_HEX"

if [ "$FAIL" = "0" ]; then
    echo "== firmware contract harness: all scenarios passed =="
else
    echo "== firmware contract harness: FAILURES ABOVE ==" >&2
fi
exit "$FAIL"
