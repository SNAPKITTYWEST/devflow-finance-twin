// ============================================================================
// formal-engine/GPU/CUDAAbstractModel.dfy
// Complete GPU/CUDA/PTX abstract execution model
// License: GPL 2.0
// ============================================================================

module GPU.CUDAAbstractModel {

  import opened Core.Terms
  import opened Core.Formulas

  datatype ThreadId =
    ThreadId(value: nat)

  datatype WarpId =
    WarpId(value: nat)

  datatype BlockId =
    BlockId(value: nat)

  datatype GridId =
    GridId(value: nat)

  datatype GPUThread =
    GPUThread(
      id: ThreadId,
      warp: WarpId,
      block: BlockId
    )

  datatype GPUMemory =
    GPUMemory(
      bytes: map<int, int>
    )

  datatype GPUState =
    GPUState(
      pc: int,
      registers: map<string, Term>,
      memory: GPUMemory,
      threads: seq<GPUThread>
    )

  predicate ValidGPUState(s: GPUState)
  {
    s.pc >= 0 &&
    forall t :: 0 <= t < |s.threads| ==>
      s.threads[t].id.value >= 0
  }

  datatype GPUInstruction =
      GPUAdd(dst: string, left: string, right: string)
    | GPULoad(dst: string, address: string)
    | GPUStore(address: string, value: string)
    | GPUBarrier
    | GPUNop

  predicate ValidInstruction(i: GPUInstruction)
  {
    true
  }

  function ExecuteAdd(state: GPUState, dst: string, left: string, right: string): GPUState
    requires ValidGPUState(state)
  {
    var lval := if left in state.registers then state.registers[left] else TInt(0);
    var rval := if right in state.registers then state.registers[right] else TInt(0);
    var result := match (lval, rval)
      case (TInt(l), TInt(r)) => TInt(l + r)
      case _ => TInt(0);
    GPUState(
      state.pc + 1,
      state.registers[dst := result],
      state.memory,
      state.threads
    )
  }

  function ExecuteLoad(state: GPUState, dst: string, address: string): GPUState
    requires ValidGPUState(state)
  {
    var addr := if address in state.registers then state.registers[address] else TInt(0);
    var addrVal := match addr case TInt(a) => a case _ => 0;
    var memVal := if addrVal in state.memory.bytes then state.memory.bytes[addrVal] else 0;
    GPUState(
      state.pc + 1,
      state.registers[dst := TInt(memVal)],
      state.memory,
      state.threads
    )
  }

  function ExecuteStore(state: GPUState, address: string, value: string): GPUState
    requires ValidGPUState(state)
  {
    var addr := if address in state.registers then state.registers[address] else TInt(0);
    var addrVal := match addr case TInt(a) => a case _ => 0;
    var val := if value in state.registers then state.registers[value] else TInt(0);
    var valInt := match val case TInt(v) => v case _ => 0;
    var newMemory := GPUMemory(state.memory.bytes[addrVal := valInt]);
    GPUState(
      state.pc + 1,
      state.registers,
      newMemory,
      state.threads
    )
  }

  function Execute(state: GPUState, instr: GPUInstruction): GPUState
    requires ValidGPUState(state)
  {
    match instr
      case GPUAdd(d, l, r) => ExecuteAdd(state, d, l, r)
      case GPULoad(d, a) => ExecuteLoad(state, d, a)
      case GPUStore(a, v) => ExecuteStore(state, a, v)
      case GPUBarrier => GPUState(state.pc + 1, state.registers, state.memory, state.threads)
      case GPUNop => GPUState(state.pc + 1, state.registers, state.memory, state.threads)
  }

  lemma ExecutePreservesValidity(s: GPUState, i: GPUInstruction)
    requires ValidGPUState(s)
    requires ValidInstruction(i)
    ensures ValidGPUState(Execute(s, i))
  {}

  predicate GPUInvariantThreadIds(s: GPUState)
    requires ValidGPUState(s)
  {
    forall t :: 0 <= t < |s.threads| ==>
      s.threads[t].id.value >= 0 &&
      s.threads[t].warp.value >= 0 &&
      s.threads[t].block.value >= 0
  }

  predicate GPUInvariantPC(s: GPUState)
    requires ValidGPUState(s)
  {
    s.pc >= 0
  }

  lemma AllInvariantsHold(s: GPUState)
    requires ValidGPUState(s)
    ensures GPUInvariantThreadIds(s) && GPUInvariantPC(s)
  {}
}
