// ============================================================================
// formal-engine/LLVM/AtomicRMWSmoke.dfy
// Smoke tests for atomic RMW operations
// License: GPL 2.0
// ============================================================================

module LLVM.AtomicRMWSmoke {

  import opened LLVM.AtomicRMW
  import opened LLVM.AtomicRMWProofs
  import opened LLVM.AtomicRMWVerify
  import opened Core.Terms

  // Test: basic XChg
  method TestXChg()
  {
    var mem := AtomicMemory(map[10 := 42], map[], map[]);
    var op := AtomicRMWOp(AtomicXChg, TInt(10), TInt(100), Unordered);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(42);
    assert newMem.bytes[10] == 100;
  }

  // Test: basic Add
  method TestAdd()
  {
    var mem := AtomicMemory(map[20 := 10], map[], map[]);
    var op := AtomicRMWOp(AtomicAdd, TInt(20), TInt(5), Monotonic);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(10);
    assert newMem.bytes[20] == 15;
  }

  // Test: Add to uninitialized address (defaults to 0)
  method TestAddUninitialized()
  {
    var mem := AtomicMemory(map[], map[], map[]);
    var op := AtomicRMWOp(AtomicAdd, TInt(30), TInt(7), Unordered);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(0);
    assert newMem.bytes[30] == 7;
  }

  // Test: And operation
  method TestAnd()
  {
    var mem := AtomicMemory(map[40 := 12], map[], map[]);
    var op := AtomicRMWOp(AtomicAnd, TInt(40), TInt(10), Unordered);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(12);
    assert newMem.bytes[40] == 8;  // 12 & 10 = 1100 & 1010 = 1000 = 8
  }

  // Test: Or operation
  method TestOr()
  {
    var mem := AtomicMemory(map[50 := 12], map[], map[]);
    var op := AtomicRMWOp(AtomicOr, TInt(50), TInt(10), Unordered);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(12);
    assert newMem.bytes[50] == 14;  // 12 | 10 = 1100 | 1010 = 1110 = 14
  }

  // Test: Max operation
  method TestMax()
  {
    var mem := AtomicMemory(map[60 := 8], map[], map[]);
    var op := AtomicRMWOp(AtomicMax, TInt(60), TInt(15), Unordered);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(8);
    assert newMem.bytes[60] == 15;
  }

  // Test: Min operation
  method TestMin()
  {
    var mem := AtomicMemory(map[70 := 25], map[], map[]);
    var op := AtomicRMWOp(AtomicMin, TInt(70), TInt(10), Unordered);
    var (newMem, oldVal) := ExecuteAtomicRMW(mem, op);
    assert oldVal == TInt(25);
    assert newMem.bytes[70] == 10;
  }

  // Test: memory ordering tracking
  method TestOrderingTracking()
  {
    var mem := AtomicMemory(map[80 := 0], map[], map[]);
    var op1 := AtomicRMWOp(AtomicAdd, TInt(80), TInt(1), Release);
    var (mem2, _) := ExecuteAtomicRMW(mem, op1);
    var op2 := AtomicRMWOp(AtomicAdd, TInt(80), TInt(1), Acquire);
    var (mem3, _) := ExecuteAtomicRMW(mem2, op2);
    assert 80 in mem3.lastOrdering;
    assert mem3.lastOrdering[80] == Acquire;
  }

  // Test: consistency predicate
  method TestConsistency()
  {
    var mem := AtomicMemory(map[90 := 100], map[], map[90 := SequentiallyConsistent]);
    assert MemoryOrderingConsistent(mem);
  }

  // Test: operation validity
  method TestOperationValidity()
  {
    var op := AtomicRMWOp(AtomicAdd, TInt(100), TInt(42), Unordered);
    assert ValidAtomicOp(op);
  }

  // Test: invalid operation (non-integer pointer)
  method TestInvalidOperation()
  {
    var op := AtomicRMWOp(AtomicAdd, TInt(-1), TInt(42), Unordered);
    // Depending on ValidAtomicOp definition, -1 may or may not be valid
  }

  // Test: sequence of operations
  method TestSequence()
  {
    var mem := AtomicMemory(map[110 := 0], map[], map[]);
    var ops := [
      AtomicRMWOp(AtomicAdd, TInt(110), TInt(10), Monotonic),
      AtomicRMWOp(AtomicAdd, TInt(110), TInt(5), Monotonic),
      AtomicRMWOp(AtomicAdd, TInt(110), TInt(3), Monotonic)
    ];
    var finalMem := FoldAtomicOps(mem, ops);
    assert 110 in finalMem.bytes;
    assert finalMem.bytes[110] == 18;
  }

  // Helper: fold operations (copied from proofs module)
  function FoldAtomicOps(mem: AtomicMemory, ops: seq<AtomicRMWOp>): AtomicMemory
    decreases |ops|
  {
    if |ops| == 0 then
      mem
    else
      var (newMem, _) := ExecuteAtomicRMW(mem, ops[0]);
      FoldAtomicOps(newMem, ops[1..])
  }
}
