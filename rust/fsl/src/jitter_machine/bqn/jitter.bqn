# Recursive Jitter Machine — BQN specification (readable as BQN)
# No host I/O. Pure array transforms.

# Kernel header indices
magic‿ver‿n‿depth‿maxdepth‿seed‿pc‿flags ← ↕8

# Deterministic LCG step
LCG ← { (1664525×𝕩) + 1013904223 }

# Jitter one cell: xor high bits of seed
Jitter ← { s‿v ← 𝕩 ⋄ ⟨LCG s, v≠s×2⋆¯16⟩ }

# Assertion fusion: ∧/ over result vector
Fuse ← ∧´

# Recursive step shape (conceptual):
# state ← state Step code
# depth bounded by maxdepth
# flags accumulate FAIL / FUSED_OK / HALT

# Example pure array assertion fusion
AssertEq ← { 𝕨=𝕩 }
FuseAsserts ← { ∧´ 𝕨 AssertEq¨ 𝕩 }

# Example:
# left ← 1‿2‿3
# right ← 1‿2‿3
# FuseAsserts left right # → 1
# FuseAsserts left 1‿2‿0 # → 0
