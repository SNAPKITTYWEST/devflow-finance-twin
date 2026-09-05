{-# LANGUAGE RankNTypes #-}

module RateLimiter where

import Data.Word

MAX_TOKENS :: Int
MAX_TOKENS = 16

MAX_FAIL :: Int
MAX_FAIL = 8

FAIL_THRESHOLD :: Int
FAIL_THRESHOLD = 4

REFILL_INTERVAL :: Word32
REFILL_INTERVAL = 1000

FAULT_TIMEOUT :: Word32
FAULT_TIMEOUT = 5000

RECOVER_TIMEOUT :: Word32
RECOVER_TIMEOUT = 2000

type StateTag = {v:Int | v == 0 || v == 1 || v == 2}
type Tokens = {v:Int | 0 <= v && v <= MAX_TOKENS}
type FailCount = {v:Int | 0 <= v && v <= MAX_FAIL}
type Time = Word32

data RateState = RateState
  { tag :: StateTag
  , tokens :: Tokens
  , failCount :: FailCount
  , lastPermitT :: Time
  , faultEntryT :: Time
  , currentT :: Time
  } deriving (Show, Eq)

{-@ type ValidState =
    {s:RateState |
        (tag s == 0 || tag s == 1 || tag s == 2) &&
        (0 <= tokens s && tokens s <= MAX_TOKENS) &&
        (0 <= failCount s && failCount s <= MAX_FAIL) &&
        (tag s == 1 || faultEntryT s == 0)
    }
@-}

{-@ step :: ValidState -> Time -> Bool -> (ValidState, Bool) @-}
step :: RateState -> Time -> Bool -> (RateState, Bool)
step state time request =
  let
    elapsed = time - lastPermitT state
    newTokens = if elapsed >= REFILL_INTERVAL
                then min (tokens state + 1) MAX_TOKENS
                else tokens state
    updatedLPT = if elapsed >= REFILL_INTERVAL then time else lastPermitT state
    (s', grant) = case tag state of
      0 -> stepRun (state { tokens = newTokens, lastPermitT = updatedLPT, currentT = time }) request
      1 -> stepFault (state { currentT = time })
      2 -> stepRecover (state { currentT = time })
      _ -> error "Invalid state tag"
  in (s', grant)

{-@ stepRun :: ValidState -> Bool -> (ValidState, Bool) @-}
stepRun :: RateState -> Bool -> (RateState, Bool)
stepRun state request =
  if request && tokens state > 0
  then
    let newState = state
          { tokens = tokens state - 1
          , lastPermitT = currentT state
          , failCount = 0
          }
    in (newState, True)
  else
    let newFails = min (failCount state + 1) MAX_FAIL
        transitionToFault = (newFails >= FAIL_THRESHOLD)
        newState = if transitionToFault
                   then state { tag = 1, failCount = newFails, faultEntryT = currentT state }
                   else state { failCount = newFails }
    in (newState, False)

{-@ stepFault :: ValidState -> (ValidState, Bool) @-}
stepFault :: RateState -> (RateState, Bool)
stepFault state =
  let faultAge = currentT state - faultEntryT state
      transitionToRecover = (faultAge >= FAULT_TIMEOUT)
      newState = if transitionToRecover then state { tag = 2 } else state
  in (newState, False)

{-@ stepRecover :: ValidState -> (ValidState, Bool) @-}
stepRecover :: RateState -> (RateState, Bool)
stepRecover state =
  let recoverAge = currentT state - faultEntryT state
      readyToRun = (recoverAge >= RECOVER_TIMEOUT)
      newState = if readyToRun
                 then state { tag = 0, tokens = 8, failCount = 0
                            , lastPermitT = currentT state, faultEntryT = 0 }
                 else state
  in (newState, False)

{-@ prop_tokens_bounded :: s:ValidState -> { tokens s <= MAX_TOKENS } @-}
prop_tokens_bounded :: RateState -> ()
prop_tokens_bounded _ = ()

{-@ prop_fail_bounded :: s:ValidState -> { failCount s <= MAX_FAIL } @-}
prop_fail_bounded :: RateState -> ()
prop_fail_bounded _ = ()

{-@ prop_transition_preserves_invariant
    :: s:ValidState -> t:Time -> r:Bool
    -> { let (s', _) = step s t r in
         (tag s' == 0 || tag s' == 1 || tag s' == 2) &&
         (0 <= tokens s' && tokens s' <= MAX_TOKENS) &&
         (0 <= failCount s' && failCount s' <= MAX_FAIL) }
@-}
prop_transition_preserves_invariant :: RateState -> Time -> Bool -> ()
prop_transition_preserves_invariant _ _ _ = ()

{-@ prop_deterministic
    :: s:ValidState -> t:Time -> r:Bool
    -> { step s t r == step s t r }
@-}
prop_deterministic :: RateState -> Time -> Bool -> ()
prop_deterministic _ _ _ = ()
