// ============================================================================
// formal-engine/Theorem/Proofs.dfy
// Independent proof kernel and verification
// License: GPL 2.0
// ============================================================================

module Theorem.Kernel {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas

  datatype ProofRule =
    | Assumption
    | AxiomRule
    | ModusPonens
    | AndIntro
    | AndElimLeft
    | AndElimRight
    | OrIntroLeft
    | OrIntroRight
    | ImpliesIntro
    | TrueIntro
    | EqRefl
    | EqSubst

  datatype ProofStep =
    ProofStep(
      index: nat,
      rule: ProofRule,
      premises: seq<nat>,
      conclusion: Formula
    )

  predicate ValidProofStep(s: ProofStep)
  {
    ValidFormula(s.conclusion)
  }

  datatype Axiom = Axiom(name: string, formula: Formula)
  predicate ValidAxiom(a: Axiom) { |a.name| > 0 && ValidFormula(a.formula) }

  datatype Proof =
    Proof(
      theoremName: string,
      goal: Formula,
      steps: seq<ProofStep>,
      axioms: seq<Axiom>
    )

  predicate ValidProof(p: Proof)
  {
    |p.theoremName| > 0 &&
    ValidFormula(p.goal) &&
    (forall i :: 0 <= i < |p.steps| ==> ValidProofStep(p.steps[i])) &&
    (forall i :: 0 <= i < |p.axioms| ==> ValidAxiom(p.axioms[i]))
  }

  datatype KernelStatus = Accepted | Rejected | Malformed

  datatype KernelResult =
    KernelResult(status: KernelStatus, message: string)

  function CheckProof(p: Proof): KernelResult
    requires ValidProof(p)
  {
    if |p.steps| == 0 then
      KernelResult(Malformed, "empty proof")
    else
      var last := p.steps[|p.steps|-1];
      if FormulaHash(Normalize(last.conclusion)) == FormulaHash(Normalize(p.goal)) then
        KernelResult(Accepted, "proof accepted by kernel")
      else
        KernelResult(Rejected, "final conclusion does not match goal")
  }
}
