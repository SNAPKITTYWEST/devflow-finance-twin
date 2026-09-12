(* Block 10 - Kernel Launch + RetroGPU IR core *)
structure Kernel =
struct
  open RetroGPUCore
  open ALU
  open Warp
  open Tensor
  open Scheduler

  datatype Dim3 = Dim3 of {x:int, y:int, z:int}

  datatype KernelArg = Arg of {
    name : string,
    space : MemorySpace,
    dtype : DataType,
    size : int
  }

  datatype BasicBlock = BB of {
    id : int,
    insts : AluInst list, (* simplified; real IR is richer *)
    preds : int list,
    succs : int list,
    liveIns : int list,
    liveOuts : int list,
    memEffects : MemorySpace list,
    syncEffects : Sync.SyncOp list
  }

  datatype KernelDef = KernelDef of {
    id : int,
    name : string,
    args : KernelArg list,
    blocks : BasicBlock list,
    grid : Dim3,
    block : Dim3,
    sharedMem : int,
    regCount : int,
    target : string
  }

  datatype Launch = Launch of {
    kernel : KernelDef,
    grid : Dim3,
    block : Dim3,
    shared : int,
    args : KernelArg list
  }

  (* Minimal RetroGPU IR module *)
  datatype Module = Module of {
    version : string,
    kernels : KernelDef list
  }
end
