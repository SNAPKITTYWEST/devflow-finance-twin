// ============================================================================
// formal-engine/Proofs/CoreProofs.dfy
// Concrete verification proofs
// License: GPL 2.0
// ============================================================================

module Proofs.CoreProofs {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas
  import opened SMT.UnitPropagation
  import opened SMT.OneUIP
  import opened SMT.ClauseMinimization
  import opened GPU.H100
  import opened Cipher
  import opened StateMachine.Core

  lemma SortHash_injective_bool()
    ensures SortHash(BOOL) == "sort:bool"
  {}

  lemma ValidTerm_MkVar(n: string, s: Sort)
    requires ValidSort(s)
    ensures ValidTerm(MkVar(n, s))
    ensures TermSort(MkVar(n, s)) == s
  {}

  lemma ValidTerm_MkLitInt(v: int)
    ensures ValidTerm(MkLitInt(v))
    ensures TermSort(MkLitInt(v)) == INT
  {}

  lemma Normalize_True()
    ensures Normalize(TrueF) == TrueF
  {}

  lemma Normalize_False()
    ensures Normalize(FalseF) == FalseF
  {}

  lemma Neg_involutive(l: Lit)
    ensures Neg(Neg(l)) == l
  {}

  lemma AssignLit_sets_value(a: Assignment, l: Lit, reason: int)
    requires IsUndef(a, l)
    ensures Value(AssignLit(a, l, reason), l) == BTrue
  {}

  lemma Backtrack_level(a: Assignment, toLevel: nat)
    requires toLevel <= a.level
    ensures Backtrack(a, toLevel).level == toLevel
  {}

  lemma LinTid_bound(t: ThreadId, b: BlockDim)
    requires ValidTid(t, b)
    ensures LinTid(t, b) < TPB(b)
  {}

  lemma InitGPU_establishes_Inv(cfg: Config, prog: seq<Instr>)
    requires ValidCfg(cfg)
    requires forall i :: 0 <= i < |prog| ==> ValidInstr(prog[i])
    ensures InvGPU(InitGPU(cfg, prog))
  {}

  lemma RotL_RotR_id(x: bv64, n: nat)
    ensures RotR(RotL(x, n), n) == x
  {}

  lemma RoundInv_holds(s: bv64, rk: bv64)
    ensures InvRound(Round(s, rk), rk) == s
  {}

  lemma KS_length(k: Key)
    requires VKey(k)
    ensures |KS(k)| == NR
  {}
}
