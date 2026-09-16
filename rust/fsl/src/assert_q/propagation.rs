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

use super::formula::{Formula, FormulaOp, FormulaArg};
use super::constraint::{ConstraintStore, ConstraintStatus, Domain};

#[derive(Debug, Clone, PartialEq)]
pub enum InterpretResult {
    Entailed,
    Failed,
    Reduce,
    Unknown,
}

pub fn interpret(f: &Formula, store: &mut ConstraintStore) -> InterpretResult {
    match f.op {
        FormulaOp::And => interpret_and(&f.args, store),
        FormulaOp::Or => interpret_or(&f.args, store),
        FormulaOp::Not => {
            if let Some(FormulaArg::Formula(sub)) = f.args.first() {
                match interpret(sub, store) {
                    InterpretResult::Entailed => InterpretResult::Failed,
                    InterpretResult::Failed => InterpretResult::Entailed,
                    _ => InterpretResult::Unknown,
                }
            } else {
                InterpretResult::Unknown
            }
        }
        FormulaOp::Implies => {
            if f.args.len() >= 2 {
                if let (Some(FormulaArg::Formula(a)), Some(FormulaArg::Formula(b))) =
                    (f.args.first(), f.args.get(1))
                {
                    let a_ref: &Formula = a;
                    let b_ref: &Formula = b;
                    let na = Formula::new(FormulaOp::Not, vec![FormulaArg::Formula(Box::new(a_ref.clone()))]);
                    let combined = Formula::new(FormulaOp::Or, vec![
                        FormulaArg::Formula(Box::new(na)),
                        FormulaArg::Formula(Box::new(b_ref.clone())),
                    ]);
                    return interpret(&combined, store);
                }
            }
            InterpretResult::Unknown
        }
        FormulaOp::Eq => interpret_cmp_eq(&f.args, store),
        FormulaOp::Neq => interpret_cmp_neq(&f.args, store),
        FormulaOp::Lt => interpret_cmp_ordering(&f.args, store, CmpMode::Exact(Ordering::Less)),
        FormulaOp::Gt => interpret_cmp_ordering(&f.args, store, CmpMode::Exact(Ordering::Greater)),
        FormulaOp::Le => interpret_cmp_ordering(&f.args, store, CmpMode::Le),
        FormulaOp::Ge => interpret_cmp_ordering(&f.args, store, CmpMode::Ge),
        FormulaOp::Domain => interpret_domain(&f.args, store),
        FormulaOp::In => interpret_in(&f.args, store),
        FormulaOp::AllDifferent => interpret_alldifferent(&f.args, store),
        FormulaOp::Sum => interpret_sum(&f.args, store),
        _ => InterpretResult::Unknown,
    }
}

use std::cmp::Ordering;

fn interpret_and(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    let mut results = Vec::new();
    for a in args {
        if let FormulaArg::Formula(f) = a {
            results.push(interpret(f, store));
        } else {
            results.push(InterpretResult::Unknown);
        }
    }
    if results.iter().any(|r| *r == InterpretResult::Failed) {
        InterpretResult::Failed
    } else if results.iter().all(|r| *r == InterpretResult::Entailed) {
        InterpretResult::Entailed
    } else if results.iter().any(|r| *r == InterpretResult::Reduce) {
        InterpretResult::Reduce
    } else {
        InterpretResult::Unknown
    }
}

fn interpret_or(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    let mut results = Vec::new();
    for a in args {
        if let FormulaArg::Formula(f) = a {
            results.push(interpret(f, store));
        }
    }
    if results.iter().any(|r| *r == InterpretResult::Entailed) {
        InterpretResult::Entailed
    } else if results.iter().all(|r| *r == InterpretResult::Failed) {
        InterpretResult::Failed
    } else {
        InterpretResult::Unknown
    }
}

fn resolve_val(arg: &FormulaArg, store: &ConstraintStore) -> Option<i64> {
    match arg {
        FormulaArg::Num(n) => Some(*n),
        FormulaArg::Var(v) => store.get_value(v),
        _ => None,
    }
}

fn interpret_cmp_eq(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    if args.len() < 2 { return InterpretResult::Unknown; }
    let x = resolve_val(&args[0], store);
    let y = resolve_val(&args[1], store);
    match (x, y) {
        (Some(a), Some(b)) => {
            if a == b { InterpretResult::Entailed } else { InterpretResult::Failed }
        }
        _ => InterpretResult::Unknown,
    }
}

fn interpret_cmp_neq(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    if args.len() < 2 { return InterpretResult::Unknown; }
    let x = resolve_val(&args[0], store);
    let y = resolve_val(&args[1], store);
    match (x, y) {
        (Some(a), Some(b)) => {
            if a != b { InterpretResult::Entailed } else { InterpretResult::Failed }
        }
        _ => InterpretResult::Unknown,
    }
}

#[derive(Debug, Clone, Copy)]
enum CmpMode {
    Exact(Ordering),
    Le,
    Ge,
}

fn interpret_cmp_ordering(args: &[FormulaArg], store: &mut ConstraintStore, mode: CmpMode) -> InterpretResult {
    if args.len() < 2 { return InterpretResult::Unknown; }
    let x = resolve_val(&args[0], store);
    let y = resolve_val(&args[1], store);
    match (x, y) {
        (Some(a), Some(b)) => {
            let actual = a.cmp(&b);
            let entailed = match mode {
                CmpMode::Exact(ord) => actual == ord,
                CmpMode::Le => actual == Ordering::Less || actual == Ordering::Equal,
                CmpMode::Ge => actual == Ordering::Greater || actual == Ordering::Equal,
            };
            if entailed { InterpretResult::Entailed } else { InterpretResult::Failed }
        }
        _ => InterpretResult::Unknown,
    }
}

