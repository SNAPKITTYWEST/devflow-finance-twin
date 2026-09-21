// ============================================================================
// formal-engine/Core/Types.dfy
// Core type definitions and sort system
// License: GPL 2.0
// ============================================================================

module Core.Types {
  datatype Sort =
    | BoolSort | IntSort | NatSort
    | BitVecSort(width: nat)
    | ArraySort(index: Sort, element: Sort)
    | TupleSort(components: seq<Sort>)
    | UninterpretedSort(name: string)

  predicate ValidSort(s: Sort) {
    match s
    case BitVecSort(w) => w > 0
    case ArraySort(i,e) => ValidSort(i) && ValidSort(e)
    case TupleSort(cs) => |cs| > 0 && forall i :: 0 <= i < |cs| ==> ValidSort(cs[i])
    case _ => true
  }

  function SortHash(s: Sort): string
    requires ValidSort(s)
  {
    match s
    case BoolSort => "sort:bool"
    case IntSort => "sort:int"
    case NatSort => "sort:nat"
    case BitVecSort(w) => "sort:bv:" + NatStr(w)
    case ArraySort(i,e) => "sort:array:" + SortHash(i) + ":" + SortHash(e)
    case TupleSort(_) => "sort:tuple"
    case UninterpretedSort(n) => "sort:uf:" + n
  }

  function NatStr(n: nat): string {
    if n == 0 then "0"
    else if n < 10 then [n as char + '0']
    else NatStr(n/10) + [(n%10) as char + '0']
  }

  const BOOL: Sort := BoolSort
  const INT: Sort := IntSort
  const NAT: Sort := NatSort

  lemma ValidBool() ensures ValidSort(BOOL) {}
  lemma ValidInt() ensures ValidSort(INT) {}
  lemma ValidNat() ensures ValidSort(NAT) {}
  lemma ValidBV(w: nat) requires w > 0 ensures ValidSort(BitVecSort(w)) {}
}
