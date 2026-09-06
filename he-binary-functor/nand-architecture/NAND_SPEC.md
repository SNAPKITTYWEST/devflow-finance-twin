# NAND Primitive Architecture Specification
## Boolean Algebra, ISA, NAND# Language, Array Processor, Bootstrap Pipeline

---

## 1. NAND Primitive and Boolean Derivations

The fundamental computational primitive is the binary NAND operation. All logical evaluation, control flow, arithmetic, and array processing reduce strictly to this single operation.

Truth table:
| A | B | NAND(A,B) |
|---|---|-----------|
| 0 | 0 | 1 |
| 0 | 1 | 1 |
| 1 | 0 | 1 |
| 1 | 1 | 0 |

All derived Boolean operators are constructed directly from NAND:

| Operator | Boolean Expression | NAND Derivation |
|---|---|---|
| NOT(a) | ¬a | NAND(a, a) |
| AND(a, b) | a ∧ b | NOT(NAND(a, b)) = NAND(NAND(a,b), NAND(a,b)) |
| OR(a, b) | a ∨ b | NAND(NOT(a), NOT(b)) = NAND(NAND(a,a), NAND(b,b)) |
| XOR(a, b) | a ⊕ b | NAND(NAND(a, NAND(a,b)), NAND(b, NAND(a,b))) |
| NOR(a, b) | ¬(a ∨ b) | NOT(OR(a,b)) = NAND(OR(a,b), OR(a,b)) |
| MUX(s, a, b) | (s∧a) ∨ (¬s∧b) | NAND(NAND(s,a), NAND(NOT(s), b)) |

---

## 2. NAND Binary ISA and Opcode Specification

Fixed 16-bit instruction word layout:

```
[ 15 14 13 | 12 11 10 9 | 8 7 6 5 | 4 3 2 1 0 ]
+----------+------------+------------+-----------------+
| OP (3)   | DST (4)    | SRCA (4)   | SRCB (5)        |
+----------+------------+------------+-----------------+
```

- **OP (Bits 15–13)**: Operation code (000=NAND, 001=LOAD, 010=STORE, 011=JMPZ, 111=HALT)
- **DST (Bits 12–9)**: Destination register index (R_0 through R_{15})
- **SRCA (Bits 8–5)**: Source operand A register index
- **SRCB (Bits 4–0)**: Source operand B register index or 5-bit immediate address offset

### Execution Environment
- **Registers**: 16 general-purpose 1-bit boolean registers (R_0 hardwired to 0)
- **Memory**: 64 KB addressable bit/byte RAM
- **Program Counter (PC)**: 16-bit word-aligned instruction pointer
- **Halt Behavior**: HALT opcode (111) freezes execution state and asserts external terminal signal
- **Invalid Opcode**: Unmapped bit patterns trap into infinite reset loop

---

## 3. NAND# Language and Intermediate Representation

NAND# provides high-level syntax that compiles downward through an IR into NAND instruction graphs.

```
NAND# Source
    ↓ Lexer / Parser
AST (Abstract Syntax Tree)
    ↓ Type Checker
Typed IR (Static Shape & Boolean Width Checking)
    ↓ Lowering Engine
NAND Instruction Graph (Directed Acyclic Graph of NAND Nodes)
    ↓ Linearizer & Assembler
Binary NAND Program (.nandbin)
```

### NAND# Grammar (EBNF Subset)
```
program     ::= statement*
statement   ::= "let" ident "=" expr ";" | "print" ident ";"
expr        ::= "nand" ident ident | "not" ident | "array" "[" int "," ... "]"
ident       ::= [a-zA-Z_][a-zA-Z0-9_]*
int         ::= [0-9]+
```

---

## 4. Array Processor and Array-to-NAND Lowering

The array subsystem lifts scalar boolean operations into an APL-inspired array algebra supporting multidimensional tensors with explicit shape metadata.

### Array Descriptor Structure
- **rank**: 8-bit unsigned integer (dimensions count)
- **shape**: Array of 16-bit dimension sizes
- **data**: Contiguous buffer of bit-packed boolean elements in row-major order

### Array Lowering Rule
When evaluating element-wise array NAND operation **C = A NAND B**, the compiler unrolls the multi-dimensional index space into a deterministic linear sequence of primitive NAND machine instructions. Memory layout offsets are computed statically using affine index transformations and row-major strides.

---

## 5. Rust Reference Implementation

### rust/src/lib.rs — Core NAND VM, ISA Decoder, Array Lowering Engine