fn interpret_domain(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    if args.len() < 3 { return InterpretResult::Unknown; }
    if let (FormulaArg::Var(v), FormulaArg::Num(lo), FormulaArg::Num(hi)) =
        (&args[0], &args[1], &args[2])
    {
        match store.get_domain(v).cloned() {
            Some(Domain::Range(existing_lo, existing_hi)) => {
                let new_lo = std::cmp::max(*lo, existing_lo);
                let new_hi = std::cmp::min(*hi, existing_hi);
                if new_lo > new_hi {
                    InterpretResult::Failed
                } else if new_lo != existing_lo || new_hi != existing_hi {
                    store.set_domain(v, Domain::Range(new_lo, new_hi));
                    InterpretResult::Reduce
                } else {
                    InterpretResult::Entailed
                }
            }
            None => {
                store.set_domain(v, Domain::Range(*lo, *hi));
                InterpretResult::Reduce
            }
            _ => InterpretResult::Unknown,
        }
    } else {
        InterpretResult::Unknown
    }
}

fn interpret_in(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    if args.len() < 2 { return InterpretResult::Unknown; }
    if let (FormulaArg::Var(v), FormulaArg::List(vals)) = (&args[0], &args[1]) {
        let int_vals: Vec<i64> = vals.iter().filter_map(|a| match a {
            FormulaArg::Num(n) => Some(*n),
            _ => None,
        }).collect();
        store.set_domain(v, Domain::Set(int_vals));
        InterpretResult::Reduce
    } else {
        InterpretResult::Unknown
    }
}

fn interpret_alldifferent(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    let ground: Vec<i64> = args.iter()
        .filter_map(|a| match a {
            FormulaArg::Var(v) => store.get_value(v),
            FormulaArg::Num(n) => Some(*n),
            _ => None,
        })
        .collect();
    let mut sorted = ground.clone();
    sorted.sort();
    let has_dup = sorted.windows(2).any(|w| w[0] == w[1]);
    if has_dup {
        InterpretResult::Failed
    } else {
        InterpretResult::Unknown
    }
}

fn interpret_sum(args: &[FormulaArg], store: &mut ConstraintStore) -> InterpretResult {
    if args.len() < 3 { return InterpretResult::Unknown; }
    if let (FormulaArg::List(vars), FormulaArg::List(coeffs), result_arg) =
        (&args[0], &args[1], &args[2])
    {
        let mut s: i64 = 0;
        let mut known = true;
        for (v, c) in vars.iter().zip(coeffs.iter()) {
            let c_val = match c {
                FormulaArg::Num(n) => *n,
                _ => { known = false; continue; }
            };
            match v {
                FormulaArg::Var(name) => {
                    if let Some(val) = store.get_value(name) {
                        s += c_val * val;
                    } else {
                        known = false;
                    }
                }
                FormulaArg::Num(n) => s += c_val * n,
                _ => known = false,
            }
        }
        if known {
            let result_val = resolve_val(result_arg, store);
            match result_val {
                Some(r) => {
                    if s == r { InterpretResult::Entailed } else { InterpretResult::Failed }
                }
                None => InterpretResult::Unknown,
            }
        } else {
            InterpretResult::Unknown
        }
    } else {
        InterpretResult::Unknown
    }
}

pub fn propagate(store: &mut ConstraintStore) {
    // Iterate until fixpoint
    loop {
        let ids: Vec<usize> = store.constraints.keys().copied().collect();
        let mut changed = false;
        for id in ids {
            let c = store.constraints.get(&id).unwrap();
            if c.status != ConstraintStatus::Active && c.status != ConstraintStatus::Posted {
                continue;
            }
            let form = c.form.clone();
            let result = interpret(&form, store);
            let c_mut = store.constraints.get_mut(&id).unwrap();
            let old_status = c_mut.status.clone();
            match result {
                InterpretResult::Entailed => c_mut.status = ConstraintStatus::Entailed,
                InterpretResult::Failed => c_mut.status = ConstraintStatus::Failed,
                InterpretResult::Reduce => {
                    c_mut.status = ConstraintStatus::Active;
                    changed = true;
                }
                _ => c_mut.status = ConstraintStatus::Active,
            }
            if c_mut.status != old_status {
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::formula::{feq, fand, fnot, fgt, flt, FormulaArg, domain as f_domain};

    #[test]
    fn test_interpret_eq() {
        let mut store = ConstraintStore::new();
        store.set_value("x", 5);
        let f = feq(FormulaArg::var("x"), FormulaArg::num(5));
        assert_eq!(interpret(&f, &mut store), InterpretResult::Entailed);

        let f2 = feq(FormulaArg::var("x"), FormulaArg::num(3));
        assert_eq!(interpret(&f2, &mut store), InterpretResult::Failed);
    }

    #[test]
    fn test_interpret_not() {
        let mut store = ConstraintStore::new();
        store.set_value("x", 1);
        let f = fnot(feq(FormulaArg::var("x"), FormulaArg::num(1)));
        assert_eq!(interpret(&f, &mut store), InterpretResult::Failed);
    }

    #[test]
    fn test_interpret_domain() {
        let mut store = ConstraintStore::new();
        let f = f_domain("x", 1, 10);
        assert_eq!(interpret(&f, &mut store), InterpretResult::Reduce);
        // Narrow
        let f2 = f_domain("x", 5, 15);
        assert_eq!(interpret(&f2, &mut store), InterpretResult::Reduce);
        let dom = store.get_domain("x").unwrap();
        assert_eq!(dom, &Domain::Range(5, 10));
    }
}
