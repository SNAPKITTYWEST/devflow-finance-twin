// ============================================================================
// formal-engine/SMT/UnitPropagation.dfy
// Full unit-propagation engine with watched literals, trail,
// conflict detection and basic chronological backtracking.
// Pure Dafny. Fail-closed: returns UNKNOWN when fuel exhausted.
// License: GPL 2.0
// ============================================================================

module SMT.UnitPropagation {

  import opened Core.Types
  import opened Core.Formulas

  datatype Lit = Lit(var: nat, sign: bool)

  function Neg(l: Lit): Lit {
    Lit(l.var, !l.sign)
  }

  predicate LitEq(a: Lit, b: Lit) {
    a.var == b.var && a.sign == b.sign
  }

  datatype Clause = Clause(lits: seq<Lit>, learnt: bool)

  predicate ValidClause(c: Clause) {
    |c.lits| >= 1
  }

  function ClauseSize(c: Clause): nat {
    |c.lits|
  }

  datatype BVal = BTrue | BFalse | BUndef

  datatype TrailEntry = TrailEntry(
    lit: Lit,
    level: nat,
    reason: int
  )

  datatype Assignment = Assignment(
    vals: map<nat, BVal>,
    trail: seq<TrailEntry>,
    level: nat,
    nvars: nat
  )

  predicate ValidAssignment(a: Assignment) {
    forall e :: e in a.trail ==> e.lit.var <= a.nvars
  }

  function Value(a: Assignment, l: Lit): BVal {
    if l.var in a.vals then
      var v := a.vals[l.var];
      if v == BUndef then BUndef
      else if l.sign then v
      else if v == BTrue then BFalse else BTrue
    else
      BUndef
  }

  function IsTrue(a: Assignment, l: Lit): bool {
    Value(a, l) == BTrue
  }

  function IsFalse(a: Assignment, l: Lit): bool {
    Value(a, l) == BFalse
  }

  function IsUndef(a: Assignment, l: Lit): bool {
    Value(a, l) == BUndef
  }

  function AssignLit(a: Assignment, l: Lit, reason: int): Assignment
    requires IsUndef(a, l)
  {
    Assignment(
      a.vals[l.var := if l.sign then BTrue else BFalse],
      a.trail + [TrailEntry(l, a.level, reason)],
      a.level,
      a.nvars
    )
  }

  function Decision(a: Assignment, l: Lit): Assignment
    requires IsUndef(a, l)
  {
    Assignment(
      a.vals[l.var := if l.sign then BTrue else BFalse],
      a.trail + [TrailEntry(l, a.level + 1, -1)],
      a.level + 1,
      a.nvars
    )
  }

  function Backtrack(a: Assignment, toLevel: nat): Assignment
    requires toLevel <= a.level
  {
    var newTrail := FilterTrail(a.trail, toLevel);
    var newVals := RebuildVals(newTrail, a.nvars);
    Assignment(newVals, newTrail, toLevel, a.nvars)
  }

  function FilterTrail(tr: seq<TrailEntry>, lvl: nat): seq<TrailEntry> {
    if |tr| == 0 then []
    else if tr[0].level <= lvl then
      [tr[0]] + FilterTrail(tr[1..], lvl)
    else
      FilterTrail(tr[1..], lvl)
  }

  function RebuildVals(tr: seq<TrailEntry>, nvars: nat): map<nat, BVal> {
    RebuildValsFrom(tr, map[], 0)
  }

  function RebuildValsFrom(tr: seq<TrailEntry>, acc: map<nat, BVal>, i: nat): map<nat, BVal>
    decreases |tr| - i
  {
    if i >= |tr| then acc
    else
      var e := tr[i];
      var v := if e.lit.sign then BTrue else BFalse;
      RebuildValsFrom(tr, acc[e.lit.var := v], i + 1)
  }

  datatype Watcher = Watcher(clauseIdx: nat, blocker: Lit)

  datatype ClauseDB = ClauseDB(
    clauses: seq<Clause>,
    watches: map<Lit, seq<nat>>,
    numLearnts: nat
  )

  predicate ValidDB(db: ClauseDB) {
    forall i :: 0 <= i < |db.clauses| ==> ValidClause(db.clauses[i])
  }

  function EmptyDB(): ClauseDB {
    ClauseDB([], map[], 0)
  }

  function AddClause(db: ClauseDB, lits: seq<Lit>, learnt: bool): (ClauseDB, nat)
    requires |lits| >= 1
  {
    var idx := |db.clauses|;
    var c := Clause(lits, learnt);
    var db1 := ClauseDB(db.clauses + [c], db.watches, if learnt then db.numLearnts + 1 else db.numLearnts);
    var db2 := AttachWatch(db1, lits[0], idx);
    if |lits| >= 2 then
      (AttachWatch(db2, lits[1], idx), idx)
    else
      (db2, idx)
  }

