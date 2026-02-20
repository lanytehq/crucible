SHELL := /bin/sh

-include make/repo-guards.mk

.PHONY: check
check: guard-no-submodules guard-version-file
	@echo "OK"

.PHONY: dev
dev: guard-no-submodules guard-version-file
	kitfly dev . --no-open

.PHONY: build
build: guard-no-submodules guard-version-file
	kitfly build .
