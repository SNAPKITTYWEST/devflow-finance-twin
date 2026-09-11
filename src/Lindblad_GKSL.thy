theory Lindblad_GKSL
imports Density_Matrix
begin

section \<open>Lindblad (GKSL) generator and basic invariants\<close>

definition comm :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "comm A B = (\<lambda>i j. (\<Sum>k. A i k * B k j - B i k * A k j))"

definition anti_comm :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "anti_comm A B = (\<lambda>i j. (\<Sum>k. A i k * B k j + B i k * A k j))"

definition lindblad_term :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "lindblad_term L \<rho> = (\<lambda>i j. (\<Sum>k l. L i k * \<rho> k l * cnj (L j l)))"

definition dissipator :: "('n) cmat list \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "dissipator Ls \<rho> = (\<Sum>L\<in>set Ls. lindblad_term L \<rho> - (1/2) * ((\<lambda>i j. (\<Sum>k. cnj (L k i) * L k j) * \<rho> i j) + (\<lambda>i j. \<rho> i j * (\<Sum>k. cnj (L k i) * L k j))))"

definition lindblad_generator :: "('n) cmat \<Rightarrow> ('n) cmat list \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "lindblad_generator H Ls \<rho> = (\<lambda>i j. (-Complex.I) * (comm H \<rho>) i j + (dissipator Ls \<rho>) i j)"

lemma trace_dissipator_zero:
  assumes "finite (set Ls)"
  shows "trace (dissipator Ls \<rho>) = 0"
proof -
  have "trace (lindblad_term L \<rho>) = trace ((dagger L) \<circ>\<^sub>m L \<circ>\<^sub>m \<rho>)"
    unfolding lindblad_term_def trace_def dagger_def
    by (simp add: algebra_simps)
  hence "trace (lindblad_term L \<rho>) = trace ((dagger L \<circ>\<^sub>m L) \<circ>\<^sub>m \<rho>)" by simp
  moreover have "trace ((\<lambda>i j. (\<Sum>k. cnj (L k i) * L k j) * \<rho> i j)) = trace ((dagger L \<circ>\<^sub>m L) \<circ>\<^sub>m \<rho>)"
    by (simp add: trace_def)
  ultimately have "trace (lindblad_term L \<rho> - (1/2) * ((\<lambda>i j. (\<Sum>k. cnj (L k i) * L k j) * \<rho> i j) + (\<lambda>i j. \<rho> i j * (\<Sum>k. cnj (L k i) * L k j)))) = 0"
    by (simp add: algebra_simps)
  then show ?thesis
    by (simp add: dissipator_def)
qed

lemma trace_lindblad_generator_zero:
  "trace (lindblad_generator H Ls \<rho>) = 0"
proof -
  have "trace ((\<lambda>i j. (-Complex.I) * (comm H \<rho>) i j)) = (-Complex.I) * trace (comm H \<rho>)"
    by (simp add: trace_def)
  moreover have "trace (comm H \<rho>) = 0"
    unfolding comm_def trace_def by (simp add: algebra_simps)
  ultimately show ?thesis
    using trace_dissipator_zero by (simp add: lindblad_generator_def)
qed

end
