# modrunner — a macOS player for MED / OctaMED modules
#
# Run `make help` for the list of targets.

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

CONFIG      ?= release
APP_NAME    := ModRunner
APP         := build/$(APP_NAME).app
INSTALL_DIR ?= /Applications
LSREGISTER  := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
EXAMPLES    := Examples

# A module to use for `make run` and `make export`.
MODULE      ?= $(EXAMPLES)/Happy Hour.med
# Seconds of audio for `make export`.
SECONDS     ?= 30
# Destination for `make export`.
WAV         ?= build/export.wav

# Release settings. VERSION names the disk image and the tag; it has no default
# on purpose, since a release built as 0.0.0 is a release nobody wants.
VERSION        ?=
SIGN_IDENTITY  ?= Developer ID Application: Lars Gossard (ZPY7FC8GVK)
NOTARY_PROFILE ?= modrunner
DRAFT          ?= 1
DMG            := build/ModRunner-$(VERSION).dmg

.DEFAULT_GOAL := help
.PHONY: help build app run install uninstall associate associations test check export cli info render tui icons lint lint-fix fmt clean clear distclean signed-app dmg release notary-setup

## help: Show this list of targets
help:
	@echo "ModRunner — available targets:"
	@echo
	@grep -E '^## [a-z-]+:' $(MAKEFILE_LIST) \
		| sed -e 's/^## //' \
		| awk -F': ' '{ printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2 }'
	@echo
	@echo "Variables:"
	@echo "  CONFIG=$(CONFIG)            debug | release"
	@echo "  INSTALL_DIR=$(INSTALL_DIR)"
	@echo "  MODULE=$(MODULE)"
	@echo "  VERSION=$(VERSION)              required by signed-app, dmg and release"
	@echo "  DRAFT=$(DRAFT)                  1 keeps the GitHub release a draft"

## build: Compile the executable
build:
	swift build -c $(CONFIG)

## app: Build the ModRunner.app bundle
app:
	Scripts/make-app.sh $(CONFIG)

## run: Build the app and play the example modules
run: app
	open $(APP) --args "$(EXAMPLES)"

## install: Copy ModRunner.app into /Applications
install: app
	@echo "Installing $(APP_NAME).app into $(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@# Launch Services caches document types and their icons per bundle. Without
	@# this the Finder keeps showing the generic icon on .med and .mod files, and
	@# the copy in build/ competes with the installed one for the same bundle id.
	@$(LSREGISTER) -u "$(APP)" 2>/dev/null || true
	$(LSREGISTER) -f -R "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed and registered. Launch it with: open -a $(APP_NAME)"

## associate: Make ModRunner the default app for .med and .mod files
associate: install
	swift Scripts/associate.swift

## associations: Show which app currently opens .med and .mod files
associations:
	@swift Scripts/associate.swift --status

## uninstall: Remove ModRunner.app from /Applications
uninstall:
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Removed $(INSTALL_DIR)/$(APP_NAME).app"

## test: Run the loader and replayer test suite
test:
	swift test

## check: Build, test and lint in one go, as CI does
check: build test lint

## cli: Build the modrunner command-line tool
cli:
	swift build -c $(CONFIG) --product modrunner
	@echo "Built $$(swift build -c $(CONFIG) --show-bin-path)/modrunner"

## info: Print what the CLI knows about MODULE
info: cli
	@"$$(swift build -c $(CONFIG) --show-bin-path)/modrunner" info "$(MODULE)"

## render: Render MODULE to WAV through the CLI
render: cli
	@mkdir -p "$$(dirname "$(WAV)")"
	@"$$(swift build -c $(CONFIG) --show-bin-path)/modrunner" render "$(MODULE)" -o "$(WAV)" \
		$(if $(SECONDS),--seconds $(SECONDS),)

## tui: Play MODULE in the terminal
tui: cli
	@"$$(swift build -c $(CONFIG) --show-bin-path)/modrunner" tui "$(MODULE)"

## notary-setup: Store the Apple credentials the notary service needs, once
notary-setup:
	@echo "Storing a keychain profile called '$(NOTARY_PROFILE)'."
	@echo "You need your Apple ID, the team id ZPY7FC8GVK, and an app-specific"
	@echo "password from appleid.apple.com (Sign-In and Security > App-Specific"
	@echo "Passwords) — not your normal Apple ID password."
	@echo
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" --team-id ZPY7FC8GVK

## signed-app: Build the app bundle signed with the Developer ID certificate
signed-app: require-version
	VERSION="$(VERSION)" SIGN_IDENTITY="$(SIGN_IDENTITY)" Scripts/make-app.sh release

## dmg: Build, sign and notarise the disk image
dmg: signed-app
	VERSION="$(VERSION)" SIGN_IDENTITY="$(SIGN_IDENTITY)" \
	NOTARY_PROFILE="$(NOTARY_PROFILE)" Scripts/make-dmg.sh

## release: Tag the version and publish the disk image on GitHub
release: dmg
	VERSION="$(VERSION)" DRAFT="$(DRAFT)" Scripts/make-release.sh

.PHONY: require-version
require-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "error: set VERSION, as in: make release VERSION=1.0.0" >&2; \
		exit 1; \
	fi

## icons: Rebuild the Finder icons for .med and .mod
icons:
	swift Scripts/make-doc-icons.swift

## export: Render a module to a WAV file for listening
export:
	@mkdir -p "$$(dirname "$(WAV)")"
	MED_EXPORT="$$(basename "$(MODULE)" .med)" \
	MED_SECONDS="$(SECONDS)" \
	MED_OUT="$(WAV)" \
	swift test --filter testExportWAVForListening
	@echo "Wrote $(WAV)"

## lint: Check the sources with SwiftLint, if it is installed
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "SwiftLint is not installed (brew install swiftlint); skipping."; \
	fi

## lint-fix: Apply the corrections SwiftLint can make on its own
lint-fix:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --fix --quiet && swiftlint lint --quiet; \
	else \
		echo "SwiftLint is not installed (brew install swiftlint); skipping."; \
	fi

## fmt: Reformat the sources with swift-format, if it is installed
fmt:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format --in-place --recursive Sources Tests; \
		echo "Formatted."; \
	else \
		echo "swift-format is not installed; skipping."; \
	fi

## clean: Remove build products
clean:
	swift package clean
	rm -rf build

## clear: Alias for clean
clear: clean

## distclean: Remove build products and all resolved package state
distclean: clean
	rm -rf .build .swiftpm
