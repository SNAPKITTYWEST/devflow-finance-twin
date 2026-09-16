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
use super::clause::{LitArg, Literal, Sign, Substitution};

pub type UnifyResult = Option<Substitution>;

pub fn unify(x: &LitArg, y: &LitArg, subst: &mut Substitution) -> bool {
    let x = resolve_var(x, subst);
    let y = resolve_var(y, subst);

    match (&x, &y) {
        (a, b) if a == b => true,
        (LitArg::Var(v), _) => {
            if occurs_in_var(v, &y, subst) {
                return false;
            }
            subst.insert(v.clone(), y);
            true
        }
        (_, LitArg::Var(v)) => {
            if occurs_in_var(v, &x, subst) {
                return false;
            }
            subst.insert(v.clone(), x);
            true
        }
        (LitArg::Func(n1, a1), LitArg::Func(n2, a2)) => {
            if n1 != n2 || a1.len() != a2.len() {
                return false;
            }
            for (a, b) in a1.iter().zip(a2.iter()) {
                if !unify(a, b, subst) {
                    return false;
                }
            }
            true
        }
        _ => false,
    }
}

pub fn unify_args(args1: &[LitArg], args2: &[LitArg], subst: &mut Substitution) -> bool {
    if args1.len() != args2.len() {
        return false;
    }
    for (a, b) in args1.iter().zip(args2.iter()) {
        if !unify(a, b, subst) {
            return false;
        }
    }
    true
}

fn resolve_var(term: &LitArg, subst: &Substitution) -> LitArg {
    match term {
        LitArg::Var(v) => {
            if let Some(val) = subst.get(v) {
                resolve_var(val, subst)
            } else {
                term.clone()
            }
        }
        LitArg::Func(n, args) => {
            let resolved: Vec<LitArg> = args.iter().map(|a| resolve_var(a, subst)).collect();
            LitArg::Func(n.clone(), resolved)
        }
        _ => term.clone(),
    }
}

fn occurs_in_var(var: &str, term: &LitArg, subst: &Substitution) -> bool {
    match term {
        LitArg::Var(v) => {
            if v == var {
                return true;
            }
            if let Some(val) = subst.get(v) {
                return occurs_in_var(var, val, subst);
            }
            false
        }
        LitArg::Func(_, args) => args.iter().any(|a| occurs_in_var(var, a, subst)),
        _ => false,
    }
}

pub fn apply_subst(subst: &Substitution, term: &LitArg) -> LitArg {
    match term {
        LitArg::Var(v) => {
            if let Some(val) = subst.get(v) {
                apply_subst(subst, val)
            } else {
                term.clone()
            }
        }
        LitArg::Func(n, args) => {
            LitArg::Func(n.clone(), args.iter().map(|a| apply_subst(subst, a)).collect())
        }
        _ => term.clone(),
    }
}

pub fn apply_subst_lit(subst: &Substitution, lit: &Literal) -> Literal {
    Literal {
        sign: lit.sign,
        pred: lit.pred.clone(),
        args: lit.args.iter().map(|a| apply_subst(subst, a)).collect(),
    }
}

pub fn apply_subst_lits(subst: &Substitution, lits: &[Literal]) -> Vec<Literal> {
    lits.iter().map(|l| apply_subst_lit(subst, l)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_unify_identical() {
        let mut s = Substitution::new();
        assert!(unify(&LitArg::Num(1), &LitArg::Num(1), &mut s));
        assert!(s.is_empty());
    }

    #[test]
    fn test_unify_var() {
        let mut s = Substitution::new();
        assert!(unify(&LitArg::Var("x".into()), &LitArg::Num(42), &mut s));
        assert_eq!(s.get("x"), Some(&LitArg::Num(42)));
    }

    #[test]
    fn test_unify_conflict() {
        let mut s = Substitution::new();
        assert!(!unify(&LitArg::Num(1), &LitArg::Num(2), &mut s));
    }

    #[test]
    fn test_occurs_check() {
        let mut s = Substitution::new();
        let term = LitArg::Func("f".into(), vec![LitArg::Var("x".into())]);
        assert!(!unify(&LitArg::Var("x".into()), &term, &mut s));
    }

    #[test]
    fn test_apply_subst() {
        let mut s = Substitution::new();
        s.insert("x".into(), LitArg::Num(5));
        let result = apply_subst(&s, &LitArg::Var("x".into()));
        assert_eq!(result, LitArg::Num(5));
    }
}
