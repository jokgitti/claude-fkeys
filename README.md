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

**Then restart any Claude sessions that were already running.** Claude Code
reads its hook configuration when a session starts, so a session that predates
the `settings.json` edit never runs the hook — it stays unbound for its whole
life, and its key stays dark, with no error anywhere. Sessions started
afterwards pick it up with no action needed. This is not "it binds on first
activity"; it never binds.

The keyboard shows nothing but bound F-keys. Every other LED is held black,
including the side strips, and that holds on any machine — plug it into a
different computer and it stays completely dark. It types normally there.
The Fn layer's RGB keycodes (`RM_*`) are still in the keymap. QMK's
`rgb_matrix_task` calls the indicator callback only while an effect is active,
so the RGB toggle key probably switches off the F-row lights as well, until it
is toggled back on. This is from reading QMK's source and has not been
confirmed on hardware. `firmware/README.md` covers going back.

F<n> is bound to tab index n-1 of the frontmost iTerm2 window — the
binding is derived from iTerm each time it's needed, never stored. A tab
with no Claude session keeps its position and stays dark.

## Files

- `~/.claude/.fkeys/` — the hook's per-session state files. The daemon
  watches this directory; nothing else may write here, since a write inside
  it re-triggers the watcher. `SessionEnd` normally removes a session's file;
  for the cases that skip it (crash, `kill -9`, a closed window), the 10s
  reconcile loop cross-checks `it2 session list` and deletes any file whose
  session is no longer live. This is separate from key assignment — it just
  keeps the directory from leaking stale files.
- `~/.claude/fkeys.log` — daemon stdout/stderr under launchd, kept outside
  the watched directory for the same reason.

## Requires

- macOS, iTerm2 3.7+ (for `it2`), `jq`
- Swift 6 toolchain to build
- Custom QMK firmware on the keyboard for the lights (see `qmk/`).
  Tab switching works without it.
