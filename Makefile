APP := Limón.app
ARCHIVE := Limon.app.zip

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
	ditto "$(APP)" "/Applications/$(APP)"

clean:
	rm -rf "$(APP)" AppIcon.iconset
	rm -f "$(ARCHIVE)"
