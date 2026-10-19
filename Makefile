CONFIG ?= debug
APP = _build/Marginalia.app
MD = $(APP)/Contents/MacOS/md
FILE ?= Fixtures/tour.md

.PHONY: build bundle run test smoke perf install clean release

build:
	swift build -c $(CONFIG)

bundle: build
	Scripts/bundle.sh $(CONFIG)

run: bundle
	$(MD) $(FILE)

test:
	swift test

smoke: bundle
	mkdir -p _build/smoke
	$(MD) --screenshot _build/smoke/light-edit.png --light $(FILE)
	$(MD) --screenshot _build/smoke/dark-edit.png --dark $(FILE)
	$(MD) --screenshot _build/smoke/light-read.png --light --reading $(FILE)
	$(MD) --screenshot _build/smoke/dark-read.png --dark --reading $(FILE)
	@ls -la _build/smoke

perf: bundle
	$(MD) --perf $(FILE)
	$(MD) --perf Fixtures/large.md

release:
	$(MAKE) bundle CONFIG=release

install: release
	rm -rf /Applications/Marginalia.app
	cp -R $(APP) /Applications/Marginalia.app
	mkdir -p $(HOME)/.local/bin
	ln -sf /Applications/Marginalia.app/Contents/MacOS/md $(HOME)/.local/bin/md
	@echo "installed. try: md Fixtures/tour.md"

clean:
	rm -rf .build _build

edit-test: bundle
	cp Fixtures/edit-start.md _build/edit.md
	$(MD) --edit-script Fixtures/edit-session.script _build/edit.md
	diff Fixtures/edit-expected.md _build/edit.md && echo "edit-test ok"
