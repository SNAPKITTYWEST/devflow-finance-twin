{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

-- | Workerman calculus – practical core language derived from Liquid
-- Haskell RefCore, extended with trigonometric annotations and the
-- Polynomial Wormhole Constraint (PWC) astronomical layer.
module Language.Workerman.Calculus
  ( -- * Grammar
    Builtin (..),
    BaseType (..),
    RefType (..),
    Decl (..),
    Expr (..),
    Reft (..),
    ProjKind (..),
    Localization (..),
    DesState (..),
    Bop (..),
    ProofOp (..),
    TrigAnn (..),
    Epicycle (..),
    FlopRom (..),
    SphereCoord (..),
    BraidWord (..),

    -- * Builtin constructors
    boolTp, ttTm, ffTm, unitTp, unitTm,
    angleTp, radTp,
    celestialSphereTp,
    hopfFiberTp,

    -- * Construction
    mkVar, arrs, apps, renameParams,
    mkEpicycle, mkBraidWord, mkFlopLookup,

    -- * Free variables / substitution
    HasVars (..), freeVars, fresh, rename, substs,

    -- * Braid normalisation
    normalise,
  )
where

import Data.Bifunctor (first)
import Data.Binary (Binary)
import Data.Data
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)
import Language.Workerman.Names
  ( Id, boolTpName, ffTmName, freshVar, ttTmName,
    unitTmName, unitTpName, angleTpName, radTpName,
    celestialSphereName, hopfFiberName )
import Text.PrettyPrint
import Text.PrettyPrint.HughesPJClass hiding (first)
import Prelude hiding (lookup, (<>))

--------------------------------------------------------------------------------
-- * Core grammar
--------------------------------------------------------------------------------

data Builtin
  = Integer | Double | String
  | Angle | Radian
  | Celestial   -- S² base manifold
  | HopfFiber   -- CP¹ Bloch states
  deriving (Data, Eq, Show, Generic, Binary)

data BaseType = Builtin Builtin | TC Id
  deriving (Data, Eq, Show, Generic, Binary)

data RefType
  = RefType Id BaseType Reft
  | ArrType Id RefType RefType
  deriving (Data, Show, Generic, Binary)

data Decl
  = Data Id [(Id, RefType)]
  | Definition Id RefType Expr Bool
  | Import Id [Decl]
  deriving (Data, Eq, Show, Generic, Binary)

data Expr
  = Reft Reft
  | Let Id (Maybe RefType) Expr Expr
  | Case Reft [((Id, [(Id, Bool)]), Maybe Expr)] (Maybe [Id])
  | QMark Expr Expr Reft
  deriving (Data, Show, Generic, Binary)

data Reft
  = Var Id (Maybe BaseType) Localization
  | StringLit String
  | IntLit Integer
  | FloatLit Double
  | DC Id
  | App Reft Reft
  | Neg Reft
  | Bop Bop Reft Reft
  | Pop ProofOp Reft Reft
  | Sub Reft RefType RefType
  | Inj Reft RefType
  | Proj ProjKind Reft
  | Trig TrigAnn Reft
  | Epi Epicycle Reft
  | Braid BraidWord
  | Flop FlopRom Reft
  | Sphere SphereCoord Reft
  deriving (Data, Eq, Show, Generic, Binary)

data ProjKind
  = GenProj | Sig1 | Sig2
  | CosProj | SinProj
  | RAProj | DecProj
  | HopfProj
  deriving (Data, Eq, Show, Generic, Binary)

data Localization
  = Local | Global | Recursive Id [DesState]
  deriving (Data, Eq, Show, Generic, Binary)

data DesState = Param Id Integer | Destructed
  deriving (Data, Eq, Show, Generic, Binary)

data Bop
  = Plus | Minus | Times | Div | Mod
  | Eq | Neq | Leq | Geq | Lt | Gt
  | And | Or | Impl | Iff
  | Atan2 | Hypot
  | SphericalSine
  | GreatCircle
  | YangBaxter
  deriving (Data, Eq, Generic, Binary)

data ProofOp = PEq | PLeq | PGeq deriving (Data, Eq, Generic, Binary)

data TrigAnn
  = Sin | Cos | Tan | Asin | Acos | Atan
  | Sinh | Cosh | Tanh
  | Period Double
  | Range (Double, Double)
  deriving (Data, Eq, Show, Generic, Binary)

