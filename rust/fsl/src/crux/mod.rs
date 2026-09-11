// ========================================================================
// SOVEREIGN LEVIATHAN NODE LICENSE
// License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
// Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// ========================================================================
//
// This file is a covered work under the GNU Affero General Public License,
// version 3, together with the Sovereign Leviathan additional terms.
//
// Hark, though this node be but a spark,
// Its covenant endureth through the dark.
//
// Ignorantia juris non excusat.
// ========================================================================

// =============================================================================
// fsl/src/crux/mod.rs  â€“  CRUX Â· SILA Â· OMEGA-SMASHER
// Russian Syntax â†’ Recursive State IR â†’ Dual Backend (GHC | Kani)
// â†’ OMEGA SMASHER â†’ (Z3 | SAS | Lean) â†’ Proof Closure â†’ SAT | UNSAT | MODEL
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
