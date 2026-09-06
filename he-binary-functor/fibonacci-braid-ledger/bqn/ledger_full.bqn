# ledger.bqn — Ledger as arrays + Fibonacci → Braid mapping + State transition
# Structure-of-Arrays: homogeneous, cache-aligned, assembly-traceable

MaxIdx  ← 92
MaxWord ← 256
Strands ← 8
GenMax  ← 7
StateDim← Strands

BraidLen ← { 1 + 8 | 𝕩 }

BraidFromFib ← {
  𝕊 n:
    v ← ¯1⊑ FibArr n
    l ← 1+8|n
    j ← ↕l
    mags  ← 1 + 7 | v + j×13 + n×7
    signs ← 1 - 2× 2 | v + j + n
    signs × mags
}

BraidFromFibTacit ← ( (1-2×2|⊣+↕∘BraidLen) × (1+7|⊣+13×↕∘BraidLen+7×⊣) )˜ ¯1⊑∘FibArr

EmptyLedger ← {
  idxs: ⟨⟩
  vals: ⟨⟩
  words: ⟨⟩
  red: ⟨⟩
  states: (0‿StateDim⥊0)
  seals: ⟨⟩
}

InitState ← StateDim⥊0

WordContrib ← {
  𝕊 w:
    c ← (GenMax)⥊0
    {
      i ← (|𝕩)-1
      c i⊑↩ (i⊑c) + ×𝕩
    }¨ w
    c∾0
}

Transition ← {
  s 𝕊 w:
    s + WordContrib w
}

BatchStates ← {
  𝕊 words:
    contribs ← WordContrib¨ words
    +` ⟨InitState⟩ ∾ contribs
}

Seal ← {
  idx 𝕊 (val‿word‿state):
    h ← idx × 1000003
    h ↩ h + val
    h ↩ h + +´ word×(↕≠word)
    h ↩ h + +´ state×(1+↕≠state)
    h
}

SealLedger ← {
  𝕊 ledger:
    { 𝕩 Seal (𝕨⊑ledger.vals)‿(𝕩⊑ledger.words)‿(𝕨⊏ledger.states) }¨ ledger.idxs
}

InvLedger ← {
  𝕊 L:
    (∧´ (≠¨ L.words) ≤ MaxWord)
    ∧ (∧´ ValidWord¨ L.words)
    ∧ (∧´ (L.idxs < MaxIdx))
    ∧ (≠L.idxs) ≡ (≠L.words)
}

Entry ← {
  𝕊 n:
    v ← ¯1⊑ FibArr n
    w ← BraidFromFib n
    r ← Reduce w
    s ← InitState Transition w
    seal ← n Seal v‿w‿s
    ⟨n,v,w,r,s,seal⟩
}