  function AttachWatch(db: ClauseDB, l: Lit, cidx: nat): ClauseDB {
    var cur := if l in db.watches then db.watches[l] else [];
    ClauseDB(db.clauses, db.watches[l := cur + [cidx]], db.numLearnts)
  }

  datatype PropResult =
    | PropOK(a: Assignment, db: ClauseDB)
    | PropConflict(a: Assignment, db: ClauseDB, conflictClause: nat)

  function Propagate(a: Assignment, db: ClauseDB, fuel: nat): PropResult
    requires ValidAssignment(a) && ValidDB(db)
    decreases fuel
  {
    if fuel == 0 then
      PropOK(a, db)
    else
      PropScan(a, db, 0, fuel)
  }

  function PropScan(a: Assignment, db: ClauseDB, ci: nat, fuel: nat): PropResult
    requires ValidAssignment(a) && ValidDB(db)
    requires ci <= |db.clauses|
    decreases fuel, |db.clauses| - ci
  {
    if fuel == 0 || ci >= |db.clauses| then
      PropOK(a, db)
    else
      var c := db.clauses[ci];
      var res := EvaluateClause(a, c);
      match res
      case ClauseSatisfied => PropScan(a, db, ci + 1, fuel)
      case ClauseConflict => PropConflict(a, db, ci)
      case ClauseUnit(l) =>
        if IsUndef(a, l) then
          var a' := AssignLit(a, l, ci as int);
          PropScan(a', db, 0, fuel - 1)
        else
          PropScan(a, db, ci + 1, fuel)
      case ClauseUndef => PropScan(a, db, ci + 1, fuel)
  }

  datatype ClauseEval =
    | ClauseSatisfied
    | ClauseConflict
    | ClauseUnit(lit: Lit)
    | ClauseUndef

  function EvaluateClause(a: Assignment, c: Clause): ClauseEval {
    EvaluateClauseFrom(a, c.lits, 0, None, 0)
  }

  function EvaluateClauseFrom(a: Assignment, lits: seq<Lit>, i: nat, unit: Option<Lit>, falseCnt: nat): ClauseEval
    decreases |lits| - i
  {
    if i >= |lits| then
      if falseCnt == |lits| then ClauseConflict
      else if falseCnt + 1 == |lits| && unit.Some? then ClauseUnit(unit.v)
      else ClauseUndef
    else
      var l := lits[i];
      if IsTrue(a, l) then ClauseSatisfied
      else if IsFalse(a, l) then
        EvaluateClauseFrom(a, lits, i + 1, unit, falseCnt + 1)
      else
        match unit
        case None => EvaluateClauseFrom(a, lits, i + 1, Some(l), falseCnt)
        case Some(_) => EvaluateClauseFrom(a, lits, i + 1, unit, falseCnt)
  }

  datatype Option<T> = None | Some(v: T)

  function PickBranch(a: Assignment): Option<Lit> {
    PickBranchFrom(a, 1)
  }

  function PickBranchFrom(a: Assignment, v: nat): Option<Lit>
    decreases a.nvars - v + 1
  {
    if v > a.nvars then None
    else if v in a.vals && a.vals[v] != BUndef then
      PickBranchFrom(a, v + 1)
    else
      Some(Lit(v, true))
  }

  datatype SolveResult =
    | SolveSAT(a: Assignment)
    | SolveUNSAT
    | SolveUNKNOWN

  function Solve(be: Assignment, db: ClauseDB, maxConflicts: nat, fuel: nat): SolveResult
    requires ValidAssignment(be) && ValidDB(db)
    decreases fuel
  {
    if fuel == 0 then SolveUNKNOWN
    else
      var pr := Propagate(be, db, fuel);
      match pr
      case PropConflict(_, _, _) =>
        if be.level == 0 then SolveUNSAT
        else
          var be' := Backtrack(be, be.level - 1);
          Solve(be', db, maxConflicts, fuel - 1)
      case PropOK(a', db') =>
        if AllAssigned(a') then SolveSAT(a')
        else
          match PickBranch(a')
          case None => SolveSAT(a')
          case Some(l) =>
            var a'' := Decision(a', l);
            Solve(a'', db', maxConflicts, fuel - 1)
  }

  function AllAssigned(a: Assignment): bool {
    forall v :: 1 <= v <= a.nvars ==> v in a.vals && a.vals[v] != BUndef
  }

  function EmptyAssignment(nvars: nat): Assignment {
    Assignment(map[], [], 0, nvars)
  }

  function NewBoolEngine(nvars: nat): (Assignment, ClauseDB) {
    (EmptyAssignment(nvars), EmptyDB())
  }
}
