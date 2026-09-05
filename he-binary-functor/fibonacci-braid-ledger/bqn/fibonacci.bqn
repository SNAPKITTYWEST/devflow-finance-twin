# fibonacci.bqn — Bounded Fibonacci array layer
# Dense array-oriented construction. No imperative loops.

MAX_FIB ← 90
WIDTH ← 64
EMPTY ← ⟨⟩

# Core: iterative scan via reverse-add
FibArr ← {
  n ← 𝕩
  n < 0 ? ! "negative index"
  n > MAX_FIB ? ! "index exceeds MAX_FIB"
  n = 0 ? ⟨0⟩
  n = 1 ? 0‿1
  ⊑¨ (+`⌽)⍟(n-1) ⟨0‿1⟩
}

Fib ← { ⊑⌽ FibArr 𝕩 }

FibSafe ← {
  n ← 𝕩
  (n < 0) ∨ (n > MAX_FIB) ? 0
  Fib n
}

Idx ← ↕∘(1+⊢)

IsFib ← {
  v ← 𝕩
  v < 0 ? 0
  a ← FibArr MAX_FIB
  v ∊ a
}

FibPref ← { (1+𝕩) ↑ FibArr MAX_FIB }

FibEmpty ← { 𝕩 ≤ 0 ? EMPTY ; FibArr 𝕩 }