```rust
pub type RegId = u8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Opcode {
    Nand = 0b000,
    Load = 0b001,
    Store = 0b010,
    JmpZ = 0b011,
    Halt = 0b111,
}

#[derive(Debug, Clone, Copy)]
pub struct Instruction {
    pub op: Opcode,
    pub dst: RegId,
    pub src_a: RegId,
    pub src_b: u8,
}

impl Instruction {
    pub fn encode(&self) -> u16 {
        let op = (self.op as u16) << 13;
        let dst = ((self.dst & 0x0F) as u16) << 9;
        let src_a = ((self.src_a & 0x0F) as u16) << 5;
        let src_b = (self.src_b & 0x1F) as u16;
        op | dst | src_a | src_b
    }

    pub fn decode(word: u16) -> Result<Self, &'static str> {
        let op_val = (word >> 13) & 0x07;
        let op = match op_val {
            0b000 => Opcode::Nand,
            0b001 => Opcode::Load,
            0b010 => Opcode::Store,
            0b011 => Opcode::JmpZ,
            0b111 => Opcode::Halt,
            _ => return Err("Invalid Opcode"),
        };
        Ok(Self {
            op,
            dst: ((word >> 9) & 0x0F) as RegId,
            src_a: ((word >> 5) & 0x0F) as RegId,
            src_b: (word & 0x1F) as u8,
        })
    }
}

pub struct VirtualMachine {
    pub regs: [bool; 16],
    pub memory: [bool; 65536],
    pub pc: u16,
    pub halted: bool,
}

impl VirtualMachine {
    pub fn new() -> Self {
        Self {
            regs: [false; 16],
            memory: [false; 65536],
            pc: 0,
            halted: false,
        }
    }

    pub fn step(&mut self, rom: &[u16]) -> Result<(), &'static str> {
        if self.halted || (self.pc as usize) >= rom.len() {
            self.halted = true;
            return Ok(());
        }

        let word = rom[self.pc as usize];
        self.pc = self.pc.checked_add(1).ok_or("PC Overflow")?;
        let inst = Instruction::decode(word)?;

        match inst.op {
            Opcode::Nand => {
                let a = if inst.src_a == 0 { false } else { self.regs[inst.src_a as usize] };
                let b_val = (inst.src_b & 0x0F) as usize;
                let b = if b_val == 0 { false } else { self.regs[b_val] };
                let res = !(a && b);
                if inst.dst > 0 {
                    self.regs[inst.dst as usize] = res;
                }
            }
            Opcode::Load => {
                let addr = inst.src_b as usize;
                if inst.dst > 0 {
                    self.regs[inst.dst as usize] = self.memory[addr];
                }
            }
            Opcode::Store => {
                let addr = inst.src_b as usize;
                let val = if inst.src_a == 0 { false } else { self.regs[inst.src_a as usize] };
                self.memory[addr] = val;
            }
            Opcode::JmpZ => {
                let cond = if inst.src_a == 0 { false } else { self.regs[inst.src_a as usize] };
                if !cond {
                    self.pc = inst.src_b as u16;
                }
            }
            Opcode::Halt => {
                self.halted = true;
            }
        }
        Ok(())
    }
}
```

---

## 6. Kani Verification Harnesses

### kani/src/verification.rs — Bounded Model-Checking

```rust
#[cfg(kani)]
mod verification {
    use super::*;

    #[kani::proof]
    fn verify_instruction_roundtrip() {
        let op_val: u8 = kani::any();
        kani::assume(op_val <= 3 || op_val == 7);
        let dst: u8 = kani::any();
        kani::assume(dst < 16);
        let src_a: u8 = kani::any();
        kani::assume(src_a < 16);
        let src_b: u8 = kani::any();
        kani::assume(src_b < 32);

        let op = match op_val {
            0 => Opcode::Nand,
            1 => Opcode::Load,
            2 => Opcode::Store,
            3 => Opcode::JmpZ,
            7 => Opcode::Halt,
            _ => unreachable!(),
        };

        let inst = Instruction { op, dst, src_a, src_b };
        let encoded = inst.encode();
        let decoded = Instruction::decode(encoded).unwrap();

        assert!(decoded.op == inst.op);
        assert!(decoded.dst == inst.dst);
        assert!(decoded.src_a == inst.src_a);
        assert!(decoded.src_b == inst.src_b);
    }

    #[kani::proof]
    fn verify_nand_truth_table() {
        let a: bool = kani::any();
        let b: bool = kani::any();

        let mut vm = VirtualMachine::new();
        vm.regs[1] = a;
        vm.regs[2] = b;

        let inst = Instruction {
            op: Opcode::Nand,
            dst: 3,
            src_a: 1,
            src_b: 2,
        };

        let rom = [inst.encode()];
        vm.step(&rom).unwrap();

        assert_eq!(vm.regs[3], !(a && b));
    }
}
```

---

## 7. Omega Bounded Verification Model

The formal symbolic model verifies array index bounds, affine transformations, and termination invariant