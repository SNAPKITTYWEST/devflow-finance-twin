# tests.bqn — Deterministic test vectors

TV0 ← ⟨0, 0, ⟨⟩, ⟨⟩, ⟨0,0,0,0,0⟩, 0⟩
TV1 ← ⟨1, 1, ⟨1⟩, ⟨1⟩, ⟨1,1,1,1,1⟩, 1⟩
TV2 ← ⟨2, 1, ⟨1⟩, ⟨1⟩, ⟨2,1,1,1,1⟩, 1⟩
TV3 ← ⟨3, 2, ⟨1, ¯2⟩, ⟨1, ¯2⟩, ⟨3,2,2,0,0⟩, 0⟩
TV5 ← ⟨5, 5, ⟨1, ¯2, 3, ¯4, 1⟩, ⟨1, ¯2, 3, ¯4, 1⟩, ⟨5,5,5,0,0⟩, 0⟩

CancelTV ← ⟨⟨1, ¯1, 2⟩, ⟨2⟩⟩
InvTV ← ⟨⟨1, 2, ¯3⟩, ⟨3, ¯2, ¯1⟩⟩

AssertEq ← { 𝕨 ≡ 𝕩 ? 1 ; ! "assert failed" }

RunTests ← {
  0 AssertEq Fib 0
  1 AssertEq Fib 1
  1 AssertEq Fib 2
  2 AssertEq Fib 3
  3 AssertEq Fib 4
  5 AssertEq Fib 5
  8 AssertEq Fib 6
  55 AssertEq Fib 10

  (FibSafe ¯1) AssertEq 0
  (FibSafe 100) AssertEq 0

  ValidWord ⟨1,2,¯1⟩ AssertEq 1
  ValidWord ⟨0⟩ AssertEq 0
  ValidWord ⟨5⟩ AssertEq 0

  (Inv ⟨1,2,¯3⟩) AssertEq ⟨3,¯2,¯1⟩
  (Inv Inv ⟨1,¯2,3⟩) AssertEq ⟨1,¯2,3⟩

  (Reduce ⟨1,¯1,2⟩) AssertEq ⟨2⟩
  (Reduce ⟨1,2,¯2,¯1⟩) AssertEq ⟨⟩
  (Reduce ⟨1,2,3⟩) AssertEq ⟨1,2,3⟩

  (BraidFromFib 0) AssertEq ⟨⟩
  (BraidFromFib 1) AssertEq ⟨1⟩
  (BraidFromFib 3) AssertEq ⟨1,¯2⟩
  (BraidFromFib 5) AssertEq ⟨1,¯2,3,¯4,1⟩

  s0 ← InitState
  s1 ← s0 Transition ⟨1⟩
  s2 ← s0 Transition ⟨1⟩
  s1 AssertEq s2

  1
}

Vectors ← ⟨
  ⟨0, 0, ⟨⟩, ⟨⟩⟩,
  ⟨1, 1, ⟨1⟩, ⟨1⟩⟩,
  ⟨3, 2, ⟨1,¯2⟩, ⟨1,¯2⟩⟩,
  ⟨5, 5, ⟨1,¯2,3,¯4,1⟩, ⟨1,¯2,3,¯4,1⟩⟩,
  ⟨6, 8, ⟨1,¯2,3,¯4,1,¯2,3,¯4⟩, ⟨1,¯2,3,¯4,1,¯2,3,¯4⟩⟩
⟩
