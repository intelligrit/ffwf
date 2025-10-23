.PHONY: help run build build-release build-debug clean install uninstall test

.DEFAULT_GOAL := help

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

install: build-release ## Install to /usr/local/bin
	@echo "Installing FFFW to /usr/local/bin..."
	@mkdir -p /usr/local/bin
	@cp .build/release/FFFW /usr/local/bin/fffw
	@echo "Installed! Run 'fffw' to launch."

uninstall: ## Remove from /usr/local/bin
	@echo "Removing FFFW from /usr/local/bin..."
	@rm -f /usr/local/bin/fffw
	@echo "Uninstalled."

package-info: ## Show package information
	swift package describe

resolve: ## Resolve package dependencies
	swift package resolve

update: ## Update package dependencies
	swift package update

xcode: ## Generate Xcode project
	swift package generate-xcodeproj
