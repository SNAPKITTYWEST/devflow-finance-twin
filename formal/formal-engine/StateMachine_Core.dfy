// ============================================================================
// formal-engine/StateMachine/Core.dfy
// State machine definitions, invariants, actions
// License: GPL 2.0
// ============================================================================

module StateMachine.Core {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas

  datatype Action = Action(name: string, params: seq<Term>, pre: Formula, post: Formula)

  predicate ValidAction(a: Action) {
    |a.name| > 0 && ValidFormula(a.pre) && ValidFormula(a.post)
  }

  datatype Invariant = Invariant(name: string, body: Formula)

  predicate ValidInvariant(inv: Invariant) {
    |inv.name| > 0 && ValidFormula(inv.body)
  }

  datatype Machine = Machine(
    name: string,
    vars: seq<Term>,
    invariants: seq<Invariant>,
    actions: seq<Action>,
    init: Formula
  )

  predicate ValidMachine(m: Machine) {
    |m.name| > 0 &&
    (forall i :: 0 <= i < |m.invariants| ==> ValidInvariant(m.invariants[i])) &&
    (forall i :: 0 <= i < |m.actions| ==> ValidAction(m.actions[i])) &&
    ValidFormula(m.init)
  }

  function SimpleCounter(N: int): Machine
    requires N >= 0
    ensures ValidMachine(SimpleCounter(N))
  {
    var x := MkVar("x", INT);
    Machine(
      "Counter",
      [x],
      [Invariant("x_nonneg", MkGe(x, LitInt(0)))],
      [
        Action("inc", [], TrueF, Implies(TrueF, TrueF)),
        Action("reset", [], TrueF, MkEq(x, LitInt(0)))
      ],
      MkEq(x, LitInt(0))
    )
  }

  function IsSafeAction(m: Machine, a: Action): bool
    requires ValidMachine(m) && ValidAction(a)
  {
    forall inv :: inv in m.invariants
      ==> (Implies(m.init, inv.body) || Implies(a.post, inv.body))
  }

  function AllActionsSafe(m: Machine): bool
    requires ValidMachine(m)
  {
    forall i :: 0 <= i < |m.actions| ==> IsSafeAction(m, m.actions[i])
  }

  lemma SimpleCounter_safe(N: int)
    requires N >= 0
    ensures AllActionsSafe(SimpleCounter(N))
  {}
}
