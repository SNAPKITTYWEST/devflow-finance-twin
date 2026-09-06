# ledger.bqn — Fibonacci → Braid → State → Seal

MAX_IDX ← 90
MAX_STATE ← 256
SEAL_MOD ← 2⋆32

# Deterministic Fibonacci → Braid mapping
# g_k = 1 + (k mod (STRANDS-1))
# s_k = (-1)^k
# w_n = s_k * g_k for k = 0..min(F_n, MAX_WORD)-1
BraidFromFib ← {
  n ← 𝕩
  n < 0 ? ! "negative fib index"
  n > MAX_IDX ? ! "index overflow"
  f ← Fib n
  L ← f ⌊ MAX_WORD
  L = 0 ? EMPTY_W
  gs ← 1 + (↕L) | MAX_GEN
  ss ← ¯1 ⋆ ↕L
  ss × gs
}

InitState ← { ⟨0, 0, 0, 0, 0⟩ }

# Transition: State × Word → State
Transition ← {
  st 𝕨
  w 𝕩
  ¬ValidWord w ? ! "invalid word"
  idx ← 0⊑st
  new_idx ← idx + 1
  new_idx > MAX_IDX ? ! "state index overflow"
  wl ← ≠w
  rw ← Reduce w
  rl ← ≠rw
  ssum ← +´ |¨ w
  new_seal ← SEAL_MOD | (3⊑st) + ssum × Fib idx
  chk ← +´ rw
  new_chk ← (4⊑st) ≠ chk
  ⟨new_idx, wl, rl, new_seal, new_chk⟩
}

Entry ← {
  n ← 𝕩
  w ← BraidFromFib n
  r ← Reduce w
  st ← InitState Transition w
  st ↩ ⟨n⟩ ∾ 1↓st
  ⟨n, w, r, st, 3⊑st⟩
}

LedgerSOA ← {
  n ← 𝕩
  idxs ← ↕1+n
  ws ← BraidFromFib¨ idxs
  rs ← Reduce¨ ws
  sts ← (InitState Transition¨ ws)
  sts ↩ idxs ∾˘ 1↓˘ >sts
  seals ← 3⊑˘ >sts
  ⟨idxs, ws, rs, sts, seals⟩
}

SealOf ← { 3⊑ 3⊑ 𝕩 }
