PREFIX  ?= $(HOME)
# Directory variables spelled out rather than derived with $(dir ...): that
# function splits on whitespace internally, so it silently corrupts a PREFIX
# containing a space (e.g. dir("/tmp/fake home/x") loses "fake").
BINDIR  := $(PREFIX)/.claude/bin
BIN     := $(BINDIR)/fkeysd
HOOK    := $(PREFIX)/.claude/fkey-status.sh
CONFDIR := $(PREFIX)/.config/fkeys
CONF    := $(CONFDIR)/palette.json
PLISTDIR := $(PREFIX)/Library/LaunchAgents
PLIST   := $(PLISTDIR)/com.lucagaleazzi.fkeys.plist

.PHONY: build test install uninstall

build:
	swift build -c release

test:
	sh scripts/swift-test
	sh hooks/tests/test-fkey-status.sh

install: build
	mkdir -p "$(BINDIR)" "$(CONFDIR)" "$(PLISTDIR)" "$(PREFIX)/.claude/.fkeys"
	install -m 755 .build/release/fkeysd "$(BIN)"
	install -m 755 hooks/fkey-status.sh "$(HOOK)"
	@# Never clobber a palette the user has tuned.
	@[ -f "$(CONF)" ] || install -m 644 config/palette.json "$(CONF)"
	sed 's|@HOME@|$(PREFIX)|g' launchd/com.lucagaleazzi.fkeys.plist.in > "$(PLIST)"
	-launchctl unload "$(PLIST)" 2>/dev/null
	launchctl load "$(PLIST)"
	@echo "installed. add $(HOOK) to the hooks in ~/.claude/settings.json"

# Deliberately leaves behind: the tuned palette ($(CONF)), the state dir
# ($(PREFIX)/.claude/.fkeys) and the daemon's own registry/log files under
# $(PREFIX)/.claude. None of those are install artifacts — they're state a
# reinstall must not wipe.
uninstall:
	-launchctl unload "$(PLIST)" 2>/dev/null
	rm -f "$(BIN)" "$(HOOK)" "$(PLIST)"
