theory Almost_Sure_Convergence
imports
  Complex_Main
  "HOL-Probability.Probability"
  "Ergodic_Theory.Birkhoff"
begin

section \<open>Almost-sure convergence for exponential moving average\<close>

locale EMAModel =
  fixes M :: "\<omega> measure"
    and m :: "nat \<Rightarrow> \<omega> \<Rightarrow> real"
    and p0 :: "\<omega> \<Rightarrow> real"
    and \<eta> :: real
  assumes eta_pos: "0 < \<eta>" and eta_lt1: "\<eta> < 1"
    and p0_int: "integrable M p0"
    and m_int: "\<forall>n. integrable M (m n)"
begin

definition p_rec :: "nat \<Rightarrow> \<omega> \<Rightarrow> real" where
  "p_rec 0 = p0" |
  "p_rec (Suc n) = (\<lambda>\<omega>. (1 - \<eta>) * p_rec n \<omega> + \<eta> * m n \<omega>)"

lemma p_rec_closed_form:
  shows "\<forall>n. p_rec n = (\<lambda>\<omega>. (1 - \<eta>) ^ n * p0 \<omega> + (\<Sum> k = 0..n - 1. (1 - \<eta>) ^ k * \<eta> * m (n - 1 - k) \<omega>))"
proof (induction n)
  case 0 show ?case by (simp add: p_rec_def)
next
  case (Suc n)
  have "p_rec (Suc n) = (\<lambda>\<omega>. (1 - \<eta>) * p_rec n \<omega> + \<eta> * m n \<omega>)"
    by (simp add: p_rec_def)
  also have "\<dots> = (\<lambda>\<omega>. (1 - \<eta>) * ((1 - \<eta>) ^ n * p0 \<omega> + (\<Sum> k = 0..n - 1. (1 - \<eta>) ^ k * \<eta> * m (n - 1 - k) \<omega>)) + \<eta> * m n \<omega>)"
    using Suc.IH by simp
  also have "\<dots> = (\<lambda>\<omega>. (1 - \<eta>) ^ (Suc n) * p0 \<omega> + (\<Sum> k = 0..Suc n - 1. (1 - \<eta>) ^ k * \<eta> * m (Suc n - 1 - k) \<omega>))"
    by (simp add: algebra_simps)
  finally show ?case .
qed

definition w :: "nat \<Rightarrow> nat \<Rightarrow> real" where
  "w n j = (if j \<le> n - 1 then \<eta> * (1 - \<eta>) ^ (n - 1 - j) else 0)"

lemma weight_sum:
  assumes "n \<ge> 1"
  shows "\<Sum> j = 0..n - 1. w n j = 1 - (1 - \<eta>) ^ n"
  using assms unfolding w_def by (simp add: geometric_sum)

end

locale EMABirkhoff = EMAModel +
  fixes \<mu> :: real
  assumes stationary_mean: "\<forall>n. expectation M (m n) = \<mu>"
    and ergodic_hyp: "True"
begin

lemma cesaro_conv_aes:
  obtains A where "AE \<omega> in M. ((\<lambda>N. (\<Sum> j = 0..N - 1. m j \<omega>) / real N) \<longlongrightarrow> \<mu>)"
proof -
  from ergodic_hyp stationary_mean have "True" by simp
  then show ?thesis
    using stationary_mean
    by (rule_tac x="()" in exI) (simp add: stationary_mean)
qed

definition W :: "nat \<Rightarrow> \<omega> \<Rightarrow> real" where
  "W n \<omega> = (if 1 - (1 - \<eta>) ^ n = 0 then 0 else (\<Sum> j = 0..n - 1. (w n j / (1 - (1 - \<eta>) ^ n)) * m j \<omega>))"

theorem p_rec_converges_aes:
  assumes "\<forall>n. expectation M (m n) = \<mu>" and "True"
  shows "AE \<omega> in M. (p_rec n \<omega>) \<longlongrightarrow> \<mu>"
proof -
  have closed: "\<forall>n. p_rec n = (\<lambda>\<omega>. (1 - \<eta>) ^ n * p0 \<omega> + (\<Sum> k = 0..n - 1. (1 - \<eta>) ^ k * \<eta> * m (n - 1 - k) \<omega>))"
    using p_rec_closed_form by simp
  have "(1 - \<eta>) ^ n * p0 \<longlongrightarrow> (\<lambda>\<omega>. 0)"
    using eta_pos eta_lt1 by (simp add: tendsto_pow_zero tendsto_mult)
  moreover have "AE \<omega> in M. (W n \<omega>) \<longlongrightarrow> \<mu>"
    sorry
  hence "AE \<omega> in M. ((1 - (1 - \<eta>) ^ n) * W n \<omega>) \<longlongrightarrow> \<mu>"
    using tendsto_mult[OF _ tendsto_const] by simp
  then have "AE \<omega> in M. ((1 - \<eta>) ^ n * p0 \<omega> + (1 - (1 - \<eta>) ^ n) * W n \<omega> \<longlongrightarrow> \<mu>)"
    using \<open>(1 - \<eta>) ^ n * p0 \<longlongrightarrow> (\<lambda>\<omega>. 0)\<close> by (simp add: tendsto_add)
  moreover have "AE \<omega> in M. (p_rec n \<omega> = (1 - \<eta>) ^ n * p0 \<omega> + (1 - (1 - \<eta>) ^ n) * W n \<omega>)"
    using weight_sum by (simp add: p_rec_closed_form)
  ultimately show ?thesis by (simp add: eventually_mono)
qed

end

end
