(* Reference interpreter for RetroGPU IR *)

open RetroGPUTypes

type interpreter_state = {
  warps : Warp.warp_state array;
  global_memory : (address, int64) Hashtbl.t;
  shared_memory : (address, int64) Hashtbl.t;
  barriers_pending : int;
}

let create_interpreter (block_dim: block_dim) : interpreter_state = {
  warps = Array.init (block_dim.x / 32) (fun i -> Warp.create_warp i 32);
  global_memory = Hashtbl.create 1000;
  shared_memory = Hashtbl.create 1000;
  barriers_pending = 0;
}

(* Execute instruction on interpreter *)

let execute_instruction (interp: interpreter_state) (instr: instruction) : unit =
  match instr with
  | AluInstr alu_instr ->
    let alu_state = ALU.create_alu_state () in
    let _ = ALU.execute_deterministic alu_state alu_instr [] in
    ()
  | BarrierInstr sync ->
    interp.barriers_pending <- interp.barriers_pending + 1
  | MemoryInstr mem_access ->
    (match mem_access.space with
    | Global -> Hashtbl.add interp.global_memory mem_access.address 0L
    | Shared -> Hashtbl.add interp.shared_memory mem_access.address 0L
    | _ -> ())
  | _ -> ()

(* Validate interpreter state *)

let validate_interpreter (interp: interpreter_state) : verification_result =
  let errors = ref [] in

  (* Check all warps *)
  Array.iter (fun warp ->
    match Warp.validate_warp warp with
    | Failure msg -> errors := msg :: !errors
    | _ -> ()
  ) interp.warps;

  if !errors = [] then Success
  else Failure (String.concat "; " !errors)
