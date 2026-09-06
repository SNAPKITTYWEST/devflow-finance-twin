-- ISA.Examples — Concrete programs: sum, factorial, bitwise, macros
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module ISA.Examples where

import ISA.Core
import ISA.Macro
import ISA.Program

-- برنامج 1: Sum first 10 natural numbers  r0=accumulator, r1=counter, r2=limit
{-@ programSum :: Program @-}
programSum :: Program
programSum =
  [ MovImm 0 0   -- r0 = 0
  , MovImm 1 0   -- r1 = 0
  , MovImm 2 10  -- r2 = 10
  , Add 0 0 1    -- r0 += r1
  , Add 1 1 2    -- (conceptual increment)
  , Sub 3 1 2    -- r3 = r1 - r2
  , JumpZero 8   -- if r3==0 jump to end
  , Jump 3       -- loop
  , Nop          -- end
  ]

-- برنامج 2: Factorial of 5  r0=result, r1=counter, r2 must be 1
{-@ programFactorial :: Program @-}
programFactorial :: Program
programFactorial =
  [ MovImm 0 1  -- r0 = 1
  , MovImm 1 5  -- r1 = 5 (counter)
  , MovImm 2 1  -- r2 = 1
  , Mul 0 0 1   -- r0 *= r1
  , Sub 1 1 2   -- r1 -= 1
  , JumpZero 6  -- if r1==0 done
  , Jump 3      -- loop back to Mul
  , Nop
  ]

-- برنامج 3: Bitwise operations
{-@ programBitwise :: Program @-}
programBitwise :: Program
programBitwise =
  [ MovImm 0 0xFF  -- r0 = 255
  , MovImm 1 0x0F  -- r1 = 15
  , And  2 0 1     -- r2 = 0xFF & 0x0F = 15
  , Or   3 0 1     -- r3 = 255
  , Xor  4 0 1     -- r4 = 240
  , Nand 5 0 1     -- r5 = ~(0xFF & 0x0F) = ~15
  , Nop
  ]

-- برنامج 4: NAND boolean demo  r6=NOT(r5), r7=AND(r5,r4), r8=OR(r5,r4)
{-@ programNandBool :: Program @-}
programNandBool :: Program
programNandBool =
  [ MovImm 4 1 ]       -- r4 = true
  ++ [ MovImm 5 0 ]    -- r5 = false
  ++ macroNot 6 4      -- r6 = NOT r4 = false
  ++ macroAnd 7 4 5 9  -- r7 = AND(r4,r5) = false
  ++ macroOr 8 4 5 9 10 -- r8 = OR(r4,r5) = true
  ++ [Nop]

-- برنامج 5: With macros
{-@ programWithMacros :: Program @-}
programWithMacros :: Program
programWithMacros =
  [ MovImm 5 100 ]
  ++ macroCopy 6 5
  ++ [ Add 7 5 6 ]
  ++ macroClear 8

-- اختبار البرنامج / test runner
{-@ testProgram :: Program -> MachineState -> IO () @-}
testProgram :: Program -> MachineState -> IO ()
testProgram prog initial = do
  let trace = traceProgram prog initial 50
  mapM_ (\(p, s) -> putStrLn $ "PC:" ++ show p ++ " r0=" ++ show (getReg 0 s)) trace
  let final = runProgram prog initial 50
  putStrLn $ "r0=" ++ show (getReg 0 final)
    ++ " r1=" ++ show (getReg 1 final)
    ++ " flags=" ++ show (flags final)

main :: IO ()
main = do
  putStrLn "=== Sum ==="        >> testProgram programSum emptyState
  putStrLn "=== Factorial ==="  >> testProgram programFactorial emptyState
  putStrLn "=== Bitwise ==="    >> testProgram programBitwise emptyState
  putStrLn "=== NAND Bool ==="  >> testProgram programNandBool emptyState
  putStrLn "=== Macros ==="     >> testProgram programWithMacros emptyState
