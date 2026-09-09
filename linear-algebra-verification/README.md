# Formal Verification of Linear Algebra Identities

## Scope

Pure mathematical verification of:
- Outer product action
- Matrix-vector linearity
- Inner product expansion
- Threshold conditions
- Orthogonal projection properties

## Statements Verified

| ID | Statement | Status |
|----|-----------|--------|
| ALG-001 | (v ⊗ xᵀ)x = ‖x‖² · v | VERIFIED |
| ALG-002 | (W + ΔW)x = Wx + ΔWx | VERIFIED |
| ALG-003 | ⟨(W+ΔW)x,v⟩ = ⟨Wx,v⟩ + ⟨ΔWx,v⟩ | VERIFIED |
| ALG-004 | ⟨(W+ΔW)x,v⟩ - ⟨Wx,v⟩ = η·‖x‖²·‖v‖² | VERIFIED |
| THR-001 | η > (θ - ⟨Wx,v⟩)/(‖x‖²·‖v‖²) ⟹ threshold | VERIFIED |
| THR-002 | ∃ η > 0 achieving any finite threshold | VERIFIED |
| PROJ-001 | P² = P | VERIFIED |
| PROJ-002 | Pᵀ = P | VERIFIED |
| PROJ-003 | P(I-P) = 0 | VERIFIED |

## Building

```bash
cd lean && lake build
cd coq && make
cd isabelle && isabelle build -d . LinearAlgebra
```

## License

MIT
