{-@ LIQUID "--reflection" "--ple" @-}
module Ledger where

{-@ type N = {v:Nat|v<=20} @-}
{-@ type Str = {v:Nat|1<=v&&v<=3} @-}
{-@ type Len = {v:Nat|v<=8} @-}
{-@ type Gen = {v:Int|(1<=v&&v<=3)||(-3<=v&&v<=-1)} @-}
{-@ type Word = {w:[Gen]|len w<=8} @-}

data Entry = E {n::N, prev::Nat, op::Nat, w::Word, st::Nat, seal::Nat}
{-@ data Entry = E {n::N, prev::Nat, op::Nat, w::Word, st::Nat, seal::Nat} @-}

{-@ reflect fib @-}
fib :: N -> Nat
fib 0=0; fib 1=1; fib n=fib(n-1)+fib(n-2)

{-@ reflect genOk @-}
genOk :: Int -> Bool
genOk g = (1<=g&&g<=3)||(-3<=g&&g<=-1)

{-@ reflect wordOk @-}
wordOk :: [Int] -> Bool
wordOk [] = True
wordOk (g:gs) = genOk g && wordOk gs

{-@ reflect transit @-}
transit :: Int -> [Int] -> Int
transit p [] = p
transit p (g:gs) = transit (p*3 + abs g) gs

{-@ reflect seal @-}
seal :: Int -> Entry -> Int
seal ps (E n pr _ w st _) =
  foldl (\s g -> (s`shiftL`5) `xor` fromIntegral g)
        (ps `xor` (n`shiftL`16) `xor` pr `xor` st) w

{-@ validTrans :: old:Entry -> e:Entry ->
      {v:Bool | v => wordOk (w e) && st e == transit (prev e) (w e)} @-}
validTrans :: Entry -> Entry -> Bool
validTrans old e = wordOk (w e) && st e == transit (prev e) (w e)
                 && n e == n old + 1
