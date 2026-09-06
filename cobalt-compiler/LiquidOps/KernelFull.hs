{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveFunctor #-}

-- LiquidOps.KernelFull — Production recursive refinement kernel
-- Full pipeline:
--   FExpr (Fixpoint-style logic)
--     → recursive normalization
--     → Logic IR
--     → NandTree (boolean reduction)
--     → typed ISA (Instr GADT)
--     → validated Program
--     → MachineState transition
--
-- Production invariants:
--   • NandTree is the only boolean form (AND/OR/NOT/IMP/IFF eliminated)
--   • Arithmetic, memory, comparisons, control flow remain explicit in ISA
--   • Termination proved by exprSize / logicSize / nandSize measures
--   • No dependency on liquid-fixpoint (FExpr is a self-contained type)
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust

module LiquidOps.KernelFull
  ( -- Machine domain
    MachineState(..), Flags(..), emptyState
  , getReg, setReg, readMem, writeMem
  , updateFlags, advancePC, setPC
    -- Instruction GADT
  , Instr(..), instrValid, validReg
    -- Program
  , Program, programValid, assembleProgram
  , runProgram, traceProgram
    -- Logic IR
  , Logic(..), logicSize
    -- NandTree
  , NandTree(..), nandSize, nandDepth
  , nandGate, nandNot, nandAnd, nandOr, nandImp, nandIff
  , nandify, nandReduce, kernelStats, KernelStats(..)
    -- FExpr (Fixpoint-style source)
  , FExpr(..), BOp(..), BRel(..), exprSize
  , normalizeExpr, toLogic, lowerToNand, nandKernel
    -- Compile to ISA
  , CompileState(..), initialCompileState, freshReg, emit
  , compileNand, compileNandProgram
    -- Macros
  , MacroLib, registerMacro, lookupMacro
  , macroCopy, macroClear, macroAddImm, macroMulImm
  , macroCompareJump, macroCountLoop
  , macroNand, macroNot, macroAnd, macroOr
  ) where

import Data.Bits
import Data.Int
import Data.Word
import Data.List (foldl')
import Data.Maybe (fromMaybe)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M

--------------------------------------------------------------------------------
-- 1. REFINED MACHINE DOMAIN
--------------------------------------------------------------------------------

{-@ type RegId  = {r:Int | 0 <= r && r < 32} @-}
{-@ type MemAddr = Word64 @-}
{-@ type Steps   = {n:Int | n >= 0} @-}

data Flags = Flags
  { zeroFlag     :: Bool
  , signFlag     :: Bool
  , carryFlag    :: Bool
  , overflowFlag :: Bool
  } deriving (Show, Eq)

data MachineState = MachineState
  { regs  :: Map Int Word64
  , mem   :: Map Word64 Word8
  , pc    :: Word64
  , flags :: Flags
  } deriving (Show, Eq)

{-@ emptyState :: MachineState @-}
emptyState :: MachineState
emptyState = MachineState
  { regs  = M.fromList [(i, 0) | i <- [0..31]]
  , mem   = M.empty
  , pc    = 0
  , flags = Flags False False False False
  }

--------------------------------------------------------------------------------
-- 2. REGISTER / MEMORY ACCESS
--------------------------------------------------------------------------------

{-@ validReg :: r:Int -> Bool @-}
validReg :: Int -> Bool
validReg r = r >= 0 && r < 32

{-@ getReg :: r:RegId -> MachineState -> Word64 @-}
getReg :: Int -> MachineState -> Word64
getReg r s = M.findWithDefault 0 r (regs s)

{-@ setReg :: r:RegId -> Word64 -> MachineState -> MachineState @-}
setReg :: Int -> Word64 -> MachineState -> MachineState
setReg r v s = s { regs = M.insert r v (regs s) }

{-@ readMem  :: Word64 -> MachineState -> Word8 @-}
readMem :: Word64 -> MachineState -> Word8
readMem a s = M.findWithDefault 0 a (mem s)

{-@ writeMem :: Word64 -> Word8 -> MachineState -> MachineState @-}
writeMem :: Word64 -> Word8 -> MachineState -> MachineState
writeMem a v s = s { mem = M.insert a v (mem s) }

--------------------------------------------------------------------------------
-- 3. FLAGS / ALU HELPERS
--------------------------------------------------------------------------------

{-@ updateFlags :: Word64 -> MachineState -> MachineState @-}
updateFlags :: Word64 -> MachineState -> MachineState
updateFlags result s = s
  { flags = (flags s)
      { zeroFlag = result == 0
      , signFlag = testBit result 63 } }

addWithCarry :: Word64 -> Word64 -> (Word64, Bool)
addWithCarry x y = let z = x + y in (z, z < x)

subWithBorrow :: Word64 -> Word64 -> (Word64, Bool)
subWithBorrow x y = (x - y, x < y)

{-@ advancePC :: MachineState -> MachineState @-}
advancePC :: MachineState -> MachineState
advancePC s = s { pc = pc s + 1 }

{-@ setPC :: Word64 -> MachineState -> MachineState @-}
setPC :: Word64 -> MachineState -> MachineState
setPC t s = s { pc = t }

--------------------------------------------------------------------------------
-- 4. INSTRUCTION GADT  (Nand is a first-class ISA opcode)
--------------------------------------------------------------------------------

data Instr where
  MovImm   :: Int -> Word64         -> Instr
  Add      :: Int -> Int -> Int     -> Instr
  Sub      :: Int -> Int -> Int     -> Instr
  Mul      :: Int -> Int -> Int     -> Instr
  Div      :: Int -> Int -> Int     -> Instr
  And      :: Int -> Int -> Int     -> Instr
  Or       :: Int -> Int -> Int     -> Instr
  Xor      :: Int -> Int -> Int     -> Instr
  Nand     :: Int -> Int -> Int     -> Instr  -- rd = ~(rs1 & rs2)
  Load     :: Int -> Int -> Word64  -> Instr
  Store    :: Int -> Int -> Word64  -> Instr
  Jump     :: Word64                -> Instr
  JumpZero :: Word64                -> Instr
  Nop      :: Instr
  deriving (Show, Eq)

{-@ instrValid :: Instr -> Bool @-}
instrValid :: Instr -> Bool
instrValid i = case i of
  MovImm rd _       -> validReg rd
  Add  rd a b       -> all validReg [rd,a,b]
  Sub  rd a b       -> all validReg [rd,a,b]
  Mul  rd a b       -> all validReg [rd,a,b]
  Div  rd a b       -> all validReg [rd,a,b]
  And  rd a b       -> all validReg [rd,a,b]
  Or   rd a b       -> all validReg [rd,a,b]
  Xor  rd a b       -> all validReg [rd,a,b]
  Nand rd a b       -> all validReg [rd,a,b]
  Load  rd ra _     -> all validReg [rd,ra]
  Store rs ra _     -> all validReg [rs,ra]
  Jump  _           -> True
  JumpZero _        -> True
  Nop               -> True

--------------------------------------------------------------------------------
-- 5. MACHINE EXECUTION
--------------------------------------------------------------------------------

execInstr :: Instr -> MachineState -> MachineState
execInstr i s = case i of
  MovImm rd imm   -> advancePC $ setReg rd imm s
  Add rd rs1 rs2  -> let (r,c) = addWithCarry (getReg rs1 s) (getReg rs2 s)
                     in  advancePC $ updateFlags r $
                           s { regs = M.insert rd r (regs s)
                             , flags = (flags s) { carryFlag = c } }
  Sub rd rs1 rs2  -> let (r,b) = subWithBorrow (getReg rs1 s) (getReg rs2 s)
                     in  advancePC $ updateFlags r $
                           s { regs = M.insert rd r (regs s)
                             , flags = (flags s) { carryFlag = b } }
  Mul rd rs1 rs2  -> let r = getReg rs1 s * getReg rs2 s
                     in  advancePC $ updateFlags r $ setReg rd r s
  Div rd rs1 rs2  -> let v2 = getReg rs2 s
                         r  = if v2 == 0 then 0 else getReg rs1 s `div` v2
                     in  advancePC $ updateFlags r $ setReg rd r s
  And rd rs1 rs2  -> let r = getReg rs1 s .&. getReg rs2 s
                     in  advancePC $ updateFlags r $ setReg rd r s
  Or  rd rs1 rs2  -> let r = getReg rs1 s .|. getReg rs2 s
                     in  advancePC $ updateFlags r $ setReg rd r s
  Xor rd rs1 rs2  -> let r = xor (getReg rs1 s) (getReg rs2 s)
                     in  advancePC $ updateFlags r $ setReg rd r s
  Nand rd rs1 rs2 -> let r = complement (getReg rs1 s .&. getReg rs2 s)
                     in  advancePC $ updateFlags r $ setReg rd r s
  Load rd ra off  -> let addr = getReg ra s + off
                         byte = fromIntegral (readMem addr s)
                     in  advancePC $ setReg rd byte s
  Store rs ra off -> let addr = getReg ra s + off
                         byte = fromIntegral (getReg rs s)
                     in  advancePC $ writeMem addr byte s
  Jump target     -> setPC target s
  JumpZero target -> if zeroFlag (flags s) then setPC target s else advancePC s
  Nop             -> advancePC s

--------------------------------------------------------------------------------
-- 6. PROGRAM
--------------------------------------------------------------------------------

type Program = [Instr]

{-@ programValid :: Program -> Bool @-}
programValid :: Program -> Bool
programValid = all instrValid

{-@ assembleProgram :: Program -> Either String Program @-}
assembleProgram :: Program -> Either String Program
assembleProgram p
  | programValid p = Right p
  | otherwise      = Left "invalid instruction sequence"

{-@ runProgram :: Program -> MachineState -> Steps -> MachineState @-}
runProgram :: Program -> MachineState -> Int -> MachineState
runProgram _ s 0 = s
runProgram prog s steps
  | pc s >= fromIntegral (length prog) = s
  | otherwise = runProgram prog (execInstr (prog !! fromIntegral (pc s)) s) (steps - 1)

{-@ traceProgram :: Program -> MachineState -> Steps -> [(Word64, MachineState)] @-}
traceProgram :: Program -> MachineState -> Int -> [(Word64, MachineState)]
traceProgram _ s 0 = [(pc s, s)]
traceProgram prog s steps
  | pc s >= fromIntegral (length prog) = [(pc s, s)]
  | otherwise = (pc s, s) : traceProgram prog (execInstr (prog !! fromIntegral (pc s)) s) (steps - 1)

--------------------------------------------------------------------------------
-- 7. LOGIC IR
--------------------------------------------------------------------------------

data Logic a
  = LTrue | LFalse | LAtom a
  | LNot (Logic a)
  | LAnd (Logic a) (Logic a)
  | LOr  (Logic a) (Logic a)
  | LImp (Logic a) (Logic a)
  | LIff (Logic a) (Logic a)
  deriving (Show, Eq, Functor)

{-@ measure logicSize @-}
logicSize :: Logic a -> Int
logicSize LTrue       = 1; logicSize LFalse     = 1; logicSize (LAtom _)  = 1
logicSize (LNot x)    = 1 + logicSize x
logicSize (LAnd x y)  = 1 + logicSize x + logicSize y
logicSize (LOr  x y)  = 1 + logicSize x + logicSize y
logicSize (LImp x y)  = 1 + logicSize x + logicSize y
logicSize (LIff x y)  = 1 + logicSize x + logicSize y

foldLogicAnd :: [Logic a] -> Logic a
foldLogicAnd [] = LTrue; foldLogicAnd [x] = x; foldLogicAnd (x:xs) = LAnd x (foldLogicAnd xs)

foldLogicOr :: [Logic a] -> Logic a
foldLogicOr [] = LFalse; foldLogicOr [x] = x; foldLogicOr (x:xs) = LOr x (foldLogicOr xs)

--------------------------------------------------------------------------------
-- 8. NAND TREE
--------------------------------------------------------------------------------

data NandTree a = NTrue | NFalse | NAtom a | NNand (NandTree a) (NandTree a)
  deriving (Show, Eq, Functor)

{-@ measure nandSize @-}
nandSize :: NandTree a -> Int
nandSize NTrue = 1; nandSize NFalse = 1; nandSize (NAtom _) = 1
nandSize (NNand x y) = 1 + nandSize x + nandSize y

{-@ measure nandDepth @-}
nandDepth :: NandTree a -> Int
nandDepth NTrue = 1; nandDepth NFalse = 1; nandDepth (NAtom _) = 1
nandDepth (NNand x y) = 1 + max (nandDepth x) (nandDepth y)

{-@ nandGate :: x:NandTree a -> y:NandTree a
             -> {v:NandTree a | nandSize v == 1 + nandSize x + nandSize y} @-}
nandGate :: NandTree a -> NandTree a -> NandTree a
nandGate = NNand

nandNot :: NandTree a -> NandTree a
nandNot x = NNand x x

nandAnd :: NandTree a -> NandTree a -> NandTree a
nandAnd x y = let n = NNand x y in NNand n n

nandOr :: NandTree a -> NandTree a -> NandTree a
nandOr x y = NNand (nandNot x) (nandNot y)

nandImp :: NandTree a -> NandTree a -> NandTree a
nandImp x y = nandOr (nandNot x) y

nandIff :: NandTree a -> NandTree a -> NandTree a
nandIff x y = nandAnd (nandImp x y) (nandImp y x)

nandify :: Logic a -> NandTree a
nandify LTrue         = NTrue
nandify LFalse        = NFalse
nandify (LAtom x)     = NAtom x
nandify (LNot x)      = nandNot (nandify x)
nandify (LAnd x y)    = nandAnd (nandify x) (nandify y)
nandify (LOr  x y)    = nandOr  (nandify x) (nandify y)
nandify (LImp x y)    = nandImp (nandify x) (nandify y)
nandify (LIff x y)    = nandIff (nandify x) (nandify y)

nandReduce :: Eq a => NandTree a -> NandTree a
nandReduce NTrue = NTrue; nandReduce NFalse = NFalse; nandReduce a@(NAtom _) = a
nandReduce (NNand x y) =
  case (nandReduce x, nandReduce y) of
    (NFalse, _) -> NTrue; (_, NFalse) -> NTrue
    (NTrue, NTrue) -> NFalse; (x', y') -> NNand x' y'

data KernelStats = KernelStats { kernelNodes :: Int, kernelDepth :: Int } deriving (Show, Eq)
kernelStats :: NandTree a -> KernelStats
kernelStats t = KernelStats (nandSize t) (nandDepth t)

--------------------------------------------------------------------------------
-- 9. FEXPR (standalone, no liquid-fixpoint dependency)
--------------------------------------------------------------------------------

data FExpr
  = EVar String | EInt Integer | EReal Double
  | EBin BOp FExpr FExpr | EApp FExpr FExpr
  | PTrue | PFalse
  | PNot FExpr | PAnd [FExpr] | POr [FExpr]
  | PImp FExpr FExpr | PIff FExpr FExpr
  | PAtom BRel FExpr FExpr
  deriving (Show, Eq)

data BOp  = Plus | Minus | Times | DivOp | ModOp deriving (Show, Eq)
data BRel = EqRel | NeRel | LtRel | LeRel | GtRel | GeRel deriving (Show, Eq)

{-@ measure exprSize @-}
exprSize :: FExpr -> Int
exprSize (EVar _) = 1; exprSize (EInt _) = 1; exprSize (EReal _) = 1
exprSize (EBin _ x y)  = 1 + exprSize x + exprSize y
exprSize (EApp x y)    = 1 + exprSize x + exprSize y
exprSize PTrue = 1; exprSize PFalse = 1
exprSize (PNot x)      = 1 + exprSize x
exprSize (PAnd xs)     = 1 + sum (map exprSize xs)
exprSize (POr  xs)     = 1 + sum (map exprSize xs)
exprSize (PImp x y)    = 1 + exprSize x + exprSize y
exprSize (PIff x y)    = 1 + exprSize x + exprSize y
exprSize (PAtom _ x y) = 1 + exprSize x + exprSize y

--------------------------------------------------------------------------------
-- 10. RECURSIVE NORMALIZATION
--------------------------------------------------------------------------------

{-@ normalizeExpr :: FExpr -> FExpr @-}
normalizeExpr :: FExpr -> FExpr
normalizeExpr e = case e of
  EBin op x y  -> foldArith op (normalizeExpr x) (normalizeExpr y)
  EApp x y     -> EApp (normalizeExpr x) (normalizeExpr y)
  PNot x       -> normNot (normalizeExpr x)
  PAnd xs      -> normAnd (map normalizeExpr xs)
  POr  xs      -> normOr  (map normalizeExpr xs)
  PImp x y     -> normImp (normalizeExpr x) (normalizeExpr y)
  PIff x y     -> normIff (normalizeExpr x) (normalizeExpr y)
  PAtom r x y  -> foldPred r (normalizeExpr x) (normalizeExpr y)
  other        -> other

foldArith :: BOp -> FExpr -> FExpr -> FExpr
foldArith Plus  (EInt a)(EInt b) = EInt (a+b)
foldArith Minus (EInt a)(EInt b) = EInt (a-b)
foldArith Times (EInt a)(EInt b) = EInt (a*b)
foldArith DivOp (EInt a)(EInt b) | b /= 0 = EInt (a `div` b)
foldArith ModOp (EInt a)(EInt b) | b /= 0 = EInt (a `mod` b)
foldArith op x y = EBin op x y

foldPred :: BRel -> FExpr -> FExpr -> FExpr
foldPred EqRel (EInt a)(EInt b) = if a==b then PTrue else PFalse
foldPred NeRel (EInt a)(EInt b) = if a/=b then PTrue else PFalse
foldPred LtRel (EInt a)(EInt b) = if a<b  then PTrue else PFalse
foldPred LeRel (EInt a)(EInt b) = if a<=b then PTrue else PFalse
foldPred GtRel (EInt a)(EInt b) = if a>b  then PTrue else PFalse
foldPred GeRel (EInt a)(EInt b) = if a>=b then PTrue else PFalse
foldPred r x y = PAtom r x y

normNot :: FExpr -> FExpr
normNot PTrue = PFalse; normNot PFalse = PTrue; normNot (PNot y) = y; normNot x = PNot x

normAnd :: [FExpr] -> FExpr
normAnd xs = let ys = concatMap flatA xs
             in  if any (==PFalse) ys then PFalse
                 else case filter (/=PTrue) ys of
                        [] -> PTrue; [x] -> x; zs -> PAnd zs
  where flatA (PAnd es) = concatMap flatA es; flatA x = [x]

normOr :: [FExpr] -> FExpr
normOr xs = let ys = concatMap flatO xs
            in  if any (==PTrue) ys then PTrue
                else case filter (/=PFalse) ys of
                       [] -> PFalse; [x] -> x; zs -> POr zs
  where flatO (POr es) = concatMap flatO es; flatO x = [x]

normImp :: FExpr -> FExpr -> FExpr
normImp PFalse _ = PTrue; normImp PTrue y = y; normImp _ PTrue = PTrue
normImp x PFalse = normNot x; normImp x y = PImp x y

normIff :: FExpr -> FExpr -> FExpr
normIff PTrue y = y; normIff x PTrue = x; normIff PFalse y = normNot y
normIff x PFalse = normNot x; normIff x y | x==y = PTrue; normIff x y = PIff x y

--------------------------------------------------------------------------------
-- 11. FEXPR → LOGIC → NAND
--------------------------------------------------------------------------------

{-@ toLogic :: FExpr -> Logic FExpr @-}
toLogic :: FExpr -> Logic FExpr
toLogic PTrue       = LTrue; toLogic PFalse = LFalse
toLogic (PNot x)    = LNot (toLogic x)
toLogic (PAnd xs)   = foldLogicAnd (map toLogic xs)
toLogic (POr  xs)   = foldLogicOr  (map toLogic xs)
toLogic (PImp x y)  = LImp (toLogic x) (toLogic y)
toLogic (PIff x y)  = LIff (toLogic x) (toLogic y)
toLogic e           = LAtom e

{-@ lowerToNand :: FExpr -> NandTree FExpr @-}
lowerToNand :: FExpr -> NandTree FExpr
lowerToNand = nandify . toLogic . normalizeExpr

fromNand :: NandTree FExpr -> FExpr
fromNand NTrue = PTrue; fromNand NFalse = PFalse; fromNand (NAtom e) = e
fromNand (NNand x y) = PNot (PAnd [fromNand x, fromNand y])

{-@ nandKernel :: FExpr -> FExpr @-}
nandKernel :: FExpr -> FExpr
nandKernel = fromNand . nandReduce . lowerToNand

--------------------------------------------------------------------------------
-- 12. COMPILE NAND → ISA
--------------------------------------------------------------------------------

data CompileState = CompileState { nextReg :: Int, code :: [Instr] } deriving (Show, Eq)

{-@ initialCompileState :: CompileState @-}
initialCompileState :: CompileState
initialCompileState = CompileState 0 []

{-@ freshReg :: CompileState -> Maybe (Int, CompileState) @-}
freshReg :: CompileState -> Maybe (Int, CompileState)
freshReg st
  | validReg (nextReg st) = Just (nextReg st, st { nextReg = nextReg st + 1 })
  | otherwise             = Nothing

{-@ emit :: Instr -> CompileState -> CompileState @-}
emit :: Instr -> CompileState -> CompileState
emit i st = st { code = code st ++ [i] }

{-@ compileNand :: NandTree a -> CompileState -> Maybe (Int, CompileState) @-}
compileNand :: NandTree a -> CompileState -> Maybe (Int, CompileState)
compileNand tree st = case tree of
  NTrue    -> do (r,s) <- freshReg st;  pure (r, emit (MovImm r 1) s)
  NFalse   -> do (r,s) <- freshReg st;  pure (r, emit (MovImm r 0) s)
  NAtom _  -> do (r,s) <- freshReg st;  pure (r, emit (MovImm r 0) s)
  NNand x y -> do
    (rx,s1) <- compileNand x st
    (ry,s2) <- compileNand y s1
    (rd,s3) <- freshReg s2
    pure (rd, emit (Nand rd rx ry) s3)

{-@ compileNandProgram :: NandTree a -> Maybe Program @-}
compileNandProgram :: NandTree a -> Maybe Program
compileNandProgram tree = do
  (_, st) <- compileNand tree initialCompileState
  let p = code st
  if all instrValid p then pure p else Nothing

--------------------------------------------------------------------------------
-- 13. MACRO LIBRARY
--------------------------------------------------------------------------------

type MacroLib = [(String, [Instr])]

registerMacro :: String -> [Instr] -> MacroLib -> MacroLib
registerMacro n b lib = (n, b) : lib

lookupMacro :: String -> MacroLib -> Maybe [Instr]
lookupMacro = lookup

macroCopy :: Int -> Int -> [Instr]
macroCopy rd rs = [Xor rd rd rd, Add rd rd rs]

macroClear :: Int -> [Instr]
macroClear r = [Xor r r r]

macroAddImm :: Int -> Int -> Word64 -> Int -> [Instr]
macroAddImm rd rs imm temp = [MovImm temp imm, Add rd rs temp]

macroMulImm :: Int -> Int -> Word64 -> [Instr]
macroMulImm rd rs imm = [MovImm rd 0] ++ replicate (fromIntegral imm) (Add rd rd rs)

macroCompareJump :: Int -> Int -> Word64 -> [Instr]
macroCompareJump rs1 rs2 target = [Sub 0 rs1 rs2, JumpZero target]

macroCountLoop :: Int -> Word64 -> [Instr] -> Word64 -> [Instr]
macroCountLoop counter limit body target =
  [MovImm counter 0] ++ body
  ++ [MovImm 31 1, Add counter counter 31, MovImm 30 limit, Sub 29 counter 30, JumpZero target]

macroNand :: Int -> Int -> Int -> [Instr]
macroNand rd rs1 rs2 = [Nand rd rs1 rs2]

macroNot :: Int -> Int -> [Instr]
macroNot rd rs = [Nand rd rs rs]

macroAnd :: Int -> Int -> Int -> Int -> [Instr]
macroAnd rd rs1 rs2 temp = [Nand temp rs1 rs2, Nand rd temp temp]

macroOr :: Int -> Int -> Int -> Int -> Int -> [Instr]
macroOr rd rs1 rs2 t1 t2 = [Nand t1 rs1 rs1, Nand t2 rs2 rs2, Nand rd t1 t2]
