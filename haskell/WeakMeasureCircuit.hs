-- weak_measure_circuit.hs
-- Quipper weak-measurement example: system + ancilla, controlled Ry(theta) on ancilla.
-- Analytic Kraus derivation is in comments below.
{-# LANGUAGE FlexibleContexts #-}
module WeakMeasureCircuit where

import Quipper

-- Controlled Ry on ancilla by system qubit
weakMeasure :: Double -> Circ (Qubit, Bit)
weakMeasure theta = do
  sys <- qinit False
  anc <- qinit False
  with_controls sys $ gate_RY theta anc
  b <- measure anc
  return (sys, b)

-- Print the circuit (for inspection)
printCircuit :: IO ()
printCircuit = print_generic Preview (weakMeasure (pi/8))

{-
ANALYTIC KRAUS DERIVATION (for this circuit)

Hilbert spaces: system (S) spanned by |0>,|1>; ancilla (A) spanned by |0>,|1>.
Ancilla initial state: |0>_A.

Unitary action U on basis states:
  U (|0>_S ⊗ |0>_A) = |0>_S ⊗ |0>_A
  U (|1>_S ⊗ |0>_A) = |1>_S ⊗ ( cos(θ/2) |0>_A + sin(θ/2) |1>_A )

Kraus operators K_m = <m|_A U |0>_A (operators on system space):

For m = 0:
  K_0 |0> =  <0| U (|0>⊗|0>) = |0>
  K_0 |1> =  <0| U (|1>⊗|0>) = cos(θ/2) |1>
Hence in system basis { |0>, |1> }:
  K_0 = diag(1, cos(θ/2))

For m = 1:
  K_1 |0> = <1| U (|0>⊗|0>) = 0
  K_1 |1> = <1| U (|1>⊗|0>) = sin(θ/2) |1>
Hence:
  K_1 = diag(0, sin(θ/2))

Check completeness:
  K_0^\dagger K_0 = diag(1, cos^2(θ/2))
  K_1^\dagger K_1 = diag(0, sin^2(θ/2))
  Sum = diag(1, cos^2 + sin^2) = I

EMA coupling angle:
  theta = 2 * arcsin(sqrt(eta * (q1 - q0)))
  Expected ancilla outcome: m = p * sin^2(theta/2) = p * eta * (q1 - q0)
  EMA step: p' = p + eta * (m - p)
-}
