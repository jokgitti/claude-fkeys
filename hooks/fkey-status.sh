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
def event_to_state:
  if . == "SessionStart" or . == "Stop" then "idle"
  elif . == "PreToolUse" or . == "PostToolUse" or . == "SubagentStop" then "working"
  elif . == "Notification" or . == "PermissionRequest" then "waiting"
  else empty
  end;

.hook_event_name as $event |
if $event == "SessionEnd" then
  "DELETE"
elif ($event | event_to_state) then
  "WRITE\t" + ({"state": ($event | event_to_state), "ts": (now|floor), "claude_session_id": (.session_id // "")} | @json)
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
