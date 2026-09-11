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

use super::domain::{Domain, DomainStore};

pub fn alldifferent(store: &mut DomainStore, vars: &[&str]) -> bool {
    // Check: no two fixed vars have the same value
    let mut fixed: Vec<i64> = Vec::new();
    for var in vars {
        if let Some(v) = store.get_value(var) {
            if fixed.contains(&v) { return false; }
            fixed.push(v);
        }
    }
    true
}

pub fn element(index_var: &str, list: &[i64], result_var: &str, store: &mut DomainStore) -> bool {
    match store.get_value(index_var) {
        Some(idx) => {
            let i = idx as usize;
            if i >= 1 && i <= list.len() {
                let val = list[i - 1];
                match store.get_value(result_var) {
                    Some(v) => v == val,
                    None => {
                        store.set_value(result_var, val);
                        true
                    }
                }
            } else {
                false
            }
        }
        None => true, // index not yet bound
    }
}

pub fn cumulative(
    starts: &[&str],
    durations: &[i64],
    resources: &[i64],
    limit: i64,
    store: &DomainStore,
) -> bool {
    // Check capacity at each time point
    let max_end: i64 = starts.iter().enumerate().map(|(i, s)| {
        let s_val = store.get_value(s).unwrap_or(0);
        s_val + durations[i]
    }).max().unwrap_or(0);

    for t in 0..max_end {
        let mut usage: i64 = 0;
        for (i, s) in starts.iter().enumerate() {
            let s_val = store.get_value(s).unwrap_or(0);
            let e = s_val + durations[i];
            if t >= s_val && t < e {
                usage += resources[i];
            }
        }
        if usage > limit { return false; }
    }
    true
}

pub fn exactly(n: i64, list: &[&str], value: i64, store: &DomainStore) -> bool {
    let count = list.iter().filter(|&&v| {
        store.get_value(v) == Some(value)
    }).count() as i64;
    let unknowns = list.iter().filter(|&&v| store.get_value(v).is_none()).count() as i64;
    // If too many already matched, or not enough can match
    count + unknowns >= n && count <= n
}

pub fn atmost(n: i64, list: &[&str], value: i64, store: &DomainStore) -> bool {
    let count = list.iter().filter(|&&v| {
        store.get_value(v) == Some(value)
    }).count() as i64;
    count <= n
}

pub fn lex_le(l1: &[&str], l2: &[&str], store: &DomainStore) -> bool {
    for (a, b) in l1.iter().zip(l2.iter()) {
        let va = store.get_value(a);
        let vb = store.get_value(b);
        match (va, vb) {
            (Some(x), Some(y)) => {
                if x < y { return true; }
                if x > y { return false; }
                // equal, continue
            }
            _ => return true, // can't determine yet
        }
    }
    l1.len() >= l2.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alldifferent() {
        let mut store = DomainStore::new();
        store.set_value("a", 1);
        store.set_value("b", 2);
        assert!(alldifferent(&mut store, &["a", "b"]));
        store.set_value("c", 2);
        assert!(!alldifferent(&mut store, &["a", "b", "c"]));
    }

    #[test]
    fn test_element() {
        let mut store = DomainStore::new();
        store.set_value("i", 2);
        assert!(element("i", &[10, 20, 30], "x", &mut store));
        assert_eq!(store.get_value("x"), Some(20));
    }

    #[test]
    fn test_exactly() {
        let mut store = DomainStore::new();
        store.set_value("a", 1);
        store.set_value("b", 1);
        assert!(exactly(2, &["a", "b", "c"], 1, &store));
        assert!(exactly(3, &["a", "b", "c"], 1, &store)); // c unknown, can be 1
        assert!(!exactly(4, &["a", "b", "c"], 1, &store)); // impossible
    }
}
