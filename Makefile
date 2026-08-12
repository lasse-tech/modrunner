# modrunner — a macOS player for MED / OctaMED modules
#
# Run `make help` for the list of targets.

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

CONFIG      ?= release
APP_NAME    := ModRunner
APP         := build/$(APP_NAME).app
INSTALL_DIR ?= /Applications
EXAMPLES    := Examples

# A module to use for `make run` and `make export`.
MODULE      ?= $(EXAMPLES)/Happy Hour.med
# Seconds of audio for `make export`.
SECONDS     ?= 30
# Destination for `make export`.
WAV         ?= build/export.wav

.DEFAULT_GOAL := help
.PHONY: help build app run install uninstall test check export fmt clean clear distclean

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
	@echo "Installed. Launch it from the Finder or with: open -a $(APP_NAME)"

## uninstall: Remove ModRunner.app from /Applications
uninstall:
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Removed $(INSTALL_DIR)/$(APP_NAME).app"

## test: Run the loader and replayer test suite
test:
	swift test

## check: Build and test in one go, as CI does
check: build test

## export: Render a module to a WAV file for listening
export:
	@mkdir -p "$$(dirname "$(WAV)")"
	MED_EXPORT="$$(basename "$(MODULE)" .med)" \
	MED_SECONDS="$(SECONDS)" \
	MED_OUT="$(WAV)" \
	swift test --filter testExportWAVForListening
	@echo "Wrote $(WAV)"

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