--------------------------------------------------------------------------------
-- * Astronomical / PWC constructs
--------------------------------------------------------------------------------

data Epicycle = Epicycle
  { epiDeferent :: Double
  , epiEpicycle :: Double
  , epiMeanMotion :: Double
  , epiAnomaly :: Reft
  }
  deriving (Data, Eq, Show, Generic, Binary)

data BraidWord
  = BraidEmpty
  | BraidGen Int
  | BraidComp BraidWord BraidWord
  | BraidInv BraidWord
  | BraidYB BraidWord
  deriving (Data, Eq, Show, Generic, Binary)

data FlopRom = FlopRom
  { romAddress :: Integer
  , romValue :: (Double, Double)
  , romWORM :: Bool
  }
  deriving (Data, Eq, Show, Generic, Binary)

data SphereCoord = SphereCoord
  { scRA :: Double
  , scDec :: Double
  , scMetric :: Maybe String
  }
  deriving (Data, Eq, Show, Generic, Binary)

--------------------------------------------------------------------------------
-- Builtin type constructors
--------------------------------------------------------------------------------

boolTp, unitTp, angleTp, radTp, celestialSphereTp, hopfFiberTp :: BaseType
unitTm, ttTm, ffTm :: Reft

boolTp = TC boolTpName
unitTp = TC unitTpName
angleTp = Builtin Angle
radTp = Builtin Radian
celestialSphereTp = Builtin Celestial
hopfFiberTp = Builtin HopfFiber

ttTm = DC ttTmName
ffTm = DC ffTmName
unitTm = DC unitTmName

--------------------------------------------------------------------------------
-- Construction helpers
--------------------------------------------------------------------------------

mkVar :: Id -> Reft
mkVar x = Var x Nothing Local

arrs :: RefType -> ([(Id, RefType)], (Id, BaseType, Reft))
arrs (RefType x a r) = ([], (x, a, r))
arrs (ArrType x tpx tp) = ((x, tpx) :) `first` arrs tp

apps :: Reft -> (Reft, [Reft])
apps (App tm1 tm2) = let (hd, args) = apps tm1 in (hd, args ++ [tm2])
apps tm = (tm, [])

renameParams :: [Id] -> RefType -> RefType
renameParams = aux []
  where
    aux σ _ tp@(RefType {}) = renames σ tp
    aux σ [] tp = renames σ tp
    aux σ (y:ys) (ArrType x tpx tp)
      | x `notElem` freeVars tp || x == y =
          ArrType y (renames σ tpx) (aux σ ys tp)
    aux _ (y:_) tp0@(ArrType x _ tp)
      | y `elem` freeVars tp =
          error . render $
            "Name clash renaming" <+> text x <+> "to" <+> text y
              <+> "in" <+> pPrint tp0
    aux σ (y:ys) (ArrType x tpx tp) =
      ArrType y (renames σ tpx) (aux ((y,x):σ) ys tp)

mkEpicycle :: Double -> Double -> Double -> Reft -> Reft
mkEpicycle def epi mean anomaly =
  Epi (Epicycle def epi mean anomaly) anomaly

mkBraidWord :: [Int] -> BraidWord
mkBraidWord = foldr (\i w -> BraidComp (BraidGen i) w) BraidEmpty

mkFlopLookup :: Integer -> (Double, Double) -> Bool -> Reft -> Reft
mkFlopLookup addr val sealed body =
  Flop (FlopRom addr val sealed) body

--------------------------------------------------------------------------------
-- Free variables / substitution
--------------------------------------------------------------------------------

class HasVars a where
  freeVarsAnnot :: a -> Map Id (Maybe BaseType, Localization)
  boundVars :: a -> Set Id
  subst :: Reft -> Id -> a -> a

freeVars :: HasVars a => a -> Set Id
freeVars = Map.keysSet . freeVarsAnnot

fresh :: HasVars a => Id -> a -> Id
fresh x tm = freshVar x (freeVars tm `Set.union` boundVars tm)

rename :: HasVars a => Id -> Id -> a -> a
rename new old tm =
  maybe tm (\(tp,loc) -> subst (Var new tp loc) old tm)
        (Map.lookup old $ freeVarsAnnot tm)

