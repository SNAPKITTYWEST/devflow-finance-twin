(* Reference GEMM kernels in RetroGPU IR style
   C = A x B (naive, tiled, shared, warp, tensor variants)
*)
structure GEMM =
struct
  open RetroGPUCore
  open ALU
  open Kernel
  open Tensor

  fun makeNaiveGEMM (M, N, K) =
    let
      (* Extremely simplified IR representation of triple loop *)
      val bb = BB {
        id = 0,
        insts = [
          AluInst {op=MUL, dst=OpReg 2, src0=OpReg 0, src1=OpReg 1,
                   src2=NONE, dtype=DT_F32, width=1, pred=NONE, latency=4}
        ],
        preds = [], succs = [], liveIns = [0,1], liveOuts = [2],
        memEffects = [MS_Global], syncEffects = []
      }
    in
      KernelDef {
        id = 1, name = "naive_gemm",
        args = [
          Arg {name="A", space=MS_Global, dtype=DT_F32, size=M*K},
          Arg {name="B", space=MS_Global, dtype=DT_F32, size=K*N},
          Arg {name="C", space=MS_Global, dtype=DT_F32, size=M*N}
        ],
        blocks = [bb],
        grid = Dim3 {x=(M+15) div 16, y=(N+15) div 16, z=1},
        block = Dim3 {x=16, y=16, z=1},
        sharedMem = 0,
        regCount = 32,
        target = "hopper"
      }
    end

  fun makeTiledGEMM (M, N, K, tileM, tileN, tileK) =
    let
      val tile = Tile {m=M, n=N, k=K, tileM=tileM, tileN=tileN, tileK=tileK}
      val bbLoad = BB {
        id = 0, insts = [], preds = [], succs = [1],
        liveIns = [], liveOuts = [], memEffects = [MS_Global, MS_Shared],
        syncEffects = []
      }
      val bbCompute = BB {
        id = 1, insts = [], preds = [0], succs = [2],
        liveIns = [], liveOuts = [], memEffects = [MS_Shared, MS_Register],
        syncEffects = [Sync.OpBlockSync]
      }
      val bbStore = BB {
        id = 2, insts = [], preds = [1], succs = [],
        liveIns = [], liveOuts = [], memEffects = [MS_Register, MS_Global],
        syncEffects = []
      }
    in
      KernelDef {
        id = 2, name = "tiled_gemm",
        args = [
          Arg {name="A", space=MS_Global, dtype=DT_F32, size=M*K},
          Arg {name="B", space=MS_Global, dtype=DT_F32, size=K*N},
          Arg {name="C", space=MS_Global, dtype=DT_F32, size=M*N}
        ],
        blocks = [bbLoad, bbCompute, bbStore],
        grid = Dim3 {x=(M+tileM-1) div tileM, y=(N+tileN-1) div tileN, z=1},
        block = Dim3 {x=tileM, y=tileN, z=1},
        sharedMem = (tileM*tileK + tileK*tileN) * 4,
        regCount = 64,
        target = "hopper"
      }
    end
end
