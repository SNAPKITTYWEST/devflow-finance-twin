theory Density_Matrix
imports Complex_Main "HOL.Matrix"
begin

section \<open>Basic definitions for density matrices\<close>

type_synonym ('n) cmat = "('n::finite) \<Rightarrow> ('n) \<Rightarrow> complex"

definition dagger :: "('n) cmat \<Rightarrow> ('n) cmat" where
  "dagger A = (\<lambda>i j. cnj (A j i))"

definition hermitian :: "('n) cmat \<Rightarrow> bool" where
  "hermitian A \<longleftrightarrow> A = dagger A"

definition trace :: "('n) cmat \<Rightarrow> complex" where
  "trace A = (\<Sum>i. A i i)"

definition pos_semidef :: "('n) cmat \<Rightarrow> bool" where
  "pos_semidef A \<longleftrightarrow> (\<forall>v. (\<Sum>i j. cnj (v i) * A i j * v j) \<in> {x. Re x \<ge> 0})"

definition density :: "('n) cmat \<Rightarrow> bool" where
  "density \<rho> \<longleftrightarrow> hermitian \<rho> \<and> pos_semidef \<rho> \<and> trace \<rho> = 1"

lemma trace_linear: "trace (A + B) = trace A + trace B"
  by (simp add: trace_def)

lemma trace_cnj: "cnj (trace A) = trace (dagger A)"
  by (simp add: trace_def dagger_def)

definition unitary :: "('n) cmat \<Rightarrow> bool" where
  "unitary U \<longleftrightarrow> (U \<circ>\<^sub>m dagger U = (\<lambda>i j. if i = j then 1 else 0)) \<and> (dagger U \<circ>\<^sub>m U = (\<lambda>i j. if i = j then 1 else 0))"

lemma trace_unitary_conj:
  assumes "unitary U"
  shows "trace (U \<circ>\<^sub>m \<rho> \<circ>\<^sub>m dagger U) = trace \<rho>"
proof -
  have "trace (U \<circ>\<^sub>m \<rho> \<circ>\<^sub>m dagger U) = trace (\<rho> \<circ>\<^sub>m dagger U \<circ>\<^sub>m U)"
    by (simp add: trace_def matrix_mult_assoc)
  moreover from assms have "dagger U \<circ>\<^sub>m U = (\<lambda>i j. if i = j then 1 else 0)"
    by (simp add: unitary_def)
  hence "trace (\<rho> \<circ>\<^sub>m dagger U \<circ>\<^sub>m U) = trace \<rho>"
    by (simp add: trace_def)
  ultimately show ?thesis by simp
qed

end