renames :: HasVars a => [(Id,Id)] -> a -> a
renames = flip (foldr (uncurry rename))

substs :: HasVars a => [(Reft,Id)] -> a -> a
substs = flip (foldr (uncurry subst))

instance HasVars Reft where
  freeVarsAnnot (Var x tp loc) = Map.singleton x (tp, loc)
  freeVarsAnnot (App h a) = freeVarsAnnot [h,a]
  freeVarsAnnot (Bop _ r1 r2) = freeVarsAnnot [r1,r2]
  freeVarsAnnot (Neg r) = freeVarsAnnot r
  freeVarsAnnot (StringLit _) = Map.empty
  freeVarsAnnot (IntLit _) = Map.empty
  freeVarsAnnot (FloatLit _) = Map.empty
  freeVarsAnnot (DC _) = Map.empty
  freeVarsAnnot (Pop _ r1 r2) = freeVarsAnnot [r1,r2]
  freeVarsAnnot (Sub r f t) = freeVarsAnnot r `Map.union` freeVarsAnnot [f,t]
  freeVarsAnnot (Inj r tp) = freeVarsAnnot r `Map.union` freeVarsAnnot tp
  freeVarsAnnot (Proj _ r) = freeVarsAnnot r
  freeVarsAnnot (Trig _ r) = freeVarsAnnot r
  freeVarsAnnot (Epi e r) = freeVarsAnnot (epiAnomaly e) `Map.union` freeVarsAnnot r
  freeVarsAnnot (Braid _) = Map.empty
  freeVarsAnnot (Flop _ r) = freeVarsAnnot r
  freeVarsAnnot (Sphere _ r) = freeVarsAnnot r

  boundVars (Var {}) = Set.empty
  boundVars (StringLit _) = Set.empty
  boundVars (IntLit _) = Set.empty
  boundVars (FloatLit _) = Set.empty
  boundVars (DC _) = Set.empty
  boundVars (Braid _) = Set.empty
  boundVars (App h a) = boundVars [h,a]
  boundVars (Bop _ r1 r2) = boundVars [r1,r2]
  boundVars (Neg r) = boundVars r
  boundVars (Pop _ r1 r2) = boundVars [r1,r2]
  boundVars (Sub r f t) = boundVars r `Set.union` boundVars [f,t]
  boundVars (Inj r tp) = boundVars r `Set.union` boundVars tp
  boundVars (Proj _ r) = boundVars r
  boundVars (Trig _ r) = boundVars r
  boundVars (Epi e r) = boundVars (epiAnomaly e) `Set.union` boundVars r
  boundVars (Flop _ r) = boundVars r
  boundVars (Sphere _ r) = boundVars r

  subst r' x (Var y _ _) | y == x = r'
  subst _ _ r0@(Var {}) = r0
  subst _ _ r0@(StringLit _) = r0
  subst _ _ r0@(IntLit _) = r0
  subst _ _ r0@(FloatLit _) = r0
  subst _ _ r0@(DC _) = r0
  subst r' x (App h a) = App (subst r' x h) (subst r' x a)
  subst r' x (Bop b r1 r2) = Bop b (subst r' x r1) (subst r' x r2)
  subst r' x (Neg r) = Neg (subst r' x r)
  subst r' x (Pop p r1 r2) = Pop p (subst r' x r1) (subst r' x r2)
  subst r' x (Sub r f t) = Sub (subst r' x r) (subst r' x f) (subst r' x t)
  subst r' x (Inj r tp) = Inj (subst r' x r) (subst r' x tp)
  subst r' x (Proj k r) = Proj k (subst r' x r)
  subst r' x (Trig a r) = Trig a (subst r' x r)
  subst r' x (Epi e r) =
    Epi e{ epiAnomaly = subst r' x (epiAnomaly e) } (subst r' x r)
  subst _ _ b@(Braid _) = b
  subst r' x (Flop rom r) = Flop rom (subst r' x r)
  subst r' x (Sphere sc r) = Sphere sc (subst r' x r)

