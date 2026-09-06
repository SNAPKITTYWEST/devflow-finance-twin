{-# LANGUAGE RecordWildCards #-}

module StateMachine where

{-@ type Counter = {v:Int | 0 <= v && v <= 65534} @-}
{-@ type Delta = {v:Int | 0 <= v && v <= 65535} @-}
{-@ type Tag = {v:Int | v == 0xAB} @-}
{-@ type Status = {v:Int | 0 <= v && v <= 2} @-}

data StateTag = Run | Fault | Recov deriving (Eq, Show)
data Opcode = Add | Sub | Reset | Recover deriving (Eq, Show)

data State = State
  { counter :: Int
  , phase :: StateTag
  } deriving (Eq, Show)

data Message = Message
  { delta :: Int
  , opcode :: Opcode
  , tag :: Int
  } deriving (Eq, Show)

data Result = Result
  { next :: State
  , status :: Int
  } deriving (Eq, Show)

{-@ measure validCounter @-}
validCounter :: Int -> Bool
validCounter n = 0 <= n && n <= 65534

{-@ measure validState @-}
validState :: State -> Bool
validState (State c Run) = validCounter c
validState (State c Fault) = validCounter c
validState (State c Recov) = validCounter c

{-@ measure validMessage @-}
validMessage :: Message -> Bool
validMessage Message{..} = tag == 0xAB

{-@ type ValidState = {s:State | validState s} @-}
{-@ type ValidMsg = {m:Message | validMessage m} @-}
{-@ type SafeResult = {r:Result |
      validState (next r) &&
      0 <= status r && status r <= 2} @-}

{-@ fault :: Result @-}
fault :: Result
fault = Result (State 0 Fault) 2

{-@ step :: ValidState -> Message -> SafeResult @-}
step :: State -> Message -> Result
step s m
  | not (validMessage m) = fault
  | otherwise =
      case phase s of
        Run -> stepRun s m
        Fault -> stepFault m
        Recov -> Result (State (counter s) Run) 0

{-@ stepRun :: {s:State | phase s == Run && validState s}
            -> ValidMsg -> SafeResult @-}
stepRun :: State -> Message -> Result
stepRun (State c Run) Message{..} =
  case opcode of
    Add
      | c + delta <= 65534 -> Result (State (c + delta) Run) 0
      | otherwise -> fault
    Sub
      | delta <= c -> Result (State (c - delta) Run) 0
      | otherwise -> fault
    Reset -> Result (State 0 Run) 0
    Recover -> Result (State c Recov) 0
stepRun _ _ = fault

{-@ stepFault :: ValidMsg -> SafeResult @-}
stepFault :: Message -> Result
stepFault Message{ opcode = Recover } = Result (State 0 Run) 1
stepFault _ = Result (State 0 Fault) 1

{-@ stepPreservesStateInvariant
      :: s:ValidState -> m:Message
      -> {v:() | validState (next (step s m))} @-}
stepPreservesStateInvariant :: State -> Message -> ()
stepPreservesStateInvariant _ _ = ()

{-@ invalidMessageFault
      :: s:ValidState
      -> m:{Message | not (validMessage m)}
      -> {v:() | phase (next (step s m)) == Fault} @-}
invalidMessageFault :: State -> Message -> ()
invalidMessageFault _ _ = ()

{-@ counterAlwaysBounded
      :: s:ValidState -> m:Message
      -> {v:() | validCounter (counter (next (step s m)))} @-}
counterAlwaysBounded :: State -> Message -> ()
counterAlwaysBounded _ _ = ()
