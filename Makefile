BUILD := Build
APP := $(BUILD)/Limón.app
DMG := $(BUILD)/Limon.dmg
ARCHIVE := $(BUILD)/Limon.app.zip

.DEFAULT_GOAL := build

.PHONY: build package run install clean

build:
	./build.sh

package: build
	rm -f "$(ARCHIVE)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(ARCHIVE)"

run: build
	open "$(APP)"

install: build
	ditto "$(APP)" "/Applications/Limón.app"

clean:
	rm -rf "$(BUILD)" AppIcon.iconset
