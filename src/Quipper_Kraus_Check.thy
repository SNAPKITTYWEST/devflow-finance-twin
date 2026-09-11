theory Quipper_Kraus_Check
imports Complex_Main "HOL-Algebra.Matrix" kraus_defs
begin

section \<open>Kraus operators for controlled-Ry weak measurement\<close>

text \<open>
  We formalize the Kraus operators for the simple controlled-Ry(\<theta>) weak
  measurement on an ancilla initialized in |0>. The Kraus operators on the
  system (2-dimensional) are diagonal:

    K0 = diag(1, cos(\<theta>/2))
    K1 = diag(0, sin(\<theta>/2))

  We prove these form a CPTP map (completeness and PSD) and compute the
  ancilla outcome probability and the effect on diagonal density matrices.
\<close>

subsection \<open>Auxiliary definitions\<close>

definition cos_half :: "real \<Rightarrow> real" where
  "cos_half \<theta> = cos (\<theta> / 2)"

definition sin_half :: "real \<Rightarrow> real" where
  "sin_half \<theta> = sin (\<theta> / 2)"

definition diag_rho :: "real \<Rightarrow> complex matrix" where
  "diag_rho p = mat 2 2 (\<lambda>(i,j). (if i = 0 \<and> j = 0 then of_real (1 - p)
                                 else if i = 1 \<and> j = 1 then of_real p else 0))"

subsection \<open>Completeness: sum K_m^\<dagger> K_m = I\<close>

lemma K0dagK0:
  "conjugate_transpose (K0 \<theta>) * K0 \<theta> = mat 2 2 (\<lambda>(i,j).
     (if i = 0 \<and> j = 0 then 1
      else if i = 1 \<and> j = 1 then of_real ((cos_half \<theta>) ^ 2)
      else 0))"
  by (simp add: K0_def mat_mult_def conj_transpose_def cos_half_def)

lemma K1dagK1:
  "conjugate_transpose (K1 \<theta>) * K1 \<theta> = mat 2 2 (\<lambda>(i,j).
     (if i = 1 \<and> j = 1 then of_real ((sin_half \<theta>) ^ 2) else 0))"
  by (simp add: K1_def mat_mult_def conj_transpose_def sin_half_def)

theorem kraus_completeness:
  "conjugate_transpose (K0 \<theta>) * K0 \<theta> + conjugate_transpose (K1 \<theta>) * K1 \<theta> = mat 2 2 (\<lambda>(i,j). if i = j then 1 else 0)"
proof -
  have A: "conjugate_transpose (K0 \<theta>) * K0 \<theta> + conjugate_transpose (K1 \<theta>) * K1 \<theta> =
            mat 2 2 (\<lambda>(i,j).
              (if i = 0 \<and> j = 0 then 1
               else if i = 1 \<and> j = 1 then of_real ((cos_half \<theta>) ^ 2 + (sin_half \<theta>) ^ 2)
               else 0))"
    using K0dagK0 K1dagK1 by (simp add: mat_add_def)
  moreover have "of_real ((cos_half \<theta>) ^ 2 + (sin_half \<theta>) ^ 2) = 1"
    by (simp add: cos_half_def sin_half_def sin_cos_squared)
  ultimately show ?thesis
    by (simp add: mat_eq_iff)
qed

subsection \<open>Positive semidefiniteness\<close>

lemma K0_pos_semidef:
  "pos_semidef (conjugate_transpose (K0 \<theta>) * K0 \<theta>)"
proof -
  have "conjugate_transpose (K0 \<theta>) * K0 \<theta> = mat 2 2 (\<lambda>(i,j).
     (if i = 0 \<and> j = 0 then 1 else if i = 1 \<and> j = 1 then of_real ((cos_half \<theta>) ^ 2) else 0))"
    using K0dagK0 by simp
  then show ?thesis
    by (simp add: pos_semidef_diag)
qed

lemma K1_pos_semidef:
  "pos_semidef (conjugate_transpose (K1 \<theta>) * K1 \<theta>)"
proof -
  have "conjugate_transpose (K1 \<theta>) * K1 \<theta> = mat 2 2 (\<lambda>(i,j).
     (if i = 1 \<and> j = 1 then of_real ((sin_half \<theta>) ^ 2) else 0))"
    using K1dagK1 by simp
  then show ?thesis
    by (simp add: pos_semidef_diag)
qed

subsection \<open>Effect on diagonal density matrices and ancilla outcome probability\<close>

lemma ancilla_prob_m:
  fixes p :: real and \<theta> :: real
  assumes "0 \<le> p" "p \<le> 1"
  shows "trace ((conjugate_transpose (K1 \<theta>) * K1 \<theta>) * diag_rho p) = of_real (p * (sin_half \<theta>) ^ 2)"
proof -
  have "conjugate_transpose (K1 \<theta>) * K1 \<theta> = mat 2 2 (\<lambda>(i,j). (if i = 1 \<and> j = 1 then of_real ((sin_half \<theta>) ^ 2) else 0))"
    using K1dagK1 by simp
  then have "((conjugate_transpose (K1 \<theta>) * K1 \<theta>) * diag_rho p) = mat 2 2 (\<lambda>(i,j).
       (if i = 1 \<and> j = 1 then of_real (p * (sin_half \<theta>) ^ 2) else 0))"
    by (simp add: diag_rho_def mat_mult_def)
  thus ?thesis by (simp add: trace_def)
qed

lemma channel_preserves_population:
  fixes p :: real and \<theta> :: real
  assumes "0 \<le> p" "p \<le> 1"
  shows "let rho = diag_rho p in
         let rho_out = (K0 \<theta>) * rho * (conjugate_transpose (K0 \<theta>)) + (K1 \<theta>) * rho * (conjugate_transpose (K1 \<theta>)) in
         (rho_out $ 1 $ 1) = of_real p"
proof -
  have K0diag: "K0 \<theta> = mat 2 2 (\<lambda>(i,j). (if i = 0 \<and> j = 0 then 1 else if i = 1 \<and> j = 1 then of_real (cos_half \<theta>) else 0))"
    using K0_def by simp
  have K1diag: "K1 \<theta> = mat 2 2 (\<lambda>(i,j). (if i = 1 \<and> j = 1 then of_real (sin_half \<theta>) else 0))"
    using K1_def by simp
  then show ?thesis
    by (simp add: diag_rho_def mat_mult_def K0diag K1diag)
qed

text \<open>
  The ancilla outcome probability for |1> is m = p * sin^2(\<theta>/2).
  A classical controller that receives ancilla samples and applies EMA
  with step \<eta> updates p \<leftarrow> p + \<eta> (m - p).
\<close>

end
