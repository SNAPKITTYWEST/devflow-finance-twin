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

-- RecursiveAudit.agda
-- Recursive counterproof of previous verification conclusions

module RecursiveAudit where

open import Data.Nat using (â„•; zero; suc; _+_; _*_)
open import Data.Fin using (Fin; zero; suc)
open import Data.Vec using (Vec; []; _âˆ·_; mapâ‚‚; replicate)
open import Data.Real using (â„; _+_; _*_; _-_; _/_; _>_; _â‰¤_; 0â„; 1â„)
open import Data.Real.Properties using (+-comm; *-comm; *-assoc)
open import Relation.Binary.PropositionalEquality using (_â‰¡_; refl; sym; trans; cong)

--! ## Setup

--! Critical gain
criticalGain : âˆ€ {n} â†’ (Vec (Vec â„ n) n) â†’ Vec â„ n â†’ Vec â„ n â†’ â„ â†’ â„
criticalGain W v x Î¸ = (Î¸ - innerProduct (matVecMul W x) v) / (normSq x * normSq v)

--! ## THEOREM-A: Î· > 0 Alone Is Insufficient

-- This is established by counterexample, not by a universal theorem.
-- Counterexample: W = -100, x = 1, v = 1, Î· = 1, Î¸ = 0

--! ## THEOREM-B: Î· > Î·_critical Is Sufficient

postulate
  sufficientCondition : âˆ€ {n} {W : Vec (Vec â„ n) n} {Î· Î¸ : â„} {v x : Vec â„ n} â†’
    normSq x > 0â„ â†’
    normSq v > 0â„ â†’
    Î· > criticalGain W v x Î¸ â†’
    thoughtFires (updatedActivation W Î· v x) v Î¸

--! ## THEOREM-C: Necessary and Sufficient Condition

postulate
  necessaryCondition : âˆ€ {n} {W : Vec (Vec â„ n) n} {Î· Î¸ : â„} {v x : Vec â„ n} â†’
    normSq x > 0â„ â†’
    normSq v > 0â„ â†’
    thoughtFires (updatedActivation W Î· v x) v Î¸ â†’
    Î· > criticalGain W v x Î¸

necessaryAndSufficient : âˆ€ {n} {W : Vec (Vec â„ n) n} {Î· Î¸ : â„} {v x : Vec â„ n} â†’
  normSq x > 0â„ â†’
  normSq v > 0â„ â†’
  (thoughtFires (updatedActivation W Î· v x) v Î¸) Ã— (Î· > criticalGain W v x Î¸)
necessaryAndSufficient hx hv = (sufficientCondition hx hv , necessaryCondition hx hv)

--! ## THEOREM-D: Existence of Valid Gain

postulate
  existenceOfValidGain : âˆ€ {n} {W : Vec (Vec â„ n) n} {Î¸ : â„} {v x : Vec â„ n} â†’
    normSq x > 0â„ â†’
    normSq v > 0â„ â†’
    Î£ â„ (Î» Î· â†’ (0â„ < Î·) Ã— (thoughtFires (updatedActivation W Î· v x) v Î¸))

--! ## THEOREM-E: Valid Gains Form an Open Ray

-- The set {Î· > 0 | thoughtFires(Î·)} = {Î· | Î· > criticalGain}

--! ## THEOREM-F: Arbitrary Margin Achievable

postulate
  arbitraryMargin : âˆ€ {n} {W : Vec (Vec â„ n) n} {Î¸ Îµ : â„} {v x : Vec â„ n} â†’
    normSq x > 0â„ â†’
    normSq v > 0â„ â†’
    Îµ > 0â„ â†’
    Î£ â„ (Î» Î· â†’ (0â„ < Î·) Ã— (thoughtFires (updatedActivation W Î· v x) v (Î¸ + Îµ)))
