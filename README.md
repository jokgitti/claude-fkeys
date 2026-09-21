# claude-fkeys

Binds F1–F12 on a GMMK Pro to Claude Code sessions in iTerm2.

- Press F<n> to focus the session bound to that key.
- The key's LED shows the session's state: orange working, green idle,
  magenta pulsing when it is blocked on a permission prompt or a question.

Design: `~/.claude/plans/2026-09-21-claude-fkeys-design.md`

## Install

    make install

Then add `~/.claude/fkey-status.sh` to the hooks in `~/.claude/settings.json`
for: SessionStart, PreToolUse, PostToolUse, Notification, PermissionRequest,
Stop, SubagentStop, SessionEnd. The entry must use `"async": true` to prevent
the hook from blocking the tool-call path.

## Requires

- macOS, iTerm2 3.7+ (for `it2`), `jq`
- Swift 6 toolchain to build
- Custom QMK firmware on the keyboard for the lights (see `qmk/`).
  Tab switching works without it.
