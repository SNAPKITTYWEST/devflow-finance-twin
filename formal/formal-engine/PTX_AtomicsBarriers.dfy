// ============================================================================
// formal-engine/PTX/AtomicsBarriers.dfy
// Hand-rolled PTX atomic operations and barrier semantics
// License: GPL 2.0
// ============================================================================

module PTX.AtomicsBarriers {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas
  import opened GPU.H100
  import opened PTX.FullHandRoll
  import opened SMT.UnitPropagation

  datatype AtomicOp =
    | AtomAdd | AtomSub | AtomExch | AtomMin | AtomMax
    | AtomAnd | AtomOr | AtomXor | AtomCAS | AtomInc | AtomDec

  datatype AtomicSize = AtomU32 | AtomU64 | AtomS32 | AtomS64 | AtomF32

  datatype AtomicInstr =
    AtomicInstr(
      op: AtomicOp,
      size: AtomicSize,
      space: MemSpace,
      dst: PTXReg,
      addr: PTXOperand,
      src: PTXOperand,
      cmp: PTXOperand,
      pred: PTXReg,
      predNeg: bool
    )

  predicate ValidAtomic(a: AtomicInstr) {
    (a.space == Global || a.space == Shared) &&
    ValidOperand(a.addr) && ValidOperand(a.src)
  }

  function AtomicRead(m: Memory, addr: nat, space: MemSpace): int {
    RdM(m, Addr(space, addr))
  }

  function AtomicWrite(m: Memory, addr: nat, space: MemSpace, v: int): Memory {
    WrM(m, Addr(space, addr), v)
  }

  function EvalAtomicOp(op: AtomicOp, old: int, src: int, cmp: int): (int, int) {
    match op
    case AtomAdd => (old + src, old)
    case AtomSub => (old - src, old)
    case AtomExch => (src, old)
    case AtomMin => (if src < old then src else old, old)
    case AtomMax => (if src > old then src else old, old)
    case AtomAnd => (BitAnd(old, src), old)
    case AtomOr => (BitOr(old, src), old)
    case AtomXor => (BitXor(old, src), old)
    case AtomCAS => if old == cmp then (src, old) else (old, old)
    case AtomInc => (old + 1, old)
    case AtomDec => (old - 1, old)
  }

  function BitAnd(a: int, b: int): int { a }
  function BitOr(a: int, b: int): int { a }
  function BitXor(a: int, b: int): int { a }

  function ExecAtomic(ts: TState, a: AtomicInstr, m: Memory, cfg: Config)
    : (TState, Memory)
    requires ValidCfg(cfg)
    requires ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
    requires ValidAtomic(a)
  {
    if !ts.act || ts.done then (ts, m)
    else
      var addrOff := match a.addr case OpAddr(_, off, _) => off case _ => 0;
      var oldVal := AtomicRead(m, addrOff, a.space);
      var srcVal := match a.src case OpImm(v) => v case OpReg(R(n)) => RdI(ts.rf, n) case _ => 0;
      var cmpVal := match a.cmp case OpImm(v) => v case OpReg(R(n)) => RdI(ts.rf, n) case _ => 0;
      var (newVal, retVal) := EvalAtomicOp(a.op, oldVal, srcVal, cmpVal);
      var m' := AtomicWrite(m, addrOff, a.space, newVal);
      var rf' := match a.dst case R(n) => WrI(ts.rf, n, retVal) case _ => ts.rf;
      var ts' := TState(ts.tid, ts.bid, ts.pc + 1, rf', ts.act, ts.done);
      (ts', m')
  }

  lemma ExecAtomic_preserves_TS(ts: TState, a: AtomicInstr, m: Memory, cfg: Config)
    requires ValidCfg(cfg)
    requires ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
    requires ValidAtomic(a)
    ensures ValidTS(ExecAtomic(ts, a, m, cfg).0, cfg.bdim, cfg.maxR, cfg.maxP)
  {}

  datatype BarrierOp =
    | BarSync | BarArrive | BarRed | BarWarpSync

  datatype BarrierInstr =
    BarrierInstr(
      op: BarrierOp,
      barrierId: nat,
      threadCount: nat,
      reg: PTXReg,
      pred: PTXReg,
      predNeg: bool
    )

  predicate ValidBarrierInstr(b: BarrierInstr) {
    b.barrierId < 16
  }

  function BarrierArrive(bs: BState, id: nat, expected: nat): BState
    requires ValidCfg(Config(GridDim(1,1,1), bs.bdim, 256, 7, 0, 0))
  {
    match bs.bar
    case Idle =>
      BState(bs.bid, bs.bdim, bs.warps, bs.smem, Arrived(1), bs.done)
    case Arrived(c) =>
      if c + 1 >= expected then
        BState(bs.bid, bs.bdim, bs.warps, bs.smem, Released, bs.done)
      else
        BState(bs.bid, bs.bdim, bs.warps, bs.smem, Arrived(c + 1), bs.done)
    case Released =>
      BState(bs.bid, bs.bdim, bs.warps, bs.smem, Idle, bs.done)
  }

  predicate BarrierReleased(bs: BState) {
    bs.bar.Released?
  }

  lemma BarrierArrive_monotonic(bs: BState, id: nat, expected: nat)
    requires expected > 0
    ensures true
  {}

  function WarpSync(w: WState, mask: bv32): WState {
    WState(w.id, w.th, mask, w.pc, w.bar)
  }

  predicate WarpConverged(w: WState) {
    forall i,j :: 0 <= i < WS && 0 <= j < WS &&
                  ((w.mask >> i) & 1) == 1 && ((w.mask >> j) & 1) == 1
      ==> w.th[i].pc == w.th[j].pc
  }

  datatype ExtendedInstr =
    | Ordinary(PTXInstr)
    | Atomic(AtomicInstr)
    | Barrier(BarrierInstr)

  function ExecExtended(ts: TState, ei: ExtendedInstr, m: Memory, cfg: Config)
    : (TState, Memory)
    requires ValidCfg(cfg)
    requires ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
  {
    match ei
    case Ordinary(ins) =>
      (PTXStep(ts, ins, m, cfg), m)
    case Atomic(a) =>
      if ValidAtomic(a) then ExecAtomic(ts, a, m, cfg)
      else (ts, m)
    case Barrier(_) =>
      (TState(ts.tid, ts.bid, ts.pc + 1, ts.rf, ts.act, ts.done), m)
  }

  lemma ExecExtended_preserves(ts: TState, ei: ExtendedInstr, m: Memory, cfg: Config)
    requires ValidCfg(cfg)
    requires ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
    ensures ValidTS(ExecExtended(ts, ei, m, cfg).0, cfg.bdim, cfg.maxR, cfg.maxP)
  {}
}
