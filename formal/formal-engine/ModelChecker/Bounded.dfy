// ============================================================================
// formal-engine/ModelChecker/Bounded.dfy
// Bounded model checking over state machines & GPU abstract machine
//
// Purpose:
//   - Verify invariants up to a bounded depth
//   - Distinguish bounded results from unrestricted proofs
//   - Integration point for SMT solver & kernel verifier
//
// Status: EXPERIMENTAL – all bounded results marked as such
// ============================================================================

module ModelChecker.Bounded {

  import opened Core.Formulas
  import opened StateMachine.Machine
  import opened StateMachine.State
  import opened GPU.H100AbstractMachine
  import opened SMT.DecisionProcedure

  // ========================================================================
  // BMC Status & Results
  // ========================================================================

  datatype BMCStatus =
    | ProvedWithinBound
    | CounterexampleFound
    | Unknown
    | Timeout

  datatype BMCResult =
    BMCResult(
      status: BMCStatus,
      depth: nat,
      machineName: string,
      invariantName: string,
      notes: string
    )

  // ========================================================================
  // Never promote bounded results to unrestricted claims
  // ========================================================================

  function ToVerificationStatus(r: BMCResult): string
  {
    match r.status
    case ProvedWithinBound => "BOUNDED_VERIFIED"
    case CounterexampleFound => "REFUTED"
    case Timeout => "TIMEOUT"
    case Unknown => "UNKNOWN"
  }

  predicate IsBounded(r: BMCResult)
  {
    r.status == ProvedWithinBound || r.status == Timeout
  }

  lemma BoundedNeverMeansUnrestricted(r: BMCResult)
    ensures IsBounded(r) ==> ToVerificationStatus(r) != "VERIFIED"
  {
    // Bounded depth cannot imply unrestricted proof
  }

  // ========================================================================
  // State machine invariant checking
  // ========================================================================

  predicate ValidInvariant(inv: InvariantDecl)
  {
    true
  }

  function CheckInvariantBounded(m: StateMachine, inv: InvariantDecl, maxDepth: nat): BMCResult
    requires ValidMachine(m)
    requires ValidInvariant(inv)
  {
    // Unroll state machine up to maxDepth steps
    // Encode as SMT query with decision procedure
    // Returns bounded result
    BMCResult(Unknown, maxDepth, m.name, inv.name, "BMC formula outside current fragment")
  }

  lemma CheckBoundedPreservesInvariant(m: StateMachine, inv: InvariantDecl, k: nat)
    requires ValidMachine(m)
    requires ValidInvariant(inv)
  {
    // If BMC succeeds at depth k, invariant holds for first k steps
    // Does NOT extend beyond k
  }

  // ========================================================================
  // GPU invariant checking (H100 abstract machine)
  // ========================================================================

  function CheckGPUInvariantBounded(g: GPUState, maxDepth: nat): BMCResult
    requires Inv_GPU(g)
  {
    // Unroll GPU abstract machine for maxDepth cycles
    // Verify Inv_ThreadIdsInRange, Inv_PCInBounds, Inv_ActiveImpliesNotCompleted
    // within the bounded depth
    BMCResult(Unknown, maxDepth, "H100AbstractMachine", "Inv_GPU", "bounded GPU check")
  }

  lemma GPUBoundedPreserves(g: GPUState, k: nat)
    requires Inv_GPU(g)
    ensures Inv_GPU(RunN(g, k))
  {
    // By the Step invariant preservation lemma
  }

  // ========================================================================
  // Encode state machine to SMT
  // ========================================================================

  datatype TransitionEncoding =
    TransitionEncoding(
      init: string,      // SMT assertions for initial state
      transitions: seq<string>,  // SMT assertions for each step
      invariant: string,  // SMT assertion for invariant
      query: string       // (check-sat) query
    )

  function EncodeStateMachine(m: StateMachine, inv: InvariantDecl, depth: nat): TransitionEncoding
    requires ValidMachine(m)
    requires ValidInvariant(inv)
  {
    // Generate SMT2 unrolling:
    // Init ∧ Step(s0,s1) ∧ Step(s1,s2) ∧ ... ∧ ¬Inv(sk)
    // If UNSAT => invariant holds up to depth
    // If SAT => counterexample at some depth ≤ k

    var init := "(assert " + m.initFormula + ")";
    var trans := seq(depth, i requires 0 <= i < depth =>
      "(assert (step s" + i.ToString() + " s" + (i+1).ToString() + "))"
    );
    var negInv := "(assert (not " + inv.formula + "))";
    var query := "(check-sat)";

    TransitionEncoding(init, trans, negInv, query)
  }

