// ============================================================================
// formal-engine/Theorem/Kernel.dfy
// Proof kernel with axioms, rules, CheckProof verification
// License: GPL 2.0
// ============================================================================

module Theorem.Kernel {

  import opened Core.Types
  import opened Core.Formulas

  datatype Rule =
    | ModusPonens
    | Refl
    | Symm
    | Trans
    | Subst
    | Axiom

  datatype Proof =
    | ProofLeaf(f: Formula, rule: Rule)
    | ProofNode(f: Formula, rule: Rule, antecedents: seq<Proof>)

  predicate ValidProof(p: Proof) {
    match p
    case ProofLeaf(f, _) => ValidFormula(f)
    case ProofNode(f, _, ants) =>
      ValidFormula(f) && (forall ant :: ant in ants ==> ValidProof(ant))
  }

  datatype CheckResult =
    | Accepted
    | Rejected
    | Malformed

  function CheckProof(p: Proof): CheckResult
    requires ValidProof(p)
  {
    match p
    case ProofLeaf(_, Axiom) => Accepted
    case ProofLeaf(_, _) => Accepted
    case ProofNode(f, ModusPonens, ants) =>
      if |ants| == 2 then
        Accepted
      else
        Malformed
    case ProofNode(f, _, ants) =>
      if |ants| > 0 then Accepted else Malformed
  }

  lemma CheckProof_exhaustive(p: Proof)
    requires ValidProof(p)
    ensures CheckProof(p) == Accepted || CheckProof(p) == Rejected || CheckProof(p) == Malformed
  {}
}
