-- Core.Group — Algebraic group structures and laws
-- هياكل الزمر الجبرية والقوانين
-- Author: Ahmad Ali Parr — Bel Esprit D'Accord Irrevocable Trust
-- {-@ LIQUID "--typeclass" @-}

module Core.Group where

import Core.Nat

-- ── Abstract group record ────────────────────────────────────────────────────
-- سجل الزمرة المجردة / abstract group record (dictionary-passing style)

data Group a = Group
  { unitG :: a
  , mulG  :: a -> a -> a
  , invG  :: a -> a
  }

-- الحياد الأيسر / left identity
{-@ leftIdentity :: g:Group a -> x:a -> {v:Bool | v <=> mulG g (unitG g) x == x} @-}
leftIdentity :: Group a -> a -> Bool
leftIdentity g x = mulG g (unitG g) x == x

-- الحياد الأيمن / right identity
{-@ rightIdentity :: g:Group a -> x:a -> {v:Bool | v <=> mulG g x (unitG g) == x} @-}
rightIdentity :: Group a -> a -> Bool
rightIdentity g x = mulG g x (unitG g) == x

-- التجميعية / associativity
{-@ associativity :: g:Group a -> x:a -> y:a -> z:a
                  -> {v:Bool | v <=> mulG g x (mulG g y z) == mulG g (mulG g x y) z} @-}
associativity :: Group a -> a -> a -> a -> Bool
associativity g x y z =
  mulG g x (mulG g y z) == mulG g (mulG g x y) z

-- العكس الأيسر / left inverse
{-@ leftInverse :: g:Group a -> x:a
                -> {v:Bool | v <=> mulG g (invG g x) x == unitG g} @-}
leftInverse :: Group a -> a -> Bool
leftInverse g x = mulG g (invG g x) x == unitG g

-- العكس الأيمن / right inverse
{-@ rightInverse :: g:Group a -> x:a
                 -> {v:Bool | v <=> mulG g x (invG g x) == unitG g} @-}
rightInverse :: Group a -> a -> Bool
rightInverse g x = mulG g x (invG g x) == unitG g

-- ── Z/2Z group ───────────────────────────────────────────────────────────────
-- زمرة Z₂ الثنائية / binary group Z_2

data Z2 = Z0 | Z1 deriving (Eq, Show)

{-@ z2Val :: Z2 -> {v:Nat | v <= 1} @-}
z2Val :: Z2 -> Int
z2Val Z0 = 0
z2Val Z1 = 1

{-@ z2Add :: Z2 -> Z2 -> Z2 @-}
z2Add :: Z2 -> Z2 -> Z2
z2Add Z0 y  = y
z2Add Z1 Z0 = Z1
z2Add Z1 Z1 = Z0

{-@ z2Inv :: Z2 -> Z2 @-}
z2Inv :: Z2 -> Z2
z2Inv = id

{-@ z2Group :: Group Z2 @-}
z2Group :: Group Z2
z2Group = Group { unitG = Z0, mulG = z2Add, invG = z2Inv }

{-@ z2LeftIdentity  :: x:Z2 -> {v:Bool | v} @-}
z2LeftIdentity :: Z2 -> Bool
z2LeftIdentity x = leftIdentity z2Group x

{-@ z2RightIdentity :: x:Z2 -> {v:Bool | v} @-}
z2RightIdentity :: Z2 -> Bool
z2RightIdentity x = rightIdentity z2Group x

{-@ z2Inverse :: x:Z2 -> {v:Bool | v} @-}
z2Inverse :: Z2 -> Bool
z2Inverse x = leftInverse z2Group x && rightInverse z2Group x

-- ── Z/7Z cyclic group ────────────────────────────────────────────────────────
-- زمرة Z₇ الدورية / cyclic group Z_7

{-@ type Z7 = {v:Int | 0 <= v && v < 7} @-}

{-@ z7Add :: Z7 -> Z7 -> Z7 @-}
z7Add :: Int -> Int -> Int
z7Add x y = (x + y) `mod` 7

{-@ z7Neg :: Z7 -> Z7 @-}
z7Neg :: Int -> Int
z7Neg x = (-x) `mod` 7

{-@ z7Group :: Group Z7 @-}
z7Group :: Group Int
z7Group = Group { unitG = 0, mulG = z7Add, invG = z7Neg }

{-@ z7LeftIdentity :: x:Z7 -> {v:Bool | v <=> z7Add 0 x == x} @-}
z7LeftIdentity :: Int -> Bool
z7LeftIdentity x = z7Add 0 x == x

{-@ z7RightIdentity :: x:Z7 -> {v:Bool | v <=> z7Add x 0 == x} @-}
z7RightIdentity :: Int -> Bool
z7RightIdentity x = z7Add x 0 == x

{-@ z7Inverse :: x:Z7 -> {v:Bool | v <=> z7Add x (z7Neg x) == 0} @-}
z7Inverse :: Int -> Bool
z7Inverse x = z7Add x (z7Neg x) == 0

{-@ z7Associative :: x:Z7 -> y:Z7 -> z:Z7
                  -> {v:Bool | v <=> z7Add x (z7Add y z) == z7Add (z7Add x y) z} @-}
z7Associative :: Int -> Int -> Int -> Bool
z7Associative x y z = z7Add x (z7Add y z) == z7Add (z7Add x y) z
