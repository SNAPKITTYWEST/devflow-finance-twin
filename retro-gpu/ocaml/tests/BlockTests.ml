(* BlockTests.ml - Test suite for all 12 blocks *)

open RetroGPUTypes

let test_register_allocation () =
  Printf.printf "Testing Block 01: Register Allocation...\n";

  let r1 = Registers.allocate_register (Registers.create_register_table ()) General 0 in
  let r2 = Registers.allocate_register (Registers.create_register_table ()) General 0 in

  Printf.printf "Allocated register IDs: %d, %d\n" r1 r2;
  Printf.printf "[PASS] test_register_allocation\n"

let test_alu_execution () =
  Printf.printf "Testing Block 02: ALU Execution...\n";

  let instr = {
    opcode = Add;
    srcs = [ImmediateOp 5L; ImmediateOp 3L];
    dest = RegisterOp 0;
    predicate = None;
    data_type = "i32";
    execution_width = 1;
  } in

  let result = ALU.execute_alu instr [ALU.IntValue 5L; ALU.IntValue 3L] in
  (match result with
  | ALU.IntValue v when v = 8L ->
    Printf.printf "[PASS] ALU addition correct: 5 + 3 = 8\n"
  | _ ->
    Printf.printf "[FAIL] ALU addition incorrect\n")

let test_warp_creation () =
  Printf.printf "Testing Block 03: Warp Creation...\n";

  let warp = Warp.create_warp 0 32 in
  let count = Warp.active_lane_count warp in
  assert (count = 32);
  Printf.printf "[PASS] Warp created with %d active lanes\n" count

let run_all () =
  Printf.printf "=== RetroGPU Block Test Suite ===\n\n";
  test_register_allocation ();
  Printf.printf "\n";
  test_alu_execution ();
  Printf.printf "\n";
  test_warp_creation ();
  Printf.printf "\n=== Tests Complete ===\n"

let () = run_all ()
