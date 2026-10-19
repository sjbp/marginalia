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
	$(MD) --screenshot _build/smoke/light-source.png --light --source $(FILE)
	$(MD) --screenshot _build/smoke/dark-source.png --dark --source $(FILE)
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

# Overlay placement regression: real key events, assertion after every keystroke (fails on any misplaced table, image, or card).
overlay-test: bundle
	python3 Scripts/make-overlay-fixture.py _build/overlay-fixture.md
	$(MD) --edit-script Fixtures/overlay.script _build/overlay-fixture.md 2>&1 | grep -E "ASSERT_OVERLAYS|MISPLACED" | tee _build/overlay-test.log
	/bin/cp -f Fixtures/tour.md _build/overlay-tour.md
	$(MD) --edit-script Fixtures/overlay-tour.script _build/overlay-tour.md 2>&1 | grep -E "ASSERT_OVERLAYS|MISPLACED" | tee -a _build/overlay-test.log
	@! grep -q FAIL _build/overlay-test.log && echo "overlay-test ok"

dmg: release
	Scripts/dmg.sh
	/bin/cp -f _build/Marginalia-*.dmg $(HOME)/Downloads/
	@ls -la $(HOME)/Downloads/Marginalia-*.dmg
