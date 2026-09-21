// ============================================================================
// formal-engine/Proofs/SMTInvariants.dfy
// Invariants of the Boolean engine
// License: GPL 2.0
// ============================================================================

module Proofs.SMTInvariants {

  import opened SMT.UnitPropagation
  import opened SMT.OneUIP
  import opened SMT.ClauseMinimization

  predicate TrailConsistent(a: Assignment) {
    forall e :: e in a.trail ==>
      e.lit.var in a.vals &&
      a.vals[e.lit.var] == (if e.lit.sign then BTrue else BFalse)
  }

  lemma AssignLit_maintains_TrailConsistent(a: Assignment, l: Lit, reason: int)
    requires IsUndef(a, l)
    requires TrailConsistent(a)
    ensures TrailConsistent(AssignLit(a, l, reason))
  {}

  lemma Decision_maintains_TrailConsistent(a: Assignment, l: Lit)
    requires IsUndef(a, l)
    requires TrailConsistent(a)
    ensures TrailConsistent(Decision(a, l))
  {}

  lemma Backtrack_maintains_TrailConsistent(a: Assignment, toLevel: nat)
    requires toLevel <= a.level
    requires TrailConsistent(a)
    ensures TrailConsistent(Backtrack(a, toLevel))
  {}

  predicate NoDuplicateVars(a: Assignment) {
    forall i,j :: 0 <= i < j < |a.trail| ==> a.trail[i].lit.var != a.trail[j].lit.var
  }

  lemma AssignLit_maintains_NoDuplicateVars(a: Assignment, l: Lit, reason: int)
    requires IsUndef(a, l)
    requires NoDuplicateVars(a)
    ensures NoDuplicateVars(AssignLit(a, l, reason))
  {}

  predicate LevelsBounded(a: Assignment) {
    forall e :: e in a.trail ==> e.level <= a.level
  }

  lemma LevelsBounded_init(nvars: nat)
    ensures LevelsBounded(EmptyAssignment(nvars))
  {}

  lemma Decision_raises_level(a: Assignment, l: Lit)
    requires IsUndef(a, l)
    ensures Decision(a, l).level == a.level + 1
  {}
}
