PREFIX ?= $(HOME)
BIN   := $(PREFIX)/.claude/bin/fkeysd
HOOK  := $(PREFIX)/.claude/fkey-status.sh
CONF  := $(PREFIX)/.config/fkeys/palette.json
PLIST := $(PREFIX)/Library/LaunchAgents/com.lucagaleazzi.fkeys.plist

.PHONY: build test install uninstall

build:
	swift build -c release

test:
	sh scripts/swift-test
	sh hooks/tests/test-fkey-status.sh

install: build
	mkdir -p $(dir $(BIN)) $(dir $(CONF)) $(dir $(PLIST)) $(PREFIX)/.claude/.fkeys
	install -m 755 .build/release/fkeysd $(BIN)
	install -m 755 hooks/fkey-status.sh $(HOOK)
	@# Never clobber a palette the user has tuned.
	@[ -f $(CONF) ] || install -m 644 config/palette.json $(CONF)
	sed 's|@HOME@|$(PREFIX)|g' launchd/com.lucagaleazzi.fkeys.plist.in > $(PLIST)
	-launchctl unload $(PLIST) 2>/dev/null
	launchctl load $(PLIST)
	@echo "installed. add $(HOOK) to the hooks in ~/.claude/settings.json"

uninstall:
	-launchctl unload $(PLIST) 2>/dev/null
	rm -f $(BIN) $(HOOK) $(PLIST)
