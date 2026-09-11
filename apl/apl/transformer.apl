â ========================================================================
â SOVEREIGN LEVIATHAN NODE LICENSE
â License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
â Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
â ========================================================================
â
â This file is a covered work under the GNU Affero General Public License,
â version 3, together with the Sovereign Leviathan additional terms.
â
â Hark, though this node be but a spark,
â Its covenant endureth through the dark.
â
â Ignorantia juris non excusat.
â ========================================================================

â Tiny Decoder-Only Transformer in Dyalog APL
â Run in Dyalog: ]load transformer.apl
â Config is tiny for readability. All arrays are 0-index friendly.

â â”€â”€ Hyperparams â”€â”€
vocabâ†512 â‹„ dModelâ†64 â‹„ nHeadsâ†4 â‹„ dkâ†dModelÃ·nHeads
dFFâ†128 â‹„ seqLenâ†32 â‹„ epsâ†1e-5

â â”€â”€ Primitives â”€â”€
â stable softmax for vector
softmaxVecâ†{eâ†*âµ-âŒˆ/âµ â‹„ eÃ·+/e}
â row-wise softmax for matrix [seq, seq]
softmaxRowsâ†softmaxVecâ¤1

â layerNorm per row: [n, d] -> [n, d]
lnVecâ†{mâ†(+/âµ)Ã·â‰¢âµ â‹„ vâ†(+/2*â¨âµ-m)Ã·â‰¢âµ â‹„ (âµ-m)Ã·âˆšv+eps}
layerNormâ†lnVecâ¤1

â gelu approx (tanh version)
geluâ†{0.5Ã—âµÃ—1+7â—‹0.79788456Ã—âµ+0.044715Ã—âµ*3}

â causal mask: 0 allowed, Â¯1e9 future
causalMaskâ†{nâ†âµ â‹„ (n nâ´0)+Â¯1e9Ã—n nâ´(â³n)âˆ˜.<â³n}
â Note: (â³n)âˆ˜.<â³n gives strictly lower triangular 1s, we invert for causal

â fix mask orientation for demo: lower-tri inclusive = allowed
causalMaskâ†{(n nâ´0)+Â¯1e9Ã—~(n nâ´(â³âµ)âˆ˜.â‰¤â³âµ)}

â â”€â”€ Attention â”€â”€
â Single head: Q K V are [seq, dk], returns [seq, dk]
attn1â†{
  scoresâ†âºâº.+.Ã—â‰âµâµ â placeholder to keep tacit clear
  âµ
}
â explicit version:
â Q K V as left,mid,right args via namespace - use dfn with 3 args via âº âµ and global
singleHeadâ†{
  â âµ is namespace with Q K V Mask
  scoresâ†(âµ.Q)+.Ã—â‰âµ.K
  scaledâ†scoresÃ·âˆšdk
  maskedâ†scaled+âµ.mask
  wâ†softmaxRows masked
  w+.Ã—âµ.V
}

â Split heads: X [seq, dModel] -> [nHeads, seq, dk]
splitHeadsâ†{nHeads (seqLen dk)â´âµ}

â mergeHeads: [nHeads, seq, dk] -> [seq, dModel]
mergeHeadsâ†{(seqLen dModel)â´â‰[0 2 1 3]âµ} â conceptual, simplified below for demo

â Simplified MHA for demo (loop over heads for clarity):
â Wq Wk Wv Wo are [dModel, dModel]
mhaâ†{
  â âµ: X [seq, dModel], âº: namespace of params
  Xâ†âµ â‹„ Pâ†âº
  Qâ†X+.Ã—P.Wq â‹„ Kâ†X+.Ã—P.Wk â‹„ Vâ†X+.Ã—P.Wv
  â reshape to heads by splitting last axis
  Qhâ†(nHeads seqLen dk)â´â‰[2 0 1] (seqLen nHeads dk)â´Q
  Khâ†(nHeads seqLen dk)â´â‰[2 0 1] (seqLen nHeads dk)â´K
  Vhâ†(nHeads seqLen dk)â´â‰[2 0 1] (seqLen nHeads dk)â´V
  maskâ†causalMask seqLen
  â per-head attention
  Ohâ†{
    sâ†(âµ.Q)+.Ã—â‰âµ.K
    wâ†softmaxRows (sÃ·âˆšdk)+mask
    w+.Ã—âµ.V
  }Â¨ (âŠ‚Qh)(âŠ‚Kh)(âŠ‚Vh) â vector of namespaces - illustrative
  Oâ†(seqLen dModel)â´,â‰[1 0 2] (seqLen nHeads dk)â´â†‘Oh
  O+.Ã—P.Wo
}

â â”€â”€ MLP â”€â”€
â params W1 [dModel, dFF] W2 [dFF, dModel] b1 b2
mlpâ†{
  Xâ†âµ â‹„ Pâ†âº
  hâ†gelu (X+.Ã—P.W1)+P.b1
  (h+.Ã—P.W2)+P.b2
}

â â”€â”€ Transformer block (pre-norm) â”€â”€
â P contains Wq Wk Wv Wo W1 W2 b1 b2
blockâ†{
  Xâ†âµ â‹„ Pâ†âº
  aâ†P mha layerNorm X
  X1â†X+a
  mâ†P mlp layerNorm X1
  X1+m
}

â â”€â”€ Jacobian blocks â”€â”€
â Linear: y = W+.Ã—x  =>  J = W (for x vector)
linearJacâ†{âº} â returns W itself

â Softmax Jacobian: J = diag(s) - sâˆ˜.Ã—s
softmaxJacâ†{
  sâ†softmaxVec âµ
  nâ†â‰¢s
  Iâ†(âˆ˜.=â¨â³n)
  Dâ†IÃ—(n nâ´s)  â diag(s)
  D-sâˆ˜.Ã—s
}

â Finite-difference checker for any vec->vec fn
â (fn x) returns vector, h step
fdJacâ†{
  fnâ†âºâº â‹„ xâ†âµ â‹„ hâ†1e-5
  nâ†â‰¢x â‹„ mâ†â‰¢fn x
  Jâ†(m n)â´0
  :For i :In â³n
    eâ†(nâ´0)+hÃ—(â³n)=i
    J[;i]â†(fn x+e)-fn xÃ·h
  :EndFor
  J
}

â â”€â”€ Demo â”€â”€
â Random tiny test (use ? for demo, replace with fixed weights in real run)
demoâ†{
  â fake X [4, 8] for readability
  Xâ†(4 8)â´0.1Ã—â³32
  sâ†softmaxVec 1 2 3
  âŽ•â†'softmax:' â‹„ âŽ•â†s
  âŽ•â†'softmax jacobian:' â‹„ âŽ•â†softmaxJac 1 2 3
  â check vs finite diff
  J1â†softmaxJac 1 2 3
  J2â†(softmaxVec fdJac) 1 2 3
  âŽ•â†'max fd error:' â‹„ âŽ•â†âŒˆ/,|J1-J2
}

â Full model forward (embeddings omitted for brevity):
â modelForward X P Q  where X [seq, dModel]
modelForwardâ†{
  Xâ†âµ â‹„ Pâ†âº
  Xâ†P.block1 block X
  Xâ†P.block2 block X
  layerNorm X
}
