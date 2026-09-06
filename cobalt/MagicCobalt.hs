{-# LANGUAGE BangPatterns #-}

module MagicCobalt
  ( CobaltConfig(..)
  , CobaltError(..)
  , Functor(..)
  , Predicate(..)
  , Rule(..)
  , Library(..)
  , Matrix(..)
  , Triad(..)
  , ISA(..)
  , Build(..)
  , magicCobalt
  , compile
  , compileBatch
  ) where

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Bits
import Data.Char
import Data.Int
import Data.List
import Data.Maybe
import Data.Word

-- ============================================================
-- CONFIGURATION
-- ============================================================

data CobaltConfig = CobaltConfig
  { maxExpansionRounds :: !Int
  , crystalDepth       :: !Int
  , matrixWidth        :: !Int
  , invertVault        :: !Bool
  } deriving (Eq, Show)

defaultConfig :: CobaltConfig
defaultConfig = CobaltConfig
  { maxExpansionRounds = 64
  , crystalDepth       = 32
  , matrixWidth        = 64
  , invertVault        = False
  }

-- ============================================================
-- ERRORS
-- ============================================================

data CobaltError
  = ParseError         !Int !String
  | ExpansionLimit
  | CrystalLimit
  | UndefinedFunctor   !String
  | InvalidRegister    !String
  | InvalidImmediate   !String
  | InvalidInstruction !String
  | MatrixError        !String
  deriving (Eq, Show)

-- ============================================================
-- DENSE FUNCTOR SYNTAX
-- ============================================================

data Functor
  = Atom      !String
  | Variable  !String
  | Apply     !String ![Functor]
  | Recursive !String ![Functor]
  | Sequence  ![Functor]
  | Reference !String
  deriving (Eq, Show)

-- ============================================================
-- LOGIC
-- ============================================================

data Predicate = Predicate
  { predicateName :: !String
  , predicateArgs :: ![Functor]
  } deriving (Eq, Show)

data Rule = Rule
  { ruleHead :: !Predicate
  , ruleBody :: ![Predicate]
  } deriving (Eq, Show)

-- ============================================================
-- LIBRARY
-- ============================================================

data Library = Library
  { libraryNodes :: !(M.Map String Functor)
  , libraryOrder :: ![String]
  } deriving (Eq, Show)

emptyLibrary :: Library
emptyLibrary = Library M.empty []

libraryInsert :: String -> Functor -> Library -> Library
libraryInsert !name !node !lib =
  case M.member name (libraryNodes lib) of
    True  -> lib
    False ->
      Library
        (M.insert name node (libraryNodes lib))
        (libraryOrder lib ++ [name])

librarySize :: Library -> Int
librarySize = M.size . libraryNodes

-- ============================================================
-- TOKENIZER
-- ============================================================

data Token
  = TAtom      !String
  | TVariable  !String
  | TOpen
  | TClose
  | TComma
  | TColonDash
  | TDot
  deriving (Eq, Show)

tokenize :: String -> [Token]
tokenize source =
  go (stripComments source)
  where
    go [] = []

    go ('-':'>':xs) = TColonDash : go xs
    go (':':'-':xs) = TColonDash : go xs
    go ('(':xs)     = TOpen      : go xs
    go (')':xs)     = TClose     : go xs
    go (',':xs)     = TComma     : go xs
    go ('.':xs)     = TDot       : go xs

    go (c:xs)
      | isSpace c = go xs
      | otherwise =
          let (word, rest) = span tokenChar (c:xs)
          in classify word : go rest

    tokenChar c =
      isAlphaNum c || c == '_' || c == '$' || c == '-'

    classify x
      | null x = TAtom ""
      | isUpper (head x) || head x == '_' = TVariable x
      | otherwise = TAtom x

stripComments :: String -> String
stripComments =
  unlines . map (takeWhile (/= '%')) . lines

-- ============================================================
-- TERM PARSER
-- ============================================================

parseTerm
  :: [Token]
  -> Either CobaltError (Functor,[Token])
parseTerm [] =
  Left (ParseError 0 "unexpected end of input")

parseTerm (token:rest) =
  case token of

    TVariable x ->
      Right (Variable x, rest)

    TAtom name ->
      case rest of
        TOpen : remaining ->
          do
            (args, tailTokens) <- parseArguments remaining
            Right (Apply name args, tailTokens)
        _ ->
          Right (Atom name, rest)

    _ ->
      Left (ParseError 0 "expected term")

parseArguments
  :: [Token]
  -> Either CobaltError ([Functor],[Token])
parseArguments (TClose:rest) =
  Right ([],rest)

parseArguments tokens =
  do
    (x,rest) <- parseTerm tokens
    case rest of
      TComma:remaining ->
        do
          (xs,tailTokens) <- parseArguments remaining
          Right (x:xs,tailTokens)

      TClose:remaining ->
        Right ([x],remaining)

      _ ->
        Left (ParseError 0 "expected comma or closing parenthesis")

-- ============================================================
-- PREDICATE PARSER
-- ============================================================

parsePredicate
  :: [Token]
  -> Either CobaltError (Predicate,[Token])
parsePredicate [] =
  Left (ParseError 0 "missing predicate")

parsePredicate (TAtom name:rest) =
  case rest of
    TOpen:remaining ->
      do
        (args,tailTokens) <- parseArguments remaining
        Right (Predicate name args, tailTokens)
    _ ->
      Right (Predicate name [], rest)

parsePredicate _ =
  Left (ParseError 0 "invalid predicate")

-- ============================================================
-- RULE PARSER
-- ============================================================

parseRule
  :: [Token]
  -> Either CobaltError (Rule,[Token])
parseRule tokens =
  do
    (headPredicate,rest) <- parsePredicate tokens
    case rest of
      TDot:remaining ->
        Right (Rule headPredicate [], remaining)

      TColonDash:remaining ->
        do
          (body,tailTokens) <- parseBody remaining
          Right (Rule headPredicate body, tailTokens)

      _ ->
        Left (ParseError 0 "expected rule terminator")

parseBody
  :: [Token]
  -> Either CobaltError ([Predicate],[Token])
parseBody tokens =
  do
    (p,rest) <- parsePredicate tokens
    case rest of
      TComma:remaining ->
        do
          (ps,tailTokens) <- parseBody remaining
          Right (p:ps, tailTokens)

      TDot:remaining ->
        Right ([p], remaining)

      _ ->
        Left (ParseError 0 "expected comma or period")

-- ============================================================
-- PROGRAM PARSER
-- ============================================================

parseProgram :: String -> Either CobaltError [Rule]
parseProgram source =
  go (tokenize source) []
  where
    go [] !acc = Right (reverse acc)
    go tokens !acc =
      do
        (rule,rest) <- parseRule tokens
        go rest (rule:acc)

-- ============================================================
-- TERM -> FUNCTOR
-- ============================================================

predicateFunctor :: Predicate -> Functor
predicateFunctor p =
  Apply (predicateName p) (predicateArgs p)

ruleFunctor :: Rule -> Functor
ruleFunctor rule =
  let name = predicateName (ruleHead rule)
      body = map predicateFunctor (ruleBody rule)
  in if any (containsName name) body
       then Recursive name body
       else Sequence body

containsName :: String -> Functor -> Bool
containsName !name node =
  case node of
    Atom _        -> False
    Variable _    -> False
    Reference x   -> x == name
    Apply x xs    -> x == name || any (containsName name) xs
    Recursive x xs -> x == name || any (containsName name) xs
    Sequence xs   -> any (containsName name) xs

-- ============================================================
-- INITIAL LIBRARY
-- ============================================================

rulesToLibrary :: [Rule] -> Library
rulesToLibrary =
  foldl' insertRule emptyLibrary
  where
    insertRule !lib !rule =
      let !name = predicateName (ruleHead rule)
          !node = ruleFunctor rule
      in libraryInsert name node lib

-- ============================================================
-- RECURSIVE EXPANSION
-- ============================================================

expandFunctor :: Library -> Functor -> (Functor,Library)
expandFunctor !lib node =
  case node of

    Atom _     -> (node,lib)
    Variable _ -> (node,lib)

    Reference name ->
      case M.lookup name (libraryNodes lib) of
        Nothing         -> (node,lib)
        Just definition -> (definition,lib)

    Apply name args ->
      let (!args',!lib') = expandList lib args
          !result        = Apply name args'
          !lib''         = libraryInsert name result lib'
      in (result,lib'')

    Recursive name args ->
      let (!args',!lib') = expandList lib args
          !result        = Recursive name args'
          !lib''         = libraryInsert name result lib'
      in (result,lib'')

    Sequence xs ->
      let (!xs',!lib') = expandList lib xs
      in (Sequence xs',lib')

expandList :: Library -> [Functor] -> ([Functor],Library)
expandList !lib [] = ([],lib)
expandList !lib (x:xs) =
  let (!x',!lib1)  = expandFunctor lib x
      (!xs',!lib2) = expandList lib1 xs
  in (x':xs',lib2)

-- ============================================================
-- FIXED-POINT EXPANSION
-- ============================================================

expandRound :: Library -> (Library,Library)
expandRound !lib =
  foldl' step (lib,lib) (libraryOrder lib)
  where
    step (!current,!next) name =
      case M.lookup name (libraryNodes current) of
        Nothing   -> (current,next)
        Just node ->
          let (!expanded,!next') = expandFunctor next node
              !next''            = libraryInsert name expanded next'
          in (current,next'')

isStable :: Library -> Library -> Bool
isStable a b =
  librarySize a == librarySize b &&
  libraryNodes a == libraryNodes b

expandUntilCrystal
  :: Int
  -> Library
  -> Either CobaltError Library
expandUntilCrystal !limit !initial =
  go 0 initial
  where
    go !roundNo !lib
      | roundNo >= limit = Left ExpansionLimit
      | otherwise =
          let (!previous,!next) = expandRound lib
          in if isStable previous next
               then Right next
               else go (roundNo + 1) next

-- ============================================================
-- VAULT TRANSFORMATION
-- ============================================================

vaultTransform :: Bool -> Functor -> Functor
vaultTransform !enabled node
  | not enabled = node
vaultTransform enabled node =
  case node of
    Atom x        -> Atom (reverse x)
    Variable x    -> Variable x
    Reference x   -> Reference (reverse x)
    Apply name args ->
      Apply (reverse name)
            (map (vaultTransform enabled) (reverse args))
    Recursive name args ->
      Recursive (reverse name)
                (map (vaultTransform enabled) args)
    Sequence xs ->
      Sequence (map (vaultTransform enabled) (reverse xs))

-- ============================================================
-- CRYSTAL FOLD
-- ============================================================

crystalFold :: Int -> Functor -> Functor
crystalFold !depth node
  | depth <= 0 = node
crystalFold !depth node =
  case node of
    Atom _     -> node
    Variable _ -> node
    Reference _ -> node
    Apply name args ->
      Apply name (map (crystalFold (depth - 1)) args)
    Recursive name args ->
      Recursive name (map (crystalFold (depth - 1)) args)
    Sequence xs ->
      Sequence (map (crystalFold (depth - 1)) xs)

crystalize :: Int -> Library -> [Functor]
crystalize !depth !lib =
  [ crystalFold depth node
  | name <- libraryOrder lib
  , Just node <- [M.lookup name (libraryNodes lib)]
  ]

-- ============================================================
-- MATRIX
-- ============================================================

data Matrix = Matrix
  { matrixRows  :: !Int
  , matrixCols  :: !Int
  , matrixCells :: !(M.Map (Int,Int) Int)
  } deriving (Eq,Show)

flatten :: Functor -> [Functor]
flatten node =
  node :
    case node of
      Atom _        -> []
      Variable _    -> []
      Reference _   -> []
      Apply _ xs    -> concatMap flatten xs
      Recursive _ xs -> concatMap flatten xs
      Sequence xs   -> concatMap flatten xs

buildMatrix :: Int -> [Functor] -> Matrix
buildMatrix !limit roots =
  let !nodes = take limit (concatMap flatten roots)
      !n     = length nodes
      !edges = concatMap (nodeEdges nodes) (zip [0..] nodes)
  in Matrix n n (M.fromList edges)

nodeEdges :: [Functor] -> (Int,Functor) -> [((Int,Int),Int)]
nodeEdges nodes (parent,node) =
  case node of
    Apply _ xs    -> childEdges 1 nodes parent xs
    Recursive _ xs -> childEdges 2 nodes parent xs
    _             -> []

childEdges :: Int -> [Functor] -> Int -> [Functor] -> [((Int,Int),Int)]
childEdges weight nodes parent children =
  [ ((parent,j), weight)
  | child <- children
  , Just j <- [findIndexEq child nodes]
  ]

findIndexEq :: Eq a => a -> [a] -> Maybe Int
findIndexEq x = go 0
  where
    go !_ []     = Nothing
    go !n (y:ys)
      | x == y    = Just n
      | otherwise = go (n+1) ys

-- ============================================================
-- TRILOCK TRIAD
-- ============================================================

data Triad = Triad
  { triA :: !Word64
  , triB :: !Word64
  , triC :: !Word64
  } deriving (Eq,Show)

mix :: Word64 -> Word64 -> Word64
mix x y =
  let z = x `xor` y
      a = z * 0x9E3779B185EBCA87
  in rotateL a 17

trilockMatrix :: Matrix -> [Triad]
trilockMatrix m =
  map make [0 .. matrixRows m - 1]
  where
    make !r =
      let !a = rowHash r
          !b = colHash r
          !c = mix a b
      in Triad a b c

    rowHash r =
      foldl (\h c ->
          mix h (fromIntegral
            (M.findWithDefault 0 (r,c) (matrixCells m))))
        0 [0 .. matrixCols m - 1]

    colHash c =
      foldl (\h r ->
          mix h (fromIntegral
            (M.findWithDefault 0 (r,c) (matrixCells m))))
        0 [0 .. matrixRows m - 1]

-- ============================================================
-- ISA
-- ============================================================

data ISA
  = Nop
  | Ret
  | XorRR  !Word8 !Word8
  | MovImm !Word8 !Word64
  | AddImm !Word8 !Int32
  deriving (Eq,Show)

lowerTriads :: [Triad] -> [ISA]
lowerTriads = concatMap lowerOne
  where
    lowerOne (Triad a b c) =
      [ MovImm 0 a
      , XorRR  0 1
      , AddImm 0 (fromIntegral (c .&. 0x7fffffff))
      ]

encodeISA :: ISA -> BS.ByteString
encodeISA Nop          = BS.pack [0x90]
encodeISA Ret          = BS.pack [0xC3]
encodeISA (XorRR d s)  =
  BS.pack [ rexB d s, 0x31, 0xC0 + ((d .&. 7) `shiftL` 3) + (s .&. 7) ]
encodeISA (MovImm r x) =
  BS.pack [ rexS r, 0xB8 + (r .&. 7) ] <> le64 x
encodeISA (AddImm r x) =
  BS.pack [ rexS r, 0x81, 0xC0 + (r .&. 7) ] <> le32 (fromIntegral x)

rexS :: Word8 -> Word8
rexS r = if r >= 8 then 0x49 else 0x48

rexB :: Word8 -> Word8 -> Word8
rexB d s = 0x48 + (if d >= 8 then 4 else 0) + (if s >= 8 then 1 else 0)

le32 :: Word32 -> BS.ByteString
le32 x = BS.pack [ fromIntegral (x `shiftR` (8*i)) | i <- [0..3] ]

le64 :: Word64 -> BS.ByteString
le64 x = BS.pack [ fromIntegral (x `shiftR` (8*i)) | i <- [0..7] ]

-- ============================================================
-- BUILD OUTPUT
-- ============================================================

data Build = Build
  { buildLibrary :: !Library
  , buildMatrix  :: !Matrix
  , buildTriads  :: ![Triad]
  , buildISA     :: ![ISA]
  , buildBinary  :: !BS.ByteString
  } deriving (Eq,Show)

-- ============================================================
-- FULL PIPELINE
-- ============================================================

magicCobalt
  :: CobaltConfig
  -> String
  -> Either CobaltError Build
magicCobalt config source = do
  rules <- parseProgram source

  let !initial = rulesToLibrary rules

  !crystal <- expandUntilCrystal
                (maxExpansionRounds config)
                initial

  let !nodes = crystalize (crystalDepth config) crystal

      !vaulted = map (vaultTransform (invertVault config)) nodes

      !m = buildMatrix (matrixWidth config) vaulted

      !triads = trilockMatrix m

      !isa = lowerTriads triads

      !binary = BS.concat (map encodeISA isa)

  Right Build
    { buildLibrary = crystal
    , buildMatrix  = m
    , buildTriads  = triads
    , buildISA     = isa
    , buildBinary  = binary
    }

compile :: CobaltConfig -> String -> Either CobaltError BS.ByteString
compile config source =
  buildBinary <$> magicCobalt config source

compileBatch
  :: CobaltConfig
  -> [(String,String)]
  -> [(String, Either CobaltError BS.ByteString)]
compileBatch config =
  map (\(name,source) -> (name, compile config source))
