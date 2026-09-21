#!/bin/sh
# Publish this Claude session's state for fkeysd, the F-key daemon.
#
# Keyed by the iTerm session UUID, not Claude's session id: `it2 session focus`
# takes that UUID and nothing else maps back to it.
#
# Runs on every tool call, so it must stay cheap — no it2 round trips, no network.
[ "$TERM_PROGRAM" = "iTerm.app" ] || exit 0
[ -n "${ITERM_SESSION_ID:-}" ] || exit 0

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ -n "$EVENT" ] || exit 0

DIR="${FKEYS_STATE_DIR:-$HOME/.claude/.fkeys}"
FILE="$DIR/${ITERM_SESSION_ID#*:}.json"

if [ "$EVENT" = "SessionEnd" ]; then
  rm -f "$FILE"
  exit 0
fi

case "$EVENT" in
  SessionStart|Stop)                   STATE=idle ;;
  PreToolUse|PostToolUse|SubagentStop) STATE=working ;;
  Notification|PermissionRequest)      STATE=waiting ;;
  *) exit 0 ;;
esac

mkdir -p "$DIR" 2>/dev/null || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Atomic: a half-written file would give the daemon a parse error on every event.
TMP="$FILE.tmp.$$"
printf '{"state":"%s","ts":%s,"claude_session_id":"%s"}\n' \
  "$STATE" "$(date +%s)" "$SID" > "$TMP" && mv -f "$TMP" "$FILE" || rm -f "$TMP"
