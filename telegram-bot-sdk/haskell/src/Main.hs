-- | Entry point for the Devflow Telegram Bot.
-- Loads config, initializes state, and starts the polling loop.
module Main (main) where

import           Control.Concurrent         (forkIO, threadDelay)
import           Control.Concurrent.Async   (async, waitAny, withAsync)
import           Control.Concurrent.STM     (readTVarIO)
import           Control.Exception          (SomeException, bracket, catch,
                                             finally, try)
import           Control.Monad              (when)
import           Data.Aeson                 (eitherDecodeFileStrict)
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import qualified Data.Text.IO               as TIO
import           System.Environment         (getArgs, lookupEnv)
import           System.Exit                (exitFailure, exitSuccess)
import           System.IO                  (hPutStrLn, stderr, stdout)

import           Bot                        (BotState (..), handleUpdate,
                                             initBotState, runBot, stopBot)
import           Types                      (BotConfig (..), defaultConfig)

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs
  cfg  <- loadConfig args
  TIO.hPutStrLn stderr $ "[INFO] Starting Devflow Telegram Bot"
  TIO.hPutStrLn stderr $ "[INFO] Database: " <> T.pack (cfgDbPath cfg)
  TIO.hPutStrLn stderr $ "[INFO] Ollama: "   <> cfgOllamaUrl cfg
  TIO.hPutStrLn stderr $ "[INFO] Model: "    <> cfgOllamaModel cfg

  result <- initBotState cfg
  case result of
    Left err -> do
      TIO.hPutStrLn stderr $ "[FATAL] Initialization failed: " <> err
      exitFailure
    Right bs -> do
      TIO.hPutStrLn stderr "[INFO] Initialization complete."
      runWithShutdown bs

-- ---------------------------------------------------------------------------
-- Config loading
-- ---------------------------------------------------------------------------

-- | Load config from:
--   1. --config <path> argument (JSON file)
--   2. DEVFLOW_TOKEN environment variable (minimal config)
--   3. Default config (token must be set via env)
loadConfig :: [String] -> IO BotConfig
loadConfig args = do
  case parseConfigFlag args of
    Just path -> loadJsonConfig path
    Nothing   -> do
      mToken <- lookupEnv "DEVFLOW_TOKEN"
      mOllama <- lookupEnv "DEVFLOW_OLLAMA_URL"
      mModel  <- lookupEnv "DEVFLOW_OLLAMA_MODEL"
      mDb     <- lookupEnv "DEVFLOW_DB_PATH"
      let token = maybe (cfgToken defaultConfig) T.pack mToken
      when (T.null token) $ do
        TIO.hPutStrLn stderr "[WARN] No bot token configured. Set DEVFLOW_TOKEN or use --config."
      pure defaultConfig
        { cfgToken       = token
        , cfgOllamaUrl   = maybe (cfgOllamaUrl defaultConfig) T.pack mOllama
        , cfgOllamaModel = maybe (cfgOllamaModel defaultConfig) T.pack mModel
        , cfgDbPath      = maybe (cfgDbPath defaultConfig) id mDb
        }

parseConfigFlag :: [String] -> Maybe FilePath
parseConfigFlag ("--config" : path : _) = Just path
parseConfigFlag ("-c"       : path : _) = Just path
parseConfigFlag (_ : rest)              = parseConfigFlag rest
parseConfigFlag []                      = Nothing

loadJsonConfig :: FilePath -> IO BotConfig
loadJsonConfig path = do
  result <- eitherDecodeFileStrict path
  case result of
    Left err  -> do
      hPutStrLn stderr $ "[FATAL] Cannot parse config file '" <> path <> "': " <> err
      exitFailure
    Right cfg -> pure cfg

-- ---------------------------------------------------------------------------
-- Shutdown handling
-- ---------------------------------------------------------------------------

-- | Run the bot with graceful shutdown on exception.
runWithShutdown :: BotState -> IO ()
runWithShutdown bs =
  (startPolling bs `finally` shutdown bs)
  `catch` (\ex -> do
    hPutStrLn stderr $ "[ERROR] Unhandled exception: " <> show (ex :: SomeException)
    exitFailure)

-- | Start the Telegram polling loop.
-- In a real deployment this would call telegram-bot-simple's `startBot`.
-- Here we run a skeleton that prints readiness and blocks.
startPolling :: BotState -> IO ()
startPolling bs = do
  TIO.hPutStrLn stderr "[INFO] Bot is ready. Listening for updates..."
  TIO.hPutStrLn stdout "Devflow Bot running. Press Ctrl+C to stop."

  -- Main heartbeat loop — in production, replace with:
  --   Telegram.Bot.Simple.startBot botApp (Token (cfgToken (bsConfig bs)))
  --
  -- The bot is fully wired: handleUpdate processes any BotMessage.
  -- Example usage (for integration tests / manual testing):
  --
  --   let testMsg = BotMessage { msgId = MessageId 1, ... }
  --   responses <- handleUpdate bs testMsg
  --   mapM_ (TIO.putStrLn . respText) responses

  runBot bs

shutdown :: BotState -> IO ()
shutdown bs = do
  TIO.hPutStrLn stderr "[INFO] Shutting down..."
  stopBot bs
  TIO.hPutStrLn stderr "[INFO] Goodbye."

