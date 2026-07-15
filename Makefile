# Resonance — thin wrappers around scripts/. Run `make` for the list.

.DEFAULT_GOAL := help
.PHONY: help setup generate build release run install uninstall clean lint format format-check scripts test check package app-store-archive app-store-upload icon

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[1;36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Install toolchain deps and generate the project
	@./scripts/setup.sh

generate: ## Regenerate Resonance.xcodeproj from project.yml
	@xcodegen generate

build: ## Build Debug
	@./scripts/build.sh Debug

release: ## Build Release
	@./scripts/build.sh Release

run: ## Build and launch (Debug)
	@./scripts/run.sh

install: ## Build Release and install to /Applications
	@./scripts/install.sh

uninstall: ## Remove the installed app and reset its permissions
	@./scripts/uninstall.sh

clean: ## Remove the generated project and build artifacts
	@./scripts/clean.sh

lint: ## Lint with SwiftLint
	@./scripts/lint.sh

format: ## Format sources with swift-format
	@./scripts/format.sh

format-check: ## Verify Swift formatting
	@./scripts/format.sh --lint

scripts: ## Validate shell, plist, and workflow files
	@./scripts/check.sh

test: ## Run unit tests
	@./scripts/test.sh

check: format-check lint scripts test build ## Run every local quality gate

package: ## Package for distribution into dist/
	@./scripts/package.sh

app-store-archive: ## Create a signed Mac App Store archive
	@./scripts/app-store.sh archive

app-store-upload: ## Archive and upload a build to App Store Connect
	@./scripts/app-store.sh upload

icon: ## Regenerate the app icon PNGs
	@swift scripts/GenerateAppIcon.swift Resources/Assets.xcassets/AppIcon.appiconset
