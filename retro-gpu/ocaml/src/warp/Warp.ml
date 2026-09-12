(* Block 03: Warp - GPU execution group *)

open RetroGPUTypes

(* Warp state machine *)

type warp_execution_state =
  | Idle
  | Active
  | Diverged
  | Synchronized
  | Terminated

type warp_state = {
  warp_id : warp_id;
  mutable execution_state : warp_execution_state;
  mutable active_mask : bool array;
  mutable predicate_mask : bool array;
  mutable program_counter : int;
  lane_registers : (lane_id, int64 array) Hashtbl.t;
  mutable instruction_count : int;
}

(* Create warp *)

let create_warp (id: warp_id) (width: int) : warp_state = {
  warp_id = id;
  execution_state = Idle;
  active_mask = Array.make width true;
  predicate_mask = Array.make width true;
  program_counter = 0;
  lane_registers = Hashtbl.create width;
  instruction_count = 0;
}

(* Lane activation *)

let activate_lane (warp: warp_state) (lane: lane_id) : bool =
  if lane >= 0 && lane < Array.length warp.active_mask then (
    warp.active_mask.(lane) <- true;
    true
  ) else false

let deactivate_lane (warp: warp_state) (lane: lane_id) : bool =
  if lane >= 0 && lane < Array.length warp.active_mask then (
    warp.active_mask.(lane) <- false;
    true
  ) else false

(* Active lane count *)

let active_lane_count (warp: warp_state) : int =
  Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 warp.active_mask

(* Warp synchronization *)

let execute_barrier (warp: warp_state) : verification_result =
  if warp.execution_state = Diverged then
    Failure "Barrier encountered in divergent warp without reconvergence"
  else (
    warp.execution_state <- Synchronized;
    Success
  )

(* Warp divergence tracking *)

let set_predicate (warp: warp_state) (lane: lane_id) (value: bool) : bool =
  if lane >= 0 && lane < Array.length warp.predicate_mask then (
    warp.predicate_mask.(lane) <- value;

    (* Detect divergence *)
    let all_same = Array.for_all (fun p -> p = warp.predicate_mask.(0)) warp.predicate_mask in
    if not all_same && warp.execution_state = Active then
      warp.execution_state <- Diverged;

    true
  ) else false

(* Warp reductions *)

let warp_reduce_add (warp: warp_state) (values: int64 array) : int64 =
  Array.fold_left Int64.add 0L values

let warp_reduce_mul (warp: warp_state) (values: int64 array) : int64 =
  Array.fold_left Int64.mul 1L values

(* Warp broadcast *)

let warp_broadcast (warp: warp_state) (lane: lane_id) (value: int64) : int64 array =
  Array.make (Array.length warp.active_mask) value

(* Warp shuffle *)

let warp_shuffle (warp: warp_state) (src_lane: lane_id) (dest_lane: lane_id)
    (value: int64) : int64 option =
  if src_lane >= 0 && src_lane < Array.length warp.active_mask &&
     warp.active_mask.(src_lane) then
    Some value
  else
    None

(* Warp validation *)

let validate_warp (warp: warp_state) : verification_result =
  let errors = ref [] in

  (* Check 1: Active mask length matches predicate mask length *)
  if Array.length warp.active_mask <> Array.length warp.predicate_mask then
    errors := "Active and predicate mask lengths mismatch" :: !errors;

  (* Check 2: Program counter is non-negative *)
  if warp.program_counter < 0 then
    errors := "Negative program counter" :: !errors;

  (* Check 3: At least one lane is active *)
  if active_lane_count warp = 0 then
    errors := "No active lanes" :: !errors;

  (* Check 4: Divergence state consistency *)
  let all_same_pred = Array.for_all (fun p -> p = warp.predicate_mask.(0)) warp.predicate_mask in
  if warp.execution_state = Diverged && all_same_pred then
    errors := "Diverged state but all predicates match" :: !errors;

  if !errors = [] then Success
  else Failure (String.concat "; " !errors)

(* Serialization for audit *)

let warp_to_string (warp: warp_state) : string =
  let state_str = match warp.execution_state with
    | Idle -> "Idle"
    | Active -> "Active"
    | Diverged -> "Diverged"
    | Synchronized -> "Synchronized"
    | Terminated -> "Terminated"
  in
  Printf.sprintf "Warp(%d, %s, active=%d, pc=%d, instructions=%d)"
    warp.warp_id
    state_str
    (active_lane_count warp)
    warp.program_counter
    warp.instruction_count