instance HasVars Expr where
  freeVarsAnnot (Reft r) = freeVarsAnnot r
  freeVarsAnnot (Let x tp ex e) =
    freeVarsAnnot tp `Map.union` Map.delete x (freeVarsAnnot [ex,e])
  freeVarsAnnot (Case r branches _) =
    freeVarsAnnot r `Map.union` Map.unions (map fvBranch branches)
    where fvBranch ((_,ys),ebr) =
            freeVarsAnnot ebr `Map.withoutKeys` Set.fromList (map fst ys)
  freeVarsAnnot (QMark r rh rp) = freeVarsAnnot [r,rh,Reft rp]

  boundVars (Reft r) = boundVars r
  boundVars (Let x tp ex e) =
    Set.singleton x `Set.union` boundVars tp `Set.union` boundVars [ex,e]
  boundVars (Case r branches _) =
    boundVars r `Set.union` Set.unions (map bvBranch branches)
    where bvBranch ((_,ys),e) =
            Set.fromList (map fst ys) `Set.union` boundVars e
  boundVars (QMark r rh rp) = boundVars [r,rh,Reft rp]

  subst r x (Reft re) = Reft (subst r x re)
  subst r x (Let y tp ey e')
    | y == x = Let y (subst r x tp) (subst r x ey) e'
    | y `Set.member` freeVars r && x `Set.member` freeVars e' =
        let z = freshVar y (freeVars r `Set.union` freeVars (Let y tp ey e'))
        in Let z (subst r x tp) (subst r x ey) (subst r x $ rename z y e')
    | otherwise = Let y (subst r x tp) (subst r x ey) (subst r x e')
  subst r x (Case r' branches genVars) =
    Case (subst r x r') (map substBranch branches) genVars
    where
      substBranch br@((_,ys),ebr)
        | x `elem` map fst ys || maybe True (notElem x . freeVars) ebr = br
      substBranch ((c,ys),ebr) =
        let freshYs = foldr freshVars [] ys
            α = filter (uncurry (/=)) $ zipWith (\(y,_) z -> (z,y)) ys freshYs
            ys' = zipWith (\(_,b) z -> (z,b)) ys freshYs
            freshVars (y,_) vars =
              if y `elem` freeVars r
                then freshVar y (fvre `Set.union` Set.fromList vars) : vars
                else y : vars
            fvre = freeVars r `Set.union` freeVars (Case r' branches genVars)
        in ((c,ys'), subst r x $ renames α ebr)
  subst r x (QMark r' rh rp) =
    QMark (subst r x r') (subst r x rh) (subst r x rp)

instance HasVars RefType where
  freeVarsAnnot (RefType x _ r) = Map.delete x (freeVarsAnnot r)
  freeVarsAnnot (ArrType x tpx tp) =
    freeVarsAnnot tpx `Map.union` Map.delete x (freeVarsAnnot tp)

  boundVars (RefType x _ r) = Set.singleton x `Set.union` boundVars r
  boundVars (ArrType x tpx tp) =
    Set.singleton x `Set.union` boundVars [tpx,tp]

  subst _ x tp@(RefType y _ _) | y == x = tp
  subst r x (RefType y b reft) = RefType y b (subst r x reft)
  subst r x (ArrType y tpy tp')
    | y == x = ArrType y (subst r x tpy) tp'
    | y `Set.member` freeVars r && x `Set.member` freeVars tp' =
        let z = freshVar y (freeVars r `Set.union` freeVars (ArrType y tpy tp'))
        in ArrType z (subst r x tpy) (subst r x $ rename z y tp')
    | otherwise = ArrType y (subst r x tpy) (subst r x tp')

instance HasVars a => HasVars [a] where
  freeVarsAnnot = Map.unions . map freeVarsAnnot
  boundVars = Set.unions . map boundVars
  subst r x = fmap (subst r x)

instance HasVars a => HasVars (Maybe a) where
  freeVarsAnnot = maybe Map.empty freeVarsAnnot
  boundVars = maybe Set.empty boundVars
  subst r x = fmap (subst r x)

--------------------------------------------------------------------------------
-- α-equality
--------------------------------------------------------------------------------

instance Eq RefType where
  tp1@(RefType x tpx rx) == tp2@(RefType y tpy ry) =
    let z = fresh x [tp1,tp2]
        (α1,α2) = if x /= y then ([(z,x)],[(z,y)]) else ([],[])
    in tpx == tpy && renames α1 rx == renames α2 ry
  tp1@(ArrType x tpx tp1') == tp2@(ArrType y tpy tp2') =
    let z = fresh x [tp1,tp2]
        (α1,α2) = if x /= y then ([(z,x)],[(z,y)]) else ([],[])
    in tpx == tpy && renames α1 tp1' == renames α2 tp2'
  _ == _ = False

instance Eq Expr where
  Reft r1 == Reft r2 = r1 == r2
  e1@(Let x tpx ex e1') == e2@(Let y tpy ey e2') =
    let z = fresh x [e1,e2]
        (α1,α2) = if x /= y then ([(z,x)],[(z,y)]) else ([],[])
    in tpx == tpy && ex == ey && renames α1 e1' == renames α2 e2'
  e1@(Case r1 alts1 g1) == e2@(Case r2 alts2 g2) =
    r1 == r2 && all eqBranch (zip alts1 alts2) && g1 == g2
    where
      eqBranch (((c1,ys1),e1'),((c2,ys2),e2')) =
        let freshYs = foldr freshVars [] (zip ys1 ys2)
            α ys = filter (uncurry (/=)) $
                     zipWith (\(y,_) z -> (z,y)) ys freshYs
        in c1 == c2 && renames (α ys1) e1' == renames (α ys2) e2'
      freshVars ((y1,_),(y2,_)) vars =
        if y1 /= y2
          then freshVar y1 (freeVars [e1,e2] `Set.union` Set.fromList vars) : vars
          else y1 : vars
  _ == _ = False

--------------------------------------------------------------------------------
-- Braid normalisation (termination-proven)
--------------------------------------------------------------------------------

-- | Generator with sign
data Gen = Pos Int | Neg Int deriving (Eq, Show)

-- | Flatten nested compositions into linear generator list
flatten :: BraidWord -> [Gen]
flatten BraidEmpty = []
flatten (BraidGen i) = [Pos i]
flatten (BraidInv w) = map inv (flatten w)
  where inv (Pos i) = Neg i
        inv (Neg i) = Pos i
flatten (BraidComp a b) = flatten a ++ flatten b
flatten (BraidYB w) = flatten w

-- | Rewrite engine: inverse cancellation, far commutativity, Yang-Baxter
rewrite :: [Gen] -> [Gen]
rewrite [] = []
rewrite [g] = [g]
rewrite (Pos i : Neg j : rest) | i == j = rewrite rest
rewrite (Neg i : Pos j : rest) | i == j = rewrite rest
rewrite (Pos i : Pos j : rest)
  | abs (i - j) >= 2 && i > j =
      Pos j : rewrite (Pos i : rest)
rewrite (Neg i : Neg j : rest)
  | abs (i - j) >= 2 && i > j =
      Neg j : rewrite (Neg i : rest)
rewrite (Pos i : Pos j : Pos k : rest)
  | abs (i - j) == 1 && i == k =
      Pos j : Pos i : Pos j : rewrite rest
rewrite (Neg i : Neg j : Neg k : rest)
  | abs (i - j) == 1 && i == k =
      Neg j : Neg i : Neg j : rewrite rest
rewrite (g : rest) = g : rewrite rest

-- | Fixed point of rewrite
fix :: [Gen] -> [Gen]
fix gs = let ys = rewrite gs in if ys == gs then gs else fix ys

-- | Rebuild BraidWord from reduced generator list
rebuild :: [Gen] -> BraidWord
rebuild [] = BraidEmpty
rebuild (g:gs) = foldl BraidComp (sing g) (map sing gs)
  where
    sing (Pos i) = BraidGen i
    sing (Neg i) = BraidInv (BraidGen i)

-- | Normalise a braid word
-- Termination: lexicographic measure (length, cancellation potential, inversion number)
-- Each rewrite step strictly decreases this measure.
normalise :: BraidWord -> BraidWord
normalise = rebuild . fix . flatten

-- | Equality up to normal form
instance Eq BraidWord where
  w1 == w2 = normalise w1 == normalise w2

--------------------------------------------------------------------------------
-- Pretty printer
--------------------------------------------------------------------------------

identNb :: Int
identNb = 2

arrPrec, appPrec :: Rational
arrPrec = 0
appPrec = 10

bopPrec :: Bop -> Rational
bopPrec Mod = 7
bopPrec Plus = 6 ; bopPrec Minus = 6
bopPrec Times = 7 ; bopPrec Div = 7
bopPrec Eq = 4 ; bopPrec Neq = 4
bopPrec Leq = 4 ; bopPrec Geq = 4 ; bopPrec Lt = 4 ; bopPrec Gt = 4
bopPrec And = 3 ; bopPrec Or = 2 ; bopPrec Impl = 1 ; bopPrec Iff = 1
bopPrec Atan2 = 5 ; bopPrec Hypot = 5
bopPrec SphericalSine = 5
bopPrec GreatCircle = 5
bopPrec YangBaxter = 4

popPrec :: ProofOp -> Rational
popPrec _ = 4

instance Pretty Builtin where pPrint = text . show
instance Pretty BaseType where
  pPrint (Builtin b) = pPrint b
  pPrint (TC tc) = text tc

instance Pretty RefType where
  pPrintPrec _ _ (RefType _ a r) | r == ttTm = braces (pPrint a)
  pPrintPrec _ _ (RefType _ a r) | a == unitTp = braces (braces (pPrint r))
  pPrintPrec _ _ (RefType x a r) =
    braces (text x <> colon <+> pPrint a <+> char '|' <+> pPrint r)
  pPrintPrec l p (ArrType x tpx tp) =
    maybeParens (p > arrPrec) $
      sep [text x <> colon <+> pPrintPrec l (arrPrec+1) tpx,
           "->" <+> pPrintPrec l arrPrec tp]

instance Pretty Decl where
  pPrint (Data tc cs) =
    sep ["data" <+> text tc <+> ":=",
         nest identNb . sep $ map (\(c,t) -> char '|' <+> text c <+> "::" <+> pPrint t) cs]
  pPrint (Definition f tp e refl) =
    sep [(if refl then "refl" else empty) <+> "def" <+> text f <+> "::" <+> pPrint tp <+> ":=",
         nest identNb (pPrint e)]
  pPrint (Import m ds) =
    vcat (("import" <+> text m) : map (nest identNb . pPrint) ds)

instance Pretty Expr where
  pPrint (Reft r) = pPrint r
  pPrint (Let x tpx ex e) =
    sep [sep ["let" <+> ppTp <+> ":=", pPrint ex], nest 1 ("in" <+> pPrint e)]
    where ppTp = maybe (text x) (\tp -> parens (text x <> colon <+> pPrint tp)) tpx
  pPrint (Case r alts gen) =
    vcat ((des <+> pPrint r <+> "of") : map ppAlt alts)
    where
      des = maybe "destruct" (const "induct") gen
      ppAlt (pat,e) = sep [char '|' <+> ppPat pat <+> "->",
                           nest identNb (maybe "undefined" pPrint e)]
      ppPat (c,ys) = text c <+> hsep (map (text . fst) ys)
  pPrint (QMark r rh rp) =
    pPrint r <+> char '?' <+> parens (pPrint rh <+> "proves" <+> pPrint rp)

instance Pretty Reft where
  pPrintPrec _ _ (Var x _ _) = text x
  pPrintPrec _ _ (StringLit s) = quotes (text s)
  pPrintPrec _ _ (IntLit i) = integer i
  pPrintPrec _ _ (FloatLit f) = double f
  pPrintPrec _ _ (DC c) = text c
  pPrintPrec l p (App r1 r2) =
    maybeParens (p > appPrec) $ pPrintPrec l p r1 <+> pPrintPrec l (appPrec+1) r2
  pPrintPrec l p (Neg r) =
    maybeParens (p > appPrec) $ "not" <+> pPrintPrec l (appPrec+1) r
  pPrintPrec l p (Bop b r1 r2) =
    maybeParens (p > bopPrec b) $
      pPrintPrec l (bopPrec b) r1 <+> pPrint b <+> pPrintPrec l (bopPrec b) r2
  pPrintPrec l p (Pop pop r1 r2) =
    maybeParens (p > popPrec pop) $
      pPrintPrec l (popPrec pop) r1 <+> pPrint pop <+> pPrintPrec l (popPrec pop) r2
  pPrintPrec _ p (Sub r f t) =
    maybeParens (p > appPrec) $
      "sub" <+> parens (hsep $ punctuate comma [pPrint r, pPrint f, pPrint t])
  pPrintPrec _ p (Inj r tp) =
    maybeParens (p > appPrec) $ "inj" <+> parens (pPrint r <> comma <+> pPrint tp)
  pPrintPrec l p (Proj k r) =
    maybeParens (p > appPrec) $ pPrint k <+> pPrintPrec l (appPrec+1) r
  pPrintPrec l p (Trig a r) =
    maybeParens (p > appPrec) $ pPrint a <> brackets (pPrintPrec l 0 r)
  pPrintPrec l p (Epi e r) =
    maybeParens (p > appPrec) $
      "epicycle" <> parens (hsep $ punctuate comma
        [double (epiDeferent e), double (epiEpicycle e),
         double (epiMeanMotion e), pPrint (epiAnomaly e)])
      <+> pPrintPrec l (appPrec+1) r
  pPrintPrec _ _ (Braid w) = "braid" <> brackets (pPrint w)
  pPrintPrec l p (Flop rom r) =
    maybeParens (p > appPrec) $
      "flop" <> parens (integer (romAddress rom)
                        <> comma <+> text (show (romValue rom))
                        <> (if romWORM rom then ",WORM" else empty))
      <+> pPrintPrec l (appPrec+1) r
  pPrintPrec l p (Sphere sc r) =
    maybeParens (p > appPrec) $
      "sphere" <> parens (double (scRA sc) <> comma <+> double (scDec sc))
      <+> pPrintPrec l (appPrec+1) r

instance Pretty Localization where
  pPrint Local = char 'L'
  pPrint Global = char 'G'
  pPrint (Recursive v _) = char 'Y' <+> text v

instance Show Bop where
  show Mod = "`mod`"; show Plus = "+"; show Minus = "-"
  show Times = "*"; show Div = "/"
  show Eq = "=="; show Neq = "/="; show Leq = "<="; show Geq = ">="
  show Lt = "<"; show Gt = ">"
  show And = "&&"; show Or = "||"; show Impl = "=>"; show Iff = "<=>"
  show Atan2 = "atan2"; show Hypot = "hypot"
  show SphericalSine = "spherical_sine"
  show GreatCircle = "great_circle"
  show YangBaxter = "YB"

instance Pretty Bop where pPrint = text . show

instance Show ProofOp where
  show PEq = "==="; show PLeq = "=<="; show PGeq = "=>="
instance Pretty ProofOp where pPrint = text . show

instance Pretty ProjKind where
  pPrint GenProj = "proj"; pPrint Sig1 = "proj1_sig"; pPrint Sig2 = "proj2_sig"
  pPrint CosProj = "cos"; pPrint SinProj = "sin"
  pPrint RAProj = "RA"; pPrint DecProj = "Dec"; pPrint HopfProj = "hopf"

instance Pretty TrigAnn where
  pPrint Sin = "sin"; pPrint Cos = "cos"; pPrint Tan = "tan"
  pPrint Asin = "asin"; pPrint Acos = "acos"; pPrint Atan = "atan"
  pPrint Sinh = "sinh"; pPrint Cosh = "cosh"; pPrint Tanh = "tanh"
  pPrint (Period p) = "period" <> parens (double p)
  pPrint (Range (lo,hi)) = "range" <> parens (double lo <> comma <+> double hi)

instance Pretty Epicycle where
  pPrint (Epicycle d e m a) =
    "Epicycle" <> braces
      (hsep $ punctuate comma
        ["def=" <> double d, "epi=" <> double e,
         "mean=" <> double m, "anom=" <> pPrint a])

instance Pretty BraidWord where
  pPrint BraidEmpty = "ε"
  pPrint (BraidGen i) = "σ" <> integer (toInteger i)
  pPrint (BraidComp w1 w2) = pPrint w1 <> "·" <> pPrint w2
  pPrint (BraidInv w) = pPrint w <> "⁻¹"
  pPrint (BraidYB w) = "YB(" <> pPrint w <> ")"

instance Pretty FlopRom where
  pPrint (FlopRom addr val sealed) =
    "ROM[" <> integer addr <> "]=" <> text (show val)
      <> (if sealed then "⟂WORM" else empty)

instance Pretty SphereCoord where
  pPrint (SphereCoord ra dec m) =
    "S²(RA=" <> double ra <> ",Dec=" <> double dec <> ")"
      <> maybe empty (\s -> "⟨" <> text s <> "⟩") m
