use super::formula::{Formula, FormulaArg};
use super::constraint::{ConstraintStore, Domain};
use super::propagation::{propagate, interpret, InterpretResult};

#[derive(Debug, Clone, PartialEq)]
pub enum SatResult {
    Sat(Vec<(String, i64)>),
    Unsat,
    Unknown,
}

pub fn solve(store: &mut ConstraintStore, limit: usize) -> SatResult {
    propagate(store);

    if store.any_failed() {
        return SatResult::Unsat;
    }

    let mut vars: Vec<String> = store.domains.keys().cloned().collect();
    vars.sort();
    search_vars(store, &vars, limit)
}

fn search_vars(store: &mut ConstraintStore, vars: &[String], limit: usize) -> SatResult {
    if limit == 0 {
        return SatResult::Unknown;
    }

    if vars.is_empty() {
        return SatResult::Sat(extract_model(store));
    }

    let v = &vars[0];
    match store.get_domain(v).cloned() {
        Some(Domain::Fixed(_)) => {
            search_vars(store, &vars[1..], limit)
        }
        Some(Domain::Set(vals)) => {
            for val in &vals {
                let old_domain = store.get_domain(v).cloned();
                store.set_domain(v, Domain::Fixed(*val));
                store.reset_statuses();
                propagate(store);
                if !store.any_failed() {
                    let result = search_vars(store, &vars[1..], limit - 1);
                    if result != SatResult::Unknown {
                        return result;
                    }
                }
                if let Some(old) = old_domain {
                    store.set_domain(v, old);
                    store.reset_statuses();
                }
            }
            SatResult::Unsat
        }
        Some(Domain::Range(lo, hi)) => {
            for val in lo..=hi {
                let old_domain = store.get_domain(v).cloned();
                store.set_domain(v, Domain::Fixed(val));
                store.reset_statuses();
                propagate(store);
                if !store.any_failed() {
                    let result = search_vars(store, &vars[1..], limit - 1);
                    if result != SatResult::Unknown {
                        return result;
                    }
                }
                if let Some(old) = old_domain {
                    store.set_domain(v, old);
                    store.reset_statuses();
                }
            }
            SatResult::Unsat
        }
        None => SatResult::Unknown,
    }
}

pub fn extract_model(store: &ConstraintStore) -> Vec<(String, i64)> {
    store.model.iter()
        .map(|(k, v)| (k.clone(), *v))
        .collect()
}

pub fn sat(store: &mut ConstraintStore) -> bool {
    matches!(solve(store, 10000), SatResult::Sat(_))
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::formula::{feq, flt, fand, domain as f_domain, FormulaArg};
    use super::super::constraint::make_constraint;

    #[test]
    fn test_solve_simple() {
        let mut store = ConstraintStore::new();
        store.set_domain("x", Domain::Range(1, 3));
        let c = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(2)), 0, "test");
        store.insert(c);

        let result = solve(&mut store, 100);
        assert_eq!(result, SatResult::Sat(vec![("x".into(), 2)]));
    }

    #[test]
    fn test_solve_unsat() {
        let mut store = ConstraintStore::new();
        store.set_domain("x", Domain::Range(1, 3));
        let c = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(5)), 0, "test");
        store.insert(c);

        let result = solve(&mut store, 100);
        assert_eq!(result, SatResult::Unsat);
    }

    #[test]
    fn test_solve_with_constraint() {
        let mut store = ConstraintStore::new();
        store.set_domain("x", Domain::Range(1, 10));
        store.set_domain("y", Domain::Range(1, 10));

        // x < y
        let c1 = make_constraint(flt(FormulaArg::var("x"), FormulaArg::var("y")), 0, "test");
        store.insert(c1);
        // x = 3
        let c2 = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(3)), 0, "test");
        store.insert(c2);

        let result = solve(&mut store, 100);
        match result {
            SatResult::Sat(model) => {
                let x = model.iter().find(|(k, _)| k == "x").map(|(_, v)| *v);
                let y = model.iter().find(|(k, _)| k == "y").map(|(_, v)| *v);
                assert_eq!(x, Some(3));
                assert!(y.unwrap() > 3);
            }
            _ => panic!("Expected SAT"),
        }
    }
}
