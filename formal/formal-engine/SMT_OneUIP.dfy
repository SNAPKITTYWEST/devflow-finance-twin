// ============================================================================
// formal-engine/SMT/OneUIP.dfy
// 1-UIP conflict analysis, learnt-clause generation
// License: GPL 2.0
// ============================================================================

module SMT.OneUIP {

  import opened SMT.UnitPropagation
  import opened Core.Types
  import opened Core.Formulas

  datatype ImpNode = ImpNode(
    lit: Lit,
    level: nat,
    reason: int,
    ante: seq<Lit>
  )

  datatype AnalysisState = AnalysisState(
    seen: set<nat>,
    learned: seq<Lit>,
    curLevelCnt: nat,
    trailIdx: nat,
    uip: Option<Lit>,
    assertLevel: nat
  )

  predicate ValidAnalysis(a: AnalysisState) { true }

  function Antecedents(db: ClauseDB, reason: int, pLit: Lit): seq<Lit>
    requires reason >= 0 ==> reason < |db.clauses|
  {
    if reason < 0 then []
    else
      var c := db.clauses[reason];
      FilterOtherLits(c.lits, pLit, 0)
  }

  function FilterOtherLits(lits: seq<Lit>, p: Lit, i: nat): seq<Lit>
    decreases |lits| - i
  {
    if i >= |lits| then []
    else if LitEq(lits[i], p) then FilterOtherLits(lits, p, i + 1)
    else [lits[i]] + FilterOtherLits(lits, p, i + 1)
  }

  function MkNode(e: TrailEntry, db: ClauseDB): ImpNode
    requires e.reason < 0 || e.reason < |db.clauses|
  {
    ImpNode(e.lit, e.level, e.reason, Antecedents(db, e.reason, e.lit))
  }

  function AnalyzeConflict(a: Assignment, db: ClauseDB, conflictIdx: nat): (seq<Lit>, nat)
    requires ValidAssignment(a) && ValidDB(db)
    requires conflictIdx < |db.clauses|
    requires a.level >= 0
  {
    if a.level == 0 then
      ([], 0)
    else
      var confClause := db.clauses[conflictIdx];
      var initLearned := confClause.lits;
      var st0 := AnalysisState({}, [], 0, |a.trail|, None, 0);
      var st1 := CountCurLevel(a, initLearned, st0, 0);
      var st2 := AnalyzeLoop(a, db, st1, initLearned, |a.trail| * 2);
      match st2.uip
      case None => (st2.learned, 0)
      case Some(u) => ([ Neg(u)] + st2.learned, st2.assertLevel)
  }

  function CountCurLevel(a: Assignment, lits: seq<Lit>, st: AnalysisState, i: nat): AnalysisState
    decreases |lits| - i
  {
    if i >= |lits| then st
    else
      var l := lits[i];
      var lvl := LitLevel(a, l);
      if lvl == a.level then
        CountCurLevel(a, lits,
          AnalysisState(st.seen + {l.var}, st.learned, st.curLevelCnt + 1, st.trailIdx, st.uip, st.assertLevel),
          i + 1)
      else if lvl > 0 then
        CountCurLevel(a, lits,
          AnalysisState(st.seen + {l.var}, st.learned + [Neg(l)], st.curLevelCnt, st.trailIdx, st.uip,
                        if lvl > st.assertLevel then lvl else st.assertLevel),
          i + 1)
      else
        CountCurLevel(a, lits,
          AnalysisState(st.seen + {l.var}, st.learned, st.curLevelCnt, st.trailIdx, st.uip, st.assertLevel),
          i + 1)
  }

  function LitLevel(a: Assignment, l: Lit): nat {
    FindLevel(a.trail, l.var, 0)
  }

  function FindLevel(tr: seq<TrailEntry>, v: nat, i: nat): nat
    decreases |tr| - i
  {
    if i >= |tr| then 0
    else if tr[i].lit.var == v then tr[i].level
    else FindLevel(tr, v, i + 1)
  }

  function AnalyzeLoop(a: Assignment, db: ClauseDB, st: AnalysisState, pending: seq<Lit>, fuel: nat): AnalysisState
    requires ValidAssignment(a) && ValidDB(db)
    decreases fuel
  {
    if fuel == 0 || st.curLevelCnt <= 1 then
      if st.curLevelCnt == 1 then
        var uipLit := FindUIP(a, st.seen);
        AnalysisState(st.seen, st.learned, st.curLevelCnt, st.trailIdx, uipLit, st.assertLevel)
      else
        st
    else
      var (e, newIdx) := NextSeenOnTrail(a.trail, st.seen, st.trailIdx);
      match e
      case None => st
      case Some(entry) =>
        var node := MkNode(entry, db);
        var st2 := Resolve(a, node, st);
        AnalyzeLoop(a, db, st2, pending, fuel - 1)
  }

