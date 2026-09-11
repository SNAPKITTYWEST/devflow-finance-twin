theory Quantum_Jump_Update
imports Lindblad_GKSL
begin

section \<open>Quantum jump (measurement) update and normalization\<close>

definition jump_map :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "jump_map L \<rho> = (\<lambda>i j. (\<Sum>k l. L i k * \<rho> k l * cnj (L j l)))"

definition jump_update :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "jump_update L \<rho> = (let num = jump_map L \<rho>;
                          denom = trace (dagger L \<circ>\<^sub>m L \<circ>\<^sub>m \<rho>)
                       in if denom = 0 then num else (\<lambda>i j. num i j / denom))"

lemma jump_preserves_hermitian:
  assumes "hermitian \<rho>"
  shows "hermitian (jump_map L \<rho>)"
proof -
  have "dagger (jump_map L \<rho>) = jump_map L \<rho>"
    unfolding jump_map_def dagger_def by (simp add: algebra_simps assms hermitian_def)
  thus ?thesis by (simp add: hermitian_def)
qed

lemma jump_preserves_pos_semidef:
  assumes "pos_semidef \<rho>"
  shows "pos_semidef (jump_map L \<rho>)"
proof -
  have "\<forall>v. (\<Sum>i j. cnj (v i) * (jump_map L \<rho>) i j * v j) = (\<Sum>i j. cnj ((dagger L \<circ>\<^sub>m v) i) * \<rho> i j * (dagger L \<circ>\<^sub>m v) j)"
    unfolding jump_map_def by (simp add: algebra_simps)
  moreover from assms have "(\<Sum>i j. cnj ((dagger L \<circ>\<^sub>m v) i) * \<rho> i j * (dagger L \<circ>\<^sub>m v) j) \<in> {x. Re x \<ge> 0}"
    using pos_semidef_def by auto
  ultimately show ?thesis
    unfolding pos_semidef_def by auto
qed

lemma jump_update_normalized:
  assumes "density \<rho>" and "trace (dagger L \<circ>\<^sub>m L \<circ>\<^sub>m \<rho>) \<noteq> 0"
  shows "trace (jump_update L \<rho>) = 1"
proof -
  have "trace (jump_map L \<rho>) = trace ((dagger L \<circ>\<^sub>m L) \<circ>\<^sub>m \<rho>)"
    unfolding jump_map_def trace_def dagger_def by (simp add: algebra_simps)
  then have "trace (jump_update L \<rho>) = trace (jump_map L \<rho>) / trace (dagger L \<circ>\<^sub>m L \<circ>\<^sub>m \<rho>)"
    unfolding jump_update_def by simp
  thus ?thesis using \<open>trace (jump_map L \<rho>) = trace (dagger L \<circ>\<^sub>m L \<circ>\<^sub>m \<rho>)\<close> by simp
qed

lemma jump_update_density:
  assumes "density \<rho>" and "trace (dagger L \<circ>\<^sub>m L \<circ>\<^sub>m \<rho>) \<noteq> 0"
  shows "density (jump_update L \<rho>)"
proof -
  have "hermitian (jump_update L \<rho>)"
    using jump_preserves_hermitian unfolding jump_update_def by (simp add: hermitian_def)
  moreover have "pos_semidef (jump_update L \<rho>)"
    using jump_preserves_pos_semidef unfolding jump_update_def pos_semidef_def by (simp add: pos_semidef_def)
  moreover have "trace (jump_update L \<rho>) = 1"
    using jump_update_normalized assms by simp
  ultimately show ?thesis
    unfolding density_def by simp
qed

end
