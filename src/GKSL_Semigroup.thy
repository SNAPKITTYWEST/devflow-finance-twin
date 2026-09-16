theory GKSL_Semigroup
imports Complex_Main "HOL.Matrix" "HOL-Library.Lim"
begin

section \<open>GKSL generator and CPTP semigroup\<close>

type_synonym ('n) cmat = "('n::finite) \<Rightarrow> ('n) \<Rightarrow> complex"

definition dagger :: "('n) cmat \<Rightarrow> ('n) cmat" where
  "dagger A = (\<lambda>i j. cnj (A j i))"

definition trace :: "('n) cmat \<Rightarrow> complex" where
  "trace A = (\<Sum>i. A i i)"

definition comm :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "comm A B = (\<lambda>i j. (\<Sum>k. A i k * B k j - B i k * A k j))"

definition lindblad_term :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "lindblad_term L \<rho> = (\<lambda>i j. (\<Sum>k l. L i k * \<rho> k l * cnj (L j l)))"

definition dissipator :: "('n) cmat list \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "dissipator Ls \<rho> = (\<Sum>L\<in>set Ls. lindblad_term L \<rho> - (1/2) * ((\<lambda>i j. (\<Sum>k. cnj (L k i) * L k j) * \<rho> i j) + (\<lambda>i j. \<rho> i j * (\<Sum>k. cnj (L k i) * L k j))))"

definition lindblad_generator :: "('n) cmat \<Rightarrow> ('n) cmat list \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "lindblad_generator H Ls \<rho> = (\<lambda>i j. (-Complex.I) * (comm H \<rho>) i j + (dissipator Ls \<rho>) i j)"

lemma lindblad_trace_zero:
  assumes "finite (set Ls)"
  shows "trace (lindblad_generator H Ls \<rho>) = 0"
  using assms
  by (simp add: lindblad_generator_def dissipator_def lindblad_term_def comm_def trace_def dagger_def algebra_simps)

theorem exp_lindblad_is_CPTP:
  fixes H :: "('n) cmat" and Ls :: "('n) cmat list"
  assumes "finite (set Ls)"
  shows "\<forall>t. 0 \<le> t \<longrightarrow> is_CPTP (exp_superop t (lindblad_generator H Ls))"
proof -
  have "(* sketch: Lindblad generator yields a norm-continuous CP semigroup *)" sorry
  thus ?thesis sorry
qed

end
