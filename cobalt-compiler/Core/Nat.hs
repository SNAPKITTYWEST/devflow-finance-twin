-- ========================================================================
-- SOVEREIGN LEVIATHAN NODE LICENSE
-- License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
-- Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
-- ========================================================================
--
-- This file is a covered work under the GNU Affero General Public License,
-- version 3, together with the Sovereign Leviathan additional terms.
--
-- Hark, though this node be but a spark,
-- Its covenant endureth through the dark.
--
-- Ignorantia juris non excusat.
-- ========================================================================

-- Core.Nat â€” Natural numbers and basic arithmetic refinements
-- Ø§Ù„Ø£Ø¹Ø¯Ø§Ø¯ Ø§Ù„Ø·Ø¨ÙŠØ¹ÙŠØ© ÙˆØªÙ†Ù‚ÙŠØ­Ø§Øª Ø§Ù„Ø­Ø³Ø§Ø¨ Ø§Ù„Ø£Ø³Ø§Ø³ÙŠØ©
-- Author: Ahmad Ali Parr â€” Bel Esprit D'Accord Irrevocable Trust
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

-- Ø¹Ø¯Ù… Ø§Ù„Ø³Ù„Ø¨ÙŠØ© / non-negativity
{-@ lemmaNatNonNeg :: x:Nat -> {v:Bool | v <=> x >= 0} @-}
lemmaNatNonNeg :: Int -> Bool
lemmaNatNonNeg x = x >= 0

-- ØªØ¨Ø§Ø¯Ù„ÙŠØ© Ø§Ù„Ø¬Ù…Ø¹ / commutativity of addition
{-@ lemmaAddComm :: x:Nat -> y:Nat -> {v:Bool | v <=> x + y == y + x} @-}
lemmaAddComm :: Int -> Int -> Bool
lemmaAddComm x y = x + y == y + x

-- ØªØ¬Ù…ÙŠØ¹ÙŠØ© Ø§Ù„Ø¬Ù…Ø¹ / associativity of addition
{-@ lemmaAddAssoc :: x:Nat -> y:Nat -> z:Nat
                  -> {v:Bool | v <=> x + (y + z) == (x + y) + z} @-}
lemmaAddAssoc :: Int -> Int -> Int -> Bool
lemmaAddAssoc x y z = x + (y + z) == (x + y) + z

-- ØªØ¨Ø§Ø¯Ù„ÙŠØ© Ø§Ù„Ø¶Ø±Ø¨ / commutativity of multiplication
{-@ lemmaMulComm :: x:Nat -> y:Nat -> {v:Bool | v <=> x * y == y * x} @-}
lemmaMulComm :: Int -> Int -> Bool
lemmaMulComm x y = x * y == y * x

-- ØªØ¬Ù…ÙŠØ¹ÙŠØ© Ø§Ù„Ø¶Ø±Ø¨ / associativity of multiplication
{-@ lemmaMulAssoc :: x:Nat -> y:Nat -> z:Nat
                  -> {v:Bool | v <=> x * (y * z) == (x * y) * z} @-}
lemmaMulAssoc :: Int -> Int -> Int -> Bool
lemmaMulAssoc x y z = x * (y * z) == (x * y) * z

-- Ø§Ù„ØªÙˆØ²ÙŠØ¹ / distributivity
{-@ lemmaMulDistrib :: x:Nat -> y:Nat -> z:Nat
                    -> {v:Bool | v <=> x * (y + z) == x*y + x*z} @-}
lemmaMulDistrib :: Int -> Int -> Int -> Bool
lemmaMulDistrib x y z = x * (y + z) == x*y + x*z

-- Ø§Ù„ØµÙØ± Ù…Ø­Ø§ÙŠØ¯ Ø§Ù„Ø¬Ù…Ø¹ / additive identity
{-@ lemmaAddZero :: x:Nat -> {v:Bool | v <=> x + 0 == x && 0 + x == x} @-}
lemmaAddZero :: Int -> Bool
lemmaAddZero x = x + 0 == x && 0 + x == x

-- Ø§Ù„ÙˆØ§Ø­Ø¯ Ù…Ø­Ø§ÙŠØ¯ Ø§Ù„Ø¶Ø±Ø¨ / multiplicative identity
{-@ lemmaMulOne :: x:Nat -> {v:Bool | v <=> x * 1 == x && 1 * x == x} @-}
lemmaMulOne :: Int -> Bool
lemmaMulOne x = x * 1 == x && 1 * x == x

-- Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø¬Ù…Ø¹ / additive closure
{-@ addNat :: Nat -> Nat -> Nat @-}
addNat :: Int -> Int -> Int
addNat x y = x + y

-- Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø¶Ø±Ø¨ / multiplicative closure
{-@ mulNat :: Nat -> Nat -> Nat @-}
mulNat :: Int -> Int -> Int
mulNat x y = x * y

-- Ø§Ù„Ø³Ù„Ù / predecessor (bounded to Nat)
{-@ predNat :: x:Nat -> {v:Nat | v <= x} @-}
predNat :: Int -> Int
predNat x
  | x == 0    = 0
  | otherwise = x - 1

-- Ø§Ù„Ù‚ÙˆØ© / power (structural recursion on exponent)
{-@ powNat :: x:Nat -> n:Nat -> Nat / [n] @-}
powNat :: Int -> Int -> Int
powNat _ 0 = 1
powNat x n = x * powNat x (n - 1)

-- Ù…Ø¬Ù…ÙˆØ¹ Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„Ø£Ø¹Ø¯Ø§Ø¯ Ø§Ù„Ø·Ø¨ÙŠØ¹ÙŠØ© / sum of Nat list
{-@ sumNatNonNeg :: xs:[Nat] -> {v:Nat | v == sumNat xs} @-}
sumNatNonNeg :: [Int] -> Int
sumNatNonNeg []     = 0
sumNatNonNeg (x:xs) = x + sumNatNonNeg xs

-- Ø·ÙˆÙ„ Ø§Ù„Ù‚Ø§Ø¦Ù…Ø© / list length
{-@ lenNonNeg :: xs:[a] -> {v:Nat | v == len xs} @-}
lenNonNeg :: [a] -> Int
lenNonNeg []     = 0
lenNonNeg (_:xs) = 1 + lenNonNeg xs
