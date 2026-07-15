SHELL := /bin/sh

-include make/repo-guards.mk
-include make/release.mk

.PHONY: help
help: ## List targets
	@grep -hE '^[a-zA-Z0-9_.-]+:.*## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "%-26s %s\n", $$1, $$2}'

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
check: guard-no-submodules guard-version-file check-dispatch-v0 ## Repo guards + schema family gates
	@echo "OK"

.PHONY: check-dispatch-v0
check-dispatch-v0: ## Validate the agentic/dispatch v0 schema family (schemas + fixtures + semantic layer)
	@if python3 -c 'import jsonschema' >/dev/null 2>&1; then \
		python3 scripts/validate-dispatch-v0.py; \
	elif command -v uv >/dev/null 2>&1; then \
		uv run --with jsonschema scripts/validate-dispatch-v0.py; \
	else \
		echo "[!!] the dispatch v0 family gate REQUIRES the python 'jsonschema' package"; \
		echo "[!!] install it (pip install jsonschema) or install uv — this gate never soft-skips"; \
		exit 1; \
	fi

.PHONY: fmt
fmt: ## Format all files (goneat: yaml, json, markdown)
	@if command -v goneat >/dev/null 2>&1; then \
		goneat format --types yaml,json,markdown --folders . --finalize-eof --quiet 2>&1 | grep -v "encountered the following formatting errors" || true; \
		echo "[ok] fmt done"; \
	else \
		echo "[--] goneat not found, skipping"; \
	fi

.PHONY: quality
quality: ## Run goneat lint checks (optional)
	@if command -v goneat >/dev/null 2>&1; then \
		goneat assess --categories lint --fail-on medium --output /dev/null; \
	else \
		echo "[--] goneat not found, skipping"; \
	fi

.PHONY: precommit
precommit: check fmt quality ## Pre-commit checks: guards + fmt + lint
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
