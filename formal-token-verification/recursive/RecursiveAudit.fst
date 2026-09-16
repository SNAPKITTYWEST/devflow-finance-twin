(* RecursiveAudit.fst
   Recursive counterproof of previous verification conclusions
*)

module RecursiveAudit

open FStar.Real
open FStar.Mul

(*! ## Core Identity: ALG-003 *)

val exact_change_in_projection:
  #n:nat ->
  W:vector n * vector n ->
  eta:real ->
  v:vector n ->
  x:vector n ->
  Lemma (requires (True))
  (ensures (innerProduct (updatedActivation W eta v x) v -.
            innerProduct (activation W x) v ==
            eta *. normSq x *. normSq v))

let exact_change_in_projection W eta v x = admit()

(*! ## Critical Gain *)

let criticalGain (#n:nat) (W: vector n * vector n) (v x: vector n) (theta: real) : Tot real =
  (theta -. innerProduct (activation W x) v) /. (normSq x *. normSq v)

(*! ## THEOREM-B: η > η_critical Is Sufficient *)

val sufficient_condition:
  #n:nat ->
  W:vector n * vector n ->
  eta:real ->
  v:vector n ->
  x:vector n ->
  theta:real ->
  Lemma (requires (normSq x >. 0.0 /\
                   normSq v >. 0.0 /\
                   eta >. criticalGain W v x theta))
  (ensures (thoughtFires (updatedActivation W eta v x) v theta == true))

let sufficient_condition W eta v x theta = admit()

(*! ## THEOREM-C: Necessary and Sufficient Condition *)

val necessary_condition:
  #n:nat ->
  W:vector n * vector n ->
  eta:real ->
  v:vector n ->
  x:vector n ->
  theta:real ->
  Lemma (requires (normSq x >. 0.0 /\
                   normSq v >. 0.0 /\
                   thoughtFires (updatedActivation W eta v x) v theta == true))
  (ensures (eta >. criticalGain W v x theta))

let necessary_condition W eta v x theta = admit()

(*! ## THEOREM-D: Existence of Valid Gain *)

val existence_of_valid_gain:
  #n:nat ->
  W:vector n * vector n ->
  v:vector n ->
  x:vector n ->
  theta:real ->
  Lemma (requires (normSq x >. 0.0 /\
                   normSq v >. 0.0))
  (ensures (exists (eta:real). eta >. 0.0 /\ thoughtFires (updatedActivation W eta v x) v theta == true))

let existence_of_valid_gain W v x theta = admit()

(*! ## THEOREM-E: Valid Gains Form an Open Ray *)

(* The set {η > 0 | threshold crosses} = {η | η > criticalGain} *)

(*! ## THEOREM-F: Arbitrary Margin Achievable *)

val arbitrary_margin:
  #n:nat ->
  W:vector n * vector n ->
  v:vector n ->
  x:vector n ->
  theta:real ->
  epsilon:real ->
  Lemma (requires (normSq x >. 0.0 /\
                   normSq v >. 0.0 /\
                   epsilon >. 0.0))
  (ensures (exists (eta:real). eta >. 0.0 /\ thoughtFires (updatedActivation W eta v x) v (theta +. epsilon) == true))

let arbitrary_margin W v x theta epsilon = admit()