  function NextSeenOnTrail(tr: seq<TrailEntry>, seen: set<nat>, from: nat): (Option<TrailEntry>, nat)
    decreases from
  {
    if from == 0 then (None, 0)
    else
      var i := from - 1;
      var e := tr[i];
      if e.lit.var in seen then (Some(e), i)
      else NextSeenOnTrail(tr, seen, i)
  }

  function FindUIP(a: Assignment, seen: set<nat>): Option<Lit> {
    FindUIPFrom(a.trail, seen, |a.trail|)
  }

  function FindUIPFrom(tr: seq<TrailEntry>, seen: set<nat>, i: nat): Option<Lit>
    decreases i
  {
    if i == 0 then None
    else
      var e := tr[i-1];
      if e.lit.var in seen && e.level == (if |tr| > 0 then tr[|tr|-1].level else 0) then
        Some(e.lit)
      else
        FindUIPFrom(tr, seen, i - 1)
  }

  function Resolve(a: Assignment, node: ImpNode, st: AnalysisState): AnalysisState {
    var newLearned := st.learned;
    var newSeen := st.seen;
    var newCnt := st.curLevelCnt - 1;
    var newAssert := st.assertLevel;
    ResolveAntes(a, node.ante, newLearned, newSeen, newCnt, newAssert, 0)
  }

  function ResolveAntes(a: Assignment, antes: seq<Lit>,
                        learned: seq<Lit>, seen: set<nat>,
                        cnt: nat, assertLvl: nat, i: nat): AnalysisState
    decreases |antes| - i
  {
    if i >= |antes| then
      AnalysisState(seen, learned, cnt, 0, None, assertLvl)
    else
      var l := antes[i];
      if l.var in seen then
        ResolveAntes(a, antes, learned, seen, cnt, assertLvl, i + 1)
      else
        var lvl := LitLevel(a, l);
        if lvl == a.level then
          ResolveAntes(a, antes, learned, seen + {l.var}, cnt + 1, assertLvl, i + 1)
        else if lvl > 0 then
          ResolveAntes(a, antes, learned + [Neg(l)], seen + {l.var}, cnt,
                       if lvl > assertLvl then lvl else assertLvl, i + 1)
        else
          ResolveAntes(a, antes, learned, seen + {l.var}, cnt, assertLvl, i + 1)
  }

  function LearnAndBackjump(a: Assignment, db: ClauseDB, conflictIdx: nat)
    : (Assignment, ClauseDB, bool)
    requires ValidAssignment(a) && ValidDB(db)
    requires conflictIdx < |db.clauses|
  {
    var (learntLits, bjLevel) := AnalyzeConflict(a, db, conflictIdx);
    if |learntLits| == 0 then
      (a, db, true)
    else
      var (db2, _) := AddClause(db, learntLits, true);
      var a2 := Backtrack(a, bjLevel);
      (a2, db2, false)
  }

  function CDCL(a: Assignment, db: ClauseDB, maxConflicts: nat, fuel: nat): SolveResult
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
          var (a2, db2, unsat) := LearnAndBackjump(a1, db1, cidx);
          if unsat then SolveUNSAT
          else CDCL(a2, db2, maxConflicts, fuel - 1)
      case PropOK(a1, db1) =>
        if AllAssigned(a1) then SolveSAT(a1)
        else
          match PickBranch(a1)
          case None => SolveSAT(a1)
          case Some(l) =>
            var a2 := Decision(a1, l);
            CDCL(a2, db1, maxConflicts, fuel - 1)
  }

  function SolveWith1UIP(nvars: nat, clauses: seq<seq<Lit>>, fuel: nat): SolveResult {
    var (a0, db0) := NewBoolEngine(nvars);
    var db1 := AddAllClauses(db0, clauses, 0);
    CDCL(a0, db1, fuel, fuel)
  }

  function AddAllClauses(db: ClauseDB, cs: seq<seq<Lit>>, i: nat): ClauseDB
    decreases |cs| - i
  {
    if i >= |cs| then db
    else if |cs[i]| == 0 then db
    else
      var (db2, _) := AddClause(db, cs[i], false);
      AddAllClauses(db2, cs, i + 1)
  }

  lemma BackjumpLevelNonNegative(a: Assignment, db: ClauseDB, cidx: nat)
    requires ValidAssignment(a) && ValidDB(db)
    requires cidx < |db.clauses|
    ensures var (_, lvl) := AnalyzeConflict(a, db, cidx); lvl <= a.level
  {}
}
