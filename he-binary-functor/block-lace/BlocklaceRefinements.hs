{-@ LIQUID "--ple" @-}
module BlocklaceRefinements where

{-@ type ParentCount = {v:Int | v >= 1 && v <= 4} @-}
{-@ type BraidLen = {v:Int | v >= 0 && v <= 16} @-}

data BlocklaceEntry = BlocklaceEntry {
    height :: Int,
    pCount :: Int,
    parents :: [Int],
    stateId :: Int,
    bLen :: Int,
    bWord :: [Int],
    selfSeal :: Int
}

{-@ validBlocklaceEntry :: e:BlocklaceEntry -> {v:Bool | v <=> (pCount e >= 1 && pCount e <= 4 && len (parents e) == pCount e && bLen e <= 16)} @-}
validBlocklaceEntry :: BlocklaceEntry -> Bool
validBlocklaceEntry e =
    pCount e >= 1 &&
    pCount e <= 4 &&
    length (parents e) == pCount e &&
    bLen e <= 16
