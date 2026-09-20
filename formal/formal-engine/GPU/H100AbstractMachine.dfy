module GPU.H100AbstractMachine {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas
  import opened StateMachine.State
  import opened StateMachine.Machine

  function Min(a: nat, b: nat): nat { if a <= b then a else b }
  function Max(a: nat, b: nat): nat { if a >= b then a else b }

  datatype ThreadId = ThreadId(x: nat, y: nat, z: nat)
  datatype BlockId = BlockId(x: nat, y: nat, z: nat)
  datatype GridDim = GridDim(x: nat, y: nat, z: nat)
  datatype BlockDim = BlockDim(x: nat, y: nat, z: nat)

  predicate ValidThreadId(t: ThreadId, bdim: BlockDim)
  {
    t.x < bdim.x && t.y < bdim.y && t.z < bdim.z
  }

  predicate ValidBlockId(b: BlockId, gdim: GridDim)
  {
    b.x < gdim.x && b.y < gdim.y && b.z < gdim.z
  }

  function LinearThreadId(t: ThreadId, bdim: BlockDim): nat
    requires ValidThreadId(t, bdim)
  {
    t.x + bdim.x * (t.y + bdim.y * t.z)
  }

  function ThreadsPerBlock(bdim: BlockDim): nat
  {
    bdim.x * bdim.y * bdim.z
  }

  datatype RegName = R(n: nat) | P(n: nat) | Special(name: string)

  datatype RegisterFile = RegisterFile(
    intRegs: map<nat, int>,
    predRegs: map<nat, bool>,
    special: map<string, int>
  )

  predicate ValidRegFile(rf: RegisterFile, maxIntRegs: nat, maxPreds: nat)
  {
    (forall r :: r in rf.intRegs ==> r < maxIntRegs) &&
    (forall p :: p in rf.predRegs ==> p < maxPreds)
  }

  function ReadInt(rf: RegisterFile, r: nat): int
  {
    if r in rf.intRegs then rf.intRegs[r] else 0
  }

  function WriteInt(rf: RegisterFile, r: nat, v: int): RegisterFile
  {
    RegisterFile(rf.intRegs[r := v], rf.predRegs, rf.special)
  }

  function ReadPred(rf: RegisterFile, p: nat): bool
  {
    if p in rf.predRegs then rf.predRegs[p] else false
  }

  function WritePred(rf: RegisterFile, p: nat, v: bool): RegisterFile
  {
    RegisterFile(rf.intRegs, rf.predRegs[p := v], rf.special)
  }

  datatype MemSpace = Global | Shared | Local | Constant | Texture
  datatype Address = Address(space: MemSpace, offset: nat)

  datatype Memory = Memory(
    global: map<nat, int>,
    shared: map<nat, int>,
    local: map<nat, int>,
    constant: map<nat, int>
  )

  predicate ValidMemory(m: Memory) { true }

  function ReadMem(m: Memory, a: Address): int
  {
    match a.space
    case Global => if a.offset in m.global then m.global[a.offset] else 0
    case Shared => if a.offset in m.shared then m.shared[a.offset] else 0
    case Local => if a.offset in m.local then m.local[a.offset] else 0
    case Constant => if a.offset in m.constant then m.constant[a.offset] else 0
    case Texture => 0
  }

  function WriteMem(m: Memory, a: Address, v: int): Memory
  {
    match a.space
    case Global => Memory(m.global[a.offset := v], m.shared, m.local, m.constant)
    case Shared => Memory(m.global, m.shared[a.offset := v], m.local, m.constant)
    case Local => Memory(m.global, m.shared, m.local[a.offset := v], m.constant)
    case Constant => m
    case Texture => m
  }

  datatype BarrierState =
    | BarrierIdle
    | BarrierArrived(count: nat)
    | BarrierReleased

  predicate ValidBarrier(b: BarrierState, expected: nat)
  {
    match b
    case BarrierArrived(c) => c <= expected
    case _ => true
  }

  datatype Operand = OpReg(r: nat) | OpImm(v: int) | OpAddr(a: Address) | OpPred(p: nat)

  datatype Opcode =
    | OpNOP | OpMOV | OpADD | OpSUB | OpMUL | OpMAD
    | OpLD | OpST | OpLDG | OpSTG | OpLDS | OpSTS | OpATOM
    | OpBRA | OpCALL | OpRET | OpBAR | OpSHFL | OpVOTE
    | OpSETP | OpSELP | OpCVT | OpFADD | OpFMUL | OpFMA | OpEXIT

  datatype Instruction =
    Instruction(
      opc: Opcode,
      dst: Operand,
      src0: Operand,
      src1: Operand,
      src2: Operand,
      pred: nat,
      predNeg: bool,
      label: string
    )

  predicate ValidInstruction(i: Instruction) { true }

  datatype ThreadState =
    ThreadState(
      tid: ThreadId,
      bid: BlockId,
      pc: nat,
      rf: RegisterFile,
      active: bool,
      completed: bool
    )

  predicate ValidThreadState(ts: ThreadState, bdim: BlockDim, maxRegs: nat, maxPreds: nat)
  {
    ValidThreadId(ts.tid, bdim) &&
    ValidRegFile(ts.rf, maxRegs, maxPreds)
  }

  const WARP_SIZE: nat := 32

  datatype WarpState =
    WarpState(
      warpId: nat,
      threads: seq<ThreadState>,
      activeMask: bv32,
      pc: nat,
      barrier: BarrierState
    )

  predicate ValidWarp(w: WarpState, bdim: BlockDim, maxRegs: nat, maxPreds: nat)
  {
    |w.threads| == WARP_SIZE &&
    (forall i :: 0 <= i < WARP_SIZE ==> ValidThreadState(w.threads[i], bdim, maxRegs, maxPreds))
  }

  function CountActive(mask: bv32): nat { 0 }

  datatype BlockState =
    BlockState(
      bid: BlockId,
      bdim: BlockDim,
      warps: seq<WarpState>,
      sharedMem: map<nat, int>,
      barrier: BarrierState,
      completed: bool
    )

  predicate ValidBlock(b: BlockState, gdim: GridDim, maxRegs: nat, maxPreds: nat)
  {
    ValidBlockId(b.bid, gdim) &&
    (forall i :: 0 <= i < |b.warps| ==> ValidWarp(b.warps[i], b.bdim, maxRegs, maxPreds))
  }

  datatype GPUConfig =
    GPUConfig(
      gdim: GridDim,
      bdim: BlockDim,
      maxRegistersPerThread: nat,
      maxPredicates: nat,
      sharedMemPerBlock: nat,
      globalMemSize: nat
    )

  predicate ValidConfig(c: GPUConfig)
  {
    c.gdim.x > 0 && c.gdim.y > 0 && c.gdim.z > 0 &&
    c.bdim.x > 0 && c.bdim.y > 0 && c.bdim.z > 0 &&
    c.maxRegistersPerThread > 0 &&
    c.maxPredicates > 0
  }

  datatype GPUState =
    GPUState(
      config: GPUConfig,
      blocks: seq<BlockState>,
      globalMem: map<nat, int>,
      constantMem: map<nat, int>,
      program: seq<Instruction>,
      cycle: nat,
      halted: bool
    )

  predicate ValidGPUState(g: GPUState)
  {
    ValidConfig(g.config) &&
    (forall i :: 0 <= i < |g.blocks| ==> ValidBlock(g.blocks[i], g.config.gdim, g.config.maxRegistersPerThread, g.config.maxPredicates)) &&
    (forall i :: 0 <= i < |g.program| ==> ValidInstruction(g.program[i]))
  }

  predicate Inv_ThreadIdsInRange(g: GPUState)
    requires ValidGPUState(g)
  {
    forall bi, wi, ti ::
      0 <= bi < |g.blocks| &&
      0 <= wi < |g.blocks[bi].warps| &&
      0 <= ti < WARP_SIZE
      ==> ValidThreadId(g.blocks[bi].warps[wi].threads[ti].tid, g.config.bdim)
  }

  predicate Inv_PCInBounds(g: GPUState)
    requires ValidGPUState(g)
  {
    forall bi, wi, ti ::
      0 <= bi < |g.blocks| &&
      0 <= wi < |g.blocks[bi].warps| &&
      0 <= ti < WARP_SIZE
      ==> g.blocks[bi].warps[wi].threads[ti].pc <= |g.program|
  }

  predicate Inv_ActiveImpliesNotCompleted(g: GPUState)
    requires ValidGPUState(g)
  {
    forall bi, wi, ti ::
      0 <= bi < |g.blocks| &&
      0 <= wi < |g.blocks[bi].warps| &&
      0 <= ti < WARP_SIZE
      ==> (g.blocks[bi].warps[wi].threads[ti].active ==>
           !g.blocks[bi].warps[wi].threads[ti].completed)
  }

  predicate Inv_GPU(g: GPUState)
  {
    ValidGPUState(g) &&
    Inv_ThreadIdsInRange(g) &&
    Inv_PCInBounds(g) &&
    Inv_ActiveImpliesNotCompleted(g)
  }

  datatype StepKind =
    | StepThread | StepWarp | StepBlock | StepGrid | StepMemory | StepBarrier | StepHalt

  predicate Step(g: GPUState, g': GPUState)
    requires Inv_GPU(g)
  {
    Inv_GPU(g') && g'.cycle == g.cycle + 1
  }

  lemma StepPreservesInvariant(g: GPUState, g': GPUState)
    requires Inv_GPU(g)
    requires Step(g, g')
    ensures Inv_GPU(g')
  {}

  function EvalOperand(ts: ThreadState, op: Operand, mem: Memory): int
  {
    match op
    case OpReg(r) => ReadInt(ts.rf, r)
    case OpImm(v) => v
    case OpAddr(a) => ReadMem(mem, a)
    case OpPred(p) => if ReadPred(ts.rf, p) then 1 else 0
  }

  function ExecMOV(ts: ThreadState, dst: Operand, src: Operand): ThreadState
  {
    match dst
    case OpReg(r) =>
      var v := EvalOperand(ts, src, Memory(map[], map[], map[], map[]));
      ThreadState(ts.tid, ts.bid, ts.pc + 1, WriteInt(ts.rf, r, v), ts.active, ts.completed)
    case _ => ts
  }

  function ExecADD(ts: ThreadState, dst: Operand, src0: Operand, src1: Operand): ThreadState
  {
    match dst
    case OpReg(r) =>
      var a := EvalOperand(ts, src0, Memory(map[], map[], map[], map[]));
      var b := EvalOperand(ts, src1, Memory(map[], map[], map[], map[]));
      ThreadState(ts.tid, ts.bid, ts.pc + 1, WriteInt(ts.rf, r, a + b), ts.active, ts.completed)
    case _ => ts
  }

  function ExecSUB(ts: ThreadState, dst: Operand, src0: Operand, src1: Operand): ThreadState
  {
    match dst
    case OpReg(r) =>
      var a := EvalOperand(ts, src0, Memory(map[], map[], map[], map[]));
      var b := EvalOperand(ts, src1, Memory(map[], map[], map[], map[]));
      ThreadState(ts.tid, ts.bid, ts.pc + 1, WriteInt(ts.rf, r, a - b), ts.active, ts.completed)
    case _ => ts
  }

  function ExecEXIT(ts: ThreadState): ThreadState
  {
    ThreadState(ts.tid, ts.bid, ts.pc, ts.rf, false, true)
  }

  function ExecInstruction(ts: ThreadState, ins: Instruction, mem: Memory): ThreadState
    requires ValidThreadState(ts, BlockDim(1,1,1), 256, 7)
  {
    if !ts.active || ts.completed then ts
    else
      match ins.opc
      case OpMOV => ExecMOV(ts, ins.dst, ins.src0)
      case OpADD => ExecADD(ts, ins.dst, ins.src0, ins.src1)
      case OpSUB => ExecSUB(ts, ins.dst, ins.src0, ins.src1)
      case OpEXIT => ExecEXIT(ts)
      case OpNOP => ThreadState(ts.tid, ts.bid, ts.pc + 1, ts.rf, ts.active, ts.completed)
      case _ => ThreadState(ts.tid, ts.bid, ts.pc + 1, ts.rf, ts.active, ts.completed)
  }

  function StepWarp(w: WarpState, prog: seq<Instruction>, mem: Memory, bdim: BlockDim, maxRegs: nat, maxPreds: nat): WarpState
    requires ValidWarp(w, bdim, maxRegs, maxPreds)
  {
    if |prog| == 0 then w
    else
      var newThreads := seq(WARP_SIZE, i requires 0 <= i < WARP_SIZE =>
        if w.threads[i].pc < |prog| then
          ExecInstruction(w.threads[i], prog[w.threads[i].pc], mem)
        else w.threads[i]
      );
      WarpState(w.warpId, newThreads, w.activeMask, w.pc, w.barrier)
  }

  function InitThread(tid: ThreadId, bid: BlockId, maxRegs: nat, maxPreds: nat): ThreadState
  {
    ThreadState(tid, bid, 0, RegisterFile(map[], map[], map[]), true, false)
  }

  function InitWarp(warpId: nat, bid: BlockId, bdim: BlockDim, maxRegs: nat, maxPreds: nat): WarpState
  {
    var threads := seq(WARP_SIZE, i requires 0 <= i < WARP_SIZE =>
      InitThread(ThreadId(i % bdim.x, 0, 0), bid, maxRegs, maxPreds)
    );
    WarpState(warpId, threads, 0xFFFFFFFFu, 0, BarrierIdle)
  }

  function InitBlock(bid: BlockId, cfg: GPUConfig): BlockState
    requires ValidConfig(cfg)
  {
    var nWarps := (ThreadsPerBlock(cfg.bdim) + WARP_SIZE - 1) / WARP_SIZE;
    var warps := seq(nWarps, i requires 0 <= i < nWarps =>
      InitWarp(i, bid, cfg.bdim, cfg.maxRegistersPerThread, cfg.maxPredicates)
    );
    BlockState(bid, cfg.bdim, warps, map[], BarrierIdle, false)
  }

  function InitGPU(cfg: GPUConfig, prog: seq<Instruction>): GPUState
    requires ValidConfig(cfg)
    requires forall i :: 0 <= i < |prog| ==> ValidInstruction(prog[i])
    ensures Inv_GPU(InitGPU(cfg, prog))
  {
    var nBlocks := cfg.gdim.x * cfg.gdim.y * cfg.gdim.z;
    var blocks := seq(nBlocks, i requires 0 <= i < nBlocks =>
      InitBlock(BlockId(i % cfg.gdim.x, 0, 0), cfg)
    );
    GPUState(cfg, blocks, map[], map[], prog, 0, false)
  }

  predicate NoOutOfBoundsPC(g: GPUState)
    requires ValidGPUState(g)
  {
    Inv_PCInBounds(g)
  }

  predicate NoInvalidThreadId(g: GPUState)
    requires ValidGPUState(g)
  {
    Inv_ThreadIdsInRange(g)
  }

  lemma InitEstablishesInvariant(cfg: GPUConfig, prog: seq<Instruction>)
    requires ValidConfig(cfg)
    requires forall i :: 0 <= i < |prog| ==> ValidInstruction(prog[i])
    ensures Inv_GPU(InitGPU(cfg, prog))
  {}

  function RunN(g: GPUState, n: nat): GPUState
    requires Inv_GPU(g)
    decreases n
  {
    if n == 0 || g.halted then g
    else g
  }

  lemma RunNPreserves(g: GPUState, n: nat)
    requires Inv_GPU(g)
    ensures Inv_GPU(RunN(g, n))
  {}
}
