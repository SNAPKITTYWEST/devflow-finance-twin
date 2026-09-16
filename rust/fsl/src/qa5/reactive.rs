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
use std::sync::{Arc, Mutex, OnceLock};

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ReactiveEvent {
    ProofStart,
    GivenClause(usize),
    NewClause(usize),
    ProofSuccess(usize),
    UsableUpdated,
    ChannelEvent(String),
}

pub type ObserverFn = Arc<dyn Fn(&ReactiveEvent) + Send + Sync>;

fn global_observers() -> &'static Mutex<Vec<ObserverFn>> {
    static INSTANCE: OnceLock<Mutex<Vec<ObserverFn>>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(Vec::new()))
}

pub fn add_observer(f: impl Fn(&ReactiveEvent) + Send + Sync + 'static) {
    global_observers().lock().unwrap().push(Arc::new(f));
}

pub fn notify_observers(event: &ReactiveEvent) {
    let observers = global_observers().lock().unwrap();
    for obs in observers.iter() {
        obs(event);
    }
}

pub fn clear_observers() {
    global_observers().lock().unwrap().clear();
}

#[derive(Debug, Clone)]
pub struct ReactiveCell {
    pub name: String,
    value: Vec<usize>,
}

impl ReactiveCell {
    pub fn new(name: &str) -> Self {
        ReactiveCell {
            name: name.to_string(),
            value: Vec::new(),
        }
    }

    pub fn value(&self) -> &[usize] {
        &self.value
    }

    pub fn push(&mut self, v: usize) {
        self.value.push(v);
        notify_observers(&ReactiveEvent::ChannelEvent(
            format!("{}:push:{}", self.name, v)
        ));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn test_observer_notification() {
        clear_observers();
        let count = Arc::new(AtomicUsize::new(0));
        let c = count.clone();
        add_observer(move |_event| {
            c.fetch_add(1, Ordering::SeqCst);
        });

        notify_observers(&ReactiveEvent::ProofStart);
        notify_observers(&ReactiveEvent::NewClause(42));

        assert_eq!(count.load(Ordering::SeqCst), 2);
        clear_observers();
    }

    #[test]
    fn test_reactive_cell() {
        let mut cell = ReactiveCell::new("test");
        cell.push(1);
        cell.push(2);
        assert_eq!(cell.value(), &[1, 2]);
    }
}
