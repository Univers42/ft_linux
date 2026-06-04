# ft_linux — single entry point. Everything runs inside Docker.
# The host needs only: docker, qemu-system-x86_64.

SHELL          := /bin/bash
PROJECT_DIR    := $(shell pwd)
BUILD_DIR      := $(PROJECT_DIR)/build
IMAGE_NAME     := ft_linux.img
IMAGE_PATH     := $(BUILD_DIR)/$(IMAGE_NAME)
SHA_PATH       := $(BUILD_DIR)/disk.sha256
DOCKER_IMG     := ft_linux/builder:latest
COMPOSE        := docker compose -f docker/docker-compose.yml

# Subject-locked values — do not change without updating CLAUDE.md
STUDENT_LOGIN  := dlesieur
KERNEL_VERSION := 6.6.32

# Interpreter the build phases run under. Pure hellish (our 42sh); override
# only for debugging: make phase-disk RUNNER=bash
RUNNER         := hellish

# Watchdog (tools/watchdog) — compiled inside the builder into the gitignored
# build/ tree; guards in-container steps against stalls/deadlocks.
WATCHDOG_BIN   := $(BUILD_DIR)/bin/watchdog
WD_SRC         := tools/watchdog/watchdog.c

# Per-phase host-side wall-clock caps (seconds): a backstop so a hung phase can
# never wedge the host. SIGTERM first (lets cleanup traps run), SIGKILL after.
# The in-container watchdog catches per-step stalls much faster.
T_DISK         ?= 900
T_TOOLCHAIN    ?= 10800
T_PACKAGES     ?= 36000
T_KERNEL       ?= 7200
T_SYSTEM       ?= 1800
HOST_GUARD     := timeout --kill-after=120

.DEFAULT_GOAL := help

# ----------------------------------------------------------------------------
# Help
# ----------------------------------------------------------------------------
.PHONY: help
help:
	@echo "ft_linux — LFS build, fully containerized"
	@echo ""
	@echo "  make deps         Check host has docker + qemu (nothing else needed)"
	@echo "  make image        Build the Docker build environment"
	@echo "  make build        Full LFS build (all 5 phases)"
	@echo "  make run          Boot build/ft_linux.img in QEMU"
	@echo "  make shell        Open shell in the build container (debugging)"
	@echo "  make shasum       Generate build/disk.sha256 for submission"
	@echo "  make lint         Static-check scripts/ (shellcheck + shfmt diff)"
	@echo "  make fmt          Auto-format scripts/ in place (shfmt)"
	@echo "  make check-hellish  Run scripts/ under hellish vs bash, report divergences"
	@echo "  make clean        Remove build/ artifacts"
	@echo "  make distclean    clean + remove Docker image and volumes"
	@echo ""
	@echo "Phases (re-entrant, run individually if needed):"
	@echo "  make phase-disk        00-init-disk.sh"
	@echo "  make phase-toolchain   01-build-toolchain.sh"
	@echo "  make phase-packages    02-build-system.sh"
	@echo "  make phase-kernel      03-build-kernel.sh"
	@echo "  make phase-system      04-configure-system.sh"
	@echo ""
	@echo "Student: $(STUDENT_LOGIN)   Kernel: $(KERNEL_VERSION)-$(STUDENT_LOGIN)"

# ----------------------------------------------------------------------------
# Host sanity check
# ----------------------------------------------------------------------------
.PHONY: deps
deps:
	@echo "==> Checking host dependencies (docker + qemu)…"
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not installed on host"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "ERROR: docker daemon not reachable"; exit 1; }
	@command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "WARN: qemu-system-x86_64 missing — needed for 'make run'"; }
	@echo "OK — host has only docker (and qemu if installed). No build tools on host."

# ----------------------------------------------------------------------------
# Docker image
# ----------------------------------------------------------------------------
.PHONY: image
image:
	@mkdir -p $(BUILD_DIR)/logs
	$(COMPOSE) build

# ----------------------------------------------------------------------------
# Watchdog — compiled in-container (honours "all compilation in Docker"),
# rebuilt only when the source changes.
# ----------------------------------------------------------------------------
$(WATCHDOG_BIN): $(WD_SRC) | image
	@mkdir -p $(BUILD_DIR)/bin
	$(COMPOSE) run --rm builder sh -c 'mkdir -p /output/bin && \
		gcc -O2 -Wall -Wextra -Werror -std=c11 -static \
		-o /output/bin/watchdog /project/tools/watchdog/watchdog.c'

