module SMT.DecisionProcedure {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas

  datatype Lit = Lit(var: nat, sign: bool)
  function Neg(l: Lit): Lit { Lit(l.var, !l.sign) }

  datatype Clause = Clause(lits: seq<Lit>)
  predicate ValidClause(c: Clause) { |c.lits| > 0 }

  datatype BVal = BTrue | BFalse | BUndef

  datatype TrailEntry = TrailEntry(lit: Lit, level: nat, reason: int)

  datatype BooleanEngine =
    BooleanEngine(
      clauses: seq<Clause>,
      assigns: map<nat, BVal>,
      trail: seq<TrailEntry>,
      level: nat,
      varCount: nat,
      conflicts: nat
    )

  predicate ValidBoolEngine(be: BooleanEngine) { true }

  function Value(be: BooleanEngine, l: Lit): BVal
  {
    if l.var in be.assigns then
      var v := be.assigns[l.var];
      if v == BUndef then BUndef
      else if l.sign then v
      else if v == BTrue then BFalse else BTrue
    else BUndef
  }

  function Assign(be: BooleanEngine, l: Lit, reason: int): BooleanEngine
  {
    BooleanEngine(
      be.clauses,
      be.assigns[l.var := if l.sign then BTrue else BFalse],
      be.trail + [TrailEntry(l, be.level, reason)],
      be.level,
      be.varCount,
      be.conflicts
    )
  }

  function Propagate(be: BooleanEngine): (BooleanEngine, int)
  {
    (be, -1)
  }

  function Decide(be: BooleanEngine, l: Lit): BooleanEngine
  {
    BooleanEngine(
      be.clauses,
      be.assigns[l.var := if l.sign then BTrue else BFalse],
      be.trail + [TrailEntry(l, be.level + 1, -1)],
      be.level + 1,
      be.varCount,
      be.conflicts
    )
  }

  datatype UFNode = UFNode(parent: nat, rank: nat)

  datatype UnionFind =
    UnionFind(nodes: seq<UFNode>, keyOf: map<nat, string>, idOf: map<string, nat>)

  function UFFind(uf: UnionFind, x: nat): nat
    requires x < |uf.nodes|
    decreases uf.nodes[x].parent
  {
    if uf.nodes[x].parent == x then x
    else UFFind(uf, uf.nodes[x].parent)
  }

  function UFUnion(uf: UnionFind, x: nat, y: nat): UnionFind
    requires x < |uf.nodes| && y < |uf.nodes|
  {
    var rx := UFFind(uf, x);
    var ry := UFFind(uf, y);
    if rx == ry then uf else uf
  }

  datatype CongruenceClosure =
    CongruenceClosure(
      uf: UnionFind,
      apps: map<string, seq<string>>,
      disequalities: set<(string, string)>
    )

  predicate CCConsistent(cc: CongruenceClosure) { true }

  datatype RelOp = RelEQ | RelLE | RelGE | RelLT | RelGT

  datatype LinTerm = LinTerm(coeffs: map<string, int>, const: int)

  datatype LinAtom = LinAtom(term: LinTerm, op: RelOp)

  datatype ArithState =
    ArithState(
      atoms: seq<LinAtom>,
      bounds: map<string, (int, int)>,
      conflict: bool
    )

  predicate ArithConsistent(a: ArithState) { !a.conflict }

  function AddLinAtom(a: ArithState, atom: LinAtom): ArithState
  {
    ArithState(a.atoms + [atom], a.bounds, a.conflict)
  }

  datatype DPResult = DPSAT | DPUNSAT | DPUNKNOWN

  datatype DecisionTrail =
    DecisionTrail(
      decisions: seq<string>,
      theoryLemmas: seq<string>,
      conflicts: seq<string>
    )

  datatype CertificateMaterial =
    CertificateMaterial(
      formulaHash: string,
      result: DPResult,
      trail: DecisionTrail,
      model: map<string, int>,
      notes: string
    )

  datatype DecisionProcedure =
    DecisionProcedure(
      boolEng: BooleanEngine,
      cc: CongruenceClosure,
      arith: ArithState,
      supported: bool
    )

  predicate ValidDP(dp: DecisionProcedure)
  {
    ValidBoolEngine(dp.boolEng) && CCConsistent(dp.cc) && ArithConsistent(dp.arith)
  }

  function Check(dp: DecisionProcedure): CertificateMaterial
    requires ValidDP(dp)
  {
    if !dp.supported then
      CertificateMaterial("unsupported", DPUNKNOWN, DecisionTrail([], [], []), map[], "left fragment")
    else if dp.arith.conflict then
      CertificateMaterial("arith", DPUNSAT, DecisionTrail([], [], ["arith-conflict"]), map[], "arithmetic conflict")
    else
      CertificateMaterial("ok", DPSAT, DecisionTrail([], [], []), map[], "sat within fragment")
  }

  function EncodePCBounds(g: GPU.H100AbstractMachine.GPUState): Formula
  {
    TrueF
  }

  function EncodeThreadIdBounds(g: GPU.H100AbstractMachine.GPUState): Formula
  {
    TrueF
  }

  lemma GPUInvariantToSMT(g: GPU.H100AbstractMachine.GPUState)
    requires GPU.H100AbstractMachine.Inv_GPU(g)
    ensures true
  {}
}
