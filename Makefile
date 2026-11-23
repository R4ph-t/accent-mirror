# Accent Mirror. CI runs exactly these targets (.github/workflows/ci.yml).
# Nothing here launches the app, uses the microphone or runs UI tests.

PROJECT      := AccentMirror.xcodeproj
SCHEME       := AccentMirror
PACKAGE      := Packages/AccentKit
DERIVED_DATA := .build/DerivedData

.PHONY: generate build test check-corpus check-ui-frameworks check \
        fetch-models bench eval agreement-record screenshots

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

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
# then checks no frame is blank. Launches the app as a test host, so it is never part of `check` or CI.
SCREENSHOT_DIR := $(CURDIR)/screenshots/ui-shell

screenshots: generate
	rm -rf $(SCREENSHOT_DIR)
	TEST_RUNNER_SCREENSHOT_DIR=$(SCREENSHOT_DIR) xcodebuild -project $(PROJECT) -scheme AccentMirrorScreenshots \
		-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) test
	scripts/check-screenshots.sh $(SCREENSHOT_DIR)
