# Repo guardrails (vendor this file into each repo).
# Keep this lightweight and dependency-free so it runs early in CI.

.PHONY: guard-no-submodules
guard-no-submodules:
	@if [ -f .gitmodules ]; then \
		echo "ERROR: git submodules are forbidden in this ecosystem."; \
		echo "Found: .gitmodules"; \
		echo "Fix: remove submodules; prefer versioned deps or repo templates."; \
		exit 2; \
	fi

.PHONY: guard-version-file
guard-version-file:
	@if [ ! -f VERSION ]; then \
		echo "ERROR: VERSION file missing."; \
		echo "Fix: add VERSION (single line, e.g. 0.0.0)."; \
		exit 2; \
	fi
	@if [ ! -s VERSION ]; then \
		echo "ERROR: VERSION file is empty."; \
		exit 2; \
	fi
