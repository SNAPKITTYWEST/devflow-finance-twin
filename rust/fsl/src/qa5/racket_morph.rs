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

use super::clause::{Clause, Literal, LitArg, Substitution, Sign};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub struct RacketClause {
    pub id: usize,
    pub lits: Vec<Literal>,
    pub parents: Vec<usize>,
    pub timestamp: u64,
}

impl From<&Clause> for RacketClause {
    fn from(c: &Clause) -> Self {
        RacketClause {
            id: c.id,
            lits: c.lits.clone(),
            parents: c.parents.clone().unwrap_or_default(),
            timestamp: c.timestamp,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RacketVar {
    pub name: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RacketConst {
    pub name: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RacketFun {
    pub name: String,
    pub args: Vec<RacketTerm>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum RacketTerm {
    Var(RacketVar),
    Const(RacketConst),
    Fun(RacketFun),
}

impl RacketTerm {
    pub fn var(name: &str) -> Self {
        RacketTerm::Var(RacketVar { name: name.to_string() })
    }
    pub fn const_(name: &str) -> Self {
        RacketTerm::Const(RacketConst { name: name.to_string() })
    }
    pub fn fun(name: &str, args: Vec<RacketTerm>) -> Self {
        RacketTerm::Fun(RacketFun { name: name.to_string(), args })
    }
}

#[derive(Debug, Clone)]
pub struct RacketBindings {
    map: HashMap<String, RacketTerm>,
    trail: Vec<String>,
}

impl RacketBindings {
    pub fn new() -> Self {
        RacketBindings { map: HashMap::new(), trail: Vec::new() }
    }

    pub fn bind(&mut self, var: &str, term: RacketTerm) {
        self.map.insert(var.to_string(), term);
        self.trail.push(var.to_string());
    }

    pub fn undo_to(&mut self, old_len: usize) {
        while self.trail.len() > old_len {
            if let Some(v) = self.trail.pop() {
                self.map.remove(&v);
            }
        }
    }

    pub fn deref(&self, term: &RacketTerm) -> RacketTerm {
        match term {
            RacketTerm::Var(v) => {
                if let Some(val) = self.map.get(&v.name) {
                    self.deref(val)
                } else {
                    term.clone()
                }
            }
            _ => term.clone(),
        }
    }

    pub fn trail_len(&self) -> usize {
        self.trail.len()
    }
}

#[derive(Debug, Clone)]
pub struct ProofStep {
    pub clause_id: usize,
    pub lits: Vec<Literal>,
    pub parent_ids: Vec<usize>,
    pub subst: Substitution,
}

#[derive(Debug, Clone)]
pub struct ProofTrace {
    pub steps: Vec<ProofStep>,
    pub empty_clause_id: Option<usize>,
}

impl ProofTrace {
    pub fn new() -> Self {
        ProofTrace { steps: Vec::new(), empty_clause_id: None }
    }

    pub fn add_step(&mut self, clause: &Clause, subst: &Substitution) {
        self.steps.push(ProofStep {
            clause_id: clause.id,
            lits: clause.lits.clone(),
            parent_ids: clause.parents.clone().unwrap_or_default(),
            subst: subst.clone(),
        });
    }

    pub fn mark_empty(&mut self, id: usize) {
        self.empty_clause_id = Some(id);
    }

    pub fn explain(&self) -> String {
        let mut out = String::from("=== PROOF TRACE ===\n");
        for step in &self.steps {
            out.push_str(&format!(
                "Clause {}: {:?} parents={:?}\n",
                step.clause_id, step.lits, step.parent_ids
            ));
        }
        if let Some(eid) = self.empty_clause_id {
            out.push_str(&format!("*** EMPTY CLAUSE {} = PROOF ***\n", eid));
        }
        out
    }
}

pub fn convert_clause(c: &Clause) -> RacketClause {
    RacketClause::from(c)
}

pub fn convert_subst_to_bindings(subst: &Substitution) -> RacketBindings {
    let mut bindings = RacketBindings::new();
    for (var, val) in subst {
        bindings.bind(var, RacketTerm::from_lit_arg(val));
    }
    bindings
}

impl RacketTerm {
    pub fn from_lit_arg(arg: &LitArg) -> Self {
        match arg {
            LitArg::Var(v) => RacketTerm::var(v),
            LitArg::Sym(s) => RacketTerm::const_(s),
            LitArg::Num(n) => RacketTerm::const_(&n.to_string()),
            LitArg::Func(name, args) => {
                RacketTerm::fun(name, args.iter().map(RacketTerm::from_lit_arg).collect())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_racket_clause_conversion() {
        let c = super::super::clause::make_clause(
            vec![Literal::pos("p", vec![LitArg::Var("x".into())])],
            Some(vec![1, 2]),
        );
        let rc = convert_clause(&c);
        assert_eq!(rc.id, c.id);
        assert_eq!(rc.parents, vec![1, 2]);
    }

    #[test]
    fn test_racket_bindings() {
        let mut b = RacketBindings::new();
        let old = b.trail_len();
        b.bind("x", RacketTerm::const_("5"));
        assert_eq!(b.deref(&RacketTerm::var("x")), RacketTerm::const_("5"));
        b.undo_to(old);
        assert_eq!(b.deref(&RacketTerm::var("x")), RacketTerm::var("x"));
    }

    #[test]
    fn test_proof_trace() {
        let mut trace = ProofTrace::new();
        let c = super::super::clause::make_clause(vec![], Some(vec![1, 2]));
        trace.add_step(&c, &Substitution::new());
        trace.mark_empty(c.id);
        let explanation = trace.explain();
        assert!(explanation.contains("PROOF"));
    }
}
