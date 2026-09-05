# Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# SPDX-License-Identifier: AGPL-3.0-or-later
# DEED-089: Sovereign Treasury Engine — Build System

CC = gcc
NASM = nasm
AR = ar
CFLAGS = -Wall -Wextra -O2 -I src/native
NFLAGS = -f elf64
LDFLAGS = -lm

# WASM modules (compiled via Node.js + wabt.js)
WASM_MODULES = wasm/runtime.wasm wasm/isa.wasm wasm/worm_frame.wasm \
               wasm/ledger_replay.wasm wasm/account_registry.wasm wasm/sha256.wasm

# Native C objects
NATIVE_OBJS = src/native/worm_commit.o

# NASM objects
ASM_OBJS = x86_64/treasury_serialization.o

# Static library
LIBRARY = lib/libworm.a

.PHONY: all wasm native asm clean test test-verbose test-unit lint help

all: wasm native asm $(LIBRARY)

# ── WASM compilation (Node.js + wabt.js) ──────────────────────────────────────

wasm:
	@echo "=== Compiling WASM modules ==="
	node compile_wasm.js

# ── Native C compilation ──────────────────────────────────────────────────────

src/native/%.o: src/native/%.c src/native/worm_block.h
	$(CC) $(CFLAGS) -c $< -o $@

native: $(NATIVE_OBJS)

# ── NASM assembly compilation ─────────────────────────────────────────────────

x86_64/%.o: x86_64/%.nasm
	$(NASM) $(NFLAGS) $< -o $@

asm: $(ASM_OBJS)

# ── Static library archive ────────────────────────────────────────────────────

$(LIBRARY): $(NATIVE_OBJS) $(ASM_OBJS)
	mkdir -p lib
	$(AR) rcs $@ $^

# ── Zig loader (if available) ─────────────────────────────────────────────────

zig-loader:
	@if command -v zig >/dev/null 2>&1; then \
		zig build; \
		echo "Zig loader built: lib/libloader.a"; \
	else \
		echo "Zig not installed, skipping native loader build"; \
	fi

# ── Scala pipeline (if sbt available) ─────────────────────────────────────────

scala-pipeline:
	@if command -v sbt >/dev/null 2>&1; then \
		sbt compile; \
		echo "Scala pipeline compiled"; \
	else \
		echo "sbt not installed, skipping Scala pipeline build"; \
	fi

# ── Chisel hardware (if sbt available) ────────────────────────────────────────

chisel:
	@if command -v sbt >/dev/null 2>&1; then \
		sbt "runMain WormFFIExport"; \
		echo "Chisel Verilog generated in generated/"; \
	else \
		echo "sbt not installed, skipping Chisel generation"; \
	fi

# ── Python tests (baseline) ──────────────────────────────────────────────────

test:
	@echo "=== Running production test suite ==="
	PYTHONPATH=src python -m pytest tests/test_stack.py -v --tb=short

test-verbose:
	@echo "=== Running production test suite (verbose) ==="
	PYTHONPATH=src python -m pytest tests/test_stack.py -v --tb=long -s

test-unit:
	@echo "=== Running unit tests only ==="
	PYTHONPATH=src python -m pytest tests/test_stack.py -v -k "not Integration and not adversarial" --tb=short

test-integration:
	@echo "=== Running integration tests ==="
	PYTHONPATH=src python -m pytest tests/test_stack.py -v -k "Integration" --tb=short

# ── Linting ───────────────────────────────────────────────────────────────────

lint:
	@echo "=== Checking Python syntax ==="
	@python -m py_compile src/worm.py && echo "worm.py: OK"
	@python -m py_compile src/twin.py && echo "twin.py: OK"
	@python -m py_compile src/audit.py && echo "audit.py: OK"
	@python -m py_compile src/quantum.py && echo "quantum.py: OK"
	@python -m py_compile src/cli.py && echo "cli.py: OK"

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -f $(NATIVE_OBJS) $(ASM_OBJS) $(LIBRARY)
	rm -rf generated/ lib/
	rm -f data/treasury-worm*.bin
	rm -f src/*.pyc
	rm -rf src/__pycache__

# ── Full build (all layers) ──────────────────────────────────────────────────

full: all zig-loader scala-pipeline chisel
	@echo "=== Sovereign Treasury Engine: Full Build Complete ==="
	@echo "WASM modules: $(WASM_MODULES)"
	@echo "Native library: $(LIBRARY)"
	@echo "Run 'make test' to verify baseline"

# ── Help ──────────────────────────────────────────────────────────────────────

help:
	@echo "Targets:"
	@echo "  all            Build WASM + native C + NASM assembly"
	@echo "  wasm           Compile WASM modules via Node.js"
	@echo "  native         Compile native C objects"
	@echo "  asm            Compile NASM assembly"
	@echo "  test           Run production test suite"
	@echo "  test-verbose   Run tests with full output"
	@echo "  test-unit      Run unit tests only"
	@echo "  test-integration  Run integration tests only"
	@echo "  lint           Syntax-check all Python sources"
	@echo "  clean          Remove build artifacts"
	@echo "  full           Full build (all layers)"
	@echo "  help           Show this help"
