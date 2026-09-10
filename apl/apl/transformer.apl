⍝ Tiny Decoder-Only Transformer in Dyalog APL
⍝ Run in Dyalog: ]load transformer.apl
⍝ Config is tiny for readability. All arrays are 0-index friendly.

⍝ ── Hyperparams ──
vocab←512 ⋄ dModel←64 ⋄ nHeads←4 ⋄ dk←dModel÷nHeads
dFF←128 ⋄ seqLen←32 ⋄ eps←1e-5

⍝ ── Primitives ──
⍝ stable softmax for vector
softmaxVec←{e←*⍵-⌈/⍵ ⋄ e÷+/e}
⍝ row-wise softmax for matrix [seq, seq]
softmaxRows←softmaxVec⍤1

⍝ layerNorm per row: [n, d] -> [n, d]
lnVec←{m←(+/⍵)÷≢⍵ ⋄ v←(+/2*⍨⍵-m)÷≢⍵ ⋄ (⍵-m)÷√v+eps}
layerNorm←lnVec⍤1

⍝ gelu approx (tanh version)
gelu←{0.5×⍵×1+7○0.79788456×⍵+0.044715×⍵*3}

⍝ causal mask: 0 allowed, ¯1e9 future
causalMask←{n←⍵ ⋄ (n n⍴0)+¯1e9×n n⍴(⍳n)∘.<⍳n}
⍝ Note: (⍳n)∘.<⍳n gives strictly lower triangular 1s, we invert for causal

⍝ fix mask orientation for demo: lower-tri inclusive = allowed
causalMask←{(n n⍴0)+¯1e9×~(n n⍴(⍳⍵)∘.≤⍳⍵)}

⍝ ── Attention ──
⍝ Single head: Q K V are [seq, dk], returns [seq, dk]
attn1←{
  scores←⍺⍺.+.×⍉⍵⍵ ⍝ placeholder to keep tacit clear
  ⍵
}
⍝ explicit version:
⍝ Q K V as left,mid,right args via namespace - use dfn with 3 args via ⍺ ⍵ and global
singleHead←{
  ⍝ ⍵ is namespace with Q K V Mask
  scores←(⍵.Q)+.×⍉⍵.K
  scaled←scores÷√dk
  masked←scaled+⍵.mask
  w←softmaxRows masked
  w+.×⍵.V
}

⍝ Split heads: X [seq, dModel] -> [nHeads, seq, dk]
splitHeads←{nHeads (seqLen dk)⍴⍵}

⍝ mergeHeads: [nHeads, seq, dk] -> [seq, dModel]
mergeHeads←{(seqLen dModel)⍴⍉[0 2 1 3]⍵} ⍝ conceptual, simplified below for demo

⍝ Simplified MHA for demo (loop over heads for clarity):
⍝ Wq Wk Wv Wo are [dModel, dModel]
mha←{
  ⍝ ⍵: X [seq, dModel], ⍺: namespace of params
  X←⍵ ⋄ P←⍺
  Q←X+.×P.Wq ⋄ K←X+.×P.Wk ⋄ V←X+.×P.Wv
  ⍝ reshape to heads by splitting last axis
  Qh←(nHeads seqLen dk)⍴⍉[2 0 1] (seqLen nHeads dk)⍴Q
  Kh←(nHeads seqLen dk)⍴⍉[2 0 1] (seqLen nHeads dk)⍴K
  Vh←(nHeads seqLen dk)⍴⍉[2 0 1] (seqLen nHeads dk)⍴V
  mask←causalMask seqLen
  ⍝ per-head attention
  Oh←{
    s←(⍵.Q)+.×⍉⍵.K
    w←softmaxRows (s÷√dk)+mask
    w+.×⍵.V
  }¨ (⊂Qh)(⊂Kh)(⊂Vh) ⍝ vector of namespaces - illustrative
  O←(seqLen dModel)⍴,⍉[1 0 2] (seqLen nHeads dk)⍴↑Oh
  O+.×P.Wo
}

⍝ ── MLP ──
⍝ params W1 [dModel, dFF] W2 [dFF, dModel] b1 b2
mlp←{
  X←⍵ ⋄ P←⍺
  h←gelu (X+.×P.W1)+P.b1
  (h+.×P.W2)+P.b2
}

⍝ ── Transformer block (pre-norm) ──
⍝ P contains Wq Wk Wv Wo W1 W2 b1 b2
block←{
  X←⍵ ⋄ P←⍺
  a←P mha layerNorm X
  X1←X+a
  m←P mlp layerNorm X1
  X1+m
}

⍝ ── Jacobian blocks ──
⍝ Linear: y = W+.×x  =>  J = W (for x vector)
linearJac←{⍺} ⍝ returns W itself

⍝ Softmax Jacobian: J = diag(s) - s∘.×s
softmaxJac←{
  s←softmaxVec ⍵
  n←≢s
  I←(∘.=⍨⍳n)
  D←I×(n n⍴s)  ⍝ diag(s)
  D-s∘.×s
}

⍝ Finite-difference checker for any vec->vec fn
⍝ (fn x) returns vector, h step
fdJac←{
  fn←⍺⍺ ⋄ x←⍵ ⋄ h←1e-5
  n←≢x ⋄ m←≢fn x
  J←(m n)⍴0
  :For i :In ⍳n
    e←(n⍴0)+h×(⍳n)=i
    J[;i]←(fn x+e)-fn x÷h
  :EndFor
  J
}

⍝ ── Demo ──
⍝ Random tiny test (use ? for demo, replace with fixed weights in real run)
demo←{
  ⍝ fake X [4, 8] for readability
  X←(4 8)⍴0.1×⍳32
  s←softmaxVec 1 2 3
  ⎕←'softmax:' ⋄ ⎕←s
  ⎕←'softmax jacobian:' ⋄ ⎕←softmaxJac 1 2 3
  ⍝ check vs finite diff
  J1←softmaxJac 1 2 3
  J2←(softmaxVec fdJac) 1 2 3
  ⎕←'max fd error:' ⋄ ⎕←⌈/,|J1-J2
}

⍝ Full model forward (embeddings omitted for brevity):
⍝ modelForward X P Q  where X [seq, dModel]
modelForward←{
  X←⍵ ⋄ P←⍺
  X←P.block1 block X
  X←P.block2 block X
  layerNorm X
}
