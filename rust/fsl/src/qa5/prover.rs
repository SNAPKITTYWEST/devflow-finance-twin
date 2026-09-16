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

use super::clause::{Clause, Literal, LitArg, make_clause, reset_counter};
use super::resolution::{resolve, make_resolvent_clause};
use super::strategy::{pick_clause, subsumed_by_any};
use super::reactive::{ReactiveEvent, notify_observers, clear_observers};
use std::collections::HashSet;

#[derive(Debug, Clone)]
pub struct QA5Config {
    pub proof_depth_limit: usize,
    pub trace_level: i32,
}

impl Default for QA5Config {
    fn default() -> Self {
        QA5Config {
            proof_depth_limit: 40,
            trace_level: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ProofResult {
    Proved {
        empty_clause: Clause,
        answers: Vec<(usize, Vec<(String, super::clause::LitArg)>)>,
    },
    Failed {
        reason: String,
    },
}

pub fn qa5_prove(
    goal_clauses: &[Vec<Literal>],
    axiom_clauses: &[Vec<Literal>],
    config: &QA5Config,
) -> ProofResult {
    reset_counter();
    clear_observers();

    let mut sos: Vec<Clause> = goal_clauses.iter()
        .map(|lits| make_clause(lits.clone(), None))
        .collect();
    let mut usable: Vec<Clause> = axiom_clauses.iter()
        .map(|lits| make_clause(lits.clone(), None))
        .collect();
    let mut answers: Vec<(usize, Vec<(String, super::clause::LitArg)>)> = Vec::new();

    notify_observers(&ReactiveEvent::ProofStart);

    for depth in 0..config.proof_depth_limit {
        if sos.is_empty() {
            return ProofResult::Failed {
                reason: "SOS exhausted".into(),
            };
        }

        let given = match pick_clause(&sos, &usable) {
            Some(c) => c.clone(),
            None => return ProofResult::Failed { reason: "No clause to pick".into() },
        };

        sos.retain(|c| c.id != given.id);
        notify_observers(&ReactiveEvent::GivenClause(given.id));

        if given.lits.is_empty() {
            notify_observers(&ReactiveEvent::ProofSuccess(given.id));
            return ProofResult::Proved {
                empty_clause: given,
                answers,
            };
        }

        let mut new_resolvents = Vec::new();
        for u in &usable {
            let mut resolvents = resolve(&given, u);
            new_resolvents.append(&mut resolvents);
        }

        for r in &new_resolvents {
            let r_clause = make_resolvent_clause(r);
            if !subsumed_by_any(&r_clause, &usable) && !subsumed_by_any(&r_clause, &sos) {
                // Extract answer if there's a substitution
                if !r.subst.is_empty() {
                    let answer_subst: Vec<_> = r.subst.iter()
                        .map(|(k, v)| (k.clone(), v.clone()))
                        .collect();
                    answers.push((r_clause.id, answer_subst));
                }
                notify_observers(&ReactiveEvent::NewClause(r_clause.id));
                sos.push(r_clause);
            }
        }

        usable.push(given);
        notify_observers(&ReactiveEvent::UsableUpdated);
    }

    ProofResult::Failed {
        reason: format!("Depth limit {} reached", config.proof_depth_limit),
    }
}

/// Convenience wrapper: Socrates demo
pub fn socrates_demo() -> ProofResult {
        let axioms = vec![
            // âˆ€x Man(x) â†’ Mortal(x)
            vec![
                Literal::neg("man", vec![LitArg::Var("x".into())]),
                Literal::pos("mortal", vec![LitArg::Var("x".into())]),
            ],
            // Man(socrates)
            vec![
                Literal::pos("man", vec![LitArg::Sym("socrates".into())]),
            ],
        ];
        let goals = vec![
            // Â¬Mortal(socrates)
            vec![
                Literal::neg("mortal", vec![LitArg::Sym("socrates".into())]),
            ],
        ];

    qa5_prove(&goals, &axioms, &QA5Config::default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_socrates_prove() {
        let result = socrates_demo();
        match &result {
            ProofResult::Proved { empty_clause, answers } => {
                assert!(empty_clause.lits.is_empty());
                assert!(!answers.is_empty());
            }
            ProofResult::Failed { reason } => panic!("Expected proof, got: {}", reason),
        }
    }

    #[test]
    fn test_unprovable() {
        // Goal: mortal(socrates), Axiom: man(socrates) â€” no rule connects them
        let axioms = vec![
            vec![Literal::pos("man", vec![LitArg::Sym("socrates".into())])],
        ];
        let goals = vec![
            vec![Literal::pos("mortal", vec![LitArg::Sym("socrates".into())])],
        ];
        let result = qa5_prove(&goals, &axioms, &QA5Config { proof_depth_limit: 5, ..Default::default() });
        assert!(matches!(result, ProofResult::Failed { .. }));
    }
}
