// =============================================================================
// fsl/src/crux/mod.rs  –  CRUX · SILA · OMEGA-SMASHER
// Russian Syntax → Recursive State IR → Dual Backend (GHC | Kani)
// → OMEGA SMASHER → (Z3 | SAS | Lean) → Proof Closure → SAT | UNSAT | MODEL
// =============================================================================

pub mod ast;
pub mod russian;
pub mod omega;
pub mod z3_backend;
pub mod sas_backend;
pub mod lean_backend;
pub mod lean_monad_stack;
pub mod pcc;
pub mod pipeline;

pub use ast::*;
pub use russian::parse_russian;
pub use omega::OmegaSmasher;
pub use lean_monad_stack::{MVarId, FVarId, TacticState, TacticContext, TacticConfig};
pub use pipeline::{run_crux_pipeline, CruxResult};
