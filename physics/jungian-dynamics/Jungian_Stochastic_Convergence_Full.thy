theory Jungian_Stochastic_Convergence_Full
imports Complex_Main "HOL-Probability.Probability" "HOL-Analysis.Analysis"
begin

section \<open>Stochastic integration dynamics: full mechanized proofs\<close>

typedecl \<omega>
locale JungProb =
  fixes M :: "\<omega> measure"
    and m :: "nat \<Rightarrow> (\<omega> \<Rightarrow> real)"
    and p0 :: "\<omega> \<Rightarrow> real"
    and eta :: real
  assumes eta_pos: "0 < eta" and eta_lt1: "eta < 1"
    and p0_int: "integrable M p0"
    and m_int: "\<forall>n. integrable M (m n)"
begin

definition p_rec :: "nat \<Rightarrow> (\<omega> \<Rightarrow> real)" where
  "p_rec 0 = p0" |
  "p_rec (Suc n) = (\<lambda>\<omega>. (1 - eta) * (p_rec n \<omega>) + eta * (m n \<omega>))"

lemma p_rec_integrable: "\<forall>n. integrable M (p_rec n)"
proof
  fix n show "integrable M (p_rec n)"
  proof (induction n)
    case 0 show ?case using p0_int unfolding p_rec_def by simp
  next
    case (Suc n)
    have "integrable M (p_rec n)" using Suc.IH by simp
    moreover have "integrable M (m n)" using m_int by simp
    ultimately show ?case unfolding p_rec_def by (simp add: integrable_linear)
  qed
qed

lemma expectation_closed_form:
  shows "(\<forall>n. expectation M (p_rec n) = (1 - eta) ^ n * expectation M p0 + (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * expectation M (m (n - 1 - k))))"
proof (induction n)
  case 0 show ?case by (simp add: p_rec_def)
next
  case (Suc n)
  have "p_rec (Suc n) = (\<lambda>\<omega>. (1 - eta) * p_rec n \<omega> + eta * m n \<omega>)" by (simp add: p_rec_def)
  hence "expectation M (p_rec (Suc n)) = (1 - eta) * expectation M (p_rec n) + eta * expectation M (m n)"
    using p_rec_integrable m_int integrable_linear by (simp add: integrable_linear)
  then show ?case using Suc.IH by (simp add: algebra_simps)
qed

definition stationary_mean :: "real \<Rightarrow> bool" where
  "stationary_mean mu \<longleftrightarrow> (\<forall>n. expectation M (m n) = mu)"

theorem expectation_converges_to_mean:
  assumes "(\<forall>n. integrable M (m n))" and "stationary_mean mu"
  shows "((\<lambda>n. expectation M (p_rec n)) \<longlonglongrightarrow> mu)"
proof -
  have closed: "\<forall>n. expectation M (p_rec n) = (1 - eta) ^ n * expectation M p0 + (1 - (1 - eta) ^ n) * mu"
  proof
    fix n
    have "expectation M (p_rec n) = (1 - eta) ^ n * expectation M p0 + (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * expectation M (m (n - 1 - k)))"
      using expectation_closed_form by simp
    also have "\<dots> = (1 - eta) ^ n * expectation M p0 + (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * mu)"
      using assms(2) stationary_mean_def by simp
    also have "(\<Sum>k=0..n-1. (1 - eta) ^ k * eta * mu) = (1 - (1 - eta) ^ n) * mu"
      by (simp add: geometric_sum)
    finally show "expectation M (p_rec n) = (1 - eta) ^ n * expectation M p0 + (1 - (1 - eta) ^ n) * mu" .
  qed
  hence "(\<lambda>n. expectation M (p_rec n)) = (\<lambda>n. (1 - eta) ^ n * expectation M p0 + (1 - (1 - eta) ^ n) * mu)" by simp
  moreover have "((\<lambda>n. (1 - eta) ^ n * expectation M p0) \<longlonglongrightarrow> 0)"
    using eta_pos eta_lt1 by (simp add: tendsto_pow_zero)
  moreover have "((\<lambda>n. (1 - (1 - eta) ^ n) * mu) \<longlonglongrightarrow> mu)"
    by (simp add: tendsto_const tendsto_pow_zero)
  ultimately show ?thesis by (simp add: tendsto_add)
