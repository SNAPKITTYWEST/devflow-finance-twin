(* GemmKernel.ml - Complete matrix multiply example *)

open RetroGPUTypes

let create_gemm_kernel ~m ~n ~k =
  let blocks = Hashtbl.create 5 in

  (* Block 1: Entry *)
  Hashtbl.add blocks 0 {
    id = 0;
    instructions = [
      AluInstr { opcode = Add; srcs = [RegisterOp 0; RegisterOp 1]; dest = RegisterOp 2;
                 predicate = None; data_type = "f32"; execution_width = 32 };
    ];
    predecessors = [];
    successors = [1];
    live_registers = [];
  };

  (* Block 2: Compute *)
  Hashtbl.add blocks 1 {
    id = 1;
    instructions = [
      BarrierInstr { kind = Barrier; domain = "block"; memory_order = AcquireRelease;
                     affected_warps = None };
    ];
    predecessors = [0];
    successors = [2];
    live_registers = [0; 1; 2];
  };

  (* Block 3: Store *)
  Hashtbl.add blocks 2 {
    id = 2;
    instructions = [];
    predecessors = [1];
    successors = [];
    live_registers = [0; 1; 2];
  };

  {
    name = Printf.sprintf "gemm_%dx%dx%d" m n k;
    blocks = blocks;
    entry_block = 0;
    exit_block = 2;
    register_file = Array.init 256 (fun i -> {
      id = i; kind = General; width = 32; active = false; owner = None
    });
    warp_model = [||];
  }

let create_launch_config ~grid_m ~grid_n ~block_m ~block_n kernel =
  {
    kernel = kernel;
    grid = { x = grid_m; y = grid_n; z = 1 };
    block = { x = block_m; y = block_n; z = 1 };
    shared_memory = 16384;
  }
