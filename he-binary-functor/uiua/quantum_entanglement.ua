; --- Quantum State Definitions ---
InitState = [0.5 0.5 0.5 0.5]

; CNOT Matrix
CNOT = [1 0 0 0
        0 1 0 0
        0 0 0 1
        0 0 1 0]

; --- Transformation Functions ---

; 1. Entangle: Matrix-Vector Multiplication
Entangle = ⊞ @ ⊞

; 2. Calculate Entanglement Degree (Simplified Concurrence)
CalcDeg = {
  a = ⊞ ; input state
  deg = 2 × abs ( (a[0] × a[3]) - (a[1] × a[2]) )
  deg
}

; 3. Gated Collapse Logic
GatedCollapse = {
  state deg thresh =
    (deg > thresh)
      ? (argmax @ (square @ state))
      : state
}

; 4. Marginal Readout
Readout = {
  probs = square @ state
  q0 = probs[2] + probs[3]
  q1 = probs[1] + probs[3]
  [q0 q1]
}

; --- Execution Pipeline ---
Pipeline = {
  S = InitState
  S1 = Entangle @ [S CNOT]
  D = CalcDeg @ S1
  S2 = GatedCollapse @ [S1 D 0.707]
  Readout @ S2
}
