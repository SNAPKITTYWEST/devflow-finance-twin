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

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};

static CLAUSE_COUNTER: AtomicUsize = AtomicUsize::new(1);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Sign {
    Pos,
    Neg,
}

impl Sign {
    pub fn opposite(self) -> Sign {
        match self {
            Sign::Pos => Sign::Neg,
            Sign::Neg => Sign::Pos,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum LitArg {
    Var(String),
    Sym(String),
    Num(i64),
    Func(String, Vec<LitArg>),
}

impl LitArg {
    pub fn is_var(&self) -> bool {
        matches!(self, LitArg::Var(_))
    }

    pub fn var_name(&self) -> Option<&str> {
        match self {
            LitArg::Var(n) => Some(n),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Literal {
    pub sign: Sign,
    pub pred: String,
    pub args: Vec<LitArg>,
}

impl Literal {
    pub fn pos(pred: &str, args: Vec<LitArg>) -> Self {
        Literal { sign: Sign::Pos, pred: pred.to_string(), args }
    }

    pub fn neg(pred: &str, args: Vec<LitArg>) -> Self {
        Literal { sign: Sign::Neg, pred: pred.to_string(), args }
    }

    pub fn is_complementary(&self, other: &Literal) -> bool {
        self.pred == other.pred && self.sign != other.sign
    }
}

pub type Substitution = HashMap<String, LitArg>;

#[derive(Debug, Clone, PartialEq)]
pub struct Clause {
    pub id: usize,
    pub lits: Vec<Literal>,
    pub parents: Option<Vec<usize>>,
    pub timestamp: u64,
}

pub fn make_clause(lits: Vec<Literal>, parents: Option<Vec<usize>>) -> Clause {
    let id = CLAUSE_COUNTER.fetch_add(1, Ordering::SeqCst);
    Clause {
        id,
        lits,
        parents,
        timestamp: 0,
    }
}

pub fn reset_counter() {
    CLAUSE_COUNTER.store(1, Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_literal_construction() {
        let l = Literal::pos("man", vec![LitArg::Var("x".into())]);
        assert_eq!(l.sign, Sign::Pos);
        assert_eq!(l.pred, "man");
        assert_eq!(l.args.len(), 1);
    }

    #[test]
    fn test_opposite_sign() {
        assert_eq!(Sign::Pos.opposite(), Sign::Neg);
        assert_eq!(Sign::Neg.opposite(), Sign::Pos);
    }

    #[test]
    fn test_complementary() {
        let l1 = Literal::pos("p", vec![]);
        let l2 = Literal::neg("p", vec![]);
        let l3 = Literal::pos("q", vec![]);
        assert!(l1.is_complementary(&l2));
        assert!(!l1.is_complementary(&l3));
    }
}
