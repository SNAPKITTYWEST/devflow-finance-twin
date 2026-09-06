{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

module Kernel where

{-@ type Mode = {v:Int | 0 <= v && v <= 2} @-}
{-@ type Cnt = {v:Int | 0 <= v && v <= 15} @-}
{-@ type Rst = {v:Int | 0 <= v && v <= 3} @-}
{-@ type Reason = {v:Int | 0 <= v && v <= 3} @-}

data State
  = Run { cnt :: Cnt }
  | Fault { why :: Reason }
  | Recov { stp :: Rst }
  deriving (Eq, Show)

{-@ data State =
      Run { cnt :: Cnt }
    | Fault { why :: Reason }
    | Recov { stp :: Rst }
  @-}

{-@ type Msg = {v:Int | 0 <= v} @-}

{-@ reflect step @-}
{-@ step :: State -> Msg -> State @-}
step :: State -> Int -> State
step (Run c) 0     = Run (if c < 15 then c+1 else c)
step (Run _) 1     = Fault 1
step (Run _) 2     = Run 0
step (Run _) _     = Fault 3
step (Fault r) 2   = Recov 0
step (Fault r) _   = Fault r
step (Recov s) 0   = if s < 3 then Recov (s+1) else Run 0
step (Recov _) 2   = Run 0
step (Recov _) _   = Fault 2

{-@ measure isLegal @-}
isLegal :: State -> Bool
isLegal (Run c)     = 0 <= c && c <= 15
isLegal (Fault r)   = 0 <= r && r <= 3
isLegal (Recov s)   = 0 <= s && s <= 3

{-@ stepPreserves :: s:State -> m:Msg -> {v:State | isLegal v && isLegal s} @-}
stepPreserves :: State -> Int -> State
stepPreserves s m = step s m

{-@ deterministic :: s:State -> m:Msg -> {step s m = step s m} @-}
deterministic :: State -> Int -> ()
deterministic s m = ()
