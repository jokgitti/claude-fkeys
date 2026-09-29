#!/bin/sh
# Publish this Claude session's state for fkeysd, the F-key daemon.
#
# Keyed by the iTerm session UUID, not Claude's session id: `it2 session focus`
# takes that UUID and nothing else maps back to it.
#
# Single jq invocation for event→state mapping and JSON output with proper escaping.
# No subprocess forks (date, second jq call), no unescaped interpolation.
[ "$TERM_PROGRAM" = "iTerm.app" ] || exit 0
[ -n "${ITERM_SESSION_ID:-}" ] || exit 0

DIR="${FKEYS_STATE_DIR:-$HOME/.claude/.fkeys}"
FILE="$DIR/${ITERM_SESSION_ID#*:}.json"

RESULT=$(cat | jq -r '
# SubagentStop is deliberately absent: a subagent finishing says nothing about
# the main agent, and arriving after Stop it would flip a finished session back
# to working. PreToolUse/PostToolUse already keep a busy session "working".
#
# Notification is mapped by notification_type. Only idle_prompt ("Claude is
# waiting for your input", the turn is over) is idle. Every other type, an
# unknown one and a missing one included, is waiting: for a notification the
# safer error is to demand attention, not to look idle.
def event_to_state:
  if .hook_event_name == "SessionStart" or .hook_event_name == "Stop" then "idle"
  elif .hook_event_name == "PreToolUse" or .hook_event_name == "PostToolUse" then "working"
  elif .hook_event_name == "Notification" then
    (if .notification_type == "idle_prompt" then "idle" else "waiting" end)
  elif .hook_event_name == "PermissionRequest" then "waiting"
  else empty
  end;

.hook_event_name as $event |
([event_to_state][0]) as $state |
if $event == "SessionEnd" then
  "DELETE"
elif $state then
  "WRITE\t" + ({"state": $state, "ts": (now|floor), "claude_session_id": (.session_id // "")} | @json)
else
  "IGNORE"
end
' 2>/dev/null)

ACTION="${RESULT%%	*}"

case "$ACTION" in
  DELETE)
    rm -f "$FILE"
    ;;
  WRITE)
    JSON="${RESULT#*	}"
    mkdir -p "$DIR" 2>/dev/null || exit 0
    TMP="$FILE.tmp.$$"
    printf '%s\n' "$JSON" > "$TMP" && mv -f "$TMP" "$FILE" || rm -f "$TMP"
    ;;
esac
