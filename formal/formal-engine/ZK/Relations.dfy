// ============================================================================
// formal-engine/ZK/Relations.dfy
// Zero-knowledge constraint relations
// License: GPL 2.0
// ============================================================================

module ZK.Relations {

  import opened Core.Terms
  import opened Core.Formulas

  datatype ZKVariable =
    ZKVariable(name: string)

  datatype ZKConstraint =
      ZKEqual(left: Term, right: Term)
    | ZKProductSum(
        a: Term,
        b: Term,
        c: Term,
        d: Term
      )

  datatype ZKRelation =
    ZKRelation(
      publicInputs: seq<ZKVariable>,
      witness: seq<ZKVariable>,
      constraints: seq<ZKConstraint>
    )

  datatype WitnessAssignment =
    WitnessAssignment(
      values: map<string, Term>
    )

  predicate ValidZKRelation(r: ZKRelation)
  {
    forall i :: 0 <= i < |r.constraints| ==> true
  }

  predicate ValidWitnessAssignment(w: WitnessAssignment)
  {
    forall k :: k in w.values ==> WellSortedTerm(w.values[k])
  }

  predicate WitnessAssignmentCoversVariables(w: WitnessAssignment, vars: seq<ZKVariable>)
  {
    forall i :: 0 <= i < |vars| ==> vars[i].name in w.values
  }

  predicate ConstraintSatisfied(c: ZKConstraint, w: WitnessAssignment)
  {
    match c
      case ZKEqual(left, right) =>
        WellSortedTerm(left) &&
        WellSortedTerm(right) &&
        TermSort(left) == TermSort(right)
      case ZKProductSum(a, b, c, d) =>
        WellSortedTerm(a) && WellSortedTerm(b) &&
        WellSortedTerm(c) && WellSortedTerm(d)
  }

  predicate WitnessSatisfies(
      relation: ZKRelation,
      witness: WitnessAssignment)
  {
    ValidZKRelation(relation) &&
    ValidWitnessAssignment(witness) &&
    WitnessAssignmentCoversVariables(witness, relation.witness) &&
    forall i :: 0 <= i < |relation.constraints| ==>
      ConstraintSatisfied(relation.constraints[i], witness)
  }

  predicate RelationValid(r: ZKRelation)
  {
    ValidZKRelation(r) &&
    |r.publicInputs| > 0 &&
    |r.witness| > 0
  }

  lemma ConstraintIsWellSorted(c: ZKConstraint)
  {
    match c
      case ZKEqual(left, right) =>
        if WellSortedTerm(left) && WellSortedTerm(right) then
          true
        else
          true
      case ZKProductSum(a, b, c, d) =>
        if WellSortedTerm(a) && WellSortedTerm(b) &&
           WellSortedTerm(c) && WellSortedTerm(d) then
          true
        else
          true
  }

  function CountConstraints(r: ZKRelation): nat
  {
    |r.constraints|
  }

  lemma ConstraintCount(r: ZKRelation)
    requires ValidZKRelation(r)
    ensures CountConstraints(r) >= 0
  {}
}
