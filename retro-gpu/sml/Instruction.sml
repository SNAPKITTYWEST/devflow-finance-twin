(* Block 11 - Instruction Encoding *)
structure Instruction =
struct
  open RetroGPUCore
  open ALU

  datatype Opcode =
      OPC_ALU of AluOp
    | OPC_LD | OPC_ST | OPC_ATOM
    | OPC_BAR | OPC_FENCE
    | OPC_SHFL | OPC_VOTE | OPC_REDUX
    | OPC_HMMA | OPC_IMMA | OPC_DMMA (* tensor *)
    | OPC_NOP | OPC_EXIT

  datatype EncodedInst = Encoded of {
    opcode : Opcode,
    dst : Operand,
    src0 : Operand,
    src1 : Operand,
    pred : Operand option,
    imm : int option,
    encoding : Word64.word option, (* concrete bits when known *)
    valid : bool
  }

  fun encode (opc, dst, src0, src1, pred, imm) =
    Encoded {
      opcode = opc, dst = dst, src0 = src0, src1 = src1,
      pred = pred, imm = imm,
      encoding = NONE, (* Hopper concrete encoding left unresolved where unknown *)
      valid = true
    }

  fun validate (Encoded e) = #valid e
end