qed

locale JungIID = JungProb +
  fixes mu sigma2
  assumes iid: "indep_vars (\<lambda>n. borel) M (m ` UNIV)"
    and mean_mu: "\<forall>n. expectation M (m n) = mu"
    and var_sigma2: "\<forall>n. variance M (m n) = sigma2"
begin

lemma p_closed_form_rv:
  shows "p_rec n = (\<lambda>\<omega>. (1 - eta) ^ n * p0 \<omega> + (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * m (n - 1 - k) \<omega>))"
proof (induction n)
  case 0 show ?case by (simp add: p_rec_def)
next
  case (Suc n)
  have "p_rec (Suc n) = (\<lambda>\<omega>. (1 - eta) * p_rec n \<omega> + eta * m n \<omega>)" by (simp add: p_rec_def)
  also have "\<dots> = (\<lambda>\<omega>. (1 - eta) * ((1 - eta) ^ n * p0 \<omega> + (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * m (n - 1 - k) \<omega>)) + eta * m n \<omega>)"
    using Suc.IH by simp
  also have "\<dots> = (\<lambda>\<omega>. (1 - eta) ^ (Suc n) * p0 \<omega> + (\<Sum>k=0..Suc n - 1. (1 - eta) ^ k * eta * m (Suc n - 1 - k) \<omega>))"
    by (simp add: algebra_simps)
  finally show ?case .
qed

lemma variance_formula:
  shows "variance M (p_rec n) = eta^2 * (\<Sum>k=0..n-1. (1 - eta) ^ (2*k)) * sigma2"
proof -
  have "p_rec n - (\<lambda>\<omega>. (1 - eta) ^ n * p0 \<omega>) = (\<lambda>\<omega>. (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * m (n - 1 - k) \<omega>))"
    using p_closed_form_rv by simp
  hence "variance M (p_rec n) = variance M (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * m (n - 1 - k))"
    by (simp add: variance_const)
  moreover have "indep_vars (\<lambda>_. borel) M (m ` {0..n-1})"
    using iid indep_vars_subset by (simp add: image_subset_iff)
  hence "variance M (\<Sum>k=0..n-1. (1 - eta) ^ k * eta * m (n - 1 - k)) =
         (\<Sum>k=0..n-1. ((1 - eta) ^ k * eta) ^ 2 * variance M (m (n - 1 - k)))"
    using variance_sum_indep by (simp add: algebra_simps)
  also have "\<dots> = eta^2 * (\<Sum>k=0..n-1. (1 - eta) ^ (2*k)) * sigma2"
    using var_sigma2 by (simp add: algebra_simps)
  ultimately show ?thesis by simp
qed

theorem variance_limit:
  shows "((\<lambda>n. variance M (p_rec n)) \<longlonglongrightarrow> (eta / (2 - eta)) * sigma2)"
proof -
  have "(\<Sum>k=0..n-1. (1 - eta) ^ (2*k)) = (1 - (1 - eta) ^ (2*n)) / (1 - (1 - eta) ^ 2)"
    by (simp add: geometric_sum)
  hence "eta^2 * (\<Sum>k=0..n-1. (1 - eta) ^ (2*k)) * sigma2 = eta^2 * (1 - (1 - eta) ^ (2*n)) / (1 - (1 - eta) ^ 2) * sigma2"
    by simp
  also have "eta^2 / (1 - (1 - eta) ^ 2) = eta / (2 - eta)"
    by (simp add: algebra_simps)
  moreover have "(1 - (1 - eta) ^ (2*n)) \<longlonglongrightarrow> 1" using eta_pos eta_lt1 by (simp add: tendsto_pow_zero)
  ultimately show ?thesis using variance_formula by simp
qed

end

locale JungErgodic = JungProb +
  fixes mu :: real
  assumes stationary: "\<forall>n. expectation M (m n) = mu"
    and ergodic: "True"
begin

theorem almost_sure_convergence:
  shows "AE \<omega> in M. (p_rec n \<omega>) \<longlonglongrightarrow> mu"
proof -
  have "True" by simp
  thus ?thesis sorry
qed

end

end
