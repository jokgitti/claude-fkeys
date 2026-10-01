#!/bin/sh
# Test the state-derivation table in hooks/fkey-status.sh.
# Uses FKEYS_STATE_DIR so nothing touches the real ~/.claude/.fkeys.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/fkey-status.sh"
TMP=$(mktemp -d)
# rm -f + rmdir rather than rm -rf: the dir is flat, and rm -rf in a repo
# script triggers a permission prompt on every run for no benefit.
trap 'rm -f "$TMP"/*; rmdir "$TMP" 2>/dev/null' EXIT

FKEYS_STATE_DIR="$TMP"; export FKEYS_STATE_DIR
TERM_PROGRAM="iTerm.app"; export TERM_PROGRAM
ITERM_SESSION_ID="w0t1p0:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"; export ITERM_SESSION_ID
FILE="$TMP/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.json"
FAIL=0

fire() {
  printf '{"hook_event_name":"%s","session_id":"claude-sid-1"}' "$1" | sh "$HOOK"
}

expect_state() { # event expected
  fire "$1"
  got=$(jq -r '.state' < "$FILE" 2>/dev/null) || got="MISSING"
  if [ "$got" = "$2" ]; then
    echo "ok    $1 -> $2"
  else
    echo "FAIL  $1 -> got '$got', want '$2'"; FAIL=1
  fi
}

expect_payload_state() { # label json expected
  printf '%s' "$2" | sh "$HOOK"
  got=$(jq -r '.state' < "$FILE" 2>/dev/null) || got="MISSING"
  if [ "$got" = "$3" ]; then
    echo "ok    $1 -> $3"
  else
    echo "FAIL  $1 -> got '$got', want '$3'"; FAIL=1
  fi
}

expect_absent() { # event
  fire "$1"
  if [ -e "$FILE" ]; then echo "FAIL  $1 -> file still present"; FAIL=1
  else echo "ok    $1 -> file removed"; fi
}

expect_state SessionStart      idle
expect_state PreToolUse        working
expect_state PostToolUse       working
expect_state PermissionRequest waiting
expect_state Stop              idle
expect_absent SessionEnd

# Notification is mapped by notification_type. The idle_prompt payload is a
# captured live one, with its extra fields.
expect_payload_state "Notification idle_prompt (captured payload)" \
  '{"session_id":"claude-sid-1","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt"}' idle
expect_payload_state "Notification permission_prompt" \
  '{"session_id":"claude-sid-1","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}' waiting
fire Stop
expect_payload_state "Notification elicitation_dialog" \
  '{"session_id":"claude-sid-1","hook_event_name":"Notification","notification_type":"elicitation_dialog"}' waiting

# Any other Notification type (unknown, missing, null) changes nothing, from
# every starting state.
expect_unchanged() { # label json start_event
  fire "$3"
  before=$(cat "$FILE")
  printf '%s' "$2" | sh "$HOOK"
  after=$(cat "$FILE" 2>/dev/null || echo MISSING)
  if [ "$before" = "$after" ]; then echo "ok    $1 leaves the $3 state untouched"
  else echo "FAIL  $1 changed the file: $after"; FAIL=1; fi
}
for start in Stop PreToolUse PermissionRequest; do
  expect_unchanged "Notification without notification_type" \
    '{"session_id":"claude-sid-1","hook_event_name":"Notification","message":"hello"}' $start
  expect_unchanged "Notification with an unrecognised type" \
    '{"session_id":"claude-sid-1","hook_event_name":"Notification","notification_type":"auth_success"}' $start
  expect_unchanged "Notification with a null type" \
    '{"session_id":"claude-sid-1","hook_event_name":"Notification","notification_type":null}' $start
done

# Input the hook cannot use must neither crash nor touch the file.
fire Stop
expect_unchanged "malformed JSON" '{"hook_event_name":"Stop"' Stop
expect_unchanged "empty input" '' Stop
expect_unchanged "payload without hook_event_name" '{"session_id":"claude-sid-1","message":"x"}' Stop
expect_unchanged "hook_event_name null" '{"hook_event_name":null}' PreToolUse

# SubagentStop after Stop must leave the file byte-for-byte unchanged (a
# finished subagent says nothing about the main agent).
fire Stop
before=$(cat "$FILE")
fire SubagentStop
after=$(cat "$FILE")
if [ "$before" = "$after" ]; then echo "ok    SubagentStop ignored (file unchanged)"
else echo "FAIL  SubagentStop rewrote the file: $after"; FAIL=1; fi

# claude_session_id is carried through
fire PreToolUse
sid=$(jq -r '.claude_session_id' < "$FILE")
if [ "$sid" = "claude-sid-1" ]; then echo "ok    carries claude_session_id"
else echo "FAIL  claude_session_id was '$sid'"; FAIL=1; fi

# An unknown event must not change the file
fire Stop
before=$(cat "$FILE")
fire SomeFutureEvent
after=$(cat "$FILE")
if [ "$before" = "$after" ]; then echo "ok    unknown event ignored"
else echo "FAIL  unknown event rewrote the file"; FAIL=1; fi

# Outside iTerm, write nothing
rm -f "$FILE"
TERM_PROGRAM=Apple_Terminal fire PreToolUse
if [ -e "$FILE" ]; then echo "FAIL  wrote a file outside iTerm"; FAIL=1
else echo "ok    no-op outside iTerm"; fi
TERM_PROGRAM="iTerm.app"

# JSON escaping: session_id with quote and backslash round-trips
rm -f "$FILE"
TRICKY='quote"back\slash'
jq -n --arg event PreToolUse --arg sid "$TRICKY" '{hook_event_name: $event, session_id: $sid}' | sh "$HOOK"
if [ -f "$FILE" ]; then
  # Verify the file is valid JSON
  if jq . < "$FILE" > /dev/null 2>&1; then
    sid=$(jq -r '.claude_session_id' < "$FILE")
    if [ "$sid" = "$TRICKY" ]; then
      echo "ok    escapes JSON special chars"
    else
      echo "FAIL  JSON escaping: got '$sid', want '$TRICKY'"; FAIL=1
    fi
  else
    echo "FAIL  JSON escaping produced invalid JSON"; FAIL=1
  fi
else
  echo "FAIL  JSON escaping test: file not created"; FAIL=1
fi

# No leftover temp files
leftovers=$(find "$TMP" -name '*.tmp.*' | wc -l | tr -d ' ')
if [ "$leftovers" = "0" ]; then echo "ok    no temp files left behind"
else echo "FAIL  $leftovers temp files left behind"; FAIL=1; fi

exit $FAIL
