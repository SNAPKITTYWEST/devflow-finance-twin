// ============================================================================
// formal-engine/Contracts/VCGen.dfy
// Verification condition generation
// License: GPL 2.0
// ============================================================================

module Contracts.VCGen {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas
  import opened Contracts.Core

  datatype VCKind =
    | Postcondition
    | InvariantInit
    | InvariantPreservation
    | Assertion
    | DecreasesCheck

  datatype VerificationCondition =
    VerificationCondition(
      id: string,
      kind: VCKind,
      formula: Formula,
      origin: string
    )

  predicate ValidVC(vc: VerificationCondition)
  {
    |vc.id| > 0 && ValidFormula(vc.formula)
  }

  function GenerateVCs(c: MethodContract, body: Formula): seq<VerificationCondition>
    requires ValidMethodContract(c)
    requires ValidFormula(body)
    ensures forall i :: 0 <= i < |GenerateVCs(c, body)| ==> ValidVC(GenerateVCs(c, body)[i])
  {
    var pre := AllRequires(c);
    var post := AllEnsures(c);
    var main := MkImplies(MkAnd([pre, body]), post);
    var vc0 := VerificationCondition("VC_MAIN_" + c.name, Postcondition, main, c.name);
    [vc0]
  }
}
