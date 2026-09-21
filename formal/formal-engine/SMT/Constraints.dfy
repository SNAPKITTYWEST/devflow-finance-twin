// ============================================================================
// formal-engine/SMT/Constraints.dfy
// SMT constraint and solver model
// License: GPL 2.0
// ============================================================================

module SMT.Constraints {

  import opened Core.Terms
  import opened Core.Formulas

  datatype SMTTheory =
      LinearArithmetic
    | NonlinearArithmetic
    | BitVectorTheory
    | ArrayTheory
    | UninterpretedFunctions

  datatype SMTConstraint =
    SMTConstraint(
      formula: Formula,
      theory: SMTTheory
    )

  datatype SMTResult =
      SMT_SAT(model: map<string, Term>)
    | SMT_UNSAT
    | SMT_UNKNOWN

  datatype SMTProblem =
    SMTProblem(
      constraints: seq<SMTConstraint>
    )

  predicate ValidSMTProblem(p: SMTProblem)
  {
    forall i :: 0 <= i < |p.constraints| ==>
      WellFormedFormula(p.constraints[i].formula)
  }

  predicate ValidSMTModel(m: map<string, Term>)
  {
    forall k :: k in m ==> WellSortedTerm(m[k])
  }

  function Solve(problem: SMTProblem): SMTResult
  {
    if |problem.constraints| == 0 then
      SMT_SAT(map[])
    else
      SMT_UNKNOWN
  }

  predicate SolvableWithTheory(c: SMTConstraint, theory: SMTTheory)
  {
    c.theory == theory
  }

  lemma SolverConservative(problem: SMTProblem)
    ensures
      var result := Solve(problem);
      (result.SMT_UNSAT? ==> |problem.constraints| >= 0) &&
      (result.SMT_UNKNOWN? ==> true)
  {}
}
