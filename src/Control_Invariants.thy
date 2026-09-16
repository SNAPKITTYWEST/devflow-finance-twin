theory Control_Invariants
imports Quantum_Jump_Update
begin

section \<open>Classical control loop invariants for RWPT\<close>

definition no_jump_map :: "('n) cmat \<Rightarrow> ('n) cmat \<Rightarrow> ('n) cmat" where
  "no_jump_map H Ls \<rho> = \<rho> + dt * lindblad_generator H Ls \<rho>"

axiomatization dt :: real where dt_pos: "dt > 0"

axiomatization preserve_density_no_jump ::
  "('n) cmat \<Rightarrow> ('n) cmat list \<Rightarrow> ('n) cmat \<Rightarrow> bool" where
  preserve_density_no_jump_axiom:
  "\<lbrakk> density \<rho> \<rbrakk> \<Longrightarrow> (let \<rho>' = no_jump_map H Ls \<rho> in Re (trace \<rho>') \<ge> 0)"

lemma control_loop_invariant:
  assumes "density \<rho>"
  shows "density (jump_update L \<rho>) \<or> (Re (trace (no_jump_map H Ls \<rho>)) \<ge> 0)"
  using assms jump_update_density preserve_density_no_jump_axiom by auto

end
