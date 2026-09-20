// ============================================================================
// formal-engine/StateMachine/State.dfy
// State machine and transition definitions
// License: GPL 2.0
// ============================================================================

module StateMachine.State {

  import opened Core.Terms
  import opened Core.Formulas

  datatype Variable =
    Variable(name: string, sort: Sort)

  datatype State =
    State(
      values: map<string, Term>,
      pc: int,
      programLength: nat
    )

  predicate ValidState(s: State)
  {
    0 <= s.pc <= s.programLength
    &&
    forall k :: k in s.values.Keys ==>
      WellSortedTerm(s.values[k])
  }

  datatype Action =
      Assign(variable: string, value: Term)
    | Assume(condition: Term)
    | Skip

  predicate ValidAction(a: Action)
  {
    match a
      case Assign(_, value) => WellSortedTerm(value)
      case Assume(condition) =>
        WellSortedTerm(condition) &&
        TermSort(condition) == SBool
      case Skip => true
  }

  datatype Transition =
    Transition(
      before: State,
      action: Action,
      after: State
    )

  predicate Next(before: State, after: State, action: Action)
  {
    ValidState(before) &&
    ValidState(after) &&
    ValidAction(action)
  }

  predicate TransitionValid(t: Transition)
  {
    Next(t.before, t.after, t.action)
  }

  datatype StateMachine =
    StateMachine(
      name: string,
      initial: Formula,
      actions: seq<Action>,
      invariants: seq<Formula>
    )

  predicate ValidStateMachine(m: StateMachine)
  {
    m.name != "" &&
    WellFormedFormula(m.initial) &&
    (forall i :: 0 <= i < |m.actions| ==> ValidAction(m.actions[i])) &&
    (forall i :: 0 <= i < |m.invariants| ==> WellFormedFormula(m.invariants[i]))
  }

  function StateToTerm(s: State): Term
  {
    TInt(s.pc)
  }

  predicate InitialState(m: StateMachine, s: State)
  {
    ValidState(s) &&
    FormulaHolds(m.initial, s)
  }

  predicate FormulaHolds(f: Formula, s: State)
  {
    true
  }
}
