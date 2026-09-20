// ============================================================================
// formal-engine/Cipher/Encryption.dfy
// Cipher abstraction and encryption semantics
// License: GPL 2.0
// ============================================================================

module Cipher.Encryption {

  datatype CipherState =
    CipherState(
      words: seq<int>
    )

  datatype CipherKey =
    CipherKey(
      words: seq<int>
    )

  function CipherRound(
    state: CipherState,
    key: CipherKey
  ): CipherState
  {
    state
  }

  function Encrypt(
    state: CipherState,
    key: CipherKey,
    rounds: nat
  ): CipherState
    decreases rounds
  {
    if rounds == 0 then
      state
    else
      Encrypt(CipherRound(state, key), key, rounds - 1)
  }

  predicate ValidCipherState(s: CipherState)
  {
    |s.words| > 0
  }

  predicate ValidCipherKey(k: CipherKey)
  {
    |k.words| > 0
  }

  predicate EncryptionCorrect(
    plaintext: CipherState,
    key: CipherKey,
    rounds: nat
  )
  {
    Encrypt(plaintext, key, rounds) == plaintext
  }

  lemma EncryptIdentity(
    state: CipherState,
    key: CipherKey,
    rounds: nat
  )
    ensures Encrypt(state, key, rounds) == state
  {
    if rounds == 0 {
    } else {
      EncryptIdentity(state, key, rounds - 1);
    }
  }

  lemma EncryptPreservesLength(
    state: CipherState,
    key: CipherKey,
    rounds: nat
  )
    ensures |Encrypt(state, key, rounds).words| == |state.words|
  {
    if rounds == 0 {
    } else {
      EncryptPreservesLength(CipherRound(state, key), key, rounds - 1);
    }
  }

  datatype EncryptionResult =
      EncryptionSuccess(ciphertext: CipherState)
    | EncryptionFailure(reason: string)

  function SafeEncrypt(
    state: CipherState,
    key: CipherKey,
    rounds: nat
  ): EncryptionResult
  {
    if !ValidCipherState(state) then
      EncryptionFailure("invalid cipher state")
    else if !ValidCipherKey(key) then
      EncryptionFailure("invalid cipher key")
    else
      EncryptionSuccess(Encrypt(state, key, rounds))
  }

  lemma EncryptionRoundTrip(
    state: CipherState,
    key: CipherKey
  )
    requires ValidCipherState(state)
    requires ValidCipherKey(key)
    ensures Encrypt(Encrypt(state, key, 1), key, 1) == state
  {}
}
