// ============================================================================
// formal-engine/Contracts/Core.dfy
// Requires/Ensures/Assert/Assume contracts
// License: GPL 2.0
// ============================================================================

module Contracts.Core {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas

  datatype Requires = Requires(formula: Formula, label: string)
  datatype Ensures = Ensures(formula: Formula, label: string)
  datatype AssertClause = AssertClause(formula: Formula, label: string)
  datatype AssumeClause = AssumeClause(formula: Formula, label: string)
  datatype LoopInvariant = LoopInvariant(formula: Formula, label: string)
  datatype Decreases = Decreases(terms: seq<Term>)

  predicate ValidRequires(r: Requires) { ValidFormula(r.formula) }
  predicate ValidEnsures(e: Ensures) { ValidFormula(e.formula) }
  predicate ValidAssert(a: AssertClause) { ValidFormula(a.formula) }
  predicate ValidAssume(a: AssumeClause) { ValidFormula(a.formula) }
  predicate ValidLoopInv(i: LoopInvariant) { ValidFormula(i.formula) }

  datatype MethodContract =
    MethodContract(
      name: string,
      parameters: seq<Term>,
      requires: seq<Requires>,
      ensures: seq<Ensures>,
      invariants: seq<LoopInvariant>,
      decreases: Decreases
    )

  predicate ValidMethodContract(c: MethodContract)
  {
    |c.name| > 0 &&
    (forall i :: 0 <= i < |c.requires| ==> ValidRequires(c.requires[i])) &&
    (forall i :: 0 <= i < |c.ensures| ==> ValidEnsures(c.ensures[i])) &&
    (forall i :: 0 <= i < |c.invariants| ==> ValidLoopInv(c.invariants[i]))
  }

  function AllRequires(c: MethodContract): Formula
    requires ValidMethodContract(c)
    ensures ValidFormula(AllRequires(c))
  {
    if |c.requires| == 0 then TrueF
    else MkAnd(seq(|c.requires|, i requires 0 <= i < |c.requires| => c.requires[i].formula))
  }

  function AllEnsures(c: MethodContract): Formula
    requires ValidMethodContract(c)
    ensures ValidFormula(AllEnsures(c))
  {
    if |c.ensures| == 0 then TrueF
    else MkAnd(seq(|c.ensures|, i requires 0 <= i < |c.ensures| => c.ensures[i].formula))
  }
}
