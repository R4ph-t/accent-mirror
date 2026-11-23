# Accent Mirror. CI runs generate, build, test and the guards (.github/workflows/ci.yml).
# Nothing CI runs launches the app, uses the microphone or runs UI tests.

PROJECT      := AccentMirror.xcodeproj
SCHEME       := AccentMirror
PACKAGE      := Packages/AccentKit
# DERIVED and RESULT_BUNDLE are the test VM's contract (manufacture test-vm / test-ui-vm set both in the guest).
DERIVED      ?= .build/DerivedData
# A path for the UI test run's .xcresult; empty: xcodebuild's default.
RESULT_BUNDLE ?=
RESULT_FLAGS  = $(if $(RESULT_BUNDLE),-resultBundlePath '$(RESULT_BUNDLE)')
# Extra xcodebuild flags for test-ui (e.g. -only-testing:AccentMirrorScreenshots/ScreenshotTests); empty locally.
UI_TEST_FLAGS ?=
MANUFACTURE  ?= $(HOME)/.local/bin/manufacture

.PHONY: generate build test test-ui test-vm test-ui-vm screenshots-vm ui-host-guard check-corpus check-ui-frameworks check \
        fetch-models bench eval agreement-record screenshots

generate:
	@command -v xcodegen >/dev/null || { echo "xcodegen is missing: brew install xcodegen"; exit 1; }
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
		-derivedDataPath '$(DERIVED)' CODE_SIGNING_ALLOWED=NO build

# AccentKit's package tests. They open no windows, so they're fine on any screen. RESULT_BUNDLE is accepted for the
# VM's contract but unused: swift test writes no .xcresult.
test:
	swift test --package-path $(PACKAGE)

check-corpus:
	scripts/check-local-corpus.sh

check-ui-frameworks:
	scripts/check-no-ui-frameworks.sh

check: build test check-corpus check-ui-frameworks
	scripts/test-check-local-corpus.sh

# Stubs until their specs land.
fetch-models:
	@echo "fetch-models: not yet: spec 03"

bench:
	@echo "bench: not yet: spec 11"

eval:
	@echo "eval: not yet: spec 03"

agreement-record:
	@echo "agreement-record: not yet: spec 03"

# Local only (spec 19): renders every UI fixture in light and dark at 2400 x 1600 into screenshots/ui-shell/,
# then checks no frame is blank. Launches the app as a test host, so it is never part of `check` or CI, and agents
# run it in the VM (make test-ui-vm), never on this screen. In the VM (RESULT_BUNDLE set) the PNGs go next to the
# .xcresult, so they come back to .factory/vm-results/<stamp>/<stamp>.xcresult.attachments/ui-shell/.
SCREENSHOT_DIR ?= $(if $(RESULT_BUNDLE),$(RESULT_BUNDLE).attachments/ui-shell,$(CURDIR)/screenshots/ui-shell)

screenshots: ui-host-guard generate
	rm -rf '$(SCREENSHOT_DIR)'
	TEST_RUNNER_SCREENSHOT_DIR='$(SCREENSHOT_DIR)' xcodebuild -project $(PROJECT) -scheme AccentMirrorScreenshots \
		-destination 'platform=macOS' -derivedDataPath '$(DERIVED)' $(RESULT_FLAGS) $(UI_TEST_FLAGS) test
	scripts/check-screenshots.sh '$(SCREENSHOT_DIR)'

# The app-hosted UI tests (today: the screenshot run and its blank-frame check). Takes over the screen it runs on, so on
# Raph's Mac it's for Raph by hand; agents use test-ui-vm. AM_HOST_UI_OK=1 is Raph's override.
test-ui: screenshots

ui-host-guard:
	@if [ -n "$$WG_FACTORY$$CLAUDECODE" ] && [ "$$AM_HOST_UI_OK" != 1 ]; then \
	  echo "UI tests run in the test VM: make test-ui-vm. Host test-ui / screenshots take over this screen; they're for Raph by hand."; \
	  exit 2; \
	fi

# Tests in the headless Tart test VM, through the installed Manufacture CLI (never a copy of its scripts). It syncs
# this checkout, runs `make generate && make <test|test-ui> DERIVED=… RESULT_BUNDLE=…` in the guest under the VM's one
# lock, and copies the .xcresult back to .factory/vm-results/<stamp>. make turns any failure into exit 2, so read the
# script's last line: "Tests: passed", "Tests: failed (rc 1)" (a real failure), or "VM: not running|busy|sync failed …"
# (not a test failure: retry later, never fall back to the host).
test-vm:
	'$(MANUFACTURE)' --project '$(CURDIR)' test-vm

test-ui-vm:
	'$(MANUFACTURE)' --project '$(CURDIR)' test-ui-vm UI_TEST_FLAGS='$(UI_TEST_FLAGS)'

# The screenshot run in the VM: the same as test-ui-vm (the renders come back with its results, see screenshots).
screenshots-vm: test-ui-vm
