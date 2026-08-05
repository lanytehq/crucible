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
check: guard-no-submodules guard-version-file check-dispatch-v0 test-epilogue fmt-check ## Repo guards + schema family gates + format honesty
	@echo "OK"

.PHONY: test-epilogue
test-epilogue: ## Fail-secure post-merge epilogue negative controls (no mutations)
	@bash scripts/test-post-merge-epilogue.sh

# Post-merge cleanup. Dry-run by default.
# Required: WORKTREE=/abs/path BRANCH=feature/name
# Optional: MAIN_CHECKOUT=/abs/path REMOTE=origin APPLY=1 CONFIRM=1
.PHONY: post-merge-epilogue
post-merge-epilogue: ## Post-merge worktree cleanup (dry-run default; see docs/guides/post-merge-epilogue.md)
	@test -n "$(WORKTREE)" || { echo "[!!] WORKTREE=/abs/path is required" >&2; exit 1; }
	@test -n "$(BRANCH)" || { echo "[!!] BRANCH=name is required" >&2; exit 1; }
	@bash scripts/post-merge-epilogue.sh \
		--worktree "$(WORKTREE)" \
		--branch "$(BRANCH)" \
		$(if $(MAIN_CHECKOUT),--main-checkout "$(MAIN_CHECKOUT)",) \
		$(if $(REMOTE),--remote "$(REMOTE)",) \
		$(if $(filter 1,$(APPLY)),--apply,) \
		$(if $(filter 1,$(CONFIRM)),--confirm,)

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
fmt: ## Format all files (goneat: yaml, json, markdown); nonzero if goneat fails any file
	@if command -v goneat >/dev/null 2>&1; then \
		goneat format --types yaml,json,markdown --folders . --finalize-eof --quiet && \
		echo "[ok] fmt done"; \
	else \
		echo "[--] goneat not found, skipping"; \
	fi

.PHONY: fmt-check
fmt-check: ## Fail if any yaml/json/markdown needs formatting (goneat required on PATH for this gate)
	@if command -v goneat >/dev/null 2>&1; then \
		goneat format --types yaml,json,markdown --folders . --finalize-eof --check && \
		echo "[ok] fmt-check clean"; \
	else \
		echo "[!!] goneat not found; fmt-check requires goneat on PATH" >&2; \
		exit 1; \
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
