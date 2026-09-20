// ============================================================================
// formal-engine/GPU/H100.dfy
// NVIDIA H100 abstract machine model
// License: GPL 2.0
// ============================================================================

module GPU.H100 {
  import opened Core.Types
  import opened Core.Formulas

  datatype ThreadId = ThreadId(x: nat, y: nat, z: nat)
  datatype BlockId = BlockId(x: nat, y: nat, z: nat)
  datatype GridDim = GridDim(x: nat, y: nat, z: nat)
  datatype BlockDim = BlockDim(x: nat, y: nat, z: nat)

  predicate ValidTid(t: ThreadId, b: BlockDim) {
    t.x < b.x && t.y < b.y && t.z < b.z
  }
  predicate ValidBid(b: BlockId, g: GridDim) {
    b.x < g.x && b.y < g.y && b.z < g.z
  }

  function LinTid(t: ThreadId, b: BlockDim): nat
    requires ValidTid(t,b)
  { t.x + b.x*(t.y + b.y*t.z) }

  function TPB(b: BlockDim): nat { b.x*b.y*b.z }

  datatype RegFile = RegFile(ints: map<nat,int>, preds: map<nat,bool>)
  predicate ValidRF(rf: RegFile, mr: nat, mp: nat) {
    (forall r :: r in rf.ints ==> r < mr) && (forall p :: p in rf.preds ==> p < mp)
  }

  function RdI(rf: RegFile, r: nat): int { if r in rf.ints then rf.ints[r] else 0 }
  function WrI(rf: RegFile, r: nat, v: int): RegFile { RegFile(rf.ints[r:=v], rf.preds) }
  function RdP(rf: RegFile, p: nat): bool { if p in rf.preds then rf.preds[p] else false }
  function WrP(rf: RegFile, p: nat, v: bool): RegFile { RegFile(rf.ints, rf.preds[p:=v]) }

  datatype MemSpace = Global | Shared | Local | Constant
  datatype Addr = Addr(sp: MemSpace, off: nat)
  datatype Memory = Memory(g: map<nat,int>, s: map<nat,int>, l: map<nat,int>, c: map<nat,int>)

  function RdM(m: Memory, a: Addr): int {
    match a.sp
    case Global => if a.off in m.g then m.g[a.off] else 0
    case Shared => if a.off in m.s then m.s[a.off] else 0
    case Local => if a.off in m.l then m.l[a.off] else 0
    case Constant => if a.off in m.c then m.c[a.off] else 0
  }

  function WrM(m: Memory, a: Addr, v: int): Memory {
    match a.sp
    case Global => Memory(m.g[a.off:=v], m.s, m.l, m.c)
    case Shared => Memory(m.g, m.s[a.off:=v], m.l, m.c)
    case Local => Memory(m.g, m.s, m.l[a.off:=v], m.c)
    case Constant => m
  }

  datatype Barrier = Idle | Arrived(cnt: nat) | Released
  predicate ValidBar(b: Barrier, exp: nat) {
    match b case Arrived(c) => c <= exp case _ => true
  }

  datatype Opnd = OReg(r: nat) | OImm(v: int) | OAddr(a: Addr) | OPred(p: nat)
  datatype Opc =
    | NOP | MOV | ADD | SUB | MUL | MAD | LD | ST | LDG | STG | LDS | STS
    | ATOM | BRA | CALL | RET | BAR | SHFL | VOTE | SETP | SELP | CVT | EXIT

  datatype Instr = Instr(opc: Opc, dst: Opnd, s0: Opnd, s1: Opnd, s2: Opnd, pred: nat, neg: bool, lab: string)
  predicate ValidInstr(i: Instr) { true }

  datatype TState = TState(tid: ThreadId, bid: BlockId, pc: nat, rf: RegFile, act: bool, done: bool)
  predicate ValidTS(ts: TState, bdim: BlockDim, mr: nat, mp: nat) {
    ValidTid(ts.tid,bdim) && ValidRF(ts.rf,mr,mp)
  }

  const WS: nat := 32
  datatype WState = WState(id: nat, th: seq<TState>, mask: bv32, pc: nat, bar: Barrier)
  predicate ValidWS(w: WState, bdim: BlockDim, mr: nat, mp: nat) {
    |w.th| == WS && forall i :: 0 <= i < WS ==> ValidTS(w.th[i],bdim,mr,mp)
  }

  datatype BState = BState(bid: BlockId, bdim: BlockDim, warps: seq<WState>, smem: map<nat,int>, bar: Barrier, done: bool)
  predicate ValidBS(b: BState, gdim: GridDim, mr: nat, mp: nat) {
    ValidBid(b.bid,gdim) && forall i :: 0 <= i < |b.warps| ==> ValidWS(b.warps[i],b.bdim,mr,mp)
  }

  datatype Config = Config(gdim: GridDim, bdim: BlockDim, maxR: nat, maxP: nat, smem: nat, gmem: nat)
  predicate ValidCfg(c: Config) {
    c.gdim.x>0 && c.gdim.y>0 && c.gdim.z>0 && c.bdim.x>0 && c.bdim.y>0 && c.bdim.z>0 && c.maxR>0 && c.maxP>0
  }

