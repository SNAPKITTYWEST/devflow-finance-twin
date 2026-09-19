module Registers {
  const MAX64: int := 0x1_0000_0000_0000_0000
  newtype Word = x: int | 0 <= x < 0x1_0000_0000_0000_0000

  datatype RegisterFile = RegisterFile(gp: seq<Word>, pc: Word, sp: Word, fp: Word, flags_word: Word)

  predicate ValidRegFile(r: RegisterFile) {
    |r.gp| == 32 && r.gp[0] == 0 as Word
  }

  function RegRead(r: RegisterFile, id: int): Word
    requires ValidRegFile(r)
    requires 0 <= id < 32
  {
    if id == 0 then 0 as Word else r.gp[id]
  }

  function RegWrite(r: RegisterFile, id: int, value: Word): RegisterFile
    requires ValidRegFile(r)
    requires 0 <= id < 32
  {
    if id == 0 then r
    else r.(gp := r.gp[id := value])
  }

  lemma R0AlwaysZero(r: RegisterFile, v: Word)
    requires ValidRegFile(r)
    ensures RegRead(RegWrite(r, 0, v), 0) == 0 as Word
  {}

  lemma WriteReadSameReg(r: RegisterFile, id: int, v: Word)
    requires ValidRegFile(r)
    requires 1 <= id < 32
    ensures RegRead(RegWrite(r, id, v), id) == v
  {}

  lemma WriteReadDiffReg(r: RegisterFile, id1: int, id2: int, v: Word)
    requires ValidRegFile(r)
    requires 0 <= id1 < 32
    requires 0 <= id2 < 32
    requires id1 != id2
    ensures RegRead(RegWrite(r, id1, v), id2) == RegRead(r, id2)
  {
    if id1 == 0 {
    } else {
      assert RegWrite(r, id1, v).gp[id2] == r.gp[id2];
    }
  }

  lemma WritePreservesValidity(r: RegisterFile, id: int, v: Word)
    requires ValidRegFile(r)
    requires 0 <= id < 32
    ensures ValidRegFile(RegWrite(r, id, v))
  {
    if id == 0 {
    } else {
      assert |RegWrite(r, id, v).gp| == 32;
      assert RegWrite(r, id, v).gp[0] == r.gp[0] == 0 as Word;
    }
  }
}
