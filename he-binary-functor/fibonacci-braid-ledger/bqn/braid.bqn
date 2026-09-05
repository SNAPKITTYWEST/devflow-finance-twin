# braid.bqn — Braid word array algebra
# Generators: positive integers σᵢ, negative = inverse σᵢ⁻¹

STRANDS ← 5
MAX_GEN ← STRANDS-1
MAX_WORD ← 64
EMPTY_W ← ⟨⟩

ValidGen ← { (1 ≤ |𝕩) ∧ (|𝕩 ≤ MAX_GEN) }
ValidWord ← {
  w ← 𝕩
  (≠w ≤ MAX_WORD) ∧ (∧´ ValidGen¨ w)
}

Inv ← -∘⌽

Append ← {
  a 𝕨
  w 𝕩
  r ← a ∾ w
  ≠r ≤ MAX_WORD ? r ; ! "word length overflow"
}

# Local cancellation: remove adjacent inverse pairs
CancelStep ← {
  𝕨 ≡ ⟨⟩ ? ⟨𝕩⟩
  last ← ⊑⌽𝕨
  last = -𝕩 ? ¯1↓𝕨 ; 𝕨∾⟨𝕩⟩
}
Reduce ← { ⟨⟩ CancelStep´ 𝕩 }

Len ← ≠∘Reduce

StrandOk ← ValidWord

GenSeq ← {
  n ← 𝕩
  n ≤ 0 ? EMPTY_W
  n > MAX_WORD ? ! "genseq overflow"
  1 + (↕n) | MAX_GEN
}

InvInvId ← { 𝕨 ≡ Inv Inv 𝕨 }
