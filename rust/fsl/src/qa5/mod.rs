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

pub mod clause;
pub mod unification;
pub mod resolution;
pub mod strategy;
pub mod reactive;
pub mod prover;
pub mod racket_morph;

pub use clause::{Clause, Literal, Sign, LitArg, make_clause};
pub use unification::{UnifyResult, unify, apply_subst};
pub use resolution::{resolve, tautology_p};
pub use strategy::{unit_clause_p, pick_clause, subsumes};
pub use reactive::{ReactiveEvent, ReactiveCell, add_observer, notify_observers};
pub use prover::{qa5_prove, ProofResult, QA5Config};
pub use racket_morph::{RacketClause, RacketBindings, RacketTerm, ProofTrace, convert_clause};
