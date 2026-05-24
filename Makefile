# AuroraOS top-level Makefile.
# One command builds the ISO end-to-end.

SHELL := /bin/bash

.PHONY: iso clean test smoke deps push-release help

iso: ## Build the AuroraOS live ISO (default)
	@build/build.sh

deps: ## Install build dependencies (AL2023/Fedora; root required)
	@build/05-prereqs.sh

test: ## Boot the built ISO under QEMU+OVMF and run automated checks
	@build/90-test.sh

clean: ## Remove all build artefacts and the rootfs (keeps tooling)
	@rm -rf work out
	@echo "Cleaned."

smoke: ## Quick sanity check of the build pipeline (no rootfs)
	@./build/00-config.sh && which xorriso && which mksquashfs && which grub2-mkstandalone && echo "OK"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := iso
