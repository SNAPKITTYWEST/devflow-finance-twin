# Hand-Rolled ISA → JVM

Deterministic custom instruction set architecture with reference interpreter.
JVM bytecode backend is the next layer; the ISA remains the source of truth.

```
ISA text → Parser → Verifier → IR / CFG → Reference Interpreter
                                         ↓ (later)
                                   JVM Bytecode (ASM)
                                         ↓
                                   Dynamic .class + Agent Runtime
```

## Status

| Component | Status |
|-----------|--------|
| Opcode table + semantics | Done |
| Type system + MachineState | Done |
| Parser / Verifier / CFG | Done |
| Reference interpreter | Done |
| Register → JVM local map | Done |
| JVM bytecode emitter (.class) | Done (core ALU/control) |
| Dynamic class registry + java runner | Done |
| Differential tests (interp ≡ JVM) | Done |
| invokedynamic bootstrap stubs | Done |
| Agent scheduler + channels | Done |
| Trace viewer | Done |

Approx **1550 LOC** total Python.

## Quick start

```bash
cd isa-jvm
PYTHONPATH=. python -m pytest tests/ -q
PYTHONPATH=. python -c "
from compiler import parse_program, verify
from runtime import Interpreter
src = open('examples/arith.isa').read()
prog = parse_program(src)
verify(prog)
st = Interpreter(prog).run()
print('R2=', st.registers.get(2), 'R4=', st.registers.get(4))
"
```

## Example ISA

```
LOAD_IMM R0, 10
LOAD_IMM R1, 32
ADD R2, R0, R1
CMP R2, R3
JE equal
...
HALT
```

## Design rules (enforced)

1. ISA is authoritative.
2. Invalid programs fail before execution.
3. Interpreter is the semantic oracle.
4. No hidden behavior in opcodes.
5. Machine state is explicit and inspectable.
