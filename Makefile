.PHONY: help run build build-release build-debug clean install uninstall test app app-signed version

.DEFAULT_GOAL := help

# Version information
VERSION := 1.0.0

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

run: ## Run the app in debug mode
	swift run

build: build-debug ## Build debug version (default)

build-debug: ## Build debug version
	swift build

build-release: ## Build release version (optimized)
	swift build -c release

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build

test: ## Run tests (if any)
	swift test

install: clean app ## Install FFWF.app to /Applications (forces rebuild)
	@echo "Installing FFWF v$(VERSION) to /Applications..."
	@# Kill any running instances
	@pkill -x FFWF 2>/dev/null || true
	@sleep 0.5
	@# Remove old version
	@rm -rf /Applications/FFWF.app
	@# Copy new version
	@cp -r FFWF.app /Applications/
	@# Verify installation
	@if [ -d /Applications/FFWF.app ]; then \
		echo "✓ Successfully installed FFWF v$(VERSION) to /Applications/"; \
		echo "  Launch from Spotlight (⌘Space → 'FFWF') or /Applications/FFWF.app"; \
	else \
		echo "✗ Installation failed!"; \
		exit 1; \
	fi

uninstall: ## Remove FFWF.app from /Applications
	@echo "Removing FFWF from /Applications..."
	@# Kill any running instances
	@pkill -x FFWF 2>/dev/null || true
	@sleep 0.5
	@rm -rf /Applications/FFWF.app
	@echo "✓ Uninstalled successfully."

version: ## Show version information
	@echo "FFWF version $(VERSION)"

package-info: ## Show package information
	swift package describe

resolve: ## Resolve package dependencies
	swift package resolve

update: ## Update package dependencies
	swift package update

xcode: ## Generate Xcode project
	swift package generate-xcodeproj

app: build-release ## Build macOS app bundle (FFWF.app)
	@echo "Creating FFWF.app bundle..."
	@rm -rf FFWF.app
	@mkdir -p FFWF.app/Contents/MacOS
	@mkdir -p FFWF.app/Contents/Resources
	@cp .build/release/FFWF FFWF.app/Contents/MacOS/FFWF
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > FFWF.app/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> FFWF.app/Contents/Info.plist
	@echo '<plist version="1.0">' >> FFWF.app/Contents/Info.plist
	@echo '<dict>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>FFWF</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>com.robertmeta.FFWF</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>CFBundleName</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>FFWF</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>$(VERSION)</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>CFBundleShortVersionString</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>$(VERSION)</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>APPL</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>11.0</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>LSUIElement</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>1</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>NSAppleEventsUsageDescription</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>FFWF needs permission to access window information and switch between windows.</string>' >> FFWF.app/Contents/Info.plist
	@echo '    <key>NSAccessibilityUsageDescription</key>' >> FFWF.app/Contents/Info.plist
	@echo '    <string>FFWF needs accessibility access to focus and raise windows.</string>' >> FFWF.app/Contents/Info.plist
	@echo '</dict>' >> FFWF.app/Contents/Info.plist
	@echo '</plist>' >> FFWF.app/Contents/Info.plist
	@# Code sign with entitlements
	@codesign --force --deep --sign - --entitlements FFWF.entitlements FFWF.app
	@echo "✓ FFWF.app created and signed successfully!"
	@echo "  To install: make install"
	@echo "  To run: open FFWF.app"

app-signed: app ## Alias for 'app' (signing is now done automatically)
	@echo "Note: 'make app' now includes code signing with entitlements"
