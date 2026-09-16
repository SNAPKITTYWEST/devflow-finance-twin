# Decoder-only Transformer in pure BQN (CBQN)
# Lines: ~185
# Functions: MatMul, Transpose, Softmax, SoftmaxJac, LayerNorm, GelU,
# Linear, LinearJac, SingleHeadAttn, MultiHeadAttn,
# MLP, TransformerBlock, Embed, PosEmbed, Unembed,
# DecoderModel, FiniteDiffJac, SGDStep, RunDemo

# ─── Utils ───────────────────────────────────────────────────────────────
MatMul ← { 𝕨 +˝∘×⎉1‿∞ 𝕩 } # (m×k) MatMul (k×n) → m×n
Transpose ← ⍉ # rank-2 transpose
•Show ¨ "MatMul shape"‿(≢ 3‿4 MatMul 4‿5⥊π)

# Stable Softmax over last axis
Softmax ← {
  m ← ⌈´˘ 𝕩
  e ← ⋆ 𝕩 - m
  e ÷˘ +´˘ e
}

# Softmax Jacobian: for vector v, Jac is diag(s) - s ⋆⊗ s (s=softmax v)
# Returns ⟨out, jac⟩ namespace-like 2-array
SoftmaxJac ← {
  s ← Softmax 𝕩
  outer ← s ⋆⌜ s
  jac ← (s × =⌜˜ ↕≠s) - outer # diag(s) - outer
  s‿jac
}

# LayerNorm over last axis (affine free for simplicity; scale/bias can be added)
LayerNorm ← {
  μ ← (+´÷≠)˘ 𝕩
  σ ← √ (1e¯5 + (+´÷≠)˘ ×˜ 𝕩-μ)
  (𝕩 - μ) ÷ σ
}

# ─── Activations ─────────────────────────────────────────────────────────
# GELU approximation
GelU ← {
  0.5 × 𝕩 × 1 + •math.Tanh 0.79788456 × 𝕩 + 0.044715 × 𝕩⋆3
}

# ─── Linear + Analytic Jacobian ──────────────────────────────────────────
# Linear: y = x MatMul W + b (b optional; here bias-free for clarity)
# Jac of Linear w.r.t. input: simply Wᵀ (broadcast)
Linear ← { 𝕨 MatMul 𝕩 } # W Linear X (W is d_out × d_in, X is … × d_in)

# Analytic Jacobian for Linear (w.r.t. input). Returns ⟨out, jac⟩
# For matrix W (out×in) applied to vector, Jac = Wᵀ
LinearJac ← {
  W ← 𝕨
  x ← 𝕩
  out ← W MatMul x
  jac ← ⍉ W # ∂(Wx)/∂x = Wᵀ
  out‿jac
}

# ─── Attention ───────────────────────────────────────────────────────────
# Causal mask: lower-triangular boolean (1 = keep, 0 = mask)
CausalMask ← { ⥊˘ ≥⌜˜ ↕ 𝕩 }

# Single-head attention (scaled dot-product + causal)
# Q,K,V : seq × d_head
SingleHeadAttn ← {
  Q‿K‿V ← 𝕩
  d ← 1⊑≢ Q
  scores ← (Q MatMul ⍉ K) ÷ √d
  mask ← CausalMask ≠Q
  scores ↩ scores + ¯1e9 × ¬ mask # large negative for masked positions
  attn ← Softmax scores
  attn MatMul V
}

# Multi-head: project, split heads, attend, concat, project out
# Wq,Wk,Wv,Wo : d_model × d_model (or d_model × (nHeads·d_head))
MultiHeadAttn ← {
  Wq‿Wk‿Wv‿Wo ← 𝕨
  X ← 𝕩 # seq × d_model
  nH ← 4 ⋄ dH ← 16 # hard-coded for toy (nHeads=4, d_model=64)
  Q ← X MatMul Wq
  K ← X MatMul Wk
  V ← X MatMul Wv
  # reshape to seq × nH × dH then transpose to nH × seq × dH
  split ← { ⍉ nH‿∘‿dH ⥊ 𝕩 }
  Qh ← split Q ⋄ Kh ← split K ⋄ Vh ← split V
  # attend per head
  Oh ← { SingleHeadAttn ⟨𝕨, 𝕩, 𝕗⟩ }¨˝ Qh‿Kh‿Vh
  # concat heads: nH × seq × dH → seq × (nH·dH)
  O ← ⥊˘ ⍉ Oh
  O MatMul Wo
}

# ─── MLP ─────────────────────────────────────────────────────────────────
MLP ← {
  W1‿W2 ← 𝕨
  h ← GelU W1 Linear 𝕩
  W2 Linear h
}

# ─── Transformer Block ───────────────────────────────────────────────────
# [Attn + res + LN] then [MLP + res + LN]
TransformerBlock ← {
  Wq‿Wk‿Wv‿Wo‿W1‿W2 ← 𝕨
  X ← 𝕩
  a ← MultiHeadAttn ⟨Wq,Wk,Wv,Wo⟩ X
  X ↩ LayerNorm X + a
  m ← MLP ⟨W1,W2⟩ X
  LayerNorm X + m
}

