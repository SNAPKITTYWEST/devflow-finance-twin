(* Block 01: Register Management *)

open RetroGPUTypes

(* Register allocation state machine *)

type allocation_state =
  | Free
  | Allocated of { owner_id: int; timestamp: int }
  | Reserved
  | Spilled

type register_table = {
  mutable registers : (register_id, register * allocation_state) Hashtbl.t;
  mutable next_id : register_id;
  mutable allocation_counter : int;
}

(* Create register table *)

let create_register_table () : register_table = {
  registers = Hashtbl.create 256;
  next_id = 0;
  allocation_counter = 0;
}

(* Allocate a new register *)

let allocate_register (table: register_table) (kind: register_kind)
    (owner_id: int) : register_id =
  let id = table.next_id in
  let reg = {
    id = id;
    kind = kind;
    width = (match kind with
      | General -> 32
      | Predicate -> 1
      | Accumulator -> 64
      | Special _ -> 32);
    active = true;
    owner = Some owner_id;
  } in
  Hashtbl.add table.registers id (reg, Allocated { owner_id; timestamp = table.allocation_counter });
  table.next_id <- table.next_id + 1;
  table.allocation_counter <- table.allocation_counter + 1;
  id

(* Release a register *)

let release_register (table: register_table) (reg_id: register_id) : bool =
  try
    let (reg, state) = Hashtbl.find table.registers reg_id in
    (match state with
    | Allocated _ ->
      Hashtbl.replace table.registers reg_id (reg, Free);
      true
    | Free ->
      Printf.eprintf "Warning: Releasing already-free register %d\n" reg_id;
      false
    | _ -> false)
  with Not_found -> false

(* Query register state *)

let get_register_state (table: register_table) (reg_id: register_id) : allocation_state option =
  try
    let (_, state) = Hashtbl.find table.registers reg_id in
    Some state
  with Not_found -> None

(* List all allocated registers *)

let allocated_registers (table: register_table) : register_id list =
  Hashtbl.fold (fun id (_, state) acc ->
    match state with
    | Allocated _ -> id :: acc
    | _ -> acc
  ) table.registers []

(* List free registers *)

let free_registers (table: register_table) : register_id list =
  Hashtbl.fold (fun id (_, state) acc ->
    match state with
    | Free -> id :: acc
    | _ -> acc
  ) table.registers []

(* Validate register invariants *)

let validate_register_table (table: register_table) : verification_result =
  let allocated = allocated_registers table in
  let errors = ref [] in

  (* Check 1: No duplicate allocations *)
  let seen = Hashtbl.create (List.length allocated) in
  List.iter (fun id ->
    if Hashtbl.mem seen id then
      errors := ("Duplicate allocation of register " ^ string_of_int id) :: !errors
    else
      Hashtbl.add seen id true
  ) allocated;

  (* Check 2: All allocated registers are active *)
  List.iter (fun id ->
    try
      let (reg, Allocated { owner_id; _ }) = Hashtbl.find table.registers id in
      if not reg.active then
        errors := ("Allocated but inactive register " ^ string_of_int id) :: !errors;
      if reg.owner <> Some owner_id then
        errors := ("Register ownership mismatch: " ^ string_of_int id) :: !errors
    with Not_found | Match_failure _ ->
      errors := ("Register state corruption: " ^ string_of_int id) :: !errors
  ) allocated;

  (* Check 3: Allocation counter is monotonically increasing *)
  if table.allocation_counter < 0 then
    errors := "Negative allocation counter" :: !errors;

  if !errors = [] then
    Success
  else
    Failure (String.concat "; " !errors)

(* Spill register to memory *)

let spill_register (table: register_table) (reg_id: register_id)
    (spill_address: address) : bool =
  try
    let (reg, Allocated info) = Hashtbl.find table.registers reg_id in
    Hashtbl.replace table.registers reg_id (reg, Spilled);
    true
  with Not_found | Match_failure _ -> false

(* Reserve register (prevent allocation) *)

let reserve_register (table: register_table) (reg_id: register_id) : bool =
  try
    let (reg, state) = Hashtbl.find table.registers reg_id in
    (match state with
    | Free ->
      Hashtbl.replace table.registers reg_id (reg, Reserved);
      true
    | _ -> false)
  with Not_found -> false

(* Unreserve register *)

let unreserve_register (table: register_table) (reg_id: register_id) : bool =
  try
    let (reg, Reserved) = Hashtbl.find table.registers reg_id in
    Hashtbl.replace table.registers reg_id (reg, Free);
    true
  with Not_found | Match_failure _ -> false

(* Statistics *)

type register_statistics = {
  total_registers : int;
  allocated : int;
  free : int;
  reserved : int;
  spilled : int;
}

let get_statistics (table: register_table) : register_statistics =
  let allocated = ref 0 in
  let free = ref 0 in
  let reserved = ref 0 in
  let spilled = ref 0 in

  Hashtbl.iter (fun _ (_, state) ->
    match state with
    | Allocated _ -> incr allocated
    | Free -> incr free
    | Reserved -> incr reserved
    | Spilled -> incr spilled
  ) table.registers;

  {
    total_registers = table.next_id;
    allocated = !allocated;
    free = !free;
    reserved = !reserved;
    spilled = !spilled;
  }

(* Serialization for audit trail *)

let register_to_string (table: register_table) (reg_id: register_id) : string =
  try
    let (reg, state) = Hashtbl.find table.registers reg_id in
    let state_str = match state with
      | Free -> "Free"
      | Allocated { owner_id; timestamp } ->
        Printf.sprintf "Allocated(owner=%d, time=%d)" owner_id timestamp
      | Reserved -> "Reserved"
      | Spilled -> "Spilled"
    in
    Printf.sprintf "Register(%d, kind=%s, width=%d, %s)"
      reg.id
      (match reg.kind with
      | General -> "General"
      | Predicate -> "Predicate"
      | Accumulator -> "Accumulator"
      | Special s -> "Special:" ^ s)
      reg.width
      state_str
  with Not_found -> Printf.sprintf "Register(%d, INVALID)" reg_id

let dump_register_table (table: register_table) : string =
  let allocated = allocated_registers table in
  let lines = List.map (register_to_string table) allocated in
  String.concat "\n" lines
