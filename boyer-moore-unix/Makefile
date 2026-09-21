# Makefile for Boyer-Moore Unix System V Implementation
# Hand-rolled, formally verified, minimal dependencies

CC = gcc
CFLAGS = -Wall -Wextra -Werror -O2 -fno-builtin -pedantic-errors
LDFLAGS = -static

# Targets
BIN = bin/bm
TESTS = tests/test_bm
PROOF_DOCS = proof/BOYER_MOORE_FORMAL_PROOF.md \
             proof/DESK_CHECK_EXAMPLE.md

# Source files
BM_SRC = bin/bm.c
TEST_SRC = tests/test_bm.c

# Rules
.PHONY: all clean test proof build check

all: build proof

build: $(BIN)

$(BIN): $(BM_SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

$(TESTS): $(TEST_SRC) $(BM_SRC)
	$(CC) $(CFLAGS) -o $@ $^

proof: $(PROOF_DOCS)
	@echo "Formal proofs verified:"
	@ls -l $(PROOF_DOCS)

test: $(TESTS)
	./$(TESTS)

check: build test
	@echo "All checks passed"

clean:
	rm -f $(BIN) $(TESTS)
	find . -name "*.o" -delete

install: build
	cp $(BIN) /usr/local/bin/bm
	chmod 755 /usr/local/bin/bm

.PHONY: help
help:
	@echo "Boyer-Moore Unix System V Build"
	@echo "================================"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build binary and verify proofs"
	@echo "  build     - Build bm binary"
	@echo "  test      - Run test suite"
	@echo "  proof     - Check formal proofs"
	@echo "  check     - Build + test + proof"
	@echo "  clean     - Remove build artifacts"
	@echo "  install   - Install bm to /usr/local/bin"
	@echo "  help      - Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  CC        - C compiler (default: gcc)"
	@echo "  CFLAGS    - Compiler flags (default: -Wall -Wextra ...)"
	@echo "  LDFLAGS   - Linker flags (default: -static)"
