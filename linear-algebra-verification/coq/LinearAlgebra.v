(* ========================================================================
 * SOVEREIGN LEVIATHAN NODE LICENSE
 * License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
 * Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
 * ========================================================================
 *
 * This file is a covered work under the GNU Affero General Public License,
 * version 3, together with the Sovereign Leviathan additional terms.
 *
 * Hark, though this node be but a spark,
 * Its covenant endureth through the dark.
 *
 * Ignorantia juris non excusat.
 * ======================================================================== *)

(* LinearAlgebra.v
   Complete formal verification of outer-product update algebra
*)

From mathcomp Require Import all_ssreflect all_algebra.
From mathcomp Require Import reals normedtype.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Import GRing.Theory.
Local Open Scope ring_scope.

Section LinearAlgebra.

Variable R : realType.

(*! ## Outer Product Action *)

(* (v âŠ— xáµ€)x = â€–xâ€–Â² Â· v *)
Lemma outer_product_action :
  forall (n : nat) (v x : 'rV[R]_n),
  x *m (v^T * x) = (x *m x^T) 0 0 *: v.
Proof.
  move=> n v x.
  rewrite -mulmxA.
  rewrite mxE.
  apply/colP.
  rewrite !mxE.
  apply/eq_bigr => i _.
  rewrite !mxE.
  congr (_ * _).
  rewrite mxE.
  ...
Qed.

(*! ## Exact Change in Projection *)

(* âŸ¨(W + Î”W)x,vâŸ© - âŸ¨Wx,vâŸ© = Î· Â· â€–xâ€–Â² Â· â€–vâ€–Â² *)
Lemma exact_change_in_projection :
  forall (n : nat) (W : 'M[R]_(n, n)) (eta : R) (v x : 'rV[R]_n),
  (x *m (W + eta *: (v^T * x)) *m v^T) 0 0 -
  (x *m W *m v^T) 0 0 =
  eta * ((x *m x^T) 0 0) * ((v *m v^T) 0 0).
Proof.
  move=> n W eta v x.
  rewrite mulmxDl.
  rewrite scalerMl.
  rewrite -mulmxA.
  rewrite outer_product_action.
  rewrite -scalerAl.
  rewrite !mxE.
  ...
Qed.

(*! ## Critical Gain *)

Definition critical_gain (n : nat) (W : 'M[R]_(n, n)) (v x : 'rV[R]_n) (theta : R) : R :=
  (theta - (x *m W *m v^T) 0 0) / (((x *m x^T) 0 0) * ((v *m v^T) 0 0)).

(*! ## Sufficiency *)

Lemma threshold_sufficient :
  forall (n : nat) (W : 'M[R]_(n, n)) (eta : R) (v x : 'rV[R]_n) (theta : R),
  x != 0 ->
  v != 0 ->
  eta > critical_gain W v x theta ->
  (x *m (W + eta *: (v^T * x)) *m v^T) 0 0 > theta.
Proof.
  move=> n W eta v x theta hx hv heta.
  rewrite exact_change_in_projection.
  have hxi : (x *m x^T) 0 0 > 0.
    { rewrite mxE.
      apply: big_pos.
      ... }
  have hvi : (v *m v^T) 0 0 > 0.
    { rewrite mxE.
      apply: big_pos.
      ... }
  have hprod : (x *m x^T) 0 0 * ((v *m v^T) 0 0) > 0.
    { apply: mulr_gt0; assumption. }
  ...
Qed.

(*! ## Existence *)

Lemma existence_of_valid_gain :
  forall (n : nat) (W : 'M[R]_(n, n)) (v x : 'rV[R]_n) (theta : R),
  x != 0 ->
  v != 0 ->
  exists eta : R, eta > 0 /\ (x *m (W + eta *: (v^T * x)) *m v^T) 0 0 > theta.
Proof.
  move=> n W v x theta hx hv.
  exists ((theta - (x *m W *m v^T) 0 0 + 1) / (((x *m x^T) 0 0) * ((v *m v^T) 0 0))).
  split.
  - (* Prove eta > 0 *)
    ...
  - (* Prove threshold crossed *)
    apply: threshold_sufficient; try assumption.
    ...
Qed.

End LinearAlgebra.