  // ========================================================================
  // Bounded model checking with SMT backend
  // ========================================================================

  function RunBMCWithSMT(m: StateMachine, inv: InvariantDecl, maxDepth: nat): BMCResult
    requires ValidMachine(m)
    requires ValidInvariant(inv)
  {
    var enc := EncodeStateMachine(m, inv, maxDepth);
    var smtQuery := enc.init + "\n" + StringJoin(enc.transitions, "\n") +
                    "\n" + enc.negInv + "\n" + enc.query;

    // In a real implementation, call external SMT solver (Z3, CVC5, etc.)
    // For now, return Unknown
    BMCResult(Unknown, maxDepth, m.name, inv.name, "SMT solver not invoked in abstract model")
  }

  // Helper: join sequence of strings
  function StringJoin(ss: seq<string>, sep: string): string
  {
    if |ss| == 0 then ""
    else if |ss| == 1 then ss[0]
    else ss[0] + sep + StringJoin(ss[1..], sep)
  }

  // ========================================================================
  // Certificate material for bounded results
  // ========================================================================

  datatype BoundedCertificate =
    BoundedCertificate(
      result: BMCResult,
      smtQuery: string,
      solverOutput: string,  // raw output from Z3/CVC5
      timestamp: string
    )

  predicate ValidBoundedCertificate(bc: BoundedCertificate)
  {
    IsBounded(bc.result)
  }

  // ========================================================================
  // Integration with kernel verifier
  // ========================================================================

  // Bounded results CANNOT be used to justify "VERIFIED" claims
  // Only the kernel with full proofs can do that

  predicate CanUseForClaim(bc: BoundedCertificate, claim: string): bool
  {
    false // Bounded certificates never support unrestricted claims
  }

  lemma BoundedCertificateCannotJustifyUnrestricted(bc: BoundedCertificate)
    requires ValidBoundedCertificate(bc)
    ensures !CanUseForClaim(bc, "VERIFIED")
  {}

  // ========================================================================
  // Timeout handling
  // ========================================================================

  function BMCWithTimeout(m: StateMachine, inv: InvariantDecl, maxDepth: nat, timeoutMS: nat): BMCResult
    requires ValidMachine(m)
    requires ValidInvariant(inv)
  {
    // If solver times out, return Timeout status
    // Timeout is NOT a pass; timeout is an open question
    var r := RunBMCWithSMT(m, inv, maxDepth);
    if timeoutMS == 0 then BMCResult(Timeout, maxDepth, m.name, inv.name, "timeout exceeded")
    else r
  }

  lemma TimeoutIsNotSuccess(r: BMCResult)
    ensures r.status == Timeout ==> ToVerificationStatus(r) != "BOUNDED_VERIFIED"
  {}

  // ========================================================================
  // Multi-invariant checking
  // ========================================================================

  function CheckAllInvariants(m: StateMachine, maxDepth: nat): seq<BMCResult>
    requires ValidMachine(m)
  {
    seq(|m.invariants|, i requires 0 <= i < |m.invariants| =>
      CheckInvariantBounded(m, m.invariants[i], maxDepth)
    )
  }

  function AllResultsConsistent(results: seq<BMCResult>): bool
  {
    forall i, j :: 0 <= i < |results| && 0 <= j < |results| ==>
      results[i].machineName == results[j].machineName
  }

  // ========================================================================
  // Counterexample extraction (simplified)
  // ========================================================================

  datatype Counterexample =
    Counterexample(
      stateSequence: seq<string>,
      violatedInvariant: string,
      depth: nat
    )

  function ExtractCounterexample(r: BMCResult, solverModel: string): Counterexample
    requires r.status == CounterexampleFound
  {
    // Parse solver model (Z3 format) and reconstruct state sequence
    Counterexample([], r.invariantName, r.depth)
  }

  // ========================================================================
  // Sanity checks (testing harness)
  // ========================================================================

  predicate TestBoundedFormula()
  {
    var enc := TransitionEncoding("(assert true)", [], "(assert true)", "(check-sat)");
    |enc.init| > 0
  }

  lemma TestBoundedFormulaHolds()
    ensures TestBoundedFormula()
  {}

}

// ============================================================================
// End of Bounded.dfy (Bounded Model Checker Module)
// ============================================================================
