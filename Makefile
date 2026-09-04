# Copyright (c) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# SPDX-License-Identifier: AGPL-3.0-or-later
# DEED-089: Sovereign Treasury Engine — Build System
# Wires PL/I, COBOL, NASM, C, Chisel, Scala, and WASM layers together.

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

.PHONY: all wasm native asm clean test

all: wasm native asm $(LIBRARY)

# ── WASM compilation (Node.js + wabt.js) ──────────────────────────────────────

wasm:
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
	python -m pytest tests/test_stack.py -v

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -f $(NATIVE_OBJS) $(ASM_OBJS) $(LIBRARY)
	rm -rf generated/
	rm -f data/treasury-worm*.bin

# ── Full build (all layers) ──────────────────────────────────────────────────

full: all zig-loader scala-pipeline chisel
	@echo "=== Sovereign Treasury Engine: Full Build Complete ==="
	@echo "WASM modules: $(WASM_MODULES)"
	@echo "Native library: $(LIBRARY)"
	@echo "Run 'make test' to verify baseline"
