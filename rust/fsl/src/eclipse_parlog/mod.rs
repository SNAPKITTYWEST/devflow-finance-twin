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

pub mod domain;
pub mod arithmetic;
pub mod suspension;
pub mod globals;
pub mod search;
pub mod parlog;

pub use domain::{Domain, DomainStore, set_domain_decl, get_domain_decl, get_bounds};
pub use arithmetic::{Constraint as ArithConstraint, eval_constraint, reify_constraint};
pub use suspension::{SuspensionStore, suspend_goal, wake_var, propagate_store};
pub use globals::{alldifferent, element, cumulative, exactly, atmost, lex_le};
pub use search::{SearchStrategy, search_vars, indomain, first_fail_select, minimize_cost};
pub use parlog::{Mode, GuardedClause, ParlogEngine, par_and, committed_or, Stream};
