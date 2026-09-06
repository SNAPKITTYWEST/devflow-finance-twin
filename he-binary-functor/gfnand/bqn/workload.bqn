# workload.bqn - BQN Array Descriptor Analysis

MatMulFLOPs ← { 2 × (⊑𝕩) × (1⊑𝕩) × (1⊑𝕪) }
ArithmeticIntensity ← { 𝕩 ÷ 𝕪 }

A_shape ← 1024‿2048
B_shape ← 2048‿4096

Flops ← A_shape MatMulFLOPs B_shape
MemBytes ← (1024×2048 + 2048×4096 + 1024×4096) × 4
Intensity ← Flops ArithmeticIntensity MemBytes

TotalFlops ← { +´ ⥊ 𝕩.shape × FlopsPerOp 𝕩.opcode }
MaxNode ← { 𝕩 ⊑˜ ⍋ TotalFlops¨ 𝕩 }
MacReduce ← { 𝕩.A_shape +´ 𝕩.B_shape }

ParamCount ← { ×´ 1⊑𝕩 }
MemBytes2 ← { (ParamCount 𝕩) × 3⊑𝕩 }

CalcFlops ← {
  type ← 0⊑𝕩
  in ← 1⊑𝕩
  out ← 2⊑𝕩
  type ≡ "MatMul" ? 2 × (0⊑in) × (1⊑in) × (1⊑out) ;
  type ≡ "Add" ? ×´ in ;
  0
}

GraphOps ← ⟨ ⟨"MatMul", ⟨1024,1024⟩, ⟨1024,1024⟩, 2⟩, ⟨"Add", ⟨1024,1024⟩, ⟨1024,1024⟩, 2⟩ ⟩
FlopCounts ← CalcFlops¨ GraphOps
MaxFlopIndex ← ⊑ ⍒ FlopCounts
MaxWorkload ← MaxFlopIndex ⊑ GraphOps
