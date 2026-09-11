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

{-|
File        : QuipperTcpSenderLH.hs
Description : Quipper TCP sender integrated with WeakMeasureKrausLH, hardened with Liquid Haskell.
Usage       : runhaskell QuipperTcpSenderLH.hs --host 127.0.0.1 --port 9001 --trials 100 --theta 0.392699081698724
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}

module Main where

import WeakMeasureKrausLH (weakMeasureCircuit, krausNumeric, krausSymbolic, emaUpdate, evidenceProb)
import Quipper
import Network.Socket
import Network.Socket.ByteString (sendAll)
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson (encode, object, (.=))
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Control.Exception (bracket, try, SomeException)
import Control.Concurrent (threadDelay)
import System.Random (randomRIO)
import Data.Maybe (fromMaybe)
import Data.Time.Clock (getCurrentTime, utctDayTime)
import Control.Monad (forM_, when)

{-@ LIQUID "--no-termination" @-}
{-@ LIQUID "--ple" @-}

{-@ type Theta  = {v:Double | 0.0 <= v && v <= 6.283185307179586} @-}
{-@ type Trials = {v:Int    | 1   <= v && v <= 100000}            @-}
{-@ type MsgLen = {v:Int    | v   >  0 && v <  4096}              @-}

defaultHost  :: String;  defaultHost  = "127.0.0.1"
defaultPort  :: String;  defaultPort  = "9001"
defaultTrials :: Int;    defaultTrials = 100
defaultTheta :: Double;  defaultTheta  = pi / 8

parseArg :: [String] -> String -> Maybe String
parseArg [] _ = Nothing
parseArg (x:y:xs) flag
  | x == flag = Just y
  | otherwise = parseArg (y:xs) flag
parseArg _ _ = Nothing

{-@ validateTheta :: Double -> Theta @-}
validateTheta :: Double -> Double
validateTheta t
  | t >= 0.0 && t <= 2 * pi = t
  | otherwise = error "theta out of bounds [0,2*pi]"

{-@ validateTrials :: Int -> Trials @-}
validateTrials :: Int -> Int
validateTrials n
  | n >= 1 && n <= 100000 = n
  | otherwise = error "trials out of bounds [1,100000]"

buildMessage :: Int -> Int -> BL.ByteString
buildMessage trial bit =
  encode (object ["trial" .= trial, "bits" .= [bit]]) <> "\n"

simulateWeakMeasure :: Double -> IO Int
simulateWeakMeasure theta = do
  eres <- trySimulateCircuit theta
  case eres of
    Just bit -> return bit
    Nothing  -> do
      let p_sys = 0.5
          m = evidenceProb p_sys theta
      r <- randomRIO (0.0, 1.0)
      return $ if r < m then 1 else 0

trySimulateCircuit :: Double -> IO (Maybe Int)
trySimulateCircuit theta = do
  result <- (do
      sv <- run_generic_io (weakMeasureCircuit theta)
      let pairs   = zip [0..] (sv :: [Complex Double])
          prob1   = sum [ magnitude amp ** 2 | (idx, amp) <- pairs, (idx `mod` 2) == 1 ]
      r <- randomRIO (0.0 :: Double, 1.0)
      return (Just (if r < prob1 then 1 else 0))
    ) `catch` (\(_ :: SomeException) -> return Nothing)
  return result

runSender :: String -> String -> Int -> Double -> IO ()
runSender host portStr trials thetaRaw = do
  let theta   = validateTheta thetaRaw
      trials' = validateTrials trials
  addrinfos <- getAddrInfo Nothing (Just host) (Just portStr)
  let serveraddr = head addrinfos
  bracket (socket (addrFamily serveraddr) Stream defaultProtocol) close $ \sock -> do
    eres <- try (connect sock (addrAddress serveraddr)) :: IO (Either SomeException ())
    case eres of
      Left e  -> putStrLn ("Failed to connect: " ++ show e) >> exitFailure
      Right _ -> do
        putStrLn $ "Connected to " ++ host ++ ":" ++ portStr
        krausSymbolic "theta"
        krausNumeric theta
        forM_ [1..trials'] $ \t -> do
          bit <- simulateWeakMeasure theta
          let msg = buildMessage t bit
              len = fromIntegral (BL.length msg) :: Int
          when (len >= 4096) (putStrLn "Message too long" >> exitFailure)
          eres2 <- try (sendAll sock (BL.toStrict msg)) :: IO (Either SomeException ())
          case eres2 of
            Left e  -> putStrLn ("Send error: " ++ show e) >> exitFailure
            Right _ -> return ()
          threadDelay 100000
        putStrLn "All trials sent."

main :: IO ()
main = do
  args <- getArgs
  let host      = fromMaybe defaultHost   (parseArg args "--host")
      port      = fromMaybe defaultPort   (parseArg args "--port")
      trialsStr = fromMaybe (show defaultTrials) (parseArg args "--trials")
      thetaStr  = fromMaybe (show defaultTheta)  (parseArg args "--theta")
      trials    = case reads trialsStr :: [(Int,    String)] of { [(n,"")] -> n; _ -> defaultTrials }
      theta     = case reads thetaStr  :: [(Double, String)] of { [(d,"")] -> d; _ -> defaultTheta  }
  runSender host port trials theta
