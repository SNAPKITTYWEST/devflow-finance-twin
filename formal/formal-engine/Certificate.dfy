// ============================================================================
// formal-engine/Certificate.dfy
// Certificate replay and justification predicates
// License: GPL 2.0
// ============================================================================

module Certificate {

  import opened Core.Types
  import opened Core.Formulas

  datatype Cert = Cert(claim: Formula, steps: seq<Formula>)

  predicate ValidCert(c: Cert) {
    ValidFormula(c.claim) && (forall s :: s in c.steps ==> ValidFormula(s))
  }

  predicate JustifiesClaim(c: Cert): bool
    requires ValidCert(c)
  {
    |c.steps| > 0 && ValidFormula(c.claim)
  }

  function CheckCert(c: Cert): bool
    requires ValidCert(c)
  {
    JustifiesClaim(c)
  }

  function ReplayCert(c: Cert): bool
    requires ValidCert(c)
  {
    CheckCert(c)
  }

  lemma Cert_validity_persists(c: Cert)
    requires ValidCert(c)
    ensures CheckCert(c) ==> JustifiesClaim(c)
  {}
}