  datatype GPUState = GPUState(cfg: Config, blocks: seq<BState>, gmem: map<nat,int>, cmem: map<nat,int>, prog: seq<Instr>, cyc: nat, halt: bool)
  predicate ValidGPU(g: GPUState) {
    ValidCfg(g.cfg) &&
    forall i :: 0 <= i < |g.blocks| ==> ValidBS(g.blocks[i], g.cfg.gdim, g.cfg.maxR, g.cfg.maxP) &&
    forall i :: 0 <= i < |g.prog| ==> ValidInstr(g.prog[i])
  }

  predicate InvTid(g: GPUState)
    requires ValidGPU(g)
  {
    forall bi,wi,ti :: 0<=bi<|g.blocks| && 0<=wi<|g.blocks[bi].warps| && 0<=ti<WS
      ==> ValidTid(g.blocks[bi].warps[wi].th[ti].tid, g.cfg.bdim)
  }

  predicate InvPC(g: GPUState)
    requires ValidGPU(g)
  {
    forall bi,wi,ti :: 0<=bi<|g.blocks| && 0<=wi<|g.blocks[bi].warps| && 0<=ti<WS
      ==> g.blocks[bi].warps[wi].th[ti].pc <= |g.prog|
  }

  predicate InvAct(g: GPUState)
    requires ValidGPU(g)
  {
    forall bi,wi,ti :: 0<=bi<|g.blocks| && 0<=wi<|g.blocks[bi].warps| && 0<=ti<WS
      ==> (g.blocks[bi].warps[wi].th[ti].act ==> !g.blocks[bi].warps[wi].th[ti].done)
  }

  predicate InvGPU(g: GPUState) {
    ValidGPU(g) && InvTid(g) && InvPC(g) && InvAct(g)
  }

  predicate Step(g: GPUState, g': GPUState)
    requires InvGPU(g)
  { InvGPU(g') && g'.cyc == g.cyc+1 }

  lemma Step_pres(g: GPUState, g': GPUState)
    requires InvGPU(g) && Step(g,g')
    ensures InvGPU(g')
  {}

  function EvalOp(ts: TState, op: Opnd, m: Memory): int {
    match op
    case OReg(r) => RdI(ts.rf,r)
    case OImm(v) => v
    case OAddr(a) => RdM(m,a)
    case OPred(p) => if RdP(ts.rf,p) then 1 else 0
  }

  function ExecMOV(ts: TState, dst: Opnd, src: Opnd): TState {
    match dst
    case OReg(r) =>
      var v := EvalOp(ts, src, Memory(map[],map[],map[],map[]));
      TState(ts.tid,ts.bid,ts.pc+1, WrI(ts.rf,r,v), ts.act, ts.done)
    case _ => ts
  }

  function ExecADD(ts: TState, dst: Opnd, s0: Opnd, s1: Opnd): TState {
    match dst
    case OReg(r) =>
      var a := EvalOp(ts,s0,Memory(map[],map[],map[],map[]));
      var b := EvalOp(ts,s1,Memory(map[],map[],map[],map[]));
      TState(ts.tid,ts.bid,ts.pc+1, WrI(ts.rf,r,a+b), ts.act, ts.done)
    case _ => ts
  }

  function ExecEXIT(ts: TState): TState {
    TState(ts.tid,ts.bid,ts.pc,ts.rf,false,true)
  }

  function Exec(ts: TState, ins: Instr, m: Memory): TState {
    if !ts.act || ts.done then ts
    else match ins.opc
    case MOV => ExecMOV(ts,ins.dst,ins.s0)
    case ADD => ExecADD(ts,ins.dst,ins.s0,ins.s1)
    case EXIT => ExecEXIT(ts)
    case NOP => TState(ts.tid,ts.bid,ts.pc+1,ts.rf,ts.act,ts.done)
    case _ => TState(ts.tid,ts.bid,ts.pc+1,ts.rf,ts.act,ts.done)
  }

  function InitTS(tid: ThreadId, bid: BlockId): TState {
    TState(tid,bid,0,RegFile(map[],map[]),true,false)
  }

  function InitWS(id: nat, bid: BlockId, bdim: BlockDim): WState {
    var th := seq(WS, i requires 0<=i<WS => InitTS(ThreadId(i%bdim.x,0,0),bid));
    WState(id,th,0xFFFFFFFFu,0,Idle)
  }

  function InitBS(bid: BlockId, cfg: Config): BState
    requires ValidCfg(cfg)
  {
    var nw := (TPB(cfg.bdim)+WS-1)/WS;
    var ws := seq(nw, i requires 0<=i<nw => InitWS(i,bid,cfg.bdim));
    BState(bid,cfg.bdim,ws,map[],Idle,false)
  }

  function InitGPU(cfg: Config, prog: seq<Instr>): GPUState
    requires ValidCfg(cfg)
    requires forall i :: 0<=i<|prog| ==> ValidInstr(prog[i])
    ensures InvGPU(InitGPU(cfg,prog))
  {
    var nb := cfg.gdim.x*cfg.gdim.y*cfg.gdim.z;
    var bs := seq(nb, i requires 0<=i<nb => InitBS(BlockId(i%cfg.gdim.x,0,0),cfg));
    GPUState(cfg,bs,map[],map[],prog,0,false)
  }

  lemma Init_establishes(cfg: Config, prog: seq<Instr>)
    requires ValidCfg(cfg) && forall i :: 0<=i<|prog| ==> ValidInstr(prog[i])
    ensures InvGPU(InitGPU(cfg,prog))
  {}
}
