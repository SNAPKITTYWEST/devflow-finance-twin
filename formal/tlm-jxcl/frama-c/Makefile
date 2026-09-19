# TLM JXCL ISA — Frama-C / WP verification Makefile
#
# Requirements:
#   frama-c >= 26  (Frama-C 26 "Manganese")
#   Alt-Ergo >= 2.4
#   Z3 >= 4.12  (optional but recommended as a second prover)
#
# Usage:
#   make verify-memory    # verify memory.c contracts
#   make verify-binary    # verify binary_parser.c contracts
#   make verify-stack     # verify execution_stack.c contracts
#   make verify-alu       # verify alu_contracts.h (lib-entry mode)
#   make verify-all       # run all four targets
#   make clean            # remove Frama-C result caches

FRAMA_C    = frama-c
CC         = gcc
CFLAGS     = -std=c11 -Wall -Wextra -pedantic -I.

# WP flags:
#   -wp             enable WeakestPrecondition plugin
#   -wp-rte         inject run-time error guards (overflow, ptr validity, …)
#   -wp-prover      comma-separated list of back-end provers to try in order
#   -wp-timeout     per-goal timeout in seconds
#   -wp-par         number of parallel prover processes
WP_FLAGS   = -wp \
             -wp-rte \
             -wp-prover alt-ergo,z3 \
             -wp-timeout 30 \
             -wp-par 4

# Extra flags for GUI-free batch runs
BATCH_FLAGS = -no-unicode -kernel-warn-key annot:missing-spec=inactive

# --------------------------------------------------------------------------
# Per-translation-unit targets
# --------------------------------------------------------------------------

.PHONY: verify-memory verify-binary verify-stack verify-alu verify-all
.PHONY: typecheck-all clean help

verify-memory: memory.c memory.h
	$(FRAMA_C) $(WP_FLAGS) $(BATCH_FLAGS) \
	    -cpp-extra-args="-I." \
	    memory.c

verify-binary: binary_parser.c binary_parser.h
	$(FRAMA_C) $(WP_FLAGS) $(BATCH_FLAGS) \
	    -cpp-extra-args="-I." \
	    binary_parser.c

verify-stack: execution_stack.c execution_stack.h memory.h
	$(FRAMA_C) $(WP_FLAGS) $(BATCH_FLAGS) \
	    -cpp-extra-args="-I." \
	    memory.c execution_stack.c

# alu_contracts.h has declarations only; use -lib-entry so Frama-C does not
# require a main() and analyses each annotated declaration in isolation.
# A thin wrapper .c is generated on the fly to give Frama-C a translation unit.
verify-alu: alu_contracts.h
	printf '#include "alu_contracts.h"\n' > _alu_entry.c
	$(FRAMA_C) $(WP_FLAGS) $(BATCH_FLAGS) \
	    -lib-entry \
	    -cpp-extra-args="-I." \
	    _alu_entry.c
	$(RM) _alu_entry.c

verify-all: verify-memory verify-binary verify-stack verify-alu

# --------------------------------------------------------------------------
# Type-check all C sources with gcc (fast sanity check before running Frama-C)
# --------------------------------------------------------------------------

typecheck-all:
	$(CC) $(CFLAGS) -fsyntax-only memory.c
	$(CC) $(CFLAGS) -fsyntax-only binary_parser.c
	$(CC) $(CFLAGS) -fsyntax-only execution_stack.c
	$(CC) $(CFLAGS) \
	    -x c -fsyntax-only alu_contracts.h

# --------------------------------------------------------------------------
# Clean Frama-C result database and any generated files
# --------------------------------------------------------------------------

clean:
	$(RM) -rf frama_c_results/ .frama-c/ _alu_entry.c

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------

help:
	@echo "TLM JXCL ISA — Frama-C verification targets"
	@echo ""
	@echo "  make verify-memory    verify memory.c"
	@echo "  make verify-binary    verify binary_parser.c"
	@echo "  make verify-stack     verify execution_stack.c (links memory.c)"
	@echo "  make verify-alu       verify alu_contracts.h (lib-entry)"
	@echo "  make verify-all       run all four targets"
	@echo "  make typecheck-all    gcc -fsyntax-only on all sources"
	@echo "  make clean            remove Frama-C caches"
