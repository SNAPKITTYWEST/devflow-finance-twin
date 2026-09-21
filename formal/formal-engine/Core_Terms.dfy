// ============================================================================
// formal-engine/Core/Terms.dfy
// Term representation and operations
// License: GPL 2.0
// ============================================================================

module Core.Terms {
  import opened Core.Types

  datatype Term =
    | Var(name: string, s: Sort)
    | Const(name: string, s: Sort)
    | LitInt(v: int)
    | LitBool(b: bool)
    | LitBV(v: int, w: nat)
    | App(op: string, args: seq<Term>, rs: Sort)
    | Primed(base: Term)
    | Old(expr: Term)

  predicate ValidTerm(t: Term) {
    match t
    case Var(_,s) => ValidSort(s)
    case Const(_,s) => ValidSort(s)
    case LitInt(_) => true
    case LitBool(_) => true
    case LitBV(_,w) => w > 0
    case App(_,args,rs) => ValidSort(rs) && forall i :: 0 <= i < |args| ==> ValidTerm(args[i])
    case Primed(b) => ValidTerm(b)
    case Old(e) => ValidTerm(e)
  }

  function TermSort(t: Term): Sort
    requires ValidTerm(t)
  {
    match t
    case Var(_,s) => s
    case Const(_,s) => s
    case LitInt(_) => INT
    case LitBool(_) => BOOL
    case LitBV(_,w) => BitVecSort(w)
    case App(_,_,rs) => rs
    case Primed(b) => TermSort(b)
    case Old(e) => TermSort(e)
  }

  function TermHash(t: Term): string
    requires ValidTerm(t)
  {
    match t
    case Var(n,s) => "var:" + n + ":" + SortHash(s)
    case Const(n,s) => "const:" + n + ":" + SortHash(s)
    case LitInt(_) => "litint"
    case LitBool(b) => if b then "litbool:1" else "litbool:0"
    case LitBV(_,w) => "litbv:" + NatStr(w)
    case App(op,_,rs) => "app:" + op + ":" + SortHash(rs)
    case Primed(b) => "primed:" + TermHash(b)
    case Old(e) => "old:" + TermHash(e)
  }

  function FreeVars(t: Term): set<string>
    requires ValidTerm(t)
  {
    match t
    case Var(n,_) => {n}
    case Const(_,_) | LitInt(_) | LitBool(_) | LitBV(_,_) => {}
    case App(_,args,_) => set i,v | 0 <= i < |args| && v in FreeVars(args[i]) :: v
    case Primed(b) => FreeVars(b)
    case Old(e) => FreeVars(e)
  }

  function MkVar(n: string, s: Sort): Term
    requires ValidSort(s)
    ensures ValidTerm(MkVar(n,s)) && TermSort(MkVar(n,s)) == s
  { Var(n,s) }

  function MkLitInt(v: int): Term
    ensures ValidTerm(MkLitInt(v)) && TermSort(MkLitInt(v)) == INT
  { LitInt(v) }

  function MkLitBool(b: bool): Term
    ensures ValidTerm(MkLitBool(b)) && TermSort(MkLitBool(b)) == BOOL
  { LitBool(b) }

  function MkPrimed(t: Term): Term
    requires ValidTerm(t)
    ensures ValidTerm(MkPrimed(t))
  { Primed(t) }

  function MkOld(t: Term): Term
    requires ValidTerm(t)
    ensures ValidTerm(MkOld(t))
  { Old(t) }

  function MkApp(op: string, args: seq<Term>, rs: Sort): Term
    requires ValidSort(rs) && forall i :: 0 <= i < |args| ==> ValidTerm(args[i])
    ensures ValidTerm(MkApp(op,args,rs))
  { App(op,args,rs) }

  lemma TermSort_valid(t: Term)
    requires ValidTerm(t)
    ensures ValidSort(TermSort(t))
  {}
}
