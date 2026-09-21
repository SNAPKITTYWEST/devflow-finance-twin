// ============================================================================
// formal-engine/SMT/ClauseMinimization.dfy
// Learnt-clause minimization after 1-UIP
// License: GPL 2.0
// ============================================================================

module SMT.ClauseMinimization {

  import opened SMT.UnitPropagation
  import opened SMT.OneUIP
  import opened Core.Types
  import opened Core.Formulas

  function LevelOf(a: Assignment, v: nat): nat {
    FindLevel(a.trail, v, 0)
  }

  function ReasonOf(a: Assignment, v: nat): int {
    ReasonFromTrail(a.trail, v, 0)
  }

  function ReasonFromTrail(tr: seq<TrailEntry>, v: nat, i: nat): int
    decreases |tr| - i
  {
    if i >= |tr| then -1
    else if tr[i].lit.var == v then tr[i].reason
    else ReasonFromTrail(tr, v, i + 1)
  }

  predicate CanEliminate(a: Assignment, db: ClauseDB, learnt: seq<Lit>, l: Lit): bool
    requires ValidAssignment(a) && ValidDB(db)
  {
    var rsn := ReasonOf(a, l.var);
    if rsn < 0 || rsn >= |db.clauses| then
      false
    else
      var reasonLits := db.clauses[rsn].lits;
      AllLitsCovered(reasonLits, learnt, l, 0)
  }

  function AllLitsCovered(reason: seq<Lit>, learnt: seq<Lit>, pivot: Lit, i: nat): bool
    decreases |reason| - i
  {
    if i >= |reason| then true
    else
      var lit := reason[i];
      if LitEq(lit, pivot) then
        AllLitsCovered(reason, learnt, pivot, i + 1)
      else if LitIn(lit, learnt) || LitIn(Neg(lit), learnt) then
        AllLitsCovered(reason, learnt, pivot, i + 1)
      else
        false
  }

  function LitIn(l: Lit, ls: seq<Lit>): bool {
    LitInFrom(l, ls, 0)
  }

  function LitInFrom(l: Lit, ls: seq<Lit>, i: nat): bool
    decreases |ls| - i
  {
    if i >= |ls| then false
    else if LitEq(l, ls[i]) then true
    else LitInFrom(l, ls, i + 1)
  }

  function MinimizeRecursive(a: Assignment, db: ClauseDB, learnt: seq<Lit>, fuel: nat): seq<Lit>
    requires ValidAssignment(a) && ValidDB(db)
    decreases fuel
  {
    if fuel == 0 || |learnt| <= 1 then
      learnt
    else
      MinimizeRecFrom(a, db, learnt, 0, fuel)
  }

  function MinimizeRecFrom(a: Assignment, db: ClauseDB, learnt: seq<Lit>, i: nat, fuel: nat): seq<Lit>
    requires ValidAssignment(a) && ValidDB(db)
    decreases fuel, |learnt| - i
  {
    if fuel == 0 || i >= |learnt| then
      learnt
    else
      var l := learnt[i];
      if CanEliminate(a, db, learnt, l) then
        var smaller := RemoveAt(learnt, i);
        MinimizeRecursive(a, db, smaller, fuel - 1)
      else
        MinimizeRecFrom(a, db, learnt, i + 1, fuel)
  }

  function RemoveAt(ls: seq<Lit>, idx: nat): seq<Lit>
    requires idx < |ls|
  {
    ls[..idx] + ls[idx+1..]
  }

  function MinimizeLocal(a: Assignment, learnt: seq<Lit>): seq<Lit>
    requires ValidAssignment(a)
  {
    if |learnt| <= 2 then learnt
    else
      var assertLit := learnt[0];
      var rest := learnt[1..];
      var kept := KeepOnePerLevel(a, rest, map[], []);
      [assertLit] + kept
  }

  function KeepOnePerLevel(a: Assignment, ls: seq<Lit>, seenLevels: map<nat,bool>, acc: seq<Lit>): seq<Lit>
    decreases |ls|
  {
    if |ls| == 0 then acc
    else
      var l := ls[0];
      var lvl := LevelOf(a, l.var);
      if lvl in seenLevels then
        KeepOnePerLevel(a, ls[1..], seenLevels, acc)
      else
        KeepOnePerLevel(a, ls[1..], seenLevels[lvl := true], acc + [l])
  }

