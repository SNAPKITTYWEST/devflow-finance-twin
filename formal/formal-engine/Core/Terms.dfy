// ============================================================================
// formal-engine/Core/Terms.dfy
// Core term and sort definitions
// License: GPL 2.0
// ============================================================================

module Core.Terms {

  datatype Sort =
      SBool
    | SInt
    | SNat
    | SBitVector(width: nat)
    | SArray(index: Sort, value: Sort)
    | SUninterpreted(name: string)

  datatype Term =
      TBool(value: bool)
    | TInt(value: int)
    | TVar(name: string, sort: Sort)
    | TNot(value: Term)
    | TAnd(left: Term, right: Term)
    | TOr(left: Term, right: Term)
    | TImplies(left: Term, right: Term)
    | TEq(left: Term, right: Term)
    | TLt(left: Term, right: Term)
    | TLe(left: Term, right: Term)
    | TAdd(left: Term, right: Term)
    | TSub(left: Term, right: Term)
    | TMul(left: Term, right: Term)
    | TApp(name: string, arguments: seq<Term>, resultSort: Sort)

  function TermSort(t: Term): Sort
  {
    match t
      case TBool(_) => SBool
      case TInt(_) => SInt
      case TVar(_, s) => s
      case TNot(_) => SBool
      case TAnd(_, _) => SBool
      case TOr(_, _) => SBool
      case TImplies(_, _) => SBool
      case TEq(_, _) => SBool
      case TLt(_, _) => SBool
      case TLe(_, _) => SBool
      case TAdd(_, _) => SInt
      case TSub(_, _) => SInt
      case TMul(_, _) => SInt
      case TApp(_, _, s) => s
  }

  predicate WellSortedTerm(t: Term)
  {
    match t
      case TBool(_) => true
      case TInt(_) => true
      case TVar(_, _) => true

      case TNot(x) =>
        WellSortedTerm(x) &&
        TermSort(x) == SBool

      case TAnd(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SBool &&
        TermSort(b) == SBool

      case TOr(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SBool &&
        TermSort(b) == SBool

      case TImplies(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SBool &&
        TermSort(b) == SBool

      case TEq(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == TermSort(b)

      case TLt(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SInt &&
        TermSort(b) == SInt

      case TLe(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SInt &&
        TermSort(b) == SInt

      case TAdd(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SInt &&
        TermSort(b) == SInt

      case TSub(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SInt &&
        TermSort(b) == SInt

      case TMul(a, b) =>
        WellSortedTerm(a) &&
        WellSortedTerm(b) &&
        TermSort(a) == SInt &&
        TermSort(b) == SInt

      case TApp(_, args, _) =>
        forall i :: 0 <= i < |args| ==> WellSortedTerm(args[i])
  }

  function TermDepth(t: Term): nat
  {
    match t
      case TBool(_) => 0
      case TInt(_) => 0
      case TVar(_, _) => 0
      case TNot(x) => 1 + TermDepth(x)
      case TAnd(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TOr(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TImplies(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TEq(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TLt(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TLe(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TAdd(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TSub(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TMul(a, b) => 1 + TermDepth(a) + TermDepth(b)
      case TApp(_, args, _) => 1 + SequenceDepth(args)
  }

  function SequenceDepth(xs: seq<Term>): nat
  {
    if |xs| == 0 then
      0
    else
      TermDepth(xs[0]) + SequenceDepth(xs[1..])
  }

  function Normalize(t: Term): Term
    decreases TermDepth(t)
  {
    match t
      case TBool(_) => t
      case TInt(_) => t
      case TVar(_, _) => t

      case TNot(x) =>
        match Normalize(x)
          case TBool(v) => TBool(!v)
          case TNot(y) => y
          case _ => TNot(Normalize(x))

      case TAnd(a, b) =>
        var na := Normalize(a);
        var nb := Normalize(b);
        if na == TBool(false) || nb == TBool(false) then
          TBool(false)
        else if na == TBool(true) then
          nb
        else if nb == TBool(true) then
          na
        else
          TAnd(na, nb)

      case TOr(a, b) =>
        var na := Normalize(a);
        var nb := Normalize(b);
        if na == TBool(true) || nb == TBool(true) then
          TBool(true)
        else if na == TBool(false) then
          nb
        else if nb == TBool(false) then
          na
        else
          TOr(na, nb)

      case TImplies(a, b) =>
        TOr(TNot(Normalize(a)), Normalize(b))

      case TEq(a, b) =>
        TEq(Normalize(a), Normalize(b))

      case TLt(a, b) =>
        TLt(Normalize(a), Normalize(b))

      case TLe(a, b) =>
        TLe(Normalize(a), Normalize(b))

      case TAdd(a, b) =>
        TAdd(Normalize(a), Normalize(b))

      case TSub(a, b) =>
        TSub(Normalize(a), Normalize(b))

      case TMul(a, b) =>
        TMul(Normalize(a), Normalize(b))

      case TApp(n, args, s) =>
        TApp(n, NormalizeSequence(args), s)
  }

  function NormalizeSequence(xs: seq<Term>): seq<Term>
    decreases |xs|
  {
    if |xs| == 0 then
      []
    else
      [Normalize(xs[0])] + NormalizeSequence(xs[1..])
  }
}
