# NAND# Language

## Design rule

Every NAND# expression reduces, through a finite sequence of pure transformations, to a finite sequence of NAND ISA instructions.

```
EVAL(e) = EXECUTE(LOWER(e))
```

for every expression `e` in the bounded subset.

## Grammar (EBNF)

```
program     ::= { definition | statement }
definition  ::= "let" ident "=" expr
statement   ::= "emit" expr
              | "assert" expr
expr        ::= primary
              | expr "nand" expr
              | "not" expr
              | "and" expr expr
              | "or" expr expr
              | "xor" expr expr
              | "mux" expr expr expr
              | "reshape" expr shape
              | "transpose" expr
              | "reduce" "nand" expr
primary     ::= ident | literal | "(" expr ")" | array_lit
array_lit   ::= "[" { expr "," } expr "]"
shape       ::= "(" { number "," } number ")"
literal     ::= "0" | "1" | number
ident       ::= letter { letter | digit | "_" }
```

## Type system (minimal)

```
τ     ::= Bool | Array τ shape
shape ::= [d₀, d₁, …, dₖ₋₁]  (rank k, each dᵢ > 0)
```

- Scalar Bool is treated as rank-0 array.
- Element-wise NAND requires identical shapes (or broadcast of rank-0).
- Reshape preserves element count.
- Transpose reverses axes (rank ≥ 1).

## Core semantic rules

```
⟦ nand e₁ e₂ ⟧ ρ = map₂ NAND (⟦e₁⟧ρ) (⟦e₂⟧ρ)
⟦ not e ⟧ ρ       = map₁ (λx. NAND(x,x)) (⟦e⟧ρ)
⟦ and e₁ e₂ ⟧ ρ   = map₂ AND …
… (all Boolean ops expand to NAND trees)
```

Array values are stored in row-major order. Index calculation is affine and bounded.

## Lowering overview

```
NAND# AST
  → typed IR (SSA-like, explicit shapes)
  → element-wise expansion (loops become unrolled or counted)
  → scalar NAND graph
  → register allocation (linear scan, ≤ 16 regs)
  → NAND ISA instruction list
  → binary encoding
```

The IR nodes that survive to the final stage are only:

- Nand(dst, a, b)
- Load / Store / Ldi / Jmp / Jz / Halt
