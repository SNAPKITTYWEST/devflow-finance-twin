(* Block 02: ALU - Arithmetic and Logical Execution *)

open RetroGPUTypes

(* Reference ALU semantics *)

type alu_value =
  | IntValue of int64
  | FloatValue of float
  | PredicateValue of bool

(* Helper: Value conversion *)

let int64_to_float (i: int64) : float =
  Int64.float_of_bits i

let float_to_int64 (f: float) : int64 =
  Int64.bits_of_float f

(* Type dispatch *)

let parse_value (data_type: string) (bits: int64) : alu_value =
  match data_type with
  | "i32" | "i64" -> IntValue bits
  | "f32" | "f64" -> FloatValue (int64_to_float bits)
  | "pred" -> PredicateValue (bits <> 0L)
  | _ -> failwith ("Unknown data type: " ^ data_type)

let value_to_bits (v: alu_value) : int64 =
  match v with
  | IntValue i -> i
  | FloatValue f -> float_to_int64 f
  | PredicateValue b -> if b then 1L else 0L

(* Reference ALU: Deterministic semantic interpreter *)

let execute_alu (instr: alu_instruction) (operand_values: alu_value list) : alu_value =
  match instr.opcode, operand_values with

  (* Integer operations *)
  | Add, [IntValue a; IntValue b] ->
    IntValue (Int64.add a b)

  | Sub, [IntValue a; IntValue b] ->
    IntValue (Int64.sub a b)

  | Mul, [IntValue a; IntValue b] ->
    IntValue (Int64.mul a b)

  | Div, [IntValue a; IntValue b] ->
    if b = 0L then failwith "Division by zero"
    else IntValue (Int64.div a b)

  | Mod, [IntValue a; IntValue b] ->
    if b = 0L then failwith "Modulo by zero"
    else IntValue (Int64.rem a b)

  (* Bitwise operations *)
  | BitwiseAnd, [IntValue a; IntValue b] ->
    IntValue (Int64.logand a b)

  | BitwiseOr, [IntValue a; IntValue b] ->
    IntValue (Int64.logor a b)

  | BitwiseXor, [IntValue a; IntValue b] ->
    IntValue (Int64.logxor a b)

  | ShiftLeft, [IntValue a; IntValue b] ->
    IntValue (Int64.shift_left a (Int64.to_int b))

  | ShiftRight, [IntValue a; IntValue b] ->
    IntValue (Int64.shift_right a (Int64.to_int b))

  (* Floating-point operations *)
  | FloatAdd, [FloatValue a; FloatValue b] ->
    FloatValue (a +. b)

  | FloatSub, [FloatValue a; FloatValue b] ->
    FloatValue (a -. b)

  | FloatMul, [FloatValue a; FloatValue b] ->
    FloatValue (a *. b)

  | FloatDiv, [FloatValue a; FloatValue b] ->
    if b = 0.0 then failwith "Float division by zero"
    else FloatValue (a /. b)

  (* Comparisons *)
  | Compare "eq", [IntValue a; IntValue b] ->
    PredicateValue (a = b)

  | Compare "lt", [IntValue a; IntValue b] ->
    PredicateValue (Int64.compare a b < 0)

  | Compare "gt", [IntValue a; IntValue b] ->
    PredicateValue (Int64.compare a b > 0)

  | Compare "le", [IntValue a; IntValue b] ->
    PredicateValue (Int64.compare a b <= 0)

  | Compare "ge", [IntValue a; IntValue b] ->
    PredicateValue (Int64.compare a b >= 0)

  | Compare "ne", [IntValue a; IntValue b] ->
    PredicateValue (a <> b)

  (* Fused Multiply-Add *)
  | FusedMultiplyAdd, [FloatValue a; FloatValue b; FloatValue c] ->
    FloatValue ((a *. b) +. c)

  | _ -> failwith "ALU instruction operand type mismatch"

(* ALU validation *)

type alu_validation_error =
  | InvalidOperandType of string
  | InvalidDataType of string
  | InvalidOpcodeForType of string * string
  | InvalidOperandCount of int * int
  | InvalidRegisterID of int

let validate_alu_instruction (instr: alu_instruction) : verification_result =
  let errors = ref [] in

  (* Check 1: Operand count matches opcode *)
  let expected_src_count = match instr.opcode with
    | FusedMultiplyAdd -> 3
    | _ -> 2
  in
  if List.length instr.srcs <> expected_src_count then
    errors := Printf.sprintf "Expected %d operands, got %d" expected_src_count (List.length instr.srcs) :: !errors;

  (* Check 2: Data type is valid *)
  (match instr.data_type with
  | "i32" | "i64" | "f32" | "f64" | "pred" -> ()
  | _ -> errors := ("Invalid data type: " ^ instr.data_type) :: !errors);

  (* Check 3: Opcode is valid for data type *)
  (match instr.opcode, instr.data_type with
  | (BitwiseAnd | BitwiseOr | BitwiseXor | ShiftLeft | ShiftRight), ("f32" | "f64") ->
    errors := "Bitwise operations not valid on floats" :: !errors
  | (FloatAdd | FloatSub | FloatMul | FloatDiv), ("i32" | "i64") ->
    errors := "Float operations not valid on integers" :: !errors
  | _ -> ());

  (* Check 4: Execution width is positive *)
  if instr.execution_width <= 0 then
    errors := "Execution width must be positive" :: !errors;

  if !errors = [] then
    Success
  else
    Failure (String.concat "; " !errors)

(* Deterministic ALU state machine *)

type alu_state = {
  last_result: alu_value option;
  last_predicate: bool;
  instruction_count: int;
}

let create_alu_state () : alu_state = {
  last_result = None;
  last_predicate = false;
  instruction_count = 0;
}

let execute_deterministic (alu: alu_state) (instr: alu_instruction)
    (operand_values: alu_value list) : alu_state =
  match validate_alu_instruction instr with
  | Failure msg -> failwith ("ALU validation failed: " ^ msg)
  | _ ->
    let result = execute_alu instr operand_values in
    let predicate = match result with
      | PredicateValue b -> b
      | _ -> alu.last_predicate
    in
    {
      last_result = Some result;
      last_predicate = predicate;
      instruction_count = alu.instruction_count + 1;
    }

(* Audit trail for determinism verification *)

let alu_trace_to_string (alu: alu_state) : string =
  Printf.sprintf "ALU State: instructions=%d, predicate=%b"
    alu.instruction_count
    alu.last_predicate
