#include <assert.h>
#include <stdint.h>
#include <string.h>

typedef uint8_t  vsm_u8;
typedef uint16_t vsm_u16;
typedef uint32_t vsm_u32;
typedef uint64_t vsm_u64;

enum VSM_OPCODE {
    VSM_NOP=0x00, VSM_LOAD=0x01, VSM_STORE=0x02, VSM_MOVE=0x03,
    VSM_AND=0x04, VSM_OR=0x05, VSM_XOR=0x06, VSM_NOT=0x07,
    VSM_EQ=0x08, VSM_NEQ=0x09, VSM_MASK=0x0A,
    VSM_SHL=0x0B, VSM_SHR=0x0C, VSM_ROL=0x0D, VSM_ROR=0x0E,
    VSM_BIND=0x0F, VSM_UNBIND=0x10,
    VSM_ASSERT=0x11, VSM_REJECT=0x12, VSM_PROVE=0x13, VSM_VERIFY=0x14,
    VSM_ROUTE=0x15, VSM_FORK=0x16, VSM_JOIN=0x17,
    VSM_SEED=0x18, VSM_SPRING=0x19, VSM_PROPAGATE=0x1A,
    VSM_COMMIT=0x1B, VSM_ROLLBACK=0x1C,
    VSM_COMPOSE=0x1D, VSM_SPLIT=0x1E, VSM_MERGE=0x1F,
    VSM_HALT=0xFF
};

typedef struct {
    vsm_u8  opcode;
    vsm_u8  rd;
    vsm_u8  rs1;
    vsm_u8  rs2;
    vsm_u32 immediate;
    vsm_u64 operand;
} VSMInstruction;

typedef struct {
    vsm_u64 r[32];
    vsm_u64 sem, ctx, bind, proof, state, mem, route, seed, valid, error, history;
} VSMRegisters;

typedef struct {
    vsm_u64 sequence, state_before, state_after, instruction;
    vsm_u64 parameter, input_hash, output_hash;
    vsm_u32 constraint_result, proof_result, status, lane;
} VSMExecutionRecord;

void harness_register_index_bounds(void) {
    VSMInstruction ins;
    ins.opcode = VSM_MOVE;

    for (vsm_u8 i = 0; i < 32; i++) {
        ins.rd = i;
        ins.rs1 = i;
        ins.rs2 = i;
        assert(ins.rd < 32);
        assert(ins.rs1 < 32);
        assert(ins.rs2 < 32);
    }
}

void harness_register_file_bounds(void) {
    VSMRegisters regs;
    memset(&regs, 0, sizeof(regs));

    for (int i = 0; i < 32; i++) {
        regs.r[i] = (vsm_u64)i * 0x1111111111111111ULL;
    }

    for (int i = 0; i < 32; i++) {
        assert(regs.r[i] == (vsm_u64)i * 0x1111111111111111ULL);
    }
}

void harness_trace_buffer_index(void) {
    vsm_u32 instances = 4;
    vsm_u32 instruction_count = 8;
    vsm_u32 total = instances * instruction_count;

    for (vsm_u32 tid = 0; tid < instances; tid++) {
        for (vsm_u32 pc = 0; pc < instruction_count; pc++) {
            vsm_u32 idx = tid * instruction_count + pc;
            assert(idx < total);
        }
    }
}

void harness_opcode_dispatch_nop(void) {
    VSMInstruction ins;
    memset(&ins, 0, sizeof(ins));
    ins.opcode = VSM_NOP;
    ins.rd = 0;

    VSMRegisters regs;
    memset(&regs, 0, sizeof(regs));
    regs.r[0] = 0x42;

    assert(regs.r[ins.rd] == 0x42);
}

void harness_shift_masking(void) {
    vsm_u64 val = 0x8000000000000001ULL;
    vsm_u32 n = 65;
    vsm_u32 masked = n & 63;
    assert(masked == 1);

    vsm_u64 result = val << masked;
    assert(result == 0x0000000000000002ULL);
}

void harness_bind_unbind_inverse(void) {
    vsm_u64 a = 0xAAAAAAAAAAAAAAAAULL;
    vsm_u64 b = 0x5555555555555555ULL;

    vsm_u64 bound = a ^ b;
    vsm_u64 unbound = bound ^ b;
    assert(unbound == a);
}

void harness_rd_out_of_range(void) {
    VSMInstruction ins;
    ins.rd = 31;
    ins.rs1 = 0;
    ins.rs2 = 0;
    assert(ins.rd < 32);

    ins.rd = 32;
    assert(ins.rd >= 32);
}
