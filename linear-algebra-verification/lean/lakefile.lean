import Lake
open Lake DSL

package linear_algebra_verification where
  leanOptions := #[⟨`autoImplicit, false⟩]

@[default_target]
lean_lib LinearAlgebraVerification where
  srcDir := "."
