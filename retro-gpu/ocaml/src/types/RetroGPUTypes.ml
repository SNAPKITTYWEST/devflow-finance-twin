(* RetroGPU Type System - Complete algebraic types for GPU compilation *)

(* REGISTERS ================================================================ *)

type register_kind =
  | General
  | Predicate
  | Accumulator
  | Special of string

type register_id = int

type register = {
  id : register_id;
  kind : register_kind;
  width : int;  (* bits *)
  mutable active : bool;
  mutable owner : int option;  (* warp or kernel ID *)
}

(* ALU OPERATIONS =========================================================== *)

type alu_opcode =
  | Add | Sub | Mul | Div | Mod
  | BitwiseAnd | BitwiseOr | BitwiseXor | ShiftLeft | ShiftRight
  | FloatAdd | FloatSub | FloatMul | FloatDiv
  | Compare of string  (* "eq", "lt", "gt", etc *)
  | FusedMultiplyAdd

type operand =
  | RegisterOp of register_id
  | ImmediateOp of int64
  | LabelOp of string

type alu_instruction = {
  opcode : alu_opcode;
  srcs : operand list;
  dest : operand;
  predicate : register_id option;
  data_type : string;  (* "i32", "f32", "f64", etc *)
  execution_width : int;
}

(* WARP SEMANTICS ========================================================== *)

type lane_id = int

type lane_state = {
  id : lane_id;
  mutable pc : int;
  mutable active : bool;
  mutable predicate : bool;
  registers : register array;
}

type warp_id = int

type warp = {
  id : warp_id;
  lanes : lane_state array;
  mutable active_mask : bool array;
  mutable program_counter : int;
}

(* MEMORY SPACES =========================================================== *)

type memory_space =
  | Global
  | Shared
  | Register
  | Local
  | Constant
  | Texture
  | Surface

type address = int64

type memory_access = {
  space : memory_space;
  address : address;
  width : int;
  alignment : int;
  ordered : bool;
  volatile : bool;
}

(* TENSOR OPERATIONS ====================================================== *)

type tensor_shape = {
  m : int;
  n : int;
  k : int option;
}

type tensor_layout =
  | RowMajor
  | ColMajor
  | TensorCore

type tensor_element_type =
  | TF32 | BF16 | F16 | F32 | F64 | I8 | I16 | I32

type tensor_fragment = {
  shape : tensor_shape;
  layout : tensor_layout;
  element_type : tensor_element_type;
  registers : register_id list;
}

(* SYNCHRONIZATION ======================================================== *)

type sync_kind =
  | Barrier
  | MemoryFence
  | WarpSync
  | BlockSync

type memory_order =
  | Relaxed
  | Acquire
  | Release
  | AcquireRelease

type synchronization = {
  kind : sync_kind;
  domain : string;
  memory_order : memory_order;
  affected_warps : warp_id list option;
}

(* SCHEDULING ============================================================= *)

type dependency =
  | DataDependency of int * int  (* instruction IDs *)
  | MemoryDependency of int * int
  | SynchronizationDependency of int * int
  | ResourceDependency of string

type schedule = {
  instructions : int array;  (* ordered instruction IDs *)
  issue_times : int array;   (* cycle at which each instruction issues *)
  dependencies : (int, dependency list) Hashtbl.t;
}

(* KERNEL REPRESENTATION ================================================== *)

type block_id = int

type instruction =
  | AluInstr of alu_instruction
  | MemoryInstr of memory_access
  | BarrierInstr of synchronization
  | TensorInstr of tensor_fragment
  | LaunchInstr

type basic_block = {
  id : block_id;
  instructions : instruction list;
  predecessors : block_id list;
  successors : block_id list;
  mutable live_registers : register_id list;
}

type kernel = {
  name : string;
  blocks : (block_id, basic_block) Hashtbl.t;
  entry_block : block_id;
  exit_block : block_id;
  register_file : register array;
  warp_model : warp array;
}

type grid_dim = { x : int; y : int; z : int }
type block_dim = { x : int; y : int; z : int }

type launch_configuration = {
  kernel : kernel;
  grid : grid_dim;
  block : block_dim;
  shared_memory : int;
}

(* INSTRUCTION ENCODING ================================================== *)

type opcode_encoding = int
type operand_encoding = int

type machine_instruction = {
  opcode : opcode_encoding;
  operands : operand_encoding list;
  predicate : opcode_encoding option;
  encoding : int64;
}

(* TARGET MACHINE MODEL ================================================== *)

type target_architecture =
  | Hopper
  | Ada
  | Ampere

type machine_model = {
  architecture : target_architecture;
  warp_width : int;
  warps_per_block : int;
  registers_per_warp : int;
  shared_memory_size : int;
  max_block_dim : block_dim;
  tensor_core_units : int;
}

(* VERIFICATION RESULTS ================================================== *)

type verification_result =
  | Success
  | Failure of string
  | Warning of string list

type invariant_check = {
  name : string;
  check : unit -> verification_result;
}

(* COMPILER STATE ======================================================== *)

type compilation_stage =
  | Parsing
  | TypeChecking
  | IRConstruction
  | RegisterAllocation
  | MemoryAnalysis
  | Scheduling
  | InstructionSelection
  | Encoding
  | HopperBackend

type compilation_context = {
  stage : compilation_stage;
  kernel : kernel option;
  machine : machine_model;
  schedule : schedule option;
  warnings : string list;
  errors : string list;
}
