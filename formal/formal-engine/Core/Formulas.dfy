// ============================================================================
// formal-engine/Core/Formulas.dfy
// Formula and verification result definitions
// License: GPL 2.0
// ============================================================================

module Core.Formulas {

  import opened Core.Terms

  datatype Formula =
      Atomic(term: Term)
    | Negation(formula: Formula)
    | Conjunction(left: Formula, right: Formula)
    | Disjunction(left: Formula, right: Formula)
    | Implication(left: Formula, right: Formula)

  datatype ProofStatus =
      Candidate
    | Proven
    | Refuted
    | Bounded
    | Unknown
    | Unsupported

  datatype VerificationResult =
      Verified
    | Failed
    | UnknownResult
    | UnsupportedResult

  function FormulaDepth(f: Formula): nat
  {
    match f
      case Atomic(_) => 1
      case Negation(x) => 1 + FormulaDepth(x)
      case Conjunction(x, y) => 1 + if FormulaDepth(x) > FormulaDepth(y)
                                      then FormulaDepth(x)
                                      else FormulaDepth(y)
      case Disjunction(x, y) => 1 + if FormulaDepth(x) > FormulaDepth(y)
                                     then FormulaDepth(x)
                                     else FormulaDepth(y)
      case Implication(x, y) => 1 + if FormulaDepth(x) > FormulaDepth(y)
                                     then FormulaDepth(x)
                                     else FormulaDepth(y)
  }

  predicate WellFormedFormula(f: Formula)
  {
    match f
      case Atomic(t) => WellSortedTerm(t)
      case Negation(x) => WellFormedFormula(x)
      case Conjunction(x, y) => WellFormedFormula(x) && WellFormedFormula(y)
      case Disjunction(x, y) => WellFormedFormula(x) && WellFormedFormula(y)
      case Implication(x, y) => WellFormedFormula(x) && WellFormedFormula(y)
  }

  function NormalizeFormula(f: Formula): Formula
    decreases FormulaDepth(f)
  {
    match f
      case Atomic(t) => Atomic(Normalize(t))
      case Negation(x) =>
        match NormalizeFormula(x)
          case Atomic(TBool(v)) => Atomic(TBool(!v))
          case Negation(y) => y
          case _ => Negation(NormalizeFormula(x))

      case Conjunction(x, y) =>
        var nx := NormalizeFormula(x);
        var ny := NormalizeFormula(y);
        match (nx, ny)
          case (Atomic(TBool(false)), _) => Atomic(TBool(false))
          case (_, Atomic(TBool(false))) => Atomic(TBool(false))
          case (Atomic(TBool(true)), _) => ny
          case (_, Atomic(TBool(true))) => nx
          case _ => Conjunction(nx, ny)

      case Disjunction(x, y) =>
        var nx := NormalizeFormula(x);
        var ny := NormalizeFormula(y);
        match (nx, ny)
          case (Atomic(TBool(true)), _) => Atomic(TBool(true))
          case (_, Atomic(TBool(true))) => Atomic(TBool(true))
          case (Atomic(TBool(false)), _) => ny
          case (_, Atomic(TBool(false))) => nx
          case _ => Disjunction(nx, ny)

      case Implication(x, y) =>
        Disjunction(Negation(NormalizeFormula(x)), NormalizeFormula(y))
  }
}
