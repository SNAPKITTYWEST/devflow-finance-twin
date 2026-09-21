// ============================================================================
// formal-engine/LLVM/AtomicRMWVerify.dfy
// Verification conditions for atomic RMW operations
// License: GPL 2.0
// ============================================================================

module LLVM.AtomicRMWVerify {

  import opened LLVM.AtomicRMW
  import opened LLVM.AtomicRMWProofs
  import opened Core.Terms
  import opened Core.Formulas

  // Verification condition: operation type consistency
  predicate VerifyOperationConsistency(ops: seq<AtomicRMWOp>)
  {
    forall i :: 0 <= i < |ops| ==> ValidAtomicOp(ops[i])
  }

  // Verification condition: pointer validity
  predicate VerifyPointerValidity(op: AtomicRMWOp, validAddrs: set<int>)
  {
    match op.ptr
      case TInt(addr) => addr in validAddrs
      case _ => false
  }

  // Verification condition: memory ordering constraints
  predicate VerifyOrderingConstraints(op1: AtomicRMWOp, op2: AtomicRMWOp)
  {
    // If op1 is Release, op2 must not violate acquire-release semantics
    (op1.ordering == Release ==> (op2.ordering == Acquire || op2.ordering == AcquireRelease || op2.ordering == SequentiallyConsistent))
    &&
    // Sequentially consistent dominates all
    (op1.ordering == SequentiallyConsistent ==> true)
    &&
    (op2.ordering == SequentiallyConsistent ==> true)
  }

  // Verification condition: atomicity of RMW
  predicate VerifyAtomicity(mem1: AtomicMemory, mem2: AtomicMemory, op: AtomicRMWOp)
  {
    // Between atomic operation, no intermediate state should exist
    // Memory can only change via the RMW operation
    match op.ptr
      case TInt(addr) =>
        var (expectedMem, _) := ExecuteAtomicRMW(mem1, op);
        // Updated address must match
        addr in mem2.bytes &&
        (expectedMem.bytes[addr] == mem2.bytes[addr])
      case _ => false
  }

  // Verification: no lost updates
  predicate VerifyNoLostUpdates(mem: AtomicMemory, ops: seq<AtomicRMWOp>)
  {
    |ops| > 0 ==>
      // For each Add operation, the total is accumulated
      (forall i :: 0 <= i < |ops| ==>
        ops[i].op == AtomicAdd ==> true)  // Placeholder
  }

  // Verification: consistency after synchronization point
  predicate VerifySynchronization(mem: AtomicMemory, syncOps: seq<AtomicRMWOp>)
  {
    // All sync operations must be SC or Release/Acquire
    forall i :: 0 <= i < |syncOps| ==>
      (syncOps[i].ordering == SequentiallyConsistent ||
       syncOps[i].ordering == Release ||
       syncOps[i].ordering == Acquire ||
       syncOps[i].ordering == AcquireRelease)
  }

  // Verification: linearizability
  predicate VerifyLinearizability(ops: seq<AtomicRMWOp>, ordering: seq<nat>)
    requires |ordering| == |ops|
    requires forall i, j :: 0 <= i < j < |ordering| ==>
              ordering[i] < ordering[j]
  {
    // Provided ordering respects causal dependencies
    true  // Placeholder
  }

  // Verification: stale reads impossible for SC
  predicate VerifyFreshReads(op: AtomicRMWOp, mem: AtomicMemory)
    requires op.ordering == SequentiallyConsistent
  {
    // Read returns value visible before the SC operation
    true  // Placeholder
  }

  // Verification wrapper
  predicate VerifyAtomicRMWCorrectness(
    mem: AtomicMemory,
    ops: seq<AtomicRMWOp>,
    validAddrs: set<int>
  )
  {
    MemoryOrderingConsistent(mem) &&
    VerifyOperationConsistency(ops) &&
    (forall i :: 0 <= i < |ops| ==> VerifyPointerValidity(ops[i], validAddrs)) &&
    (forall i, j :: 0 <= i < j < |ops| ==> VerifyOrderingConstraints(ops[i], ops[j]))
  }
}
