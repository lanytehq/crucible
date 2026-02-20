SHELL := /bin/sh

# Vendor guardrails so CI does not depend on sibling repos.
-include make/repo-guards.mk

.PHONY: build
build: guard-no-submodules
	@echo "No build configured for crucible yet."

.PHONY: check
check: guard-no-submodules
	@echo "OK"

