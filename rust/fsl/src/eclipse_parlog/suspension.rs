use std::collections::HashMap;
use super::arithmetic::{Constraint, EvalResult, eval_constraint};
use super::domain::DomainStore;

#[derive(Debug, Clone)]
pub struct SuspensionEntry {
    pub id: usize,
    pub constraint: Constraint,
    pub priority: i32,
    pub watch_vars: Vec<String>,
    pub fired: bool,
}

#[derive(Debug, Clone, Default)]
pub struct SuspensionStore {
    entries: Vec<SuspensionEntry>,
    next_id: usize,
}

impl SuspensionStore {
    pub fn new() -> Self { Self::default() }

    pub fn suspend(&mut self, c: Constraint, priority: i32, watch_vars: Vec<String>) -> usize {
        let id = self.next_id;
        self.next_id += 1;
        self.entries.push(SuspensionEntry {
            id,
            constraint: c,
            priority,
            watch_vars,
            fired: false,
        });
        id
    }

    pub fn wake(&mut self, var: &str, store: &mut DomainStore) -> Vec<usize> {
        let mut fired_ids = Vec::new();
        for entry in &mut self.entries {
            if !entry.fired && entry.watch_vars.iter().any(|v| v == var) {
                match eval_constraint(&entry.constraint, store) {
                    EvalResult::Entailed | EvalResult::Failed => {
                        entry.fired = true;
                        fired_ids.push(entry.id);
                    }
                    EvalResult::Unknown => {}
                }
            }
        }
        fired_ids
    }

    pub fn active_count(&self) -> usize {
        self.entries.iter().filter(|e| !e.fired).count()
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        self.next_id = 0;
    }
}

pub fn suspend_goal(store: &mut SuspensionStore, c: Constraint, priority: i32, watch_vars: Vec<String>) -> usize {
    store.suspend(c, priority, watch_vars)
}

pub fn wake_var(store: &mut SuspensionStore, var: &str, domain_store: &mut DomainStore) -> Vec<usize> {
    store.wake(var, domain_store)
}

pub fn propagate_store(susp_store: &mut SuspensionStore, domain_store: &mut DomainStore) {
    loop {
        let mut any_fired = false;
        let vars: Vec<String> = domain_store.vars().into_iter().map(|s| s.to_string()).collect();
        for var in &vars {
            let fired = susp_store.wake(var, domain_store);
            if !fired.is_empty() {
                any_fired = true;
            }
        }
        if !any_fired { break; }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::domain::Domain;

    #[test]
    fn test_suspend_and_wake() {
        let mut ss = SuspensionStore::new();
        let mut ds = DomainStore::new();
        ds.set_domain("x", Domain::Range(1, 10));

        let id = ss.suspend(Constraint::eq("x", 5), 1, vec!["x".into()]);
        assert_eq!(ss.active_count(), 1);

        ds.set_value("x", 5);
        let fired = ss.wake("x", &mut ds);
        assert!(fired.contains(&id));
        assert_eq!(ss.active_count(), 0);
    }

    #[test]
    fn test_propagate() {
        let mut ss = SuspensionStore::new();
        let mut ds = DomainStore::new();
        ds.set_domain("x", Domain::Range(1, 10));
        ds.set_domain("y", Domain::Range(1, 10));

        ss.suspend(Constraint::eq("x", 3), 1, vec!["x".into()]);
        ss.suspend(Constraint::lt("x", "y"), 2, vec!["x".into(), "y".into()]);

        ds.set_value("x", 3);
        propagate_store(&mut ss, &mut ds);
        // eq(x,3) fires and becomes Entailed; lt(x,y) stays Active (y unknown)
        assert!(ss.active_count() <= 1);
    }
}