# ─── Embedding / Positional / Unembed ────────────────────────────────────
Embed ← { 𝕨 ⊏˜ 𝕩 } # table ⊏ tokens
PosEmbed ← { 𝕨 ⊏˜ ↕ ≠ 𝕩 } # learned pos table + input (broadcast add later)
Unembed ← { 𝕨 MatMul ⍉ 𝕩 } # (vocab × d) Unembed (seq × d) → seq × vocab

# ─── Full Decoder Model ──────────────────────────────────────────────────
# params: ⟨Emb, Pos, blocks…, finalLN scale (identity), Unemb⟩
# For toy we keep two blocks with their own weights
DecoderModel ← {
  Emb‿Pos‿B1‿B2‿Unemb ← 𝕨
  toks ← 𝕩 # ⟨seq⟩ of ints
  X ← (Emb Embed toks) + (Pos PosEmbed toks)
  X ↩ B1 TransformerBlock X
  X ↩ B2 TransformerBlock X
  X ↩ LayerNorm X
  Unemb Unembed X # logits: seq × vocab
}

# ─── Finite-difference Jacobian (validation) ─────────────────────────────
# FiniteDiffJac f x → approximate Jac of f at vector x
# Uses central differences, eps=1e-5
FiniteDiffJac ← {
  f ← 𝕨 ⋄ x ← 𝕩
  n ← ≠x
  eps ← 1e¯5
  { # column j
    e ← eps × j=↕n
    (f x+e) - (f x-e)
  }¨ ↕n
  ÷ 2×eps
}

# ─── Tiny SGD step (prove gradient flow) ─────────────────────────────────
# One Linear layer: loss = ½‖y - target‖², update W with SGD
SGDStep ← {
  W‿x‿target‿lr ← 𝕨
  y ← W MatMul x
  # analytic grad w.r.t W: (y-target) ⋆⊗ x
  gW ← (y - target) ⋆⌜ x
  W - lr × gW
}

# ─── Demo / Tests ────────────────────────────────────────────────────────
RunDemo ← {
  •Show "=== Softmax Jacobian finite-diff check (4-vector) ==="
  v ← 0.2‿¯0.5‿1.1‿¯0.3
  s‿Jana ← SoftmaxJac v
  Jfd ← Softmax FiniteDiffJac v
  •Show "Analytic Jac:"
  •Show Jana
  •Show "Finite-diff Jac:"
  •Show Jfd
  maxAbsErr ← ⌈´|⥊ Jana - Jfd
  •Show "Max abs error:"‿maxAbsErr
  •Show (maxAbsErr < 1e¯3)⊑⟨"FAIL","PASS"⟩

  •Show "=== Linear Jacobian (tiny) ==="
  W ← 3‿2⥊ 0.1‿0.2‿¯0.3‿0.4‿0.5‿¯0.1
  x ← 1.0‿¯0.5
  y‿Jlin ← W LinearJac x
  •Show "Linear out:"‿y
  •Show "Linear Jac (should be Wᵀ):"‿Jlin

  •Show "=== SGD step on Linear ==="
  target ← 0.5‿¯0.2‿0.1
  Wnew ← SGDStep ⟨W, x, target, 0.1⟩
  •Show "W after one SGD step:"
  •Show Wnew

  •Show "=== Full forward pass (toy model) ==="
  # Random-ish but deterministic small weights for reproducibility
  d ← 64 ⋄ vsz ← 512 ⋄ seq ← 8 # use seq=8 for speed in demo
  Emb ← vsz‿d ⥊ •math.Sin ↕vsz×d
  Pos ← seq‿d ⥊ •math.Cos ↕seq×d
  # One block weights (shared shape for both blocks)
  MkW ← { 𝕩‿𝕩 ⥊ •math.Sin ↕ 𝕩⋆2 }
  Wq ← MkW d ⋄ Wk ← MkW d ⋄ Wv ← MkW d ⋄ Wo ← MkW d
  W1 ← 128‿d ⥊ •math.Cos ↕128×d
  W2 ← d‿128 ⥊ •math.Sin ↕d×128
  B1 ← ⟨Wq,Wk,Wv,Wo,W1,W2⟩
  B2 ← ⟨Wq,Wk,Wv,Wo,W1,W2⟩ # reuse for toy
  Unemb ← vsz‿d ⥊ •math.Sin ↕vsz×d
  params ← ⟨Emb, Pos, B1, B2, Unemb⟩
  toks ← seq ⥊ 3‿7‿1‿0‿4‿2‿5‿6
  logits ← params DecoderModel toks
  •Show "Logits shape (expect ⟨seq, vocab⟩):"‿(≢logits)
  •Show "First 3 logits of first token:"‿(3↑⊏logits)
  "Demo complete"
}
