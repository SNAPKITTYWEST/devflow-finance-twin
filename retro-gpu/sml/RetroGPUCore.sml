(* RetroGPU Core Types - shared across all blocks *)
structure RetroGPUCore =
struct
  datatype DataType =
      DT_I8 | DT_I16 | DT_I32 | DT_I64
    | DT_U8 | DT_U16 | DT_U32 | DT_U64
    | DT_F16 | DT_BF16 | DT_F32 | DT_F64
    | DT_PRED | DT_TF32

  datatype MemorySpace =
      MS_Register | MS_Shared | MS_Global | MS_Local | MS_Constant | MS_Special

  datatype MemoryOrder =
      MO_Relaxed | MO_Acquire | MO_Release | MO_AcqRel | MO_SeqCst

  type WarpWidth = int (* parameterized; Hopper default 32 *)
  type LaneID = int
  type WarpID = int
  type BlockID = int
  type GridID = int

  datatype Operand =
      OpReg of int (* RegisterID *)
    | OpImm of int (* immediate *)
    | OpAddr of MemorySpace * int (* address space + offset *)
    | OpPred of int (* predicate register *)
    | OpNone

  fun dtToString DT_I8 = "i8" | dtToString DT_I16 = "i16" | dtToString DT_I32 = "i32"
    | dtToString DT_I64 = "i64" | dtToString DT_U8 = "u8" | dtToString DT_U16 = "u16"
    | dtToString DT_U32 = "u32" | dtToString DT_U64 = "u64" | dtToString DT_F16 = "f16"
    | dtToString DT_BF16 = "bf16" | dtToString DT_F32 = "f32" | dtToString DT_F64 = "f64"
    | dtToString DT_PRED = "pred" | dtToString DT_TF32 = "tf32"
end