.PHONY: watchdog
watchdog: $(WATCHDOG_BIN)
	@echo "OK — watchdog at $(WATCHDOG_BIN)"

# ----------------------------------------------------------------------------
# Full build pipeline
# ----------------------------------------------------------------------------
.PHONY: build
build: image phase-disk phase-toolchain phase-packages phase-kernel phase-system
	@echo ""
	@echo "==> Build complete. Image: $(IMAGE_PATH)"
	@echo "    Run:    make run"
	@echo "    Submit: make shasum"

# ----------------------------------------------------------------------------
# Individual phases — each just runs the matching script in the container
# ----------------------------------------------------------------------------
.PHONY: phase-disk phase-toolchain phase-packages phase-kernel phase-system

phase-disk: image $(WATCHDOG_BIN)
	@mkdir -p $(BUILD_DIR)/logs
	$(HOST_GUARD) $(T_DISK) $(COMPOSE) run --rm builder $(RUNNER) /project/scripts/00-init-disk.sh

phase-toolchain: image $(WATCHDOG_BIN)
	$(HOST_GUARD) $(T_TOOLCHAIN) $(COMPOSE) run --rm builder $(RUNNER) /project/scripts/01-build-toolchain.sh

phase-packages: image $(WATCHDOG_BIN)
	$(HOST_GUARD) $(T_PACKAGES) $(COMPOSE) run --rm builder $(RUNNER) /project/scripts/02-build-system.sh

phase-kernel: image $(WATCHDOG_BIN)
	$(HOST_GUARD) $(T_KERNEL) $(COMPOSE) run --rm builder $(RUNNER) /project/scripts/03-build-kernel.sh

phase-system: image $(WATCHDOG_BIN)
	$(HOST_GUARD) $(T_SYSTEM) $(COMPOSE) run --rm builder $(RUNNER) /project/scripts/04-configure-system.sh

# ----------------------------------------------------------------------------
# QEMU boot — runs on host (needs KVM passthrough), no install required
# ----------------------------------------------------------------------------
.PHONY: run run-gui
run:
	@test -f $(IMAGE_PATH) || { echo "ERROR: $(IMAGE_PATH) not found. Run 'make build' first."; exit 1; }
	@bash scripts/vm-run.sh "$(IMAGE_PATH)" nographic

run-gui:
	@test -f $(IMAGE_PATH) || { echo "ERROR: $(IMAGE_PATH) not found. Run 'make build' first."; exit 1; }
	@bash scripts/vm-run.sh "$(IMAGE_PATH)" gui

# ----------------------------------------------------------------------------
# Debug shell inside the build container
# ----------------------------------------------------------------------------
.PHONY: shell
shell: image
	$(COMPOSE) run --rm builder bash

# ----------------------------------------------------------------------------
# Submission artifact
# ----------------------------------------------------------------------------
.PHONY: shasum
shasum:
	@test -f $(IMAGE_PATH) || { echo "ERROR: $(IMAGE_PATH) not found."; exit 1; }
	@echo "==> Hashing $(IMAGE_PATH) (this can take a minute on a 20 GB image)…"
	@sha256sum $(IMAGE_PATH) | tee $(SHA_PATH)
	@echo "==> Wrote $(SHA_PATH). Commit this file, not the image."

# ----------------------------------------------------------------------------
# Quality: static checks + hellish compatibility (host tools, nothing installed)
# ----------------------------------------------------------------------------
SCRIPTS := $(wildcard scripts/*.sh) docker/entrypoint.sh

.PHONY: lint fmt check-hellish
lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "ERROR: shellcheck not found on host"; exit 1; }
	@command -v shfmt      >/dev/null 2>&1 || { echo "ERROR: shfmt not found on host"; exit 1; }
	shellcheck -x $(SCRIPTS)
	shfmt -d -i 4 -ci $(SCRIPTS)
	@echo "OK — scripts lint clean."

fmt:
	@command -v shfmt >/dev/null 2>&1 || { echo "ERROR: shfmt not found on host"; exit 1; }
	shfmt -w -i 4 -ci $(SCRIPTS)

check-hellish:
	@command -v hellish >/dev/null 2>&1 || { echo "ERROR: hellish not found on host"; exit 1; }
	@bash scripts/check-hellish.sh

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
.PHONY: clean distclean
clean:
	@echo "==> Removing build/ artifacts…"
	rm -rf $(BUILD_DIR)

distclean: clean
	@echo "==> Removing Docker image…"
	-$(COMPOSE) down -v --rmi local
