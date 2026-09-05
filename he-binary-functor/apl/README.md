# apl

**APL Braid Interpreter** — Recursive blob execution engine with opcode-based braid operations, evidence-gated verification, and cryptographic LEDGER_STATE locking.

## Files

| File | Description |
|------|-------------|
| `BRAID_INTERPRETER.apl` | Core recursive blob exec, ApplyOp, ExecBraid, Contract |
| `VECTORIZED_OPS.apl` | Opcode encoding (0-9), verification registry, B_blob |
| `OPCODES_V1.apl` | Full opcode set, Braid A01 encoding, LEDGER_STATE |
| `EVIDENCE_GATES.apl` | 5 verification gates (OS, Vacuum, Gap, Corr, Confinement) |
| `EXEC_INTERPRETER.apl` | Full Exec with evidence, Contract, Braid A01, LEDGER_STATE |

## Opcode Encoding

| Opcode | Mnemonic | Operands | Description |
|--------|----------|----------|-------------|
| 0 | HALT | — | Terminate successfully |
| 1 | ADD | x | state ← state + x |
| 2 | MUL | x | state ← state × x |
| 3 | RECURSE | n, subprogram | Execute subprogram |
| 4 | CONTRACT | — | Taylor contraction on state |
| 9 | VERIFY | check_id | Run evidence gate |

## Braid A01 Encoding

```
σ₁  = 1 3          (QFT existence)
σ₂  = 2 2          (gauge invariance)
σ₃⁻¹ = 9 0         (OS consistency check, id=0)
σ₄  = 3 3 1 2 0    (reconstruction)
σ₅  = 1 5          (Hamiltonian existence)
σ₆⁻¹ = 9 1         (vacuum check, id=1)
σ₇  = 2 3          (spectral positivity)
σ₈  = 4            (strict mass gap)
σ₉⁻¹ = 9 2         (correlation decay, id=2)
σ₁₀ = 3 2 1 4      (confinement implication)
```

## Evidence Gates (5)

| Gate | Check ID | Verification |
|------|----------|--------------|
| OS_Gate | 0 | 5 boolean flags or proof hash |
| Vacuum_Gate | 1 | Exists flag or zero-mode norm |
| Gap_Check | 3 | Δ > 0, no eigenvalues in (0,Δ) |
| CorrDecay_Gate | 2 | Exponential decay rate ≥ 0.01 |
| Confinement_Gate | 4 | Sigma ≥ 1e-3 |

## LEDGER_STATE

```
LEDGER_STATE ← 'LOCKED'
:If success = 1
    LEDGER_STATE ← 'UNLOCKED'
:EndIf
```

## Execution

```bash
# Run in Dyalog APL or GNU APL
]load BRAID_INTERPRETER.apl
]load EXEC_INTERPRETER.apl

# Execute
initState ← 10 8 6 4 2
state success ← Exec initState (B_blob 0 evidence)
```

## Key Features

- **Recursive subprogram execution** (opcode 3)
- **Taylor-like contraction** (opcode 4, r=0.5)
- **Evidence-gated verification** (opcode 9)
- **Proof hash or numeric proxy** fallback
- **LEDGER_STATE** unlocks only on full success
- **Taylor contraction**: r × a ÷ (1+⍳≢a), r=0.5