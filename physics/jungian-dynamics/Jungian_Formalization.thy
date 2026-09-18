theory Jungian_Formalization
imports Complex_Main
begin

section \<open>Types and basic relations\<close>

typedecl Agent
typedecl Archetype
typedecl Symbol

type_synonym State = "Archetype set \<times> Symbol set"

consts projects :: "Agent \<Rightarrow> Archetype \<Rightarrow> Agent \<Rightarrow> bool"
consts integrates :: "Agent \<Rightarrow> Archetype \<Rightarrow> bool"
consts manifests :: "Agent \<Rightarrow> Symbol \<Rightarrow> bool"
consts expresses :: "Archetype \<Rightarrow> Symbol \<Rightarrow> bool"
consts whole :: "Agent \<Rightarrow> bool"
consts wholeness_score :: "Agent \<Rightarrow> real"
consts integration_process :: "Agent \<Rightarrow> Archetype \<Rightarrow> bool"

section \<open>Axioms\<close>

axiomatization where
  archetype_persistence: "True"

axiomatization where
  projection_from_unintegrated:
    "\<lbrakk> \<not> integrates A \<alpha> \<rbrakk> \<Longrightarrow> (\<exists>B. projects A \<alpha> B) \<longleftrightarrow> (manifests A s \<and> expresses \<alpha> s)"

axiomatization where
  integration_reduces_projection:
    "\<lbrakk> integrates A \<alpha> \<rbrakk> \<Longrightarrow> (\<forall>B. \<not> projects A \<alpha> B)"

axiomatization where
  imagination_facilitates_integration:
    "(\<exists>s. manifests A s \<and> expresses \<alpha> s) \<Longrightarrow> integrates A \<alpha> \<or> (integration_process A \<alpha>)"

axiomatization where
  wholeness_monotone:
    "integrates A \<alpha> \<Longrightarrow> wholeness_score A \<le> wholeness_score A + 0.0"

section \<open>Derived lemmas\<close>

lemma no_projection_if_all_integrated:
  assumes "\<forall>\<alpha>. (\<exists>s. manifests A s \<and> expresses \<alpha> s) \<longrightarrow> integrates A \<alpha>"
  shows "\<forall>\<alpha> B. (\<exists>s. manifests A s \<and> expresses \<alpha> s) \<longrightarrow> \<not> projects A \<alpha> B"
proof
  fix \<alpha> B
  assume H: "(\<exists>s. manifests A s \<and> expresses \<alpha> s)"
  from assms have "integrates A \<alpha>" using H by auto
  then show "\<not> projects A \<alpha> B" using integration_reduces_projection by auto
qed

corollary imagination_leads_to_integration:
  assumes "(\<exists>s. manifests A s \<and> expresses \<alpha> s)"
  shows "integrates A \<alpha> \<or> integration_process A \<alpha>"
  using imagination_facilitates_integration assms by auto

theorem integration_reduces_misattribution:
  assumes "integrates A \<alpha>"
  shows "\<forall>B. \<not> projects A \<alpha> B"
  using assms integration_reduces_projection by auto

end
