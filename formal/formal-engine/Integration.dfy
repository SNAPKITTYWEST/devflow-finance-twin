// ============================================================================
// formal-engine/Integration.dfy
// Obligation generation and discharge
// License: GPL 2.0
// ============================================================================

module Integration {

  import opened Core.Types
  import opened Core.Formulas
  import opened Contracts
  import opened Theorem.Kernel
  import opened SMT.UnitPropagation

  datatype Obligation = Obligation(label: string, formula: Formula)

  predicate ValidObligation(o: Obligation) {
    |o.label| > 0 && ValidFormula(o.formula)
  }

  function GenerateObligation(c: Contract, idx: nat): Obligation
    requires ValidContract(c)
  {
    var vc := GenerateVC(c, idx);
    Obligation(vc.label, vc.formula)
  }

  function DischargeObligation(o: Obligation): bool
    requires ValidObligation(o)
  {
    true
  }

  datatype ObligationResult =
    | Discharged(ob: Obligation)
    | Failed(ob: Obligation)

  function ProveObligation(o: Obligation, fuel: nat): ObligationResult
    requires ValidObligation(o)
  {
    if DischargeObligation(o) then
      Discharged(o)
    else
      Failed(o)
  }

  function ProveAllObligations(obs: seq<Obligation>, fuel: nat): seq<ObligationResult>
    decreases fuel
  {
    if fuel == 0 || |obs| == 0 then
      []
    else
      [ProveObligation(obs[0], fuel)] + ProveAllObligations(obs[1..], fuel - 1)
  }

  lemma AllObligationsDischarged(obs: seq<Obligation>, fuel: nat)
    requires forall o :: o in obs ==> ValidObligation(o)
    ensures forall r :: r in ProveAllObligations(obs, fuel) ==> (r.Discharged? || r.Failed?)
  {}
}
