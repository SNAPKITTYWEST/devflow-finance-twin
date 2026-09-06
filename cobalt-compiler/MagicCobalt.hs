module MagicCobalt
  ( CobaltConfig(..)
  , defaultConfig
  , compile
  , CompileResult(..)
  ) where

import           Cobalt.Dense
import           Cobalt.Trilock       (mkTrilock, trilockHash)
import           X86BatchAssembler
import           Data.ByteString      (ByteString)
import qualified Data.Map.Strict      as M

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

data CobaltConfig = CobaltConfig
  { invertVault  :: Bool   -- vaultTransform: reverse atoms + arg order
  , crystalDepth :: Int    -- max depth for crystalFold (default 16)
  } deriving (Show)

defaultConfig :: CobaltConfig
defaultConfig = CobaltConfig
  { invertVault  = False
  , crystalDepth = 16
  }

-- ---------------------------------------------------------------------------
-- Vault transform — structural inversion
-- ---------------------------------------------------------------------------

vaultTransform :: Functor' -> Functor'
vaultTransform (Atom name)          = Atom (reverse name)
vaultTransform (Compound name args) = Compound (reverse name) (reverse (map vaultTransform args))
vaultTransform (Recursive name args)= Recursive (reverse name) (reverse (map vaultTransform args))

-- ---------------------------------------------------------------------------
-- Full pipeline
-- ---------------------------------------------------------------------------

data CompileResult = CompileResult
  { crBytes    :: ByteString
  , crLibrary  :: Library
  , crCrystal  :: [Functor']
  , crTrilocks :: [(String, String)]   -- (functor label, trilock hash)
  } deriving (Show)

compile :: CobaltConfig -> String -> Either String CompileResult
compile cfg source = do
  let rules   = parsePrologRules source
  let lib0    = rulesToLibrary rules
  let crystal = expandUntilCrystal lib0
  let flat    = concatMap (crystalFold (crystalDepth cfg)) (crystalize crystal)
  let flat'   = if invertVault cfg then map vaultTransform flat else flat

  -- Per-unit assembly with label table
  let unitName i f = "unit_" ++ show i ++ "_" ++ functorName f
  let st0 = newAssemblerState
  let st1 = foldr (\(i,f) s -> emitUnit (unitName i f) (lowerFunctor f) s)
                  st0
                  (zip [0 :: Int ..] flat')
  st2 <- resolveLabels st1

  let locks = [ (unitName i f, trilockHash (mkTrilock f))
              | (i, f) <- zip [0 :: Int ..] flat' ]

  Right CompileResult
    { crBytes    = finalBytes st2
    , crLibrary  = crystal
    , crCrystal  = flat'
    , crTrilocks = locks
    }

functorName :: Functor' -> String
functorName (Atom n)          = n
functorName (Compound n _)    = n
functorName (Recursive n _)   = "rec_" ++ n
