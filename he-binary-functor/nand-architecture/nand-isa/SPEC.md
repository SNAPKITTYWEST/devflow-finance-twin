# NAND ISA Specification

## 1. Primitive

```
NAND(a, b) ≜ ¬(a ∧ b)
```

Truth table (only primitive):

| a | b | NAND |
|---|---|------|
| 0 | 0 | 1 |
| 0 | 1 | 1 |
| 1 | 0 | 1 |
| 1 | 1 | 0 |

### Derived operators (all reduced to NAND)

```
NOT(x)   = NAND(x, x)
AND(a,b) = NOT(NAND(a,b)) = NAND(NAND(a,b), NAND(a,b))
OR(a,b)  = NAND(NOT(a), NOT(b)) = NAND(NAND(a,a), NAND(b,b))
NOR(a,b) = NOT(OR(a,b))
XOR(a,b) = OR(AND(a,NOT(b)), AND(NOT(a),b))
MUX(s,a,b) = OR(AND(NOT(s),a), AND(s,b))
```

Every Boolean function of finite arity is expressible by a finite NAND circuit.

## 2. Instruction encoding

Fixed 16-bit instruction word.

```
15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
┌───────┬──────────┬──────────┬──────────┐
│  OP   │   DST    │    A     │    B     │
│ 4 bit │  4 bit   │  4 bit   │  4 bit   │
└───────┴──────────┴──────────┴──────────┘
```

- OP   : opcode (only 0x0 = NAND is defined; others trap)
- DST  : destination register r0–r15
- A    : source register or immediate flag
- B    : source register or immediate flag

### Opcode map

| OP | Mnemonic | Semantics                              |
|-----|----------|----------------------------------------|
| 0x0 | NAND     | R[DST] ← NAND(R[A], R[B])             |
| 0x1 | HALT     | stop execution                         |
| 0x2 | LOAD     | R[DST] ← MEM[R[A] + imm4(B)]          |
| 0x3 | STORE    | MEM[R[A] + imm4(B)] ← R[DST]          |
| 0x4 | LDI      | R[DST] ← zero-extend(imm8 = A∥B)      |
| 0x5 | JMP      | PC ← R[A]                             |
| 0x6 | JZ       | if R[DST]==0 then PC ← R[A]           |
| 0x7–F| —       | INVALID → trap                         |

Immediate encoding for LDI: the 8-bit value is formed by concatenating the 4-bit A and B fields.

## 3. Machine state

```
Registers : R[0..15] each 32-bit (R0 hard-wired 0 on write)
Memory    : M[0..65535] 16-bit cells (byte-addressable view also supported)
PC        : 16-bit program counter
IR        : 16-bit instruction register
Halted    : bool
Trap      : bool (set on invalid opcode / out-of-bounds)
```

### Execution cycle (deterministic)

```
1. IR ← M[PC]
2. PC ← PC + 1
3. decode IR
4. if OP invalid → Trap ← true; Halted ← true
5. execute according to OP
6. if HALT → Halted ← true
```

Out-of-range memory access sets Trap and leaves the target unchanged.

## 4. Invariants

- R[0] is always 0 after any write.
- PC and all addresses are taken modulo 2^16 (wrap) *or* trap (implementation chooses trap).
- Every instruction has a unique 16-bit encoding; no overlapping bit patterns for defined ops.
- Execution is completely determined by the initial (PC, R, M) triple.
