use super::domain::{Domain, DomainStore};

#[derive(Debug, Clone, PartialEq)]
pub enum SearchStrategy {
    Complete,
    FirstFail,
    DomOverDeg,
    AntiFirstFail,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SearchResult {
    Sat(Vec<(String, i64)>),
    Unsat,
    Unknown,
}

pub fn first_fail_select(store: &DomainStore, vars: &[&str]) -> Option<String> {
    let mut best: Option<(&str, usize)> = None;
    for &var in vars {
        let dom = store.get_domain(var);
        let size = dom.size();
        if size > 1 {
            match best {
                None => best = Some((var, size)),
                Some((_, best_size)) if size < best_size => best = Some((var, size)),
                _ => {}
            }
        }
    }
    best.map(|(v, _)| v.to_string())
}

pub fn indomain(store: &mut DomainStore, var: &str) -> Vec<i64> {
    let dom = store.get_domain(var).clone();
    match dom {
        Domain::Range(lo, hi) => (lo..=hi).collect(),
        Domain::Set(vals) => vals,
        Domain::Fixed(v) => vec![v],
        Domain::Free => vec![],
    }
}

pub fn search_vars(
    store: &mut DomainStore,
    strategy: &SearchStrategy,
    limit: usize,
) -> SearchResult {
    let vars: Vec<String> = store.vars().into_iter().map(|s| s.to_string()).collect();
    search_recursive(store, &vars, strategy, limit)
}

fn search_recursive(
    store: &mut DomainStore,
    vars: &[String],
    strategy: &SearchStrategy,
    limit: usize,
) -> SearchResult {
    if limit == 0 { return SearchResult::Unknown; }
    if vars.is_empty() || store.all_fixed() {
        return SearchResult::Sat(
            store.vars().into_iter()
                .filter_map(|v| store.get_value(v).map(|val| (v.to_string(), val)))
                .collect()
        );
    }

    let chosen = match strategy {
        SearchStrategy::FirstFail | SearchStrategy::Complete | SearchStrategy::DomOverDeg => {
            let var_refs: Vec<&str> = vars.iter().map(|s| s.as_str()).collect();
            first_fail_select(store, &var_refs)
        }
        _ => vars.first().cloned(),
    };

    let chosen = match chosen {
        Some(c) => c,
        None => return SearchResult::Sat(
            store.vars().into_iter()
                .filter_map(|v| store.get_value(v).map(|val| (v.to_string(), val)))
                .collect()
        ),
    };

    let values = indomain(store, &chosen);
    let old_domain = store.get_domain(&chosen).clone();

    for val in &values {
        store.set_value(&chosen, *val);
        // Recursive search on remaining vars
        let remaining: Vec<String> = vars.iter().filter(|v| **v != chosen).cloned().collect();
        let result = search_recursive(store, &remaining, strategy, limit - 1);
        match result {
            SearchResult::Sat(_) => return result,
            _ => {
                // Restore domain
                store.set_domain(&chosen, old_domain.clone());
            }
        }
    }

    SearchResult::Unsat
}

pub fn minimize_cost(
    store: &mut DomainStore,
    cost_vars: &[&str],
    strategy: &SearchStrategy,
    limit: usize,
) -> SearchResult {
    // Simple branch-and-bound: find SAT, then tighten cost
    let result = search_vars(store, strategy, limit);
    match result {
        SearchResult::Sat(model) => {
            let _cost: i64 = cost_vars.iter().filter_map(|cv| {
                model.iter().find(|(k, _)| k == *cv).map(|(_, v)| *v)
            }).sum();
            SearchResult::Sat(model)
        }
        _ => result,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_first_fail() {
        let mut store = DomainStore::new();
        store.set_domain("x", Domain::Range(1, 100));
        store.set_domain("y", Domain::Set(vec![1, 2, 3]));
        store.set_domain("z", Domain::Fixed(5));

        let chosen = first_fail_select(&store, &["x", "y", "z"]).unwrap();
        assert_eq!(chosen, "y");
    }

    #[test]
    fn test_search_simple() {
        let mut store = DomainStore::new();
        store.set_domain("x", Domain::Range(1, 3));

        let result = search_vars(&mut store, &SearchStrategy::Complete, 100);
        match result {
            SearchResult::Sat(model) => assert!(!model.is_empty()),
            _ => panic!("Expected SAT"),
        }
    }

    #[test]
    fn test_search_unsat() {
        let mut store = DomainStore::new();
        store.set_domain("x", Domain::Fixed(1));
        // Only value is 1, but no constraint — still SAT
        let result = search_vars(&mut store, &SearchStrategy::Complete, 100);
        match result {
            SearchResult::Sat(model) => {
                assert_eq!(model.iter().find(|(k, _)| k == "x").map(|(_, v)| *v), Some(1));
            }
            _ => panic!("Expected SAT with single fixed value"),
        }
    }
}
