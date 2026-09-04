module CliIsa where

import qualified Data.ByteString as BS
import Data.Word (Word8, Word64)
import Data.Bits (shiftL, (.&.), (.|.))
import qualified Data.Map.Strict as M

type AccountIDHash = Word64
type Balance = Word64

data LedgerState = LedgerState {
    accounts :: M.Map AccountIDHash Balance
} deriving (Show, Eq)

initialState :: LedgerState
initialState = LedgerState M.empty

unpackU64 :: BS.ByteString -> Int -> Word64
unpackU64 bs offset = foldr (\i acc -> (acc `shiftL` 8) .|. fromIntegral (BS.index bs (offset + i))) 0 [7,6..0]

executeBinaryIsa :: BS.ByteString -> LedgerState -> (Bool, LedgerState)
executeBinaryIsa instBS state
    | BS.null instBS = (False, state)
    | otherwise =
        let opcode = BS.head instBS
            payload = BS.tail instBS
        in case opcode of
            0x10 ->
                if BS.length payload < 16
                then (False, state)
                else
                    let idHash = unpackU64 payload 0
                        balance = unpackU64 payload 8
                        newAccounts = M.insert idHash balance (accounts state)
                    in (True, state { accounts = newAccounts })
            0x20 ->
                (True, state)
            _ ->
                (False, state)
