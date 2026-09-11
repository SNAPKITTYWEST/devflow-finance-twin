{-# OPTIONS --without-K --safe #-}

module SymbolOscillatorInvariant where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Fin using (Fin; toℕ)
open import Data.Vec using (Vec; []; _∷_; tabulate; map; zipWith)
open import Data.Product using (_×_; _,_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import Function using (_∘_)
open import Data.Rational using (ℚ; _+_; _*_; _-_; _/_ ; fromℕ; ∣_∣)
open import Data.Unit using (⊤; tt)

-- Simple complex numbers as pairs of rationals
Complex : Set
Complex = ℚ × ℚ

_+c_ : Complex → Complex → Complex
(x₁ , y₁) +c (x₂ , y₂) = (x₁ + x₂ , y₁ + y₂)

_-c_ : Complex → Complex → Complex
(x₁ , y₁) -c (x₂ , y₂) = (x₁ - x₂ , y₁ - y₂)

_*c_ : Complex → Complex → Complex
(x₁ , y₁) *c (x₂ , y₂) = (x₁ * x₂ - y₁ * y₂ , x₁ * y₂ + y₁ * x₂)

scalec : ℚ → Complex → Complex
scalec a (x , y) = (a * x , a * y)

zeroC : Complex
zeroC = (0ℚ , 0ℚ)

sqMag : Complex → ℚ
sqMag (x , y) = x * x + y * y

VecC : ℕ → Set
VecC N = Vec Complex N

Matrix : ℕ → Set
Matrix N = Vec (Vec ℚ N) N

record Params (N : ℕ) : Set where
  field
    α  : ℚ
    Δt : ℚ
    K  : Matrix N
    F  : Vec ℚ N

open Params

vadd : ∀ {N} → VecC N → VecC N → VecC N
vadd {zero}  []        []        = []
vadd {suc n} (x ∷ xs) (y ∷ ys)  = (x +c y) ∷ vadd xs ys

dotRow : ∀ {N} → Vec ℚ N → VecC N → Complex
dotRow {zero}  []       []       = zeroC
dotRow {suc n} (k ∷ ks) (z ∷ zs) = scalec k z +c dotRow ks zs

matVec : ∀ {N} → Matrix N → VecC N → VecC N
matVec {zero}  []       []  = []
matVec {suc n} (r ∷ rs) z   = dotRow r z ∷ matVec rs z

nonlinearTerm : ℚ → Complex → Complex
nonlinearTerm α z = scalec (α - sqMag z) z

index : ∀ {N} → VecC N → Fin N → Complex
index {suc _} (x ∷ _ )  Fin.zero     = x
index {suc n} (_ ∷ xs) (Fin.suc i)   = index xs i

indexF : ∀ {N} → Vec ℚ N → Fin N → ℚ
indexF {suc _} (x ∷ _ )  Fin.zero    = x
indexF {suc n} (_ ∷ xs) (Fin.suc i)  = indexF xs i

iterate : ∀ {N} → Params N → ℕ → VecC N → VecC N
iterate p zero    z = z
iterate p (suc n) z = iterate p n (Tstep p z)
  where
  Tstep : ∀ {N} → Params N → VecC N → VecC N
  Tstep p z =
    let coupling = matVec (K p) z
        go : Fin _ → Complex
        go i =
          let zi   = index z i
              nonl = nonlinearTerm (α p) zi
              coup = index coupling i
              fi   = indexF (F p) i
          in  zi +c scalec (Δt p) (nonl +c (coup -c zi) +c (scalec fi (1ℚ , 0ℚ)))
    in tabulate go

VecDist : ∀ {N} → VecC N → VecC N → ℚ
VecDist {zero}  []        []        = 0ℚ
VecDist {suc n} (x ∷ xs) (y ∷ ys)  =
  ∣ proj₁ x - proj₁ y ∣ + ∣ proj₂ x - proj₂ y ∣ + VecDist xs ys
  where open import Data.Product using (proj₁; proj₂)

ConvergesTo : ∀ {N} → (ℕ → VecC N) → VecC N → Set
ConvergesTo seq limit =
  ∀ ε → ε > 0ℚ → ∃ λ N0 → ∀ n → n ≥ N0 → VecDist (seq n) limit < ε
  where open import Data.Rational using (_>_; _<_)
        open import Data.Nat using (_≥_)
        open import Data.Product using (∃)

IsFixedPoint : ∀ {N} → Params N → VecC N → Set
IsFixedPoint p x = Tstep p x ≡ x
  where
  Tstep : ∀ {N} → Params N → VecC N → VecC N
  Tstep p z =
    let coupling = matVec (K p) z
        go : Fin _ → Complex
        go i =
          let zi   = index z i
              nonl = nonlinearTerm (α p) zi
              coup = index coupling i
              fi   = indexF (F p) i
          in  zi +c scalec (Δt p) (nonl +c (coup -c zi) +c (scalec fi (1ℚ , 0ℚ)))
    in tabulate go

InBasin : ∀ {N} → Params N → VecC N → VecC N → Set
InBasin p z pstar = ConvergesTo (λ n → iterate p n z) pstar

-- One-step invariance: if z converges to pstar then so does Tstep p z.
oneStepInvariant :
  ∀ {N} (p : Params N) (z pstar : VecC N) →
  InBasin p z pstar → InBasin p (iterate p 1 z) pstar
oneStepInvariant p z pstar conv ε εpos =
  let N0 , prop = conv ε εpos
  in N0 , λ n ge → prop (suc n) (suc-ge ge)
  where
  suc-ge : ∀ {n m} → n ≥ m → suc n ≥ suc m
  suc-ge = Data.Nat.s≤s
  open import Data.Nat using (_≥_; s≤s)
  open import Data.Product using (_,_)

fixedPointInvariant :
  ∀ {N} (p : Params N) (pstar : VecC N) →
  IsFixedPoint p pstar → iterate p 1 pstar ≡ pstar
fixedPointInvariant p pstar isfp = isfp
