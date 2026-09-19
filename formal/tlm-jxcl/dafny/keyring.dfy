module KeyRing {

  datatype KeyStatus = Active | DecryptOnly | Retired

  datatype KeyRingState = KeyRingState(entries: map<int, KeyStatus>)

  predicate AtMostOneActive(s: KeyRingState) {
    forall v1: int, v2: int ::
      v1 in s.entries && v2 in s.entries &&
      s.entries[v1] == Active && s.entries[v2] == Active ==>
      v1 == v2
  }

  predicate HasActiveKey(s: KeyRingState) {
    exists v :: v in s.entries && s.entries[v] == Active
  }

  function SetActive(s: KeyRingState, v: int): KeyRingState
    requires v in s.entries
  {
    KeyRingState(
      map ver | ver in s.entries ::
        if ver == v then Active
        else if s.entries[ver] == Active then DecryptOnly
        else s.entries[ver]
    )
  }

  predicate NoNewRetirements(before: KeyRingState, after: KeyRingState) {
    forall v :: v in before.entries && v in after.entries ==>
      (before.entries[v] != Retired ==> after.entries[v] != Retired)
  }

  lemma SetActivePreservesAtMostOne(s: KeyRingState, v: int)
    requires v in s.entries
    ensures AtMostOneActive(SetActive(s, v))
  {
    var after := SetActive(s, v);
    forall v1, v2 |
      v1 in after.entries && v2 in after.entries &&
      after.entries[v1] == Active && after.entries[v2] == Active
    ensures v1 == v2
    {
      assert after.entries[v1] == Active ==> v1 == v;
      assert after.entries[v2] == Active ==> v2 == v;
    }
  }

  lemma SetActiveNeverRetires(s: KeyRingState, v: int)
    requires v in s.entries
    ensures NoNewRetirements(s, SetActive(s, v))
  {
    var after := SetActive(s, v);
    forall ver | ver in s.entries && ver in after.entries && s.entries[ver] != Retired
    ensures after.entries[ver] != Retired
    {
      if ver == v {
        assert after.entries[ver] == Active;
      } else if s.entries[ver] == Active {
        assert after.entries[ver] == DecryptOnly;
      } else {
        assert after.entries[ver] == s.entries[ver];
      }
    }
  }

  lemma SetActiveActivatesTarget(s: KeyRingState, v: int)
    requires v in s.entries
    ensures SetActive(s, v).entries[v] == Active
  {}

  lemma SetActiveDemotesOthers(s: KeyRingState, v1: int, v: int)
    requires v in s.entries
    requires v1 in s.entries
    requires v1 != v
    requires s.entries[v1] == Active
    ensures SetActive(s, v).entries[v1] == DecryptOnly
  {}
}
