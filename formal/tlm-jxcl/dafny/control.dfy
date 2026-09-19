module Control {
  const MAX64: int := 0x1_0000_0000_0000_0000
  newtype Word = x: int | 0 <= x < 0x1_0000_0000_0000_0000

  datatype Flags = Flags(z: bool, n: bool, c: bool, v: bool)

  datatype Cond = JZ | JNZ | JC | JNC | JL | JGE | JG | JLE | JMP

  // PC-relative branch: pc_after + signed disp, wrapping
  function BranchTarget(pc_after: Word, disp: int): Word {
    var raw := pc_after as int + disp;
    (((raw % MAX64) + MAX64) % MAX64) as Word
  }

  function ConditionHolds(cond: Cond, f: Flags): bool {
    match cond {
      case JMP => true
      case JZ  => f.z
      case JNZ => !f.z
      case JC  => f.c
      case JNC => !f.c
      case JL  => f.n != f.v
      case JGE => f.n == f.v
      case JG  => !f.z && f.n == f.v
      case JLE => f.z || f.n != f.v
    }
  }

  lemma ZeroDisplacementIsNoop(pc: Word)
    ensures BranchTarget(pc, 0) == pc
  {}

  lemma BranchTargetReversible(pc: Word, d: int)
    ensures BranchTarget(BranchTarget(pc, d), -d) == pc
  {
    var mid := BranchTarget(pc, d);
    var raw1 := pc as int + d;
    var mid_val := ((raw1 % MAX64) + MAX64) % MAX64;
    var raw2 := mid_val + (-d);
    var final := ((raw2 % MAX64) + MAX64) % MAX64;
    assert final == pc as int by {
      assert raw2 == pc as int;
      assert ((pc as int % MAX64) + MAX64) % MAX64 == pc as int;
    }
  }

  lemma JZJNZComplementary(f: Flags)
    ensures ConditionHolds(JZ, f) == !ConditionHolds(JNZ, f)
  {}

  lemma JCJNCComplementary(f: Flags)
    ensures ConditionHolds(JC, f) == !ConditionHolds(JNC, f)
  {}

  lemma JLJGEComplementary(f: Flags)
    ensures ConditionHolds(JL, f) == !ConditionHolds(JGE, f)
  {}

  lemma JGJLEComplementary(f: Flags)
    ensures ConditionHolds(JG, f) == !ConditionHolds(JLE, f)
  {}

  lemma JGImpliesJGE(f: Flags)
    ensures ConditionHolds(JG, f) ==> ConditionHolds(JGE, f)
  {}

  lemma JLEIsZOrJL(f: Flags)
    ensures ConditionHolds(JLE, f) == (f.z || ConditionHolds(JL, f))
  {}
}
