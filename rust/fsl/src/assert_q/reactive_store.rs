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

use std::sync::{Arc, Mutex, OnceLock};
use super::constraint::{ConstraintStore, Constraint};
use super::propagation::propagate;

pub type WatcherFn = Arc<dyn Fn(&str) + Send + Sync>;

fn global_watchers() -> &'static Mutex<Vec<(String, WatcherFn)>> {
    static INSTANCE: OnceLock<Mutex<Vec<(String, WatcherFn)>>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(Vec::new()))
}

pub fn watch(var: &str, f: impl Fn(&str) + Send + Sync + 'static) {
    global_watchers().lock().unwrap().push((var.to_string(), Arc::new(f)));
}

pub fn clear_watchers() {
    global_watchers().lock().unwrap().clear();
}

#[derive(Debug, Clone)]
pub struct ReactiveStore {
    pub store: ConstraintStore,
}

impl ReactiveStore {
    pub fn new() -> Self {
        ReactiveStore {
            store: ConstraintStore::new(),
        }
    }

    pub fn assert_q(&mut self, c: Constraint) {
        self.store.insert(c);
        propagate(&mut self.store);
        self.notify_watchers();
    }

    pub fn propagate(&mut self) {
        propagate(&mut self.store);
        self.notify_watchers();
    }

    fn notify_watchers(&self) {
        let watchers = global_watchers().lock().unwrap();
        for (var, f) in watchers.iter() {
            if self.store.domains.contains_key(var) {
                f(var);
            }
        }
    }

    pub fn is_sat(&self) -> bool {
        !self.store.any_failed() && self.store.all_entailed_or_failed()
    }

    pub fn is_failed(&self) -> bool {
        self.store.any_failed()
    }

    pub fn model(&self) -> Vec<(String, i64)> {
        super::solver::extract_model(&self.store)
    }
}

impl Default for ReactiveStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::formula::{feq, flt, FormulaArg, domain as f_domain};
    use super::super::constraint::{make_constraint, Domain};
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn test_reactive_store_assert() {
        let mut rs = ReactiveStore::new();
        rs.store.set_domain("x", Domain::Range(1, 10));
        let c = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(5)), 0, "test");
        rs.assert_q(c);
        // Constraint posted and propagation ran (x still in range, not yet solved)
        assert_eq!(rs.store.constraints.len(), 1);
        // Solver should find x=5
        let result = super::super::solver::solve(&mut rs.store, 100);
        assert!(matches!(result, super::super::solver::SatResult::Sat(_)));
    }

    #[test]
    fn test_watcher_fires() {
        clear_watchers();
        let count = Arc::new(AtomicUsize::new(0));
        let c = count.clone();
        watch("x", move |_| {
            c.fetch_add(1, Ordering::SeqCst);
        });

        let mut rs = ReactiveStore::new();
        rs.store.set_domain("x", Domain::Range(1, 10));
        let constr = make_constraint(feq(FormulaArg::var("x"), FormulaArg::num(3)), 0, "test");
        rs.assert_q(constr);

        assert!(count.load(Ordering::SeqCst) > 0);
        clear_watchers();
    }
}
