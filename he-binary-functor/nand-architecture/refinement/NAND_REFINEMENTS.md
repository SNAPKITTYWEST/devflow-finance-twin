# Refinement Types for NAND and Pointer Arithmetic

## 1. Boolean NAND refinements

```haskell
{-@ measure isBit :: Int -> Bool @-}
{-@ isBit :: x:Int -> {v:Bool | v <=> (x == 0 || x == 1)} @-}

{-@ type Bit = {v:Int | isBit v} @-}

{-@ nand :: a:Bit -> b:Bit -> {v:Bit | v == 1 - (a * b)} @-}
nand :: Int -> Int -> Int
nand a b = 1 - (a * b)

{-@ notR :: x:Bit -> {v:Bit | v == 1 - x} @-}
{-@ andR :: a:Bit -> b:Bit -> {v:Bit | v == a * b} @-}
{-@ orR :: a:Bit -> b:Bit -> {v:Bit | v == a + b - a*b} @-}
```

## 2. Pointer / address refinements

```haskell
{-@ type Addr = {v:Nat | v < 65536} @-}
{-@ type Off = {v:Int | 0 <= v && v < 16} @-}

{-@ validPtr :: base:Addr -> off:Off -> {v:Addr | v == (base + off) mod 65536} @-}
```

### Load / Store contracts

```haskell
{-@ load :: m:Mem -> p:Addr -> Bit @-}
{-@ store :: m:Mem -> p:Addr -> Bit -> Mem @-}
```

## 3. Array index arithmetic

```haskell
{-@ linear :: base:Addr
           -> idxs:[{v:Nat | v < di}]
           -> {v:Addr | v < base + product(shape)} @-}
```

## 4. Semantic preservation under refinement

```
EVAL(e) : refined Boolean / array value
LOWER(e) : sequence of Instr with refined registers & addresses
EXECUTE(LOWER(e)): machine state whose observable bits equal EVAL(e)
```

The refinement types make `EXECUTE(LOWER(e)) = EVAL(e)` a type-level statement.
