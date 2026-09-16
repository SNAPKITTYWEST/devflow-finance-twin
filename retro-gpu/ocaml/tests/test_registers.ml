(* Unit tests for Register block *)

open RetroGPUTypes
open Registers

let test_allocate_single () =
  let table = create_register_table () in
  let id = allocate_register table General 1 in
  assert (id = 0);
  assert (get_register_state table id = Some (Allocated { owner_id = 1; timestamp = 0 }));
  Printf.printf "[PASS] test_allocate_single\n"

let test_allocate_multiple () =
  let table = create_register_table () in
  let id1 = allocate_register table General 1 in
  let id2 = allocate_register table Predicate 1 in
  let id3 = allocate_register table Accumulator 1 in
  assert (id1 = 0 && id2 = 1 && id3 = 2);
  assert (List.length (allocated_registers table) = 3);
  Printf.printf "[PASS] test_allocate_multiple\n"

let test_release () =
  let table = create_register_table () in
  let id = allocate_register table General 1 in
  assert (release_register table id = true);
  assert (get_register_state table id = Some Free);
  Printf.printf "[PASS] test_release\n"

let test_release_nonexistent () =
  let table = create_register_table () in
  assert (release_register table 999 = false);
  Printf.printf "[PASS] test_release_nonexistent\n"

let test_reserve () =
  let table = create_register_table () in
  let id = allocate_register table General 1 in
  release_register table id;
  assert (reserve_register table id = true);
  assert (get_register_state table id = Some Reserved);
  Printf.printf "[PASS] test_reserve\n"

let test_validation_success () =
  let table = create_register_table () in
  let _id1 = allocate_register table General 1 in
  let _id2 = allocate_register table Predicate 2 in
  let result = validate_register_table table in
  assert (result = Success);
  Printf.printf "[PASS] test_validation_success\n"

let test_statistics () =
  let table = create_register_table () in
  let id1 = allocate_register table General 1 in
  let id2 = allocate_register table Predicate 2 in
  release_register table id1;
  reserve_register table id2;

  let stats = get_statistics table in
  assert (stats.allocated = 1);
  assert (stats.free = 1);
  assert (stats.reserved = 1);
  Printf.printf "[PASS] test_statistics\n"

let test_deterministic_allocation () =
  (* Test: identical inputs produce identical outputs *)
  let table1 = create_register_table () in
  let table2 = create_register_table () in

  let _ = allocate_register table1 General 1 in
  let _ = allocate_register table1 Predicate 1 in
  let _ = allocate_register table1 Accumulator 1 in

  let _ = allocate_register table2 General 1 in
  let _ = allocate_register table2 Predicate 1 in
  let _ = allocate_register table2 Accumulator 1 in

  let stats1 = get_statistics table1 in
  let stats2 = get_statistics table2 in

  assert (stats1.total_registers = stats2.total_registers);
  assert (stats1.allocated = stats2.allocated);
  Printf.printf "[PASS] test_deterministic_allocation\n"

let run_all_tests () =
  Printf.printf "\n=== Running Register Block Tests ===\n";
  test_allocate_single ();
  test_allocate_multiple ();
  test_release ();
  test_release_nonexistent ();
  test_reserve ();
  test_validation_success ();
  test_statistics ();
  test_deterministic_allocation ();
  Printf.printf "=== All Register Tests Passed ===\n\n"

let () = run_all_tests ()
