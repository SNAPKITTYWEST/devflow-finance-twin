(* Block 12 - Hopper Backend
   Consumes RetroGPU IR only. No LLVM, no CUDA source, no MLIR.
*)
structure Hopper =
struct
  open RetroGPUCore
  open Kernel
  open Instruction

  datatype HopperTarget = Target of {
    arch : string, (* "sm_90" *)
    warpWidth : int, (* 32 *)
    maxRegs : int,
    sharedMemKB : int,
    tensorCores : bool,
    maxThreadsPerBlock : int
  }

  val hopperDefault = Target {
    arch = "sm_90",
    warpWidth = 32,
    maxRegs = 255,
    sharedMemKB = 228,
    tensorCores = true,
    maxThreadsPerBlock = 1024
  }

  (* Lowering: Kernel IR -> HopperInstructionIR (still project-owned) *)
  fun lowerKernel (KernelDef k) =
    (* placeholder: identity for now; real lowering would map ALU/Tensor ops
       onto Hopper opcodes while staying inside RetroGPU IR *)
    KernelDef k

  fun scheduleHopper (k, policy) =
    let
      val instCount = 0 (* derive from blocks *)
    in
      Scheduler.schedule (instCount, [], policy)
    end

  fun encodeHopper (k) =
    (* Produce list of EncodedInst; concrete bit patterns only where documented *)
    []

  (* Final pipeline stage *)
  fun compileToHopper (m : Module, target : HopperTarget) =
    let
      val Module {kernels, ...} = m
      val lowered = List.map lowerKernel kernels
      val encoded = List.map encodeHopper lowered
    in
      (lowered, encoded, target)
    end

  (* Explicit unresolved interface for unknown encodings *)
  exception UnresolvedEncoding of string
end
