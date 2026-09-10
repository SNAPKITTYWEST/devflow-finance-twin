use std::collections::{HashMap, HashSet};
use std::time::Instant;
use super::terms::{Atom, Constant, Substitution, Term, Variable};
use super::unify::{unify, apply_subst};
use super::errors::{UnsafeRuleError, EvaluationError};

#[derive(Debug, Clone)]
pub struct Fact {
    pub atom: Atom,
    pub fact_id: String,
    pub source: String,
    pub rule_id: String,
    pub parent_ids: Vec<String>,
    pub depth: usize,
}

impl Fact {
    pub fn new(atom: Atom, source: &str) -> Self {
        let fact_id = fact_id(&atom);
        Fact {
            atom,
            fact_id,
            source: source.to_string(),
            rule_id: String::new(),
            parent_ids: Vec::new(),
            depth: 0,
        }
    }

    pub fn derived(atom: Atom, rule_id: &str, parent_ids: Vec<String>, depth: usize) -> Self {
        let fact_id = fact_id(&atom);
        Fact {
            atom,
            fact_id,
            source: "derived".to_string(),
            rule_id: rule_id.to_string(),
            parent_ids,
            depth,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Rule {
    pub head: Atom,
    pub body: Vec<Atom>,
    pub rule_id: String,
}

impl Rule {
    pub fn new(head: Atom, body: Vec<Atom>, rule_id: &str) -> Self {
        let rid = if rule_id.is_empty() {
            format!("rule_{:08x}", hash_rule(&head, &body))
        } else {
            rule_id.to_string()
        };
        Rule { head, body, rule_id: rid }
    }
}

fn hash_rule(head: &Atom, body: &[Atom]) -> u32 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    head.hash(&mut hasher);
    body.hash(&mut hasher);
    hasher.finish() as u32
}

pub fn fact_id(atom: &Atom) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    atom.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn check_safe(rule: &Rule) -> Result<(), UnsafeRuleError> {
    let head_vars: HashSet<&Variable> = rule.head.variables().into_iter().collect();
    let mut body_vars: HashSet<&Variable> = HashSet::new();
    for lit in &rule.body {
        body_vars.extend(lit.variables());
    }
    let unbound: Vec<&&Variable> = head_vars.difference(&body_vars).collect();
    if !unbound.is_empty() {
        let names: Vec<String> = unbound.iter().map(|v| (**v).0.clone()).collect();
        return Err(UnsafeRuleError {
            message: format!("head variables {} not bound in body", names.join(", ")),
            rule_id: rule.rule_id.clone(),
        });
    }
    Ok(())
}

#[derive(Debug, Clone, Default)]
pub struct EvaluationStats {
    pub iterations: usize,
    pub facts_before: usize,
    pub facts_after: usize,
    pub rules_fired: usize,
    pub derived: usize,
    pub elapsed_ms: f64,
}

pub struct KnowledgeBase {
    pub kb_id: String,
    facts: HashMap<String, Fact>,
    by_pred: HashMap<String, HashSet<String>>,
    rules: HashMap<String, Rule>,
    version: usize,
}

impl KnowledgeBase {
    pub fn new(kb_id: Option<&str>) -> Self {
        KnowledgeBase {
            kb_id: kb_id.unwrap_or("default").to_string(),
            facts: HashMap::new(),
            by_pred: HashMap::new(),
            rules: HashMap::new(),
            version: 0,
        }
    }

    pub fn add_fact(&mut self, atom: Atom, source: &str) -> Fact {
        let f = Fact::new(atom.clone(), source);
        if self.facts.contains_key(&f.fact_id) {
            return self.facts[&f.fact_id].clone();
        }
        self.by_pred.entry(atom.predicate.clone()).or_default().insert(f.fact_id.clone());
        self.facts.insert(f.fact_id.clone(), f.clone());
        self.version += 1;
        f
    }

    pub fn add_fact_str(&mut self, pred: &str, args: &[&str]) -> Fact {
        let atom = Atom::new(pred, args.iter().map(|a| Term::const_(a)).collect());
        self.add_fact(atom, "asserted")
    }

    pub fn add_rule(&mut self, head: Atom, body: Vec<Atom>, rule_id: &str) -> Result<Rule, UnsafeRuleError> {
        let rule = Rule::new(head, body, rule_id);
        check_safe(&rule)?;
        if let Some(existing) = self.rules.get(&rule.rule_id) {
            if existing.head == rule.head && existing.body == rule.body {
                return Ok(existing.clone());
            }
        }
        self.rules.insert(rule.rule_id.clone(), rule.clone());
        self.version += 1;
        Ok(rule)
    }

    pub fn evaluate(&mut self) -> EvaluationStats {
        let t0 = Instant::now();
        let mut stats = EvaluationStats {
            facts_before: self.facts.len(),
            ..Default::default()
        };

        let mut changed = true;
        let mut iteration = 0;

        while changed {
            changed = false;
            iteration += 1;
            let mut new_facts: Vec<Fact> = Vec::new();

            let rule_ids: Vec<String> = self.rules.keys().cloned().collect();
            for rule_id in &rule_ids {
                let rule = self.rules[rule_id].clone();
                for derived in self.apply_rule(&rule) {
                    if !self.facts.contains_key(&derived.fact_id) {
                        new_facts.push(derived);
                        changed = true;
                        stats.rules_fired += 1;
                    }
                }
            }

            new_facts.sort_by(|a, b| a.fact_id.cmp(&b.fact_id));
            for f in new_facts {
                self.by_pred.entry(f.atom.predicate.clone()).or_default().insert(f.fact_id.clone());
                self.facts.insert(f.fact_id.clone(), f);
                stats.derived += 1;
            }

            if iteration > 10_000 {
                return EvaluationStats {
                    iterations: iteration,
                    ..stats
                };
            }
        }

        stats.iterations = iteration;
        stats.facts_after = self.facts.len();
        stats.elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0;
        self.version += 1;
        stats
    }

    fn apply_rule(&self, rule: &Rule) -> Vec<Fact> {
        if rule.body.is_empty() {
            if rule.head.is_ground() {
                return vec![Fact::derived(rule.head.clone(), &rule.rule_id, vec![], 1)];
            }
            return vec![];
        }

        let mut substitutions: Vec<(Substitution, Vec<String>)> = vec![(Substitution::new(), vec![])];

        for lit in &rule.body {
            let mut next_subs: Vec<(Substitution, Vec<String>)> = Vec::new();
            let candidates = self.facts_for(&lit.predicate);

            for (subst, parents) in &substitutions {
                for fact in &candidates {
                    let partial = apply_subst(lit, subst);
                    match unify(&partial, &fact.atom, Some(subst)) {
                        Ok(new_subst) => {
                            let mut new_parents = parents.clone();
                            new_parents.push(fact.fact_id.clone());
                            next_subs.push((new_subst, new_parents));
                        }
                        Err(_) => continue,
                    }
                }
            }
            substitutions = next_subs;
            if substitutions.is_empty() {
                return vec![];
            }
        }

        let mut results = Vec::new();
        let mut seen = HashSet::new();

        for (subst, parents) in substitutions {
            let head_ground = apply_subst(&rule.head, &subst);
            if !head_ground.is_ground() {
                continue;
            }
            let fid = fact_id(&head_ground);
            if seen.contains(&fid) || self.facts.contains_key(&fid) {
                continue;
            }
            seen.insert(fid);
            let depth = 1 + parents.iter()
                .filter_map(|p| self.facts.get(p).map(|f| f.depth))
                .max()
                .unwrap_or(0);
            results.push(Fact::derived(head_ground, &rule.rule_id, parents, depth));
        }

        results
    }

    fn facts_for(&self, predicate: &str) -> Vec<Fact> {
        let ids = self.by_pred.get(predicate).cloned().unwrap_or_default();
        let mut facts: Vec<Fact> = ids.iter()
            .filter_map(|id| self.facts.get(id).cloned())
            .collect();
        facts.sort_by(|a, b| a.fact_id.cmp(&b.fact_id));
        facts
    }

    pub fn has_fact(&self, atom: &Atom) -> bool {
        self.facts.contains_key(&fact_id(atom))
    }

    pub fn facts(&self, predicate: Option<&str>) -> Vec<Fact> {
        match predicate {
            Some(p) => self.facts_for(p),
            None => {
                let mut f: Vec<Fact> = self.facts.values().cloned().collect();
                f.sort_by(|a, b| a.fact_id.cmp(&b.fact_id));
                f
            }
        }
    }

    pub fn rules(&self) -> Vec<Rule> {
        let mut r: Vec<Rule> = self.rules.values().cloned().collect();
        r.sort_by(|a, b| a.rule_id.cmp(&b.rule_id));
        r
    }

    pub fn version(&self) -> usize {
        self.version
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_fact() {
        let mut kb = KnowledgeBase::new(None);
        kb.add_fact_str("role", &["w1", "analyst"]);
        assert!(kb.has_fact(&Atom::new("role", vec![Term::const_("w1"), Term::const_("analyst")])));
    }

    #[test]
    fn test_add_rule_derivation() {
        let mut kb = KnowledgeBase::new(None);
        kb.add_fact_str("role", &["w1", "analyst"]);
        kb.add_fact_str("permitted", &["analyst", "analyze_code"]);

        let head = Atom::new("authorized", vec![Term::var("A"), Term::var("T")]);
        let body = vec![
            Atom::new("role", vec![Term::var("A"), Term::var("R")]),
            Atom::new("permitted", vec![Term::var("R"), Term::var("T")]),
        ];
        kb.add_rule(head, body, "auth").unwrap();
        let stats = kb.evaluate();
        assert!(stats.derived >= 1);
        assert!(kb.has_fact(&Atom::new("authorized", vec![
            Term::const_("w1"), Term::const_("analyze_code")
        ])));
    }

    #[test]
    fn test_unsafe_rule() {
        let mut kb = KnowledgeBase::new(None);
        let head = Atom::new("foo", vec![Term::var("X")]);
        let body = vec![Atom::new("bar", vec![Term::var("Y")])];
        assert!(kb.add_rule(head, body, "").is_err());
    }

    #[test]
    fn test_fixed_point_transitive() {
        let mut kb = KnowledgeBase::new(None);
        kb.add_fact_str("edge", &["a", "b"]);
        kb.add_fact_str("edge", &["b", "c"]);

        let head1 = Atom::new("path", vec![Term::var("X"), Term::var("Y")]);
        kb.add_rule(head1, vec![Atom::new("edge", vec![Term::var("X"), Term::var("Y")])], "base").unwrap();

        let head2 = Atom::new("path", vec![Term::var("X"), Term::var("Z")]);
        let body2 = vec![
            Atom::new("edge", vec![Term::var("X"), Term::var("Y")]),
            Atom::new("path", vec![Term::var("Y"), Term::var("Z")]),
        ];
        kb.add_rule(head2, body2, "step").unwrap();

        kb.evaluate();
        assert!(kb.has_fact(&Atom::new("path", vec![Term::const_("a"), Term::const_("c")])));
    }
}
