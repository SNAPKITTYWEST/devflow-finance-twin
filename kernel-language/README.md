# KERNEL LANGUAGE

Hand-rolled compiler and language founded on **BLISS + PL/M + CORAL 66**

Target machine: NVIDIA Ampere SM_86

## What this is

A dense, explicit, systems-programmer-style implementation of a kernel language
whose semantics, storage model, expression orientation, bit/word operations and
real-time annotations are taken directly from the three named languages.

It is **not** a CUDA wrapper, not a Mamba implementation, not an LLVM/MLIR
front-end, and not a translation into C/C++/Rust.

## Foundations preserved

- **BLISS**: word-oriented computation, expression-oriented evaluation,
  structured low-overhead control, BIND/OWN/LOCAL storage feel, macros (skeleton).
- **PL/M**: BASED variables, absolute addressing (AT), explicit bit-field
  extraction, processor-oriented declarations, direct memory interaction.
- **CORAL 66**: BEGIN/END structured blocks, IF/THEN/ELSE/FI, FOR/WHILE,
  PRIORITY/DEADLINE/BOUNDED annotations, deterministic barrier discipline.

## Repository layout

```
include/          public headers (token, ast, lexer, parser, ir, codegen, symtab, regalloc)
src/              hand-written C implementation
  lexer.c         keyword + operator scanner
  parser.c        recursive-descent, expression-oriented + structured statements
  ir.c            KERNEL IR (register machine + predicates + barriers + collectives)
  codegen.c       AST -> KERNEL IR lowering
  symtab.c        scoped symbol table + linear-scan register allocator
  regalloc.c      graph-coloring register allocator (Chaitin-style)
  main.c          driver
examples/         programs written in the language itself
oberon/           Oberon-style Kernel + ML annotation modules
runtime/          CPL bridge (host-side FFI), Smalltalk-80 annotation runtime
```

## Build

```
make
```

Produces the compiler binary `klc`.

## Usage

```
./klc examples/word_arith.kl -emit-ir
./klc examples/bit_ops.kl -emit-ir
./klc examples/parallel_add.kl -emit-ir
./klc examples/word_arith.kl -dump-ast
./klc examples/word_arith.kl -emit-ir -regalloc
```

## Current status

**Working**
- Lexer with full keyword set from the three languages
- Recursive-descent parser for modules, routines, declarations,
  expression language, structured statements, PARALLEL, BARRIER
- AST construction
- KERNEL IR definition (add/sub/mul/..., ld/st, setp/selp, bar.sync, shfl/vote/redux, ...)
- Code generation of arithmetic, bit extraction, simple control flow,
  barriers and exit into the IR
- Graph-coloring register allocator (interference graph + greedy coloring)
- Linear-scan register allocator (alternative)
- Example kernels that parse and emit IR

**Still incomplete**
- Full symbol table + register allocation (variables currently lower to
  placeholder moves; the IR shape is correct)
- Complete IF/FI and nested block robustness under all punctuation variants
- Macro expansion
- Full BASED / AT absolute addressing lowering
- SASS binary emitter / cubin writer
- Runtime loader

The IR is deliberately close to Ampere SASS so that a subsequent
hand-written assembler or external tool can finish the path to SM_86
without changing the language or the front-end.

## Design discipline

Every stage is written in plain C with direct data structures.
No parser generators, no LLVM, no framework scaffolding.
The code is intended to be auditable by a systems programmer who
knows BLISS, PL/M or CORAL 66.
