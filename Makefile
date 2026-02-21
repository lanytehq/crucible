SHELL := /bin/sh

-include make/repo-guards.mk

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "%-22s %s\n", $$1, $$2}'

.PHONY: hooks-install
hooks-install: ## Configure git to use .githooks (local setting)
	@git config core.hooksPath .githooks
	@echo "[ok] core.hooksPath=.githooks"

.PHONY: all
all: check ## Default target (alias of check)

.PHONY: test
test: check ## Run tests (alias of check)

.PHONY: clean
clean: ## Remove build artifacts (placeholder)
	@echo "[ok] nothing to clean"

.PHONY: check
check: guard-no-submodules guard-version-file ## Repo guards
	@echo "OK"

.PHONY: quality
quality: ## Run goneat lint checks (optional)
	@if command -v goneat >/dev/null 2>&1; then \
		goneat assess --categories lint --fail-on medium --output /dev/null; \
	else \
		echo "[--] goneat not found, skipping"; \
	fi

.PHONY: precommit
precommit: check ## Pre-commit checks (fast)
	@echo "[ok] Pre-commit checks passed"

.PHONY: prepush
prepush: check build ## Pre-push checks (thorough)
	@echo "[ok] Pre-push checks passed"

.PHONY: dev
dev: check ## Local dev server
	kitfly dev . --no-open

.PHONY: build
build: check ## Build docs
	kitfly build .
