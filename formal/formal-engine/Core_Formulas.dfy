// ============================================================================
// formal-engine/Core/Formulas.dfy
// Formula representation and semantics
// License: GPL 2.0
// ============================================================================

module Core.Formulas {
  import opened Core.Types
  import opened Core.Terms

  datatype Formula =
    | TrueF | FalseF
    | Atom(t: Term)
    | Not(f: Formula)
    | And(args: seq<Formula>)
    | Or(args: seq<Formula>)
    | Implies(a: Formula, c: Formula)
    | Iff(l: Formula, r: Formula)
    | Forall(bs: seq<Term>, body: Formula)
    | Exists(bs: seq<Term>, body: Formula)

  predicate ValidFormula(f: Formula) {
    match f
    case TrueF | FalseF => true
    case Atom(t) => ValidTerm(t) && TermSort(t) == BOOL
    case Not(g) => ValidFormula(g)
    case And(args) => forall i :: 0 <= i < |args| ==> ValidFormula(args[i])
    case Or(args) => forall i :: 0 <= i < |args| ==> ValidFormula(args[i])
    case Implies(a,c) => ValidFormula(a) && ValidFormula(c)
    case Iff(l,r) => ValidFormula(l) && ValidFormula(r)
    case Forall(bs,body) =>
      (forall i :: 0 <= i < |bs| ==> ValidTerm(bs[i]) && bs[i].Var?) && ValidFormula(body)
    case Exists(bs,body) =>
      (forall i :: 0 <= i < |bs| ==> ValidTerm(bs[i]) && bs[i].Var?) && ValidFormula(body)
  }

  function FormulaHash(f: Formula): string
    requires ValidFormula(f)
  {
    match f
    case TrueF => "T"
    case FalseF => "F"
    case Atom(t) => "A:" + TermHash(t)
    case Not(g) => "N:" + FormulaHash(g)
    case And(_) => "And"
    case Or(_) => "Or"
    case Implies(a,c) => "I:" + FormulaHash(a) + ":" + FormulaHash(c)
    case Iff(_,_) => "Iff"
    case Forall(_,b) => "All:" + FormulaHash(b)
    case Exists(_,b) => "Ex:" + FormulaHash(b)
  }

  function Normalize(f: Formula): Formula
    requires ValidFormula(f)
    ensures ValidFormula(Normalize(f))
  {
    match f
    case Not(Not(g)) => Normalize(g)
    case Not(TrueF) => FalseF
    case Not(FalseF) => TrueF
    case And(args) if |args| == 0 => TrueF
    case And(args) if |args| == 1 => Normalize(args[0])
    case Or(args) if |args| == 0 => FalseF
    case Or(args) if |args| == 1 => Normalize(args[0])
    case Implies(TrueF,c) => Normalize(c)
    case Implies(FalseF,_) => TrueF
    case Implies(_,TrueF) => TrueF
    case _ => f
  }

  function MkAtom(t: Term): Formula
    requires ValidTerm(t) && TermSort(t) == BOOL
    ensures ValidFormula(MkAtom(t))
  { Atom(t) }

  function MkNot(f: Formula): Formula
    requires ValidFormula(f)
    ensures ValidFormula(MkNot(f))
  { Not(f) }

  function MkAnd(fs: seq<Formula>): Formula
    requires forall i :: 0 <= i < |fs| ==> ValidFormula(fs[i])
    ensures ValidFormula(MkAnd(fs))
  { And(fs) }

  function MkOr(fs: seq<Formula>): Formula
    requires forall i :: 0 <= i < |fs| ==> ValidFormula(fs[i])
    ensures ValidFormula(MkOr(fs))
  { Or(fs) }

  function MkImplies(a: Formula, c: Formula): Formula
    requires ValidFormula(a) && ValidFormula(c)
    ensures ValidFormula(MkImplies(a,c))
  { Implies(a,c) }

  function MkEq(t1: Term, t2: Term): Formula
    requires ValidTerm(t1) && ValidTerm(t2) && TermSort(t1) == TermSort(t2)
    ensures ValidFormula(MkEq(t1,t2))
  { Atom(App("=", [t1,t2], BOOL)) }

  function MkLe(t1: Term, t2: Term): Formula
    requires ValidTerm(t1) && ValidTerm(t2) && TermSort(t1) == INT && TermSort(t2) == INT
    ensures ValidFormula(MkLe(t1,t2))
  { Atom(App("<=", [t1,t2], BOOL)) }

  function MkGe(t1: Term, t2: Term): Formula
    requires ValidTerm(t1) && ValidTerm(t2) && TermSort(t1) == INT && TermSort(t2) == INT
    ensures ValidFormula(MkGe(t1,t2))
  { Atom(App(">=", [t1,t2], BOOL)) }

  function MkLt(t1: Term, t2: Term): Formula
    requires ValidTerm(t1) && ValidTerm(t2) && TermSort(t1) == INT && TermSort(t2) == INT
    ensures ValidFormula(MkLt(t1,t2))
  { Atom(App("<", [t1,t2], BOOL)) }

  lemma Normalize_idem(f: Formula)
    requires ValidFormula(f)
    ensures Normalize(Normalize(f)) == Normalize(f)
  {}
}
