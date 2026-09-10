use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use super::formula::Formula;

static CONSTRAINT_COUNTER: AtomicUsize = AtomicUsize::new(1);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConstraintStatus {
    Posted,
    Active,
    Entailed,
    Failed,
}

#[derive(Debug, Clone)]
pub struct Constraint {
    pub id: usize,
    pub form: Formula,
    pub status: ConstraintStatus,
    pub priority: i32,
    pub origin: String,
}

pub fn make_constraint(form: Formula, priority: i32, origin: &str) -> Constraint {
    let id = CONSTRAINT_COUNTER.fetch_add(1, Ordering::SeqCst);
    Constraint {
        id,
        form,
        status: ConstraintStatus::Posted,
        priority,
        origin: origin.to_string(),
    }
}

#[derive(Debug, Clone)]
pub struct ConstraintStore {
    pub constraints: HashMap<usize, Constraint>,
    pub domains: HashMap<String, Domain>,
    pub model: HashMap<String, i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Domain {
    Range(i64, i64),
    Set(Vec<i64>),
    Fixed(i64),
}

impl ConstraintStore {
    pub fn new() -> Self {
        ConstraintStore {
            constraints: HashMap::new(),
            domains: HashMap::new(),
            model: HashMap::new(),
        }
    }

    pub fn insert(&mut self, c: Constraint) {
        self.constraints.insert(c.id, c);
    }

    pub fn set_domain(&mut self, var: &str, dom: Domain) {
        if let Domain::Fixed(v) = &dom {
            self.model.insert(var.to_string(), *v);
        }
        self.domains.insert(var.to_string(), dom);
    }

    pub fn get_domain(&self, var: &str) -> Option<&Domain> {
        self.domains.get(var)
    }

    pub fn set_value(&mut self, var: &str, val: i64) {
        self.domains.insert(var.to_string(), Domain::Fixed(val));
        self.model.insert(var.to_string(), val);
    }

    pub fn get_value(&self, var: &str) -> Option<i64> {
        match self.domains.get(var)? {
            Domain::Fixed(v) => Some(*v),
            _ => self.model.get(var).copied(),
        }
    }

    pub fn any_failed(&self) -> bool {
        self.constraints.values().any(|c| c.status == ConstraintStatus::Failed)
    }

    pub fn all_entailed_or_failed(&self) -> bool {
        self.constraints.values().all(|c| {
            c.status == ConstraintStatus::Entailed || c.status == ConstraintStatus::Failed
        })
    }

    pub fn reset(&mut self) {
        self.constraints.clear();
        self.domains.clear();
        self.model.clear();
        CONSTRAINT_COUNTER.store(1, Ordering::SeqCst);
    }

    pub fn reset_statuses(&mut self) {
        for c in self.constraints.values_mut() {
            if c.status != ConstraintStatus::Posted {
                c.status = ConstraintStatus::Active;
            }
        }
    }
}

impl Default for ConstraintStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::formula::{feq, FormulaArg};

    #[test]
    fn test_store_insert() {
        let mut store = ConstraintStore::new();
        let c = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(1)), 0, "test");
        store.insert(c);
        assert_eq!(store.constraints.len(), 1);
    }

    #[test]
    fn test_domain_fixed() {
        let mut store = ConstraintStore::new();
        store.set_domain("x", Domain::Fixed(5));
        assert_eq!(store.get_value("x"), Some(5));
    }

    #[test]
    fn test_any_failed() {
        let mut store = ConstraintStore::new();
        let mut c = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(1)), 0, "test");
        c.status = ConstraintStatus::Failed;
        store.insert(c);
        assert!(store.any_failed());
    }
}
