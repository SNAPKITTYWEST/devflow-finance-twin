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

-- TokenModel.agda
-- Core definitions for formal verification of linear-algebraic transformation protocol
--
-- This file defines:
-- - Finite-dimensional real vector spaces
-- - Linear operators (matrices)
-- - Outer products
-- - Update operators
-- - Activation functions
-- - Threshold predicates

module TokenModel where

open import Data.Nat using (â„•; zero; suc; _+_; _*_)
open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _âˆ·_; mapâ‚‚; replicate)
open import Data.Real using (â„; _+_; _*_; _-_; _>_; _â‰¤_; 0â„; 1â„)
open import Data.Real.Properties using (+-comm; *-comm; *-assoc)
open import Relation.Binary.PropositionalEquality using (_â‰¡_; refl; sym; trans; cong)

--! ## Vector Space Definitions

--! A finite-dimensional real vector space
Vector : â„• â†’ Set
Vector n = Vec â„ n

--! Inner product
innerProduct : âˆ€ {n} â†’ Vector n â†’ Vector n â†’ â„
innerProduct [] [] = 0â„
innerProduct (x âˆ· xs) (y âˆ· ys) = (x * y) + innerProduct xs ys

--! Norm squared
normSq : âˆ€ {n} â†’ Vector n â†’ â„
normSq v = innerProduct v v

--! ## Outer Product

--! Outer product of two vectors
outerProduct : âˆ€ {n} â†’ Vector n â†’ Vector n â†’ Vec (Vector n) n
outerProduct [] ys = []
outerProduct (x âˆ· xs) ys = mapâ‚‚ (Î» xi xj â†’ xi * xj) (replicate x) ys âˆ· outerProduct xs ys

--! ## Update Operator

--! Update operator: Î”W = Î· Â· (v âŠ— xáµ€)
updateOperator : âˆ€ {n} â†’ â„ â†’ Vector n â†’ Vector n â†’ Vec (Vector n) n
updateOperator Î· v x = mapâ‚‚ (Î» row vi â†’ vi * Î·) (outerProduct v x) v

--! ## Activation

--! Matrix-vector multiplication
matVecMul : âˆ€ {n} â†’ Vec (Vector n) n â†’ Vector n â†’ Vector n
matVecMul [] [] = []
matVecMul (row âˆ· rows) (x âˆ· xs) = innerProduct row (x âˆ· xs) âˆ· matVecMul rows xs

--! Activation of input x under operator W
activation : âˆ€ {n} â†’ Vec (Vector n) n â†’ Vector n â†’ Vector n
activation W x = matVecMul W x

--! Updated activation
updatedActivation : âˆ€ {n} â†’ Vec (Vector n) n â†’ â„ â†’ Vector n â†’ Vector n â†’ Vector n
updatedActivation W Î· v x = matVecMul (mapâ‚‚ (mapâ‚‚ _+_) W (updateOperator Î· v x)) x

--! ## Threshold Predicate

--! Threshold predicate: ThoughtFires(y, v, Î¸) âŸº âŸ¨y, vâŸ© > Î¸
thoughtFires : âˆ€ {n} â†’ Vector n â†’ Vector n â†’ â„ â†’ Set
thoughtFires y v Î¸ = innerProduct y v > Î¸

--! ## Core Theorems

--! AX-001: Outer product action
--! (v âŠ— xáµ€)x = â€–xâ€–Â² Â· v
postulate
  outerProductAction : âˆ€ {n} (v x : Vector n) â†’
    matVecMul (outerProduct v x) x â‰¡ mapâ‚‚ _*_ (replicate (normSq x)) v

--! AX-002: Update action
--! Î”W Â· x = Î· Â· â€–xâ€–Â² Â· v
postulate
  updateAction : âˆ€ {n} (Î· : â„) (v x : Vector n) â†’
    matVecMul (updateOperator Î· v x) x â‰¡ mapâ‚‚ _*_ (replicate (Î· * normSq x)) v

--! ALG-001: Linearity of updated activation
--! (W + Î”W)x = Wx + Î”Wx
postulate
  linearityOfUpdatedActivation : âˆ€ {n} (W : Vec (Vector n) n) (Î· : â„) (v x : Vector n) â†’
    updatedActivation W Î· v x â‰¡ mapâ‚‚ _+_ (activation W x) (matVecMul (updateOperator Î· v x) x

--! ALG-002: Projection expansion
--! âŸ¨(W + Î”W)x, vâŸ© = âŸ¨Wx, vâŸ© + âŸ¨Î”Wx, vâŸ©
postulate
  projectionExpansion : âˆ€ {n} (W : Vec (Vector n) n) (Î· : â„) (v x : Vector n) â†’
    innerProduct (updatedActivation W Î· v x) v â‰¡
    innerProduct (activation W x) v + innerProduct (matVecMul (updateOperator Î· v x) x) v

--! ALG-003: Exact change in projection
--! âŸ¨(W + Î”W)x, vâŸ© - âŸ¨Wx, vâŸ© = Î· Â· â€–xâ€–Â² Â· â€–vâ€–Â²
postulate
  exactChangeInProjection : âˆ€ {n} (W : Vec (Vector n) n) (Î· : â„) (v x : Vector n) â†’
    innerProduct (updatedActivation W Î· v x) v - innerProduct (activation W x) v â‰¡
    Î· * normSq x * normSq v

--! THR-001: Sufficient condition for threshold crossing
postulate
  thresholdSufficientCondition : âˆ€ {n} {W : Vec (Vector n) n} {Î· Î¸ : â„} {v x : Vector n} â†’
    normSq x > 0â„ â†’
    normSq v > 0â„ â†’
    Î· > (Î¸ - innerProduct (activation W x) v) / (normSq x * normSq v) â†’
    thoughtFires (updatedActivation W Î· v x) v Î¸
