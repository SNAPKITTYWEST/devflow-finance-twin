{-@ LIQUID "--ple" @-}
module ModelParserRefinement where

data Dtype = Float32 | Float16 | Int8 | Uint8 | Bfloat16
  deriving (Eq, Show)

data TensorDescriptor = TensorDescriptor {
    tensorId :: Int,
    offset :: Int,
    lengthVal :: Int,
    dtype :: Dtype,
    rank :: Int,
    shape :: [Int],
    alignment :: Int
}

{-@ type MaxTensors = 16384 @-}
{-@ type MaxRank = 8 @-}
{-@ type BlobLen = {v:Int | v >= 64} @-}

{-@ type TCount = {v:Int | v >= 0 && v <= 16384} @-}
{-@ type TRank = {v:Int | v > 0 && v <= 8} @-}
{-@ type SafeOffset = {v:Int | v >= 64} @-}

{-@ checkBounds :: blobSize:{v:Int|v>=0} -> offset:{v:Int|v>=0} -> len:{v:Int|v>=0}
                -> {v:Bool | v <=> offset + len <= blobSize} @-}
checkBounds :: Int -> Int -> Int -> Bool
checkBounds blobSize offset len =
    offset <= blobSize && len <= (blobSize - offset)

{-@ dtypeSize :: dtype:{v:Int|v>=1 && v<=5} -> {v:Int | v > 0} @-}
dtypeSize :: Int -> Int
dtypeSize dtype
    | dtype == 1 = 4 -- Float32
    | dtype == 2 = 2 -- Float16
    | dtype == 3 = 1 -- Int8
    | dtype == 4 = 4 -- Int32
    | dtype == 5 = 4 -- Bfloat16
    | otherwise = 1

{-@ validDescriptor :: len:BlobLen -> TensorDescriptor -> {v:Bool | v <=> true} @-}
validDescriptor :: Int -> TensorDescriptor -> Bool
validDescriptor blobLen desc =
    offset desc >= 64 &&
    lengthVal desc >= 0 &&
    lengthVal desc <= blobLen - offset desc &&
    rank desc > 0 &&
    rank desc <= 8 &&
    length (shape desc) == rank desc
