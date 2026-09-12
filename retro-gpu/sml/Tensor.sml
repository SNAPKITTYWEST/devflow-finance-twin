(* Blocks 07 + 08 - Tensor & Memory Movement *)
structure Tensor =
struct
  open RetroGPUCore

  datatype TensorLayout = RowMajor | ColMajor | Swizzled | Custom of int list

  datatype TensorShape = Shape of int list (* e.g. [M,N,K] *)

  datatype TensorFragment = Frag of {
    shape : TensorShape,
    layout : TensorLayout,
    dtype : DataType,
    elements : int,
    owner : MemorySpace
  }

  datatype TensorOp =
      TLoad of TensorFragment * Operand
    | TStore of TensorFragment * Operand
    | TMul of TensorFragment * TensorFragment * TensorFragment (* A,B,C *)
    | TFMA of TensorFragment * TensorFragment * TensorFragment
    | TAccumulate of TensorFragment * TensorFragment

  (* Tile descriptors for GEMM *)
  datatype Tile = Tile of {
    m : int, n : int, k : int,
    tileM : int, tileN : int, tileK : int
  }

  datatype Transfer = Transfer of {
    srcSpace : MemorySpace,
    dstSpace : MemorySpace,
    size : int,
    async : bool,
    dep : int option (* dependency token *)
  }
end
