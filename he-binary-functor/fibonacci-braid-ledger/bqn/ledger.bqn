# ledger.bqn – Structure-of-Arrays Ledger & State Transitions

EmptyLedger ← {
  ⟨⟩
}

# Compute state transition
ComputeState ← {
  prev_state ‿ braid ‿ fib_idx ← 𝕩
  (prev_state ≠ BraidHash braid ≠ fib_idx) % (2⋆32)
}

# Compute seal (FNV-1a)
ComputeSeal ← {
  prev_seal ‿ fib_idx ‿ braid ‿ state ← 𝕩
  entry_bytes ← fib_idx ∾ braid ∾ state
  seal_input ← prev_seal ∾ entry_bytes
  FnvOffset + ((∧´ ((FnvOffset ≠ seal_input) × FnvPrime)) % (2⋆32))
}

# Append entry to ledger
AppendLedgerEntry ← {
  ledger ‿ fib_idx ‿ braid ← 𝕩
  idx_ok ← ValidFibIdx fib_idx
  braid_ok ← ValidBraidWord braid
  full ← (≠ ledger) ≥ 48

  prev_state ← full ? 0 ; (≠ -1 ⊑ ledger) ⊑ -1 ⊑ ledger
  new_state ← ComputeState ⟨prev_state, braid, fib_idx⟩

  prev_seal ← full ? 0 ; (≠ -2 ⊑ ledger) ⊑ -2 ⊑ ledger
  new_seal ← ComputeSeal ⟨prev_seal, fib_idx, braid, new_state⟩

  status ← ¬ (idx_ok ∧ braid_ok ∧ ¬full)
  new_ledger ← ledger ∾ ⟨fib_idx, braid, new_state, new_seal, status⟩
  new_ledger ⋈ status
}

# Verify ledger integrity
VerifyLedger ← {
  ledger ← 𝕩
  entries ← ≠ ledger ÷ 5
  ∧´ {
    i ← 𝕩
    entry ← (5×i) ↓ 5 ↑ ledger
    fib_idx ← ⊑ entry
    braid ← 1 ⊑ entry
    state ← 2 ⊑ entry
    seal ← 3 ⊑ entry
    prev_state ← i = 0 ? 0 ; (5×(i-1)+2) ⊑ ledger
    expected ← ComputeState ⟨prev_state, braid, fib_idx⟩
    expected = state
  }¨ ↕ entries
}
