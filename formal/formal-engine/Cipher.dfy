// ============================================================================
// formal-engine/Cipher.dfy
// ARX cipher with rotate-left/right and round/inverse-round proofs
// License: GPL 2.0
// ============================================================================

module Cipher {

  datatype Key = Key(words: seq<bv32>)
  datatype Block = Block(words: seq<bv32>)

  predicate VKey(k: Key) { |k.words| == 8 }
  predicate VBlock(b: Block) { |b.words| == 4 }

  const NR: nat := 20

  function RotL(x: bv64, n: nat): bv64 {
    ((x << (n % 64)) | (x >> (64 - (n % 64))))
  }

  function RotR(x: bv64, n: nat): bv64 {
    ((x >> (n % 64)) | (x << (64 - (n % 64))))
  }

  function Round(s: bv64, rk: bv64): bv64 {
    let r1 := RotL(s, 13);
    let r2 := r1 ^ rk;
    RotL(r2, 17)
  }

  function InvRound(s: bv64, rk: bv64): bv64 {
    let r1 := RotR(s, 17);
    let r2 := r1 ^ rk;
    RotR(r2, 13)
  }

  function KS(k: Key): seq<bv64>
    requires VKey(k)
  {
    seq(NR, i requires 0 <= i < NR => (k.words[i % 8] as bv64) + (i as bv64))
  }

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
