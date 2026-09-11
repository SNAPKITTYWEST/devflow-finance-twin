theory Jungian_Prob_Dynamics
imports Complex_Main
begin

section \<open>Probabilistic/time-dependent Jungian dynamics\<close>

typedecl Agent
typedecl Archetype
type_synonym time = nat

consts p :: "Agent \<Rightarrow> Archetype \<Rightarrow> time \<Rightarrow> real"
consts m :: "Agent \<Rightarrow> Archetype \<Rightarrow> time \<Rightarrow> real"

consts eta :: real
axiomatization where eta_pos: "0 < eta" and eta_lt1: "eta < 1"

axiomatization where
  p_bounds: "\<forall>A \<alpha> t. 0 \<le> p A \<alpha> t \<and> p A \<alpha> t \<le> 1"
  and m_bounds: "\<forall>A \<alpha> t. 0 \<le> m A \<alpha> t \<and> m A \<alpha> t \<le> 1"

axiomatization where
  update_rule: "\<forall>A \<alpha> t. p A \<alpha> (Suc t) = p A \<alpha> t + eta * (m A \<alpha> t - p A \<alpha> t)"

lemma update_convex:
  assumes "0 \<le> p A \<alpha> t" "p A \<alpha> t \<le> 1" "0 \<le> m A \<alpha> t" "m A \<alpha> t \<le> 1"
  shows "0 \<le> p A \<alpha> (Suc t) \<and> p A \<alpha> (Suc t) \<le> 1"
  using assms update_rule eta_pos eta_lt1
  by (simp add: algebra_simps) (auto)

lemma monotone_if_evidence_ge:
  assumes "m A \<alpha> t \<ge> p A \<alpha> t"
  shows "p A \<alpha> (Suc t) \<ge> p A \<alpha> t"
  using assms update_rule eta_pos by (simp add: algebra_simps)

lemma monotone_if_evidence_le:
  assumes "m A \<alpha> t \<le> p A \<alpha> t"
  shows "p A \<alpha> (Suc t) \<le> p A \<alpha> t"
  using assms update_rule eta_pos by (simp add: algebra_simps)

definition const_evidence :: "Agent \<Rightarrow> Archetype \<Rightarrow> real \<Rightarrow> bool" where
  "const_evidence A \<alpha> mstar \<longleftrightarrow> (\<forall>t. m A \<alpha> t = mstar)"

lemma closed_form:
  assumes "const_evidence A \<alpha> mstar"
  shows "p A \<alpha> n = (1 - eta) ^ n * p A \<alpha> 0 + (1 - (1 - eta) ^ n) * mstar"
proof (induction n)
  case 0 then show ?case by simp
next
  case (Suc n)
  have "p A \<alpha> (Suc n) = p A \<alpha> n + eta * (m A \<alpha> n - p A \<alpha> n)" using update_rule by simp
  also have "\<dots> = (1 - eta) * p A \<alpha> n + eta * mstar" using assms const_evidence_def by simp
  also have "\<dots> = (1 - eta) * ((1 - eta) ^ n * p A \<alpha> 0 + (1 - (1 - eta) ^ n) * mstar) + eta * mstar"
    using Suc.IH by simp
  also have "\<dots> = (1 - eta) ^ (Suc n) * p A \<alpha> 0 + (1 - (1 - eta) ^ (Suc n)) * mstar"
    by (simp add: algebra_simps)
  finally show ?case .
qed

theorem convergence_constant_evidence:
  assumes "const_evidence A \<alpha> mstar"
  shows "(\<lambda>n. p A \<alpha> n) \<longlonglongrightarrow> mstar"
proof -
  have "p A \<alpha> n = (1 - eta) ^ n * p A \<alpha> 0 + (1 - (1 - eta) ^ n) * mstar" using closed_form[OF assms] .
  moreover have "(1 - eta) ^ n \<longlonglongrightarrow> 0"
    using eta_pos eta_lt1 by (simp add: tendsto_pow_zero)
  ultimately have "p A \<alpha> n \<longlonglongrightarrow> mstar"
    by (simp add: tendsto_add tendsto_mult_const tendsto_const)
  thus ?thesis .
qed

end
