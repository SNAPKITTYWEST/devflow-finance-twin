// ============================================================================
// formal-engine/Contracts.dfy
// Method contracts and verification condition generation
// License: GPL 2.0
// ============================================================================

module Contracts {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas

  datatype Contract = Contract(
    name: string,
    requires: seq<Formula>,
    ensures: seq<Formula>
  )

  predicate ValidContract(c: Contract) {
    |c.name| > 0 &&
    (forall i :: 0 <= i < |c.requires| ==> ValidFormula(c.requires[i])) &&
    (forall i :: 0 <= i < |c.ensures| ==> ValidFormula(c.ensures[i]))
  }

  datatype VC = VC(label: string, formula: Formula)

  predicate ValidVC(v: VC) {
    |v.label| > 0 && ValidFormula(v.formula)
  }

  function GenerateVC(c: Contract, index: nat): VC
    requires ValidContract(c)
  {
    var pre := if |c.requires| > 0 then c.requires[0] else TrueF;
    var post := if |c.ensures| > 0 && index < |c.ensures| then c.ensures[index] else TrueF;
    VC(c.name + "_vc_" + NatStr(index), Implies(pre, post))
  }

  function GenerateAllVCs(c: Contract): seq<VC>
    requires ValidContract(c)
  {
    if |c.ensures| == 0 then
      [GenerateVC(c, 0)]
    else
      seq(|c.ensures|, i requires 0 <= i < |c.ensures| => GenerateVC(c, i))
  }

  function NatStr(n: nat): string {
    if n == 0 then "0"
    else if n < 10 then [n as char + '0']
    else NatStr(n / 10) + [((n % 10) as char) + '0']
  }

  lemma GenerateVCs_all_valid(c: Contract)
    requires ValidContract(c)
    ensures forall i :: 0 <= i < |GenerateAllVCs(c)| ==> ValidVC(GenerateAllVCs(c)[i])
  {}
}