  function MinimizeLearnt(a: Assignment, db: ClauseDB, rawLearnt: seq<Lit>, fuel: nat): seq<Lit>
    requires ValidAssignment(a) && ValidDB(db)
  {
    var m1 := MinimizeRecursive(a, db, rawLearnt, fuel);
    var m2 := MinimizeLocal(a, m1);
    Dedup(m2)
  }

  function Dedup(ls: seq<Lit>): seq<Lit> {
    DedupFrom(ls, {}, [])
  }

  function DedupFrom(ls: seq<Lit>, seen: set<nat>, acc: seq<Lit>): seq<Lit>
    decreases |ls|
  {
    if |ls| == 0 then acc
    else
      var l := ls[0];
      if l.var in seen then
        DedupFrom(ls[1..], seen, acc)
      else
        DedupFrom(ls[1..], seen + {l.var}, acc + [l])
  }

  function AnalyzeAndMinimize(a: Assignment, db: ClauseDB, conflictIdx: nat, fuel: nat)
    : (seq<Lit>, nat)
    requires ValidAssignment(a) && ValidDB(db)
    requires conflictIdx < |db.clauses|
  {
    var (raw, bj) := AnalyzeConflict(a, db, conflictIdx);
    if |raw| == 0 then
      ([], 0)
    else
      var mini := MinimizeLearnt(a, db, raw, fuel);
      var newBJ := RecomputeBJLevel(a, mini);
      (mini, newBJ)
  }

  function RecomputeBJLevel(a: Assignment, ls: seq<Lit>): nat {
    if |ls| <= 1 then 0
    else
      MaxLevelFrom(a, ls, 1, 0)
  }

  function MaxLevelFrom(a: Assignment, ls: seq<Lit>, i: nat, cur: nat): nat
    decreases |ls| - i
  {
    if i >= |ls| then cur
    else
      var lvl := LevelOf(a, ls[i].var);
      MaxLevelFrom(a, ls, i + 1, if lvl > cur then lvl else cur)
  }

  function LearnMinimizeBackjump(a: Assignment, db: ClauseDB, conflictIdx: nat, fuel: nat)
    : (Assignment, ClauseDB, bool)
    requires ValidAssignment(a) && ValidDB(db)
    requires conflictIdx < |db.clauses|
  {
    var (learntLits, bjLevel) := AnalyzeAndMinimize(a, db, conflictIdx, fuel);
    if |learntLits| == 0 then
      (a, db, true)
    else
      var (db2, _) := AddClause(db, learntLits, true);
      var a2 := Backtrack(a, bjLevel);
      (a2, db2, false)
  }

  function CDCLMin(a: Assignment, db: ClauseDB, maxConflicts: nat, fuel: nat): SolveResult
    requires ValidAssignment(a) && ValidDB(db)
    decreases fuel
  {
    if fuel == 0 then SolveUNKNOWN
    else
      var pr := Propagate(a, db, fuel);
      match pr
      case PropConflict(a1, db1, cidx) =>
        if a1.level == 0 then
          SolveUNSAT
        else
          var (a2, db2, unsat) := LearnMinimizeBackjump(a1, db1, cidx, fuel);
          if unsat then SolveUNSAT
          else CDCLMin(a2, db2, maxConflicts, fuel - 1)
      case PropOK(a1, db1) =>
        if AllAssigned(a1) then SolveSAT(a1)
        else
          match PickBranch(a1)
          case None => SolveSAT(a1)
          case Some(l) =>
            var a2 := Decision(a1, l);
            CDCLMin(a2, db1, maxConflicts, fuel - 1)
  }

  function SolveMinimized(nvars: nat, clauses: seq<seq<Lit>>, fuel: nat): SolveResult {
    var (a0, db0) := NewBoolEngine(nvars);
    var db1 := AddAllClauses(db0, clauses, 0);
    CDCLMin(a0, db1, fuel, fuel)
  }

  lemma MinimizationNeverEnlarges(a: Assignment, db: ClauseDB, raw: seq<Lit>, fuel: nat)
    requires ValidAssignment(a) && ValidDB(db)
    ensures |MinimizeLearnt(a, db, raw, fuel)| <= |raw|
  {}
}
