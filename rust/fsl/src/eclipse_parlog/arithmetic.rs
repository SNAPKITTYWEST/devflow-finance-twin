use super::domain::{Domain, DomainStore};

#[derive(Debug, Clone, PartialEq)]
pub enum Constraint {
    Eq(String, i64),
    Neq(String, i64),
    Lt(String, String),
    Le(String, String),
    Gt(String, String),
    Ge(String, String),
    Linear(Vec<(String, i64)>, i64),
    Reified(Box<Constraint>, String),
}

impl Constraint {
    pub fn eq(var: &str, val: i64) -> Self {
        Constraint::Eq(var.to_string(), val)
    }
    pub fn neq(var: &str, val: i64) -> Self {
        Constraint::Neq(var.to_string(), val)
    }
    pub fn lt(a: &str, b: &str) -> Self {
        Constraint::Lt(a.to_string(), b.to_string())
    }
    pub fn le(a: &str, b: &str) -> Self {
        Constraint::Le(a.to_string(), b.to_string())
    }
    pub fn gt(a: &str, b: &str) -> Self {
        Constraint::Gt(a.to_string(), b.to_string())
    }
    pub fn ge(a: &str, b: &str) -> Self {
        Constraint::Ge(a.to_string(), b.to_string())
    }
    pub fn linear(terms: Vec<(String, i64)>, rhs: i64) -> Self {
        Constraint::Linear(terms, rhs)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum EvalResult {
    Entailed,
    Failed,
    Unknown,
}

pub fn eval_constraint(c: &Constraint, store: &DomainStore) -> EvalResult {
    match c {
        Constraint::Eq(var, val) => match store.get_value(var) {
            Some(v) => if v == *val { EvalResult::Entailed } else { EvalResult::Failed },
            None => {
                let dom = store.get_domain(var);
                if !dom.contains(*val) { EvalResult::Failed }
                else { EvalResult::Unknown }
            }
        },
        Constraint::Neq(var, val) => match store.get_value(var) {
            Some(v) => if v != *val { EvalResult::Entailed } else { EvalResult::Failed },
            None => {
                let dom = store.get_domain(var);
                if dom == &Domain::Fixed(*val) { EvalResult::Failed }
                else { EvalResult::Unknown }
            }
        },
        Constraint::Lt(a, b) => {
            let va = store.get_value(a);
            let vb = store.get_value(b);
            match (va, vb) {
                (Some(x), Some(y)) => if x < y { EvalResult::Entailed } else { EvalResult::Failed },
                (Some(x), None) => {
                    let dom_b = store.get_domain(b);
                    match dom_b.min() {
                        Some(m) if x < m => EvalResult::Entailed,
                        Some(m) if x >= m => EvalResult::Unknown,
                        _ => EvalResult::Unknown,
                    }
                }
                _ => EvalResult::Unknown,
            }
        }
        Constraint::Le(a, b) => {
            let va = store.get_value(a);
            let vb = store.get_value(b);
            match (va, vb) {
                (Some(x), Some(y)) => if x <= y { EvalResult::Entailed } else { EvalResult::Failed },
                _ => EvalResult::Unknown,
            }
        }
        Constraint::Gt(a, b) => {
            let va = store.get_value(a);
            let vb = store.get_value(b);
            match (va, vb) {
                (Some(x), Some(y)) => if x > y { EvalResult::Entailed } else { EvalResult::Failed },
                _ => EvalResult::Unknown,
            }
        }
        Constraint::Ge(a, b) => {
            let va = store.get_value(a);
            let vb = store.get_value(b);
            match (va, vb) {
                (Some(x), Some(y)) => if x >= y { EvalResult::Entailed } else { EvalResult::Failed },
                _ => EvalResult::Unknown,
            }
        }
        Constraint::Linear(terms, rhs) => {
            let mut sum: i64 = 0;
            let mut all_ground = true;
            for (var, coeff) in terms {
                match store.get_value(var) {
                    Some(v) => sum += coeff * v,
                    None => all_ground = false,
                }
            }
            if all_ground {
                if sum == *rhs { EvalResult::Entailed } else { EvalResult::Failed }
            } else {
                EvalResult::Unknown
            }
        }
        Constraint::Reified(_, _) => EvalResult::Unknown,
    }
}

pub fn reify_constraint(c: &Constraint, store: &DomainStore) -> i64 {
    match eval_constraint(c, store) {
        EvalResult::Entailed => 1,
        EvalResult::Failed => 0,
        EvalResult::Unknown => -1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_eval_eq() {
        let mut store = DomainStore::new();
        store.set_value("x", 5);
        assert_eq!(eval_constraint(&Constraint::eq("x", 5), &store), EvalResult::Entailed);
        assert_eq!(eval_constraint(&Constraint::eq("x", 3), &store), EvalResult::Failed);
    }

    #[test]
    fn test_eval_lt() {
        let mut store = DomainStore::new();
        store.set_value("x", 3);
        store.set_value("y", 7);
        assert_eq!(eval_constraint(&Constraint::lt("x", "y"), &store), EvalResult::Entailed);
        assert_eq!(eval_constraint(&Constraint::lt("y", "x"), &store), EvalResult::Failed);
    }

    #[test]
    fn test_reify() {
        let mut store = DomainStore::new();
        store.set_value("x", 5);
        assert_eq!(reify_constraint(&Constraint::eq("x", 5), &store), 1);
        assert_eq!(reify_constraint(&Constraint::eq("x", 3), &store), 0);
    }
}
