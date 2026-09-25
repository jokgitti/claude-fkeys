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

F<n> is bound to tab index n-1 of the frontmost iTerm2 window — the
binding is derived from iTerm each time it's needed, never stored. A tab
with no Claude session keeps its position and stays dark.

## Files

- `~/.claude/.fkeys/` — the hook's per-session state files. The daemon
  watches this directory; nothing else may write here, since a write inside
  it re-triggers the watcher.
- `~/.claude/fkeys.log` — daemon stdout/stderr under launchd, kept outside
  the watched directory for the same reason.

## Requires

- macOS, iTerm2 3.7+ (for `it2`), `jq`
- Swift 6 toolchain to build
- Custom QMK firmware on the keyboard for the lights (see `qmk/`).
  Tab switching works without it.
