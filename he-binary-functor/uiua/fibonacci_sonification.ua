; --- Fibonacci Cantor Sonification ---

; 1. Generate Fibonacci Sequence (Substitution Rule)
; A -> AB, B -> A
FibSeq = {
  n = 10 ; iterations
  seq = "A"
  repeat n {
    seq = replace "A" "AB" seq
    seq = replace "B" "A" seq
  }
  seq
}

; 2. Spectral Projection to Energy (E_k)
ProjectSpectrum = {
  seq = FibSeq
  vals = map (char == "A" ? 1.0 : 0.618) seq
  vals = map (v -> v * pow 0.618 (index vals)) vals
  vals
}

; 3. Acoustic Mapping (E_k -> f_k)
Sonify = {
  E = ProjectSpectrum
  f0 = 440.0 ; A4 tuning
  p = 1.5 ; Harmonic scaling power
  Emax = max @ E

  freqs = map (Ek -> f0 * pow (Ek / Emax) p) E
  freqs
}

; --- Execution ---
AudioStream = Sonify
