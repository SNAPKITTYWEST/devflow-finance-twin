(* RetroGPUTypes.sml
   Core algebraic datatypes for GPU compilation
   All compiler objects are explicitly typed
*)

signature REGISTER_TYPES = sig
  datatype RegisterKind
    = General (* R0-R255 *)
    | Predicate (* P0-P7 *)
    | Accumulator (* Tensor accumulators *)
    | Special (* %tid, %ctaid, etc *)

  datatype RegisterWidth
    = W32
    | W64
    | W128

  type RegisterID = int
  type RegisterName = string

  datatype Register = Reg of {
    id : RegisterID,
    kind : RegisterKind,
    width : RegisterWidth,
    name : RegisterName,
    state : RegisterState
  }

  and RegisterState
    = Unallocated
    | Allocated of int
    | Spilled of int
    | Reserved

  type RegisterFile = Register list
end

signature OPERAND_TYPES = sig
  datatype Operand
    = RegOperand of int
    | ImmediateOperand of int
    | ImmediateLongOperand of int
    | LabelOperand of string
    | AddressOperand of {
        base : int option,
        offset : int,
        space : int
      }

  val operandToString : Operand -> string
  val operandWidth : Operand -> int
end

signature ALU_TYPES = sig
  datatype ALUOp
    = Add
    | Subtract
    | Multiply
    | Divide
    | Modulo
    | BitwiseAnd
    | BitwiseOr
    | BitwiseXor
    | LeftShift
    | RightShift
    | FloatAdd
    | FloatMultiply
    | FloatDivide
    | FusedMultiplyAdd
    | Compare of CompareOp

  and CompareOp
    = EQ | NE | LT | LE | GT | GE

  datatype DataType
    = Int32
    | Int64
    | Float32
    | Float64
    | Predicate

  datatype ALUInstruction = ALU of {
    op : ALUOp,
    dataType : DataType,
    srcA : Operand,
    srcB : Operand,
    dst : int,
    predicate : int option,
    negate : bool
  }

  val aluToString : ALUInstruction -> string
end

signature WARP_TYPES = sig
  type LaneID = int
  type WarpID = int

  datatype LaneState
    = Active
    | Inactive of string

  datatype WarpOp
    = Shuffle of { dir : string, dist : int }
    | Broadcast of int
    | Reduce of { op : string }
    | BarrierSync

  val activeLaneCount : LaneState list -> int
end

signature SHARED_MEMORY_TYPES = sig
  type SharedAddress = int
  type SharedBank = int

  datatype BankConflict
    = NoConflict
    | Conflict of int
    | Broadcast

  val addressToBank : SharedAddress -> int -> SharedBank
end

signature GLOBAL_MEMORY_TYPES = sig
  type GlobalAddress = int

  datatype MemoryOrder
    = Relaxed
    | Acquire
    | Release
    | AcquireRelease

  val validateAlignment : GlobalAddress * int -> bool
end

signature SYNCHRONIZATION_TYPES = sig
  datatype Barrier
    = ThreadBlockBarrier
    | WarpBarrier
    | NamedBarrier of string

  datatype SyncDomain
    = ThreadBlock
    | Warp
    | Named of string

  datatype MemoryFence
    = ThreadBlockFence
    | GPUFence
    | SystemFence

  datatype MemoryScope
    = ThreadScope
    | WarpScope
    | BlockScope
    | GPUScope

  datatype SyncInvariant
    = AllWarpsReach of Barrier
    | NoDeadlock
    | ProperOrdering

  val validateSyncPlacement : unit -> bool
end

signature TENSOR_TYPES = sig
  datatype TensorShape
    = Shape of { rows : int, cols : int, depth : int option }

  datatype TensorLayout
    = RowMajor
    | ColumnMajor
    | TensorLayout of string

  datatype TensorElementType
    = TF32
    | Float16
    | Float32
    | Float64
    | Int32
    | Int64

  val validateShape : TensorShape -> bool
end

signature KERNEL_TYPES = sig
  type BlockID = int

  datatype LaunchConfiguration
    = LaunchConfig of {
        gridDim : { x : int, y : int, z : int },
        blockDim : { x : int, y : int, z : int },
        sharedMemory : int,
        stream : int option
      }

  val validateLaunchConfig : LaunchConfiguration -> bool
end

signature HOPPER_TYPES = sig
  datatype HopperTarget = HopperTarget of {
    sm : int,
    warpWidth : int,
    numWarps : int,
    registerFileSize : int,
    sharedMemorySize : int,
    numTensorCores : int,
    instructionSet : string
  }

  datatype HopperConstraint
    = RegisterConstraint of int
    | MemoryConstraint of int
    | TensorConstraint of int
    | InstructionFormat of string

  val hopperTarget : HopperTarget
end
