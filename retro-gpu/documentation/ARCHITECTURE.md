# RetroGPU Compiler Architecture

## Overview

RetroGPU is a complete GPU compiler stack replacing CUDA and LLVM, built from first principles using Modula-2 and Standard ML.

## Design Philosophy

- **Deterministic compilation**: Identical inputs produce identical outputs
- **Explicit semantics**: No hidden state, no opaque optimizations
- **Modular architecture**: Each block is independently testable
- **Formal verification**: Every component validates its invariants
- **Auditable transforms**: Complete trace from source to machine code

## System Architecture (12 Blocks)

```
Block 01: Registers
  - Type: register_id, register_kind, allocation_state
  - Operations: allocate, release, validate, spill

Block 02: ALU
  - Type: alu_opcode, operand, alu_instruction
  - Semantics: reference interpreter for all operations

Block 03: Warp
  - Type: warp_id, lane_state, warp_execution_state
  - Operations: divergence tracking, synchronization, reduction

Block 04: Shared Memory
  - Type: memory_access, shared_address, bank
  - Analysis: bank conflicts, alignment verification

Block 05: Global Memory
  - Type: memory_space, address, memory_order
  - Semantics: explicit memory ownership and ordering

Block 06: Synchronization
  - Type: synchronization, memory_order, sync_domain
  - Verification: barrier placement, memory visibility

Block 07: Tensor Operations
  - Type: tensor_shape, tensor_fragment, tensor_layout
  - Semantics: independent of CUDA tensor core syntax

Block 08: Memory Movement
  - Type: tile, matrix_view, transfer_dependency
  - Framework: explicit tiling, asynchronous movement

Block 09: Scheduling
  - Type: dependency, schedule, issue_time
  - Algorithm: deterministic dependency-based scheduling

Block 10: Kernel Launch
  - Type: launch_configuration, grid_dim, block_dim
  - Model: independent kernel launch abstraction

Block 11: Instruction Encoding
  - Type: opcode_encoding, machine_instruction
  - Operations: encode, decode, validate

Block 12: Hopper Backend
  - Target: NVIDIA Hopper architecture
  - Mapping: project IR -> machine instructions
```

## Pipeline

```
Source -> AST -> Type Checker -> Kernel IR -> CFG -> Memory Analysis
-> Register Analysis -> Tensor Analysis -> Dependency Analysis
-> Deterministic Scheduler -> Instruction Selection -> Register Allocation
-> Instruction Encoding -> Hopper Backend
```

Every stage produces an explicit, inspectable intermediate representation.
Compilation is required to be deterministic.

## Determinism Guarantees

All compilation stages produce byte-for-byte identical output given:
- Same source program
- Same compiler version
- Same target configuration
- Same command-line flags

No probabilistic optimization, no machine learning, no randomized algorithms.

## Multi-Language Implementation

```
retro-gpu/
  *.occ                    # OCCAM CSP split modules (original)
  src/RetroGPU.occ         # OCCAM monolithic 12-block compiler
  examples/gemm.occ        # OCCAM GEMM kernel

  ocaml/                   # OCaml implementation
    src/types/             # Algebraic types
    src/registers/         # Block 01
    src/alu/               # Block 02
    src/warp/              # Block 03
    src/shared/            # Block 04
    src/compiler/          # Pipeline
    src/interpreter/       # Reference interpreter

  sml/                     # Standard ML implementation
    RetroGPUCore.sml       # Core types
    ALU.sml                # Block 02
    Warp.sml               # Block 03
    Memory.sml             # Blocks 04+05
    Sync.sml               # Block 06
    Tensor.sml             # Blocks 07+08
    Scheduler.sml          # Block 09
    Kernel.sml             # Block 10
    Instruction.sml        # Block 11
    Hopper.sml             # Block 12
    Interpreter.sml        # Semantic oracle
    Compiler.sml           # Pipeline driver
    GEMM.sml               # Reference kernels

  modula2/definitions/     # Modula-2 DEFINITION MODULEs
    Registers.def          # Block 01 interface
    ALU.def                # Block 02 interface
    Warp.def               # Block 03 interface
    RetroGPU.def           # Top-level interface
```

## Verification Strategy

Each block exposes:
1. **Type invariants**: Encoded in ML types and Modula signatures
2. **Verification procedures**: `validate_*` functions return `verification_result`
3. **Reference semantics**: Interpreter for comparison
4. **Test coverage**: Unit tests + negative tests + property tests

## Hard Constraints

- No CUDA C++ / LLVM IR / MLIR / Clang as primary artefacts
- No TypeScript / JS runtime / Python-generated code
- No GC, no hidden dynamic allocation, no opaque passes
- Explicit types, explicit dependencies, deterministic scheduling
- Hopper-specific details stay inside Block 12
- PTX / SASS only as optional edge representations

## Design Principle

> What is the minimum structured programming system required to express a modern GPU?
> Construct it from Modula + ALGOL + Pascal + FORTRAN + ML ideas.

The result is small, typed, deterministic, modular, auditable and machine-aware.
