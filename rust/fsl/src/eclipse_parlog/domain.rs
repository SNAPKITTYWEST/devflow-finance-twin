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

#[derive(Debug, Clone, PartialEq)]
pub enum Domain {
    Range(i64, i64),
    Set(Vec<i64>),
    Fixed(i64),
    Free,
}

impl Domain {
    pub fn size(&self) -> usize {
        match self {
            Domain::Range(lo, hi) => (*hi - *lo + 1) as usize,
            Domain::Set(vals) => vals.len(),
            Domain::Fixed(_) => 1,
            Domain::Free => 0,
        }
    }

    pub fn contains(&self, val: i64) -> bool {
        match self {
            Domain::Range(lo, hi) => val >= *lo && val <= *hi,
            Domain::Set(vals) => vals.contains(&val),
            Domain::Fixed(v) => *v == val,
            Domain::Free => true,
        }
    }

    pub fn intersect(&self, other: &Domain) -> Option<Domain> {
        match (self, other) {
            (Domain::Range(a_lo, a_hi), Domain::Range(b_lo, b_hi)) => {
                let lo = std::cmp::max(*a_lo, *b_lo);
                let hi = std::cmp::min(*a_hi, *b_hi);
                if lo <= hi { Some(Domain::Range(lo, hi)) } else { None }
            }
            (Domain::Range(lo, hi), Domain::Set(vals)) |
            (Domain::Set(vals), Domain::Range(lo, hi)) => {
                let filtered: Vec<i64> = vals.iter().copied().filter(|v| v >= lo && v <= hi).collect();
                if filtered.is_empty() { None } else { Some(Domain::Set(filtered)) }
            }
            (Domain::Set(a), Domain::Set(b)) => {
                let filtered: Vec<i64> = a.iter().filter(|v| b.contains(v)).copied().collect();
                if filtered.is_empty() { None } else { Some(Domain::Set(filtered)) }
            }
            (Domain::Fixed(v), other) | (other, Domain::Fixed(v)) => {
                if other.contains(*v) { Some(Domain::Fixed(*v)) } else { None }
            }
            _ => None,
        }
    }

    pub fn remove(&self, val: i64) -> Option<Domain> {
        match self {
            Domain::Range(lo, hi) => {
                if val < *lo || val > *hi { return Some(self.clone()); }
                if *lo == *hi { return None; }
                if val == *lo { Some(Domain::Range(lo + 1, *hi)) }
                else if val == *hi { Some(Domain::Range(*lo, hi - 1)) }
                else {
                    // Split into two ranges â€” approximate with set
                    let vals: Vec<i64> = (*lo..=*hi).filter(|v| *v != val).collect();
                    Some(Domain::Set(vals))
                }
            }
            Domain::Set(vals) => {
                let filtered: Vec<i64> = vals.iter().copied().filter(|v| *v != val).collect();
                if filtered.is_empty() { None } else { Some(Domain::Set(filtered)) }
            }
            Domain::Fixed(v) if *v == val => None,
            Domain::Fixed(_) | Domain::Free => Some(self.clone()),
        }
    }

    pub fn min(&self) -> Option<i64> {
        match self {
            Domain::Range(lo, _) => Some(*lo),
            Domain::Set(vals) => vals.iter().copied().min(),
            Domain::Fixed(v) => Some(*v),
            Domain::Free => None,
        }
    }

    pub fn max(&self) -> Option<i64> {
        match self {
            Domain::Range(_, hi) => Some(*hi),
            Domain::Set(vals) => vals.iter().copied().max(),
            Domain::Fixed(v) => Some(*v),
            Domain::Free => None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct DomainStore {
    domains: HashMap<String, Domain>,
    values: HashMap<String, i64>,
}

impl DomainStore {
    pub fn new() -> Self { Self::default() }

    pub fn set_domain(&mut self, var: &str, dom: Domain) {
        if let Domain::Fixed(v) = &dom {
            self.values.insert(var.to_string(), *v);
        }
        self.domains.insert(var.to_string(), dom);
    }

    pub fn get_domain(&self, var: &str) -> &Domain {
        self.domains.get(var).unwrap_or(&Domain::Free)
    }

    pub fn get_value(&self, var: &str) -> Option<i64> {
        self.values.get(var).copied()
    }

    pub fn set_value(&mut self, var: &str, val: i64) {
        self.values.insert(var.to_string(), val);
        self.domains.insert(var.to_string(), Domain::Fixed(val));
    }

    pub fn get_bounds(&self, var: &str) -> (Option<i64>, Option<i64>) {
        let dom = self.get_domain(var);
        (dom.min(), dom.max())
    }

    pub fn vars(&self) -> Vec<&str> {
        self.domains.keys().map(|s| s.as_str()).collect()
    }

    pub fn any_empty(&self) -> bool {
        self.domains.values().any(|d| matches!(d, Domain::Free))
    }

    pub fn all_fixed(&self) -> bool {
        self.domains.values().all(|d| matches!(d, Domain::Fixed(_)))
    }

    pub fn reset_statuses(&mut self) {
        // no-op for DomainStore; constraint statuses live elsewhere
    }
}

pub fn set_domain_decl(store: &mut DomainStore, var: &str, dom: Domain) {
    store.set_domain(var, dom);
}

pub fn get_domain_decl(store: &DomainStore, var: &str) -> Domain {
    store.get_domain(var).clone()
}

pub fn get_bounds(store: &DomainStore, var: &str) -> (Option<i64>, Option<i64>) {
    store.get_bounds(var)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_domain_range() {
        let d = Domain::Range(1, 10);
        assert_eq!(d.size(), 10);
        assert!(d.contains(5));
        assert!(!d.contains(11));
    }

    #[test]
    fn test_domain_intersect() {
        let a = Domain::Range(1, 5);
        let b = Domain::Range(3, 8);
        assert_eq!(a.intersect(&b), Some(Domain::Range(3, 5)));
    }

    #[test]
    fn test_domain_remove() {
        let d = Domain::Range(1, 3);
        assert_eq!(d.remove(2), Some(Domain::Set(vec![1, 3])));
        assert_eq!(d.remove(1), Some(Domain::Range(2, 3)));
        assert_eq!(d.remove(4), Some(Domain::Range(1, 3)));
    }

    #[test]
    fn test_domain_store() {
        let mut store = DomainStore::new();
        store.set_domain("x", Domain::Range(1, 10));
        assert_eq!(store.get_domain("x"), &Domain::Range(1, 10));
        store.set_value("x", 5);
        assert_eq!(store.get_value("x"), Some(5));
        assert_eq!(store.get_domain("x"), &Domain::Fixed(5));
    }
}
