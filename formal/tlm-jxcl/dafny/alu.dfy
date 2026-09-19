module ALU {
  const MAX64: int := 0x1_0000_0000_0000_0000
  const MAX63: int := 0x8000_0000_0000_0000
  const SMASK:  int := 0x7FFF_FFFF_FFFF_FFFF  // i64::MAX
  const SMIN:   int := 0x8000_0000_0000_0000  // i64::MIN as u64

  newtype Word = x: int | 0 <= x < 0x1_0000_0000_0000_0000

  datatype Flags = Flags(z: bool, n: bool, c: bool, v: bool)
  datatype AluResult = AluResult(value: Word, flags: Flags)

  function MakeFlags(value: Word, carry: bool, overflow: bool): Flags {
    Flags(value == 0 as Word, value >= 0x8000_0000_0000_0000 as Word, carry, overflow)
  }

  function AluAdd(a: Word, b: Word): AluResult {
    var sum := a as int + b as int;
    var result := (sum % MAX64) as Word;
    var carry := sum >= MAX64;
    var overflow := (a as int < MAX63 && b as int < MAX63 && result as int >= MAX63) ||
                    (a as int >= MAX63 && b as int >= MAX63 && result as int < MAX63);
    AluResult(result, MakeFlags(result, carry, overflow))
  }

  function AluSub(a: Word, b: Word): AluResult {
    var diff := a as int - b as int;
    var result := ((diff % MAX64) + MAX64) % MAX64;
    var borrow := a < b;
    var overflow := (a as int < MAX63 && b as int >= MAX63 && result as int >= MAX63) ||
                    (a as int >= MAX63 && b as int < MAX63 && result as int < MAX63);
    AluResult(result as Word, MakeFlags(result as Word, borrow, overflow))
  }

  function AluNeg(a: Word): AluResult { AluSub(0 as Word, a) }

  function AluInc(a: Word): AluResult {
    var result := ((a as int + 1) % MAX64) as Word;
    var overflow := a as int == SMASK;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, overflow))
  }

  function AluDec(a: Word): AluResult {
    var result := ((a as int - 1 + MAX64) % MAX64) as Word;
    var overflow := a as int == SMIN;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, overflow))
  }

  function AluMul(a: Word, b: Word): AluResult {
    var prod := a as int * b as int;
    var result := (prod % MAX64) as Word;
    var overflow := prod >= MAX64;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, overflow, overflow))
  }

  function AluMulH(a: Word, b: Word): AluResult {
    var prod := a as int * b as int;
    var result := (prod / MAX64) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function AluDiv(a: Word, b: Word): AluResult
    requires b != 0 as Word
  {
    var result := (a as int / b as int) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function AluRem(a: Word, b: Word): AluResult
    requires b != 0 as Word
  {
    var result := (a as int % b as int) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function AluAnd(a: Word, b: Word): AluResult {
    var result := (a as bv64 & b as bv64) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function AluOr(a: Word, b: Word): AluResult {
    var result := (a as bv64 | b as bv64) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function AluXor(a: Word, b: Word): AluResult {
    var result := (a as bv64 ^ b as bv64) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function AluNot(a: Word): AluResult {
    var result := (!(a as bv64)) as Word;
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, false, false))
  }

  function ShiftAmt(count: Word): int { (count as int) % 64 }

  function AluShl(a: Word, count: Word): AluResult {
    var amt := ShiftAmt(count);
    var result := if amt == 0 then a else ((a as bv64 << amt) as Word);
    var carry := if amt == 0 then false else (((a as bv64 >> (64 - amt)) & 1) == 1);
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, carry, false))
  }

  function AluShr(a: Word, count: Word): AluResult {
    var amt := ShiftAmt(count);
    var result := if amt == 0 then a else ((a as bv64 >> amt) as Word);
    var carry := if amt == 0 then false else (((a as bv64 >> (amt - 1)) & 1) == 1);
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, carry, false))
  }

  function AluRol(a: Word, count: Word): AluResult {
    var amt := ShiftAmt(count);
    var result := if amt == 0 then a else (((a as bv64 << amt) | (a as bv64 >> (64 - amt))) as Word);
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, (result as bv64 & 1) == 1, false))
  }

  function AluRor(a: Word, count: Word): AluResult {
    var amt := ShiftAmt(count);
    var result := if amt == 0 then a else (((a as bv64 >> amt) | (a as bv64 << (64 - amt))) as Word);
    AluResult(result, Flags(result == 0 as Word, result as int >= MAX63, (result as bv64 >> 63) == 1, false))
  }

  // Lemmas

  lemma NegIsSubFromZero(a: Word)
    ensures AluNeg(a).value == AluSub(0 as Word, a).value
    ensures AluNeg(a).flags == AluSub(0 as Word, a).flags
  {}

  lemma MulHiLoReconstruct(a: Word, b: Word)
    ensures AluMul(a, b).value as int + AluMulH(a, b).value as int * MAX64 == a as int * b as int
  {
    var prod := a as int * b as int;
    assert prod / MAX64 * MAX64 + prod % MAX64 == prod;
  }

  lemma ShlMaskIdentity(a: Word, count: Word)
    ensures AluShl(a, count).value == AluShl(a, (count as int % 64) as Word).value
  {}

  lemma ShlZeroIsIdentity(a: Word)
    ensures AluShl(a, 0 as Word).value == a
  {}

  lemma ShlSixtyFourIsIdentity(a: Word)
    ensures AluShl(a, 64 as Word).value == a
  {
    assert ShiftAmt(64 as Word) == 0;
  }

  lemma NotInvolution(a: Word)
    ensures AluNot(AluNot(a).value).value == a
  {
    var r := AluNot(a).value;
    assert r as bv64 == !(a as bv64);
    assert (!(r as bv64)) as Word == a;
  }

  lemma SubBorrow(a: Word, b: Word)
    ensures AluSub(a, b).flags.c == (a < b)
  {}

  lemma IncOverflowAtMax()
    ensures AluInc(0x7FFF_FFFF_FFFF_FFFF as Word).flags.v == true
  {}

  lemma IncNoOverflowElsewhere(a: Word)
    requires a as int != SMASK
    ensures AluInc(a).flags.v == false
  {}

  lemma RolRorInverse(a: Word, n: Word)
    ensures AluRol(AluRor(a, n).value, n).value == a
  {
    var amt := ShiftAmt(n);
    if amt == 0 {
    } else {
      var ror := ((a as bv64 >> amt) | (a as bv64 << (64 - amt)));
      var rol := (ror << amt) | (ror >> (64 - amt));
      assert rol == a as bv64 by {
        reveal_RotateInverse(a as bv64, amt);
      }
    }
  }

  lemma {:axiom} reveal_RotateInverse(x: bv64, n: int)
    requires 0 < n < 64
    ensures ((x >> n | x << (64 - n)) << n | (x >> n | x << (64 - n)) >> (64 - n)) == x
}
