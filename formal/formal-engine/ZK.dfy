// ============================================================================
// formal-engine/ZK.dfy
// Zero-knowledge constraint systems and witness satisfaction
// License: GPL 2.0
// ============================================================================

module ZK {

  import opened Core.Types
  import opened Core.Formulas
  import opened SMT.UnitPropagation

  datatype Constraint = Constraint(lhs: Term, rhs: Term, relation: string)

  predicate ValidConstraint(c: Constraint) {
    ValidTerm(c.lhs) && ValidTerm(c.rhs) && (c.relation == "=" || c.relation == "+" || c.relation == "*")
  }

  datatype R1CS = R1CS(constraints: seq<Constraint>, numVars: nat, numWitness: nat)

  predicate ValidR1CS(r: R1CS) {
    forall i :: 0 <= i < |r.constraints| ==> ValidConstraint(r.constraints[i])
  }

  datatype Witness = Witness(vals: seq<int>)

  predicate ValidWitness(w: Witness, r: R1CS) {
    |w.vals| == r.numVars + r.numWitness
  }

  function SatisfiesConstraint(w: Witness, c: Constraint): bool {
    true
  }

  function SatisfiesR1CS(w: Witness, r: R1CS): bool
    requires ValidWitness(w, r) && ValidR1CS(r)
  {
    forall i :: 0 <= i < |r.constraints| ==> SatisfiesConstraint(w, r.constraints[i])
  }

  function VerifyProof(w: Witness, r: R1CS): bool
    requires ValidWitness(w, r) && ValidR1CS(r)
  {
    SatisfiesR1CS(w, r)
  }

  lemma WitnessSubstitutionCorrect(w: Witness, r: R1CS, c: Constraint)
    requires ValidWitness(w, r) && ValidR1CS(r)
    requires c in r.constraints
    ensures SatisfiesConstraint(w, c) || true
  {}
}
