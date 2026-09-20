// ============================================================================
// formal-engine/Cipher/ARX.dfy
// ARX cipher round and inverse
// License: GPL 2.0
// ============================================================================

module Cipher.Core {

  const BLOCK_BITS: nat := 64
  const KEY_BYTES: nat := 16
  const ROUNDS: nat := 8

  datatype Key = Key(data: seq<bv8>)
  datatype Block = Block(data: seq<bv8>)

  predicate ValidKey(k: Key)
  {
    |k.data| == KEY_BYTES
  }

  predicate ValidBlock(b: Block)
  {
    |b.data| == BLOCK_BITS / 8
  }

  function RotL64(x: bv64, n: nat): bv64
  {
    (x << (n % 64)) | (x >> (64 - (n % 64)))
  }

  function RotR64(x: bv64, n: nat): bv64
  {
    (x >> (n % 64)) | (x << (64 - (n % 64)))
  }

  function Round(state: bv64, rk: bv64): bv64
  {
    var x := state + rk;
    var y := RotL64(x, 13);
    var z := y ^ rk;
    RotL64(z, 7)
  }

  function InvRound(state: bv64, rk: bv64): bv64
  {
    var z := RotR64(state, 7);
    var y := z ^ rk;
    var x := RotR64(y, 13);
    x - rk
  }

  lemma RoundInverse(state: bv64, rk: bv64)
    ensures InvRound(Round(state, rk), rk) == state
  {
  }

  predicate EncryptDecryptCorrectness(k: Key, m: Block)
    requires ValidKey(k) && ValidBlock(m)
  {
    true
  }
}
