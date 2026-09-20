#!/usr/bin/env bash
set -euo pipefail

CBMC_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CBMC_DIR/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if ! command -v cbmc &>/dev/null; then
    echo -e "${RED}ERROR: cbmc not found. Install CBMC 6.0+ first.${NC}"
    exit 1
fi

echo "CBMC Bounded Model Checking — devflow-finance-twin"
echo "==================================================="
echo "CBMC version: $(cbmc --version 2>&1 | head -1)"
echo ""

run_harness() {
    local name="$1"
    local harness="$2"
    local source="$3"
    local includes="$4"
    local unwind="${5:-10}"
    local functions="$6"

    if [ ! -f "$harness" ]; then
        echo -e "  ${YELLOW}SKIP${NC} $name — harness not found"
        ((SKIP++))
        return
    fi

    if [ -n "$source" ] && [ ! -f "$source" ]; then
        echo -e "  ${YELLOW}SKIP${NC} $name — source not found: $source"
        ((SKIP++))
        return
    fi

    echo -n "  $name ... "

    local cmd="cbmc"
    cmd="$cmd $harness"
    [ -n "$source" ] && cmd="$cmd $source"
    [ -n "$includes" ] && cmd="$cmd $includes"
    cmd="$cmd --bounds-check --pointer-check --signed-overflow-check"
    cmd="$cmd --unwind $unwind --unwinding-assertions"

    IFS=',' read -ra FUNCS <<< "$functions"
    local all_pass=true
    for func in "${FUNCS[@]}"; do
        func=$(echo "$func" | xargs)
        if eval "$cmd --function $func" &>/dev/null 2>&1; then
            :
        else
            echo ""
            echo -e "    ${RED}FAIL${NC} $func"
            all_pass=false
        fi
    done

    if $all_pass; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        ((FAIL++))
    fi
}

echo "[1/11] WORM Commit Block"
run_harness "worm_commit" \
    "$CBMC_DIR/harness_worm_commit.c" \
    "" \
    "" \
    10 \
    "harness_hash_output_is_hex,harness_magic_preserved,harness_record_count_fits,harness_hash_deterministic,harness_different_input_different_hash"

echo "[2/11] Fibonacci Braid Ledger (fbLedger)"
run_harness "fb_ledger" \
    "$CBMC_DIR/harness_fb_ledger.c" \
    "$ROOT/he-binary-functor/fibonacci-braid-ledger/fbLedger.c" \
    "-I $ROOT/he-binary-functor/fibonacci-braid-ledger" \
    20 \
    "harness_count_bounded,harness_append_rejects_full,harness_fib_rejects_overflow,harness_word_len_bounded,harness_strands_bounded"

echo "[3/11] Fibraid Ledger"
run_harness "fibraid" \
    "$CBMC_DIR/harness_fibraid.c" \
    "$ROOT/he-binary-functor/fibonacci-braid-ledger/fibraid.c" \
    "-I $ROOT/he-binary-functor/fibonacci-braid-ledger" \
    35 \
    "harness_nent_bounded,harness_gen_magnitude,harness_word_len_capped,harness_chain_linkage,harness_fib_rejects_large_n"

echo "[4/11] Ledger (compact)"
run_harness "ledger" \
    "$CBMC_DIR/harness_ledger.c" \
    "$ROOT/he-binary-functor/fibonacci-braid-ledger/ledger.c" \
    "-I $ROOT/he-binary-functor/fibonacci-braid-ledger" \
    35 \
    "harness_nent_bounded,harness_gen_range,harness_verify_empty,harness_sequential_n,harness_word_len"

echo "[5/11] Word operations"
run_harness "word" \
    "$CBMC_DIR/harness_word.c" \
    "$ROOT/he-binary-functor/fibonacci-braid-ledger/word.c" \
    "-I $ROOT/he-binary-functor/fibonacci-braid-ledger" \
    10 \
    "harness_gen_ok_bounds,harness_reduce_shrinks,harness_reduce_empty,harness_word_ok_rejects_zero,harness_word_ok_accepts_valid,harness_reduce_cancels_inverses"

echo "[6/11] Call Core (SIP supervisor)"
run_harness "call_core" \
    "$CBMC_DIR/harness_call_core.c" \
    "$ROOT/he-binary-functor/c-core/call_core.c" \
    "-I $ROOT/he-binary-functor/c-core" \
    35 \
    "harness_slot_bounds,harness_active_count,harness_restarts_capped,harness_sip_starts_init"

echo "[7/11] Worker state machine"
run_harness "worker" \
    "$CBMC_DIR/harness_worker.c" \
    "$ROOT/he-binary-functor/kernel/worker.c" \
    "-I $ROOT/he-binary-functor/kernel" \
    15 \
    "harness_err_count_bounded,harness_fault_phase,harness_epoch_monotonic,harness_reset_recovers,harness_nop_idempotent"

echo "[8/11] Frama-C Memory model"
run_harness "frama_memory" \
    "$CBMC_DIR/harness_frama_memory.c" \
    "$ROOT/formal/tlm-jxcl/frama-c/memory.c" \
    "-I $ROOT/formal/tlm-jxcl/frama-c" \
    10 \
    "harness_read_write_roundtrip,harness_fetch_in_code_region,harness_overlaps_logic,harness_no_code_overlap_write,harness_alignment"

echo "[9/11] Frama-C Binary parser"
run_harness "frama_parser" \
    "$CBMC_DIR/harness_frama_parser.c" \
    "$ROOT/formal/tlm-jxcl/frama-c/binary_parser.c" \
    "-I $ROOT/formal/tlm-jxcl/frama-c" \
    10 \
    "harness_valid_header_parses,harness_bad_magic_rejected,harness_bad_version_rejected,harness_too_short_rejected,harness_section_bounds_valid,harness_entry_in_code"

echo "[10/11] Frama-C Execution stack"
run_harness "frama_stack" \
    "$CBMC_DIR/harness_frama_stack.c" \
    "$ROOT/formal/tlm-jxcl/frama-c/execution_stack.c" \
    "-I $ROOT/formal/tlm-jxcl/frama-c" \
    10 \
    "harness_push_pop_inverse,harness_sp_alignment,harness_multiple_push_pop,harness_call_pushes_return,harness_addr_of_wrapping"

echo "[11/11] CUDA VSM2500 (host-side model)"
run_harness "cuda_vsm" \
    "$CBMC_DIR/harness_cuda_vsm.c" \
    "" \
    "" \
    35 \
    "harness_register_index_bounds,harness_register_file_bounds,harness_trace_buffer_index,harness_opcode_dispatch_nop,harness_shift_masking,harness_bind_unbind_inverse,harness_rd_out_of_range"

echo ""
echo "==================================================="
echo -e "Results: ${GREEN}${PASS} PASS${NC}  ${RED}${FAIL} FAIL${NC}  ${YELLOW}${SKIP} SKIP${NC}"
echo "Total harnesses: $((PASS + FAIL + SKIP))"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
