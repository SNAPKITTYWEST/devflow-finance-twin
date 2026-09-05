# braid.bqn – Braid Word Algebra & Reduction Primitives
MaxStrands ← 8
MaxWordLen ← 16

# Valid generator: [-7..-1, 1..7] excluding 0
ValidGen ← { (1 ≤ |𝕩) ∧ (|𝕩 < MaxStrands) }

# Validate entire braid word
ValidBraidWord ← { (0 ≤ ≠𝕩) ∧ (≠𝕩 ≤ MaxWordLen) ∧ ∧´ ValidGen¨ 𝕩 }

# Braid word inversion: reverse and negate
InverseBraid ← - ⌽ 𝕩

# Local cancellation: remove adjacent inverse pairs
ReduceStep ← {
  pairs ← (↕ ≠𝕩 - 1) ⊔ ⟨⟩
  found ← / (¯1 ≠ (𝕩 ⊏˜ ↕ ≠𝕩-1) +` 𝕩 ⊏˜ 1+ ↕ ≠𝕩-1)
  (0 < ≠found) ? (𝕩 ∾˜ ⟨⟩) ; 𝕩
}

# Full reduction: fixed point
ReduceBraid ← { 𝕩 } # placeholder for iterative reduction

# FNV-1a hash of braid word
FnvPrime ← 16777619
FnvOffset ← 2166136261

BraidHash ← {
  bytes ← (≠𝕩) ∾ (𝕩 + 128)
  FnvOffset { ((𝕨 ≠ 𝕩) × FnvPrime) }´ bytes
}

# Deterministic Fibonacci → Braid mapping
BraidFromFibonacci ← {
  fib_val ← FibLookup 𝕩
  bits ← fib_val
  gens ← ⟨⟩
  loop ← {
    (bits = 0) ∨ (≠gens ≥ 8) ? gens ; (
      pair ← bits ⋈ 7
      bits ← pair ÷ 8
      pair = 0 ? 𝕊 bits ⋈ gens
      : pair ≤ 3 ? 𝕊 (bits ⋈ gens∾pair)
      : 𝕊 (bits ⋈ gens∾(pair-6))
    )
  }
  loop bits ⋈ gens
}
