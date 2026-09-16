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

{-# OPTIONS --without-K --safe #-}

module SymbolOscillatorInvariant where

open import Data.Nat using (â„•; zero; suc)
open import Data.Fin using (Fin; toâ„•)
open import Data.Vec using (Vec; []; _âˆ·_; tabulate; map; zipWith)
open import Data.Product using (_Ã—_; _,_)
open import Relation.Binary.PropositionalEquality using (_â‰¡_; refl; cong)
open import Function using (_âˆ˜_)
open import Data.Rational using (â„š; _+_; _*_; _-_; _/_ ; fromâ„•; âˆ£_âˆ£)
open import Data.Unit using (âŠ¤; tt)

-- Simple complex numbers as pairs of rationals
Complex : Set
Complex = â„š Ã— â„š

_+c_ : Complex â†’ Complex â†’ Complex
(xâ‚ , yâ‚) +c (xâ‚‚ , yâ‚‚) = (xâ‚ + xâ‚‚ , yâ‚ + yâ‚‚)

_-c_ : Complex â†’ Complex â†’ Complex
(xâ‚ , yâ‚) -c (xâ‚‚ , yâ‚‚) = (xâ‚ - xâ‚‚ , yâ‚ - yâ‚‚)

_*c_ : Complex â†’ Complex â†’ Complex
(xâ‚ , yâ‚) *c (xâ‚‚ , yâ‚‚) = (xâ‚ * xâ‚‚ - yâ‚ * yâ‚‚ , xâ‚ * yâ‚‚ + yâ‚ * xâ‚‚)

scalec : â„š â†’ Complex â†’ Complex
scalec a (x , y) = (a * x , a * y)

zeroC : Complex
zeroC = (0â„š , 0â„š)

sqMag : Complex â†’ â„š
sqMag (x , y) = x * x + y * y

VecC : â„• â†’ Set
VecC N = Vec Complex N

Matrix : â„• â†’ Set
Matrix N = Vec (Vec â„š N) N

record Params (N : â„•) : Set where
  field
    Î±  : â„š
    Î”t : â„š
    K  : Matrix N
    F  : Vec â„š N

open Params

vadd : âˆ€ {N} â†’ VecC N â†’ VecC N â†’ VecC N
vadd {zero}  []        []        = []
vadd {suc n} (x âˆ· xs) (y âˆ· ys)  = (x +c y) âˆ· vadd xs ys

dotRow : âˆ€ {N} â†’ Vec â„š N â†’ VecC N â†’ Complex
dotRow {zero}  []       []       = zeroC
dotRow {suc n} (k âˆ· ks) (z âˆ· zs) = scalec k z +c dotRow ks zs

matVec : âˆ€ {N} â†’ Matrix N â†’ VecC N â†’ VecC N
matVec {zero}  []       []  = []
matVec {suc n} (r âˆ· rs) z   = dotRow r z âˆ· matVec rs z

nonlinearTerm : â„š â†’ Complex â†’ Complex
nonlinearTerm Î± z = scalec (Î± - sqMag z) z

index : âˆ€ {N} â†’ VecC N â†’ Fin N â†’ Complex
index {suc _} (x âˆ· _ )  Fin.zero     = x
index {suc n} (_ âˆ· xs) (Fin.suc i)   = index xs i

indexF : âˆ€ {N} â†’ Vec â„š N â†’ Fin N â†’ â„š
indexF {suc _} (x âˆ· _ )  Fin.zero    = x
indexF {suc n} (_ âˆ· xs) (Fin.suc i)  = indexF xs i

iterate : âˆ€ {N} â†’ Params N â†’ â„• â†’ VecC N â†’ VecC N
iterate p zero    z = z
iterate p (suc n) z = iterate p n (Tstep p z)
  where
  Tstep : âˆ€ {N} â†’ Params N â†’ VecC N â†’ VecC N
  Tstep p z =
    let coupling = matVec (K p) z
        go : Fin _ â†’ Complex
        go i =
          let zi   = index z i
              nonl = nonlinearTerm (Î± p) zi
              coup = index coupling i
              fi   = indexF (F p) i
          in  zi +c scalec (Î”t p) (nonl +c (coup -c zi) +c (scalec fi (1â„š , 0â„š)))
    in tabulate go

VecDist : âˆ€ {N} â†’ VecC N â†’ VecC N â†’ â„š
VecDist {zero}  []        []        = 0â„š
VecDist {suc n} (x âˆ· xs) (y âˆ· ys)  =
  âˆ£ projâ‚ x - projâ‚ y âˆ£ + âˆ£ projâ‚‚ x - projâ‚‚ y âˆ£ + VecDist xs ys
  where open import Data.Product using (projâ‚; projâ‚‚)

ConvergesTo : âˆ€ {N} â†’ (â„• â†’ VecC N) â†’ VecC N â†’ Set
ConvergesTo seq limit =
  âˆ€ Îµ â†’ Îµ > 0â„š â†’ âˆƒ Î» N0 â†’ âˆ€ n â†’ n â‰¥ N0 â†’ VecDist (seq n) limit < Îµ
  where open import Data.Rational using (_>_; _<_)
        open import Data.Nat using (_â‰¥_)
        open import Data.Product using (âˆƒ)

IsFixedPoint : âˆ€ {N} â†’ Params N â†’ VecC N â†’ Set
IsFixedPoint p x = Tstep p x â‰¡ x
  where
  Tstep : âˆ€ {N} â†’ Params N â†’ VecC N â†’ VecC N
  Tstep p z =
    let coupling = matVec (K p) z
        go : Fin _ â†’ Complex
        go i =
          let zi   = index z i
              nonl = nonlinearTerm (Î± p) zi
              coup = index coupling i
              fi   = indexF (F p) i
          in  zi +c scalec (Î”t p) (nonl +c (coup -c zi) +c (scalec fi (1â„š , 0â„š)))
    in tabulate go

InBasin : âˆ€ {N} â†’ Params N â†’ VecC N â†’ VecC N â†’ Set
InBasin p z pstar = ConvergesTo (Î» n â†’ iterate p n z) pstar

-- One-step invariance: if z converges to pstar then so does Tstep p z.
oneStepInvariant :
  âˆ€ {N} (p : Params N) (z pstar : VecC N) â†’
  InBasin p z pstar â†’ InBasin p (iterate p 1 z) pstar
oneStepInvariant p z pstar conv Îµ Îµpos =
  let N0 , prop = conv Îµ Îµpos
  in N0 , Î» n ge â†’ prop (suc n) (suc-ge ge)
  where
  suc-ge : âˆ€ {n m} â†’ n â‰¥ m â†’ suc n â‰¥ suc m
  suc-ge = Data.Nat.sâ‰¤s
  open import Data.Nat using (_â‰¥_; sâ‰¤s)
  open import Data.Product using (_,_)

fixedPointInvariant :
  âˆ€ {N} (p : Params N) (pstar : VecC N) â†’
  IsFixedPoint p pstar â†’ iterate p 1 pstar â‰¡ pstar
fixedPointInvariant p pstar isfp = isfp
