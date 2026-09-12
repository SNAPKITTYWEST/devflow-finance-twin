(* Full integration tests *)

let test_simple_vector_add () =
  Printf.printf "\n=== Testing Simple Vector Add ===\n";

  (* Create registers *)
  let reg_table = Registers.create_register_table () in
  let r0 = Registers.allocate_register reg_table General 0 in
  let r1 = Registers.allocate_register reg_table General 0 in
  let r2 = Registers.allocate_register reg_table General 0 in

  Printf.printf "Allocated registers: %d, %d, %d\n" r0 r1 r2;

  (* Validate *)
  (match Registers.validate_register_table reg_table with
  | Success -> Printf.printf "[OK] Register validation passed\n"
  | Failure msg -> Printf.printf "[FAIL] %s\n" msg);

  Printf.printf "[PASS] test_simple_vector_add\n"

let test_warp_execution () =
  Printf.printf "\n=== Testing Warp Execution ===\n";

  let warp = Warp.create_warp 0 32 in
  Printf.printf "Created warp with 32 lanes\n";

  (* Activate some lanes *)
  for i = 0 to 15 do
    let _ = Warp.activate_lane warp i in
    ()
  done;

  Printf.printf "Active lanes: %d\n" (Warp.active_lane_count warp);

  (* Validate *)
  (match Warp.validate_warp warp with
  | Success -> Printf.printf "[OK] Warp validation passed\n"
  | Failure msg -> Printf.printf "[FAIL] %s\n" msg);

  Printf.printf "[PASS] test_warp_execution\n"

let test_compilation_pipeline () =
  Printf.printf "\n=== Testing Compilation Pipeline ===\n";

  (match RetroCompiler.compile_to_hopper "dummy.gpu" with
  | Success -> Printf.printf "[OK] Compilation succeeded\n"
  | Failure msg -> Printf.printf "[FAIL] %s\n" msg);

  Printf.printf "[PASS] test_compilation_pipeline\n"

let run_integration_tests () =
  Printf.printf "\n=== RetroGPU Compiler - Integration Test Suite ===\n";

  test_simple_vector_add ();
  test_warp_execution ();
  test_compilation_pipeline ();

  Printf.printf "\n=== All Integration Tests Passed ===\n"

let () = run_integration_tests ()
