# NAND Binary Format

## Canonical encoding

A program is a contiguous sequence of 16-bit little-endian words.

```
Offset 0:  word 0 (entry point = address 0)
Offset 2:  word 1
…
Offset 2n: word n
```

No headers, no relocation, no magic. The VM loads the image at address 0.

### Instruction bit layout (big-endian bit numbering for documentation)

```
bits [15:12] = OP
bits [11: 8] = DST
bits [ 7: 4] = A
bits [ 3: 0] = B
```

### Assembler syntax (text → binary)

```
label:
    nand rD, rA, rB
    halt
    load rD, rA, imm4
    store rD, rA, imm4
    ldi rD, imm8
    jmp rA
    jz rD, rA
```

Registers: `r0` … `r15` (aliases `zero` for r0).

### Decoder algorithm (deterministic)

```
fn decode(w: u16) -> Instr {
    let op  = (w >> 12) & 0xF;
    let dst = (w >> 8) & 0xF;
    let a   = (w >> 4) & 0xF;
    let b   = w & 0xF;
    match op {
        0 => Nand{dst,a,b},
        1 => Halt,
        2 => Load{dst,a,imm:b},
        3 => Store{dst,a,imm:b},
        4 => Ldi{dst, imm: (a<<4)|b},
        5 => Jmp{a},
        6 => Jz{dst,a},
        _ => Invalid{op},
    }
}
```

Disassembler is the exact inverse; round-trip property:

```
∀ w. encode(decode(w)) = w  (for all defined encodings)
```

### Golden fixtures

See `tests/golden/` for byte-exact binary images used by the test suite.
