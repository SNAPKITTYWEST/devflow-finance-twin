(* Block 02 - ALU *)
structure ALU =
struct
  open RetroGPUCore

  datatype AluOp =
      ADD | SUB | MUL | DIV | MOD
    | AND | OR | XOR | SHL | SHR | SAR
    | CMP_EQ | CMP_NE | CMP_LT | CMP_LE | CMP_GT | CMP_GE
    | FADD | FSUB | FMUL | FDIV | FMA
    | SEL | NOT | NEG | ABS
    | POPC | CLZ | BREV

  datatype AluInst = AluInst of {
    op : AluOp,
    dst : Operand,
    src0 : Operand,
    src1 : Operand,
    src2 : Operand option, (* for FMA *)
    dtype : DataType,
    width : int, (* execution width in elements *)
    pred : Operand option, (* guarding predicate *)
    latency : int (* abstract latency units *)
  }

  (* Reference interpreter - semantic oracle *)
  fun evalInt ADD a b = a + b
    | evalInt SUB a b = a - b
    | evalInt MUL a b = a * b
    | evalInt DIV a b = if b = 0 then 0 else a div b
    | evalInt MOD a b = if b = 0 then 0 else a mod b
    | evalInt AND a b = Word.toInt (Word.andb (Word.fromInt a, Word.fromInt b))
    | evalInt OR a b = Word.toInt (Word.orb (Word.fromInt a, Word.fromInt b))
    | evalInt XOR a b = Word.toInt (Word.xorb (Word.fromInt a, Word.fromInt b))
    | evalInt SHL a b = Word.toInt (Word.<< (Word.fromInt a, Word.fromInt b))
    | evalInt SHR a b = Word.toInt (Word.>> (Word.fromInt a, Word.fromInt b))
    | evalInt _ a b = a (* fallback *)

  fun opToString ADD = "ADD" | opToString SUB = "SUB" | opToString MUL = "MUL"
    | opToString DIV = "DIV" | opToString MOD = "MOD" | opToString AND = "AND"
    | opToString OR = "OR" | opToString XOR = "XOR" | opToString SHL = "SHL"
    | opToString SHR = "SHR" | opToString SAR = "SAR" | opToString FADD = "FADD"
    | opToString FSUB = "FSUB" | opToString FMUL = "FMUL" | opToString FDIV = "FDIV"
    | opToString FMA = "FMA" | opToString SEL = "SEL" | opToString NOT = "NOT"
    | opToString NEG = "NEG" | opToString ABS = "ABS" | opToString POPC = "POPC"
    | opToString CLZ = "CLZ" | opToString BREV = "BREV"
    | opToString CMP_EQ = "CMP_EQ" | opToString CMP_NE = "CMP_NE"
    | opToString CMP_LT = "CMP_LT" | opToString CMP_LE = "CMP_LE"
    | opToString CMP_GT = "CMP_GT" | opToString CMP_GE = "CMP_GE"
end
