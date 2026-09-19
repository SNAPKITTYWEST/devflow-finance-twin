module Flags {
  datatype Flags = Flags(z: bool, n: bool, c: bool, v: bool)
  datatype FlagEffect = FlagEffect(z: bool, n: bool, c: bool, v: bool)

  const NONE: FlagEffect := FlagEffect(false, false, false, false)
  const FULL: FlagEffect := FlagEffect(true, true, true, true)

  // Encode: bit0=Z, bit1=N, bit2=C, bit3=V
  function ToBits(f: Flags): int
    ensures 0 <= ToBits(f) < 16
  {
    (if f.z then 1 else 0) +
    (if f.n then 2 else 0) +
    (if f.c then 4 else 0) +
    (if f.v then 8 else 0)
  }

  function FromBits(b: int): Flags
    requires 0 <= b < 16
  {
    Flags(b % 2 == 1, (b / 2) % 2 == 1, (b / 4) % 2 == 1, (b / 8) % 2 == 1)
  }

  function ApplyEffect(current: int, effect: FlagEffect, fresh: Flags): int
    requires 0 <= current < 16
    ensures 0 <= ApplyEffect(current, effect, fresh) < 16
  {
    var cur := FromBits(current);
    var zb := if effect.z then fresh.z else cur.z;
    var nb := if effect.n then fresh.n else cur.n;
    var cb := if effect.c then fresh.c else cur.c;
    var vb := if effect.v then fresh.v else cur.v;
    ToBits(Flags(zb, nb, cb, vb))
  }

  lemma FlagsRoundTrip(f: Flags)
    ensures FromBits(ToBits(f)) == f
  {
    var b := ToBits(f);
    assert b / 8 % 2 == (if f.v then 1 else 0);
    assert b / 4 % 2 == (if f.c then 1 else 0);
    assert b / 2 % 2 == (if f.n then 1 else 0);
    assert b % 2     == (if f.z then 1 else 0);
  }

  lemma ApplyNoneIsIdentity(bits: int, f: Flags)
    requires 0 <= bits < 16
    ensures ApplyEffect(bits, NONE, f) == bits
  {
    var cur := FromBits(bits);
    FlagsRoundTrip(cur);
  }

  lemma ApplyFullIsOverwrite(bits: int, f: Flags)
    requires 0 <= bits < 16
    ensures ApplyEffect(bits, FULL, f) == ToBits(f)
  {}

  lemma BitIsolation()
    ensures forall z: bool, n: bool, c: bool, v: bool ::
      var f := Flags(z, n, c, v);
      ToBits(f) / 1 % 2 == (if z then 1 else 0) &&
      ToBits(f) / 2 % 2 == (if n then 1 else 0) &&
      ToBits(f) / 4 % 2 == (if c then 1 else 0) &&
      ToBits(f) / 8 % 2 == (if v then 1 else 0)
  {}
}
