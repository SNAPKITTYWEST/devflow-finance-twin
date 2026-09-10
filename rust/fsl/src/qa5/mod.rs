pub mod clause;
pub mod unification;
pub mod resolution;
pub mod strategy;
pub mod reactive;
pub mod prover;

pub use clause::{Clause, Literal, Sign, LitArg, make_clause};
pub use unification::{UnifyResult, unify, apply_subst};
pub use resolution::{resolve, tautology_p};
pub use strategy::{unit_clause_p, pick_clause, subsumes};
pub use reactive::{ReactiveEvent, ReactiveCell, add_observer, notify_observers};
pub use prover::{qa5_prove, ProofResult,QA5Config};
