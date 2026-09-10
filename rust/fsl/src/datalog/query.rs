use std::collections::HashMap;
use super::terms::{Atom, Constant, Substitution, Term, Variable};
use super::kb::{KnowledgeBase, Fact, fact_id};
use super::unify::{unify, apply_subst};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KnowledgeStatus {
    True,
    False,
    Unknown,
}

#[derive(Debug, Clone)]
pub struct ProofNode {
    pub atom: String,
    pub fact_id: String,
    pub source: String,
    pub rule_id: String,
    pub children: Vec<ProofNode>,
}

impl ProofNode {
    pub fn to_string_tree(&self) -> String {
        let mut out = format!("{} [{}] ({})", self.atom, self.fact_id, self.source);
        if !self.rule_id.is_empty() {
            out += &format!(" by {}", self.rule_id);
        }
        if !self.children.is_empty() {
            out += " { ";
            for (i, c) in self.children.iter().enumerate() {
                if i > 0 { out += ", "; }
                out += &c.to_string_tree();
            }
            out += " }";
        }
        out
    }
}

#[derive(Debug, Clone)]
pub struct QueryResult {
    pub status: KnowledgeStatus,
    pub bindings: Vec<HashMap<String, String>>,
    pub proofs: Vec<ProofNode>,
    pub supporting_facts: Vec<String>,
    pub supporting_rules: Vec<String>,
    pub query: String,
}

impl QueryResult {
    pub fn is_true(&self) -> bool {
        self.status == KnowledgeStatus::True
    }

    pub fn status_str(&self) -> &'static str {
        match self.status {
            KnowledgeStatus::True => "TRUE",
            KnowledgeStatus::False => "FALSE",
            KnowledgeStatus::Unknown => "UNKNOWN",
        }
    }

    pub fn summary(&self) -> String {
        format!("{}: {} | {} bindings | {} proofs | {} facts | {} rules",
            self.query, self.status_str(),
            self.bindings.len(), self.proofs.len(),
            self.supporting_facts.len(), self.supporting_rules.len())
    }
}

pub fn query(kb: &mut KnowledgeBase, atom: &Atom) -> QueryResult {
    kb.evaluate();
    let qstr = atom.to_string();

    let candidates = kb.facts(Some(&atom.predicate));
    let mut matches: Vec<(Substitution, Fact)> = Vec::new();

    for fact in &candidates {
        if let Ok(subst) = unify(atom, &fact.atom, None) {
            matches.push((subst, fact.clone()));
        }
    }

    if matches.is_empty() {
        return QueryResult {
            status: KnowledgeStatus::Unknown,
            bindings: Vec::new(),
            proofs: Vec::new(),
            supporting_facts: Vec::new(),
            supporting_rules: Vec::new(),
            query: qstr,
        };
    }

    let mut bindings: Vec<HashMap<String, String>> = Vec::new();
    let mut proofs: Vec<ProofNode> = Vec::new();
    let mut fact_ids: Vec<String> = Vec::new();
    let mut rule_ids: std::collections::HashSet<String> = std::collections::HashSet::new();

    for (subst, fact) in &matches {
        let binding: HashMap<String, String> = subst.iter()
            .filter_map(|(v, t)| {
                if let Term::Variable(_) = t {
                    Some((v.0.clone(), t.to_string()))
                } else {
                    Some((v.0.clone(), t.to_string()))
                }
            })
            .collect();
        bindings.push(binding);
        fact_ids.push(fact.fact_id.clone());
        if !fact.rule_id.is_empty() {
            rule_ids.insert(fact.rule_id.clone());
        }
        proofs.push(build_proof(kb, fact));
    }

    // Deduplicate bindings
    let mut seen = std::collections::HashSet::new();
    let mut uniq = Vec::new();
    let mut sorted_bindings = bindings;
    sorted_bindings.sort_by(|a, b| format!("{:?}", a).cmp(&format!("{:?}", b)));
    for b in sorted_bindings {
        let key = format!("{:?}", b);
        if seen.insert(key) {
            uniq.push(b);
        }
    }

    QueryResult {
        status: KnowledgeStatus::True,
        bindings: uniq,
        proofs,
        supporting_facts: {
            let mut v = fact_ids;
            v.sort();
            v.dedup();
            v
        },
        supporting_rules: {
            let mut v: Vec<String> = rule_ids.into_iter().collect();
            v.sort();
            v
        },
        query: qstr,
    }
}

fn build_proof(kb: &KnowledgeBase, fact: &Fact) -> ProofNode {
    let children: Vec<ProofNode> = fact.parent_ids.iter()
        .filter_map(|pid| kb.facts(None).into_iter().find(|f| &f.fact_id == pid))
        .map(|parent| build_proof(kb, &parent))
        .collect();

    ProofNode {
        atom: fact.atom.to_string(),
        fact_id: fact.fact_id.clone(),
        source: fact.source.clone(),
        rule_id: fact.rule_id.clone(),
        children,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_query_true() {
        let mut kb = KnowledgeBase::new(None);
        kb.add_fact_str("role", &["w1", "analyst"]);
        kb.add_fact_str("permitted", &["analyst", "analyze_code"]);

        let head = Atom::new("authorized", vec![Term::var("A"), Term::var("T")]);
        let body = vec![
            Atom::new("role", vec![Term::var("A"), Term::var("R")]),
            Atom::new("permitted", vec![Term::var("R"), Term::var("T")]),
        ];
        kb.add_rule(head, body, "auth").unwrap();

        let result = query(&mut kb, &Atom::new("authorized", vec![
            Term::const_("w1"), Term::const_("analyze_code")
        ]));
        assert_eq!(result.status, KnowledgeStatus::True);
        assert!(!result.proofs.is_empty());
    }

    #[test]
    fn test_query_unknown() {
        let mut kb = KnowledgeBase::new(None);
        kb.add_fact_str("role", &["w1", "analyst"]);

        let result = query(&mut kb, &Atom::new("authorized", vec![
            Term::const_("bob"), Term::const_("task1")
        ]));
        assert_eq!(result.status, KnowledgeStatus::Unknown);
    }

    #[test]
    fn test_query_bindings() {
        let mut kb = KnowledgeBase::new(None);
        kb.add_fact_str("role", &["w1", "analyst"]);
        kb.add_fact_str("permitted", &["analyst", "analyze_code"]);

        let head = Atom::new("authorized", vec![Term::var("A"), Term::var("T")]);
        let body = vec![
            Atom::new("role", vec![Term::var("A"), Term::var("R")]),
            Atom::new("permitted", vec![Term::var("R"), Term::var("T")]),
        ];
        kb.add_rule(head, body, "auth").unwrap();

        let result = query(&mut kb, &Atom::new("authorized", vec![
            Term::var("X"), Term::const_("analyze_code")
        ]));
        assert_eq!(result.status, KnowledgeStatus::True);
        assert!(result.bindings.iter().any(|b| b.get("X") == Some(&"w1".to_string())));
    }
}
