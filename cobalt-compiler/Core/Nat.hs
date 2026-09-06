-- Core.Nat — Natural numbers and basic arithmetic refinements
-- الأعداد الطبيعية وتنقيحات الحساب الأساسية
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--ple" @-}

module Core.Nat where

{-@ type Nat = {v:Int | v >= 0} @-}
{-@ type Pos = {v:Nat | v > 0} @-}

{-@ measure len @-}
len :: [a] -> Int
len []     = 0
len (_:xs) = 1 + len xs

{-@ measure sumNat @-}
sumNat :: [Int] -> Int
sumNat []     = 0
sumNat (x:xs) = x + sumNat xs

-- عدم السلبية / non-negativity
{-@ lemmaNatNonNeg :: x:Nat -> {v:Bool | v <=> x >= 0} @-}
lemmaNatNonNeg :: Int -> Bool
lemmaNatNonNeg x = x >= 0

-- تبادلية الجمع / commutativity of addition
{-@ lemmaAddComm :: x:Nat -> y:Nat -> {v:Bool | v <=> x + y == y + x} @-}
lemmaAddComm :: Int -> Int -> Bool
lemmaAddComm x y = x + y == y + x

-- تجميعية الجمع / associativity of addition
{-@ lemmaAddAssoc :: x:Nat -> y:Nat -> z:Nat
                  -> {v:Bool | v <=> x + (y + z) == (x + y) + z} @-}
lemmaAddAssoc :: Int -> Int -> Int -> Bool
lemmaAddAssoc x y z = x + (y + z) == (x + y) + z

-- تبادلية الضرب / commutativity of multiplication
{-@ lemmaMulComm :: x:Nat -> y:Nat -> {v:Bool | v <=> x * y == y * x} @-}
lemmaMulComm :: Int -> Int -> Bool
lemmaMulComm x y = x * y == y * x

-- تجميعية الضرب / associativity of multiplication
{-@ lemmaMulAssoc :: x:Nat -> y:Nat -> z:Nat
                  -> {v:Bool | v <=> x * (y * z) == (x * y) * z} @-}
lemmaMulAssoc :: Int -> Int -> Int -> Bool
lemmaMulAssoc x y z = x * (y * z) == (x * y) * z

-- التوزيع / distributivity
{-@ lemmaMulDistrib :: x:Nat -> y:Nat -> z:Nat
                    -> {v:Bool | v <=> x * (y + z) == x*y + x*z} @-}
lemmaMulDistrib :: Int -> Int -> Int -> Bool
lemmaMulDistrib x y z = x * (y + z) == x*y + x*z

-- الصفر محايد الجمع / additive identity
{-@ lemmaAddZero :: x:Nat -> {v:Bool | v <=> x + 0 == x && 0 + x == x} @-}
lemmaAddZero :: Int -> Bool
lemmaAddZero x = x + 0 == x && 0 + x == x

-- الواحد محايد الضرب / multiplicative identity
{-@ lemmaMulOne :: x:Nat -> {v:Bool | v <=> x * 1 == x && 1 * x == x} @-}
lemmaMulOne :: Int -> Bool
lemmaMulOne x = x * 1 == x && 1 * x == x

-- إغلاق الجمع / additive closure
{-@ addNat :: Nat -> Nat -> Nat @-}
addNat :: Int -> Int -> Int
addNat x y = x + y

-- إغلاق الضرب / multiplicative closure
{-@ mulNat :: Nat -> Nat -> Nat @-}
mulNat :: Int -> Int -> Int
mulNat x y = x * y

-- السلف / predecessor (bounded to Nat)
{-@ predNat :: x:Nat -> {v:Nat | v <= x} @-}
predNat :: Int -> Int
predNat x
  | x == 0    = 0
  | otherwise = x - 1

-- القوة / power (structural recursion on exponent)
{-@ powNat :: x:Nat -> n:Nat -> Nat / [n] @-}
powNat :: Int -> Int -> Int
powNat _ 0 = 1
powNat x n = x * powNat x (n - 1)

-- مجموع قائمة الأعداد الطبيعية / sum of Nat list
{-@ sumNatNonNeg :: xs:[Nat] -> {v:Nat | v == sumNat xs} @-}
sumNatNonNeg :: [Int] -> Int
sumNatNonNeg []     = 0
sumNatNonNeg (x:xs) = x + sumNatNonNeg xs

-- طول القائمة / list length
{-@ lenNonNeg :: xs:[a] -> {v:Nat | v == len xs} @-}
lenNonNeg :: [a] -> Int
lenNonNeg []     = 0
lenNonNeg (_:xs) = 1 + lenNonNeg xs
