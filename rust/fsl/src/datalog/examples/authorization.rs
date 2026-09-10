#[cfg(test)]
mod tests {
    use crate::datalog::terms::{Atom, Term};
    use crate::datalog::kb::KnowledgeBase;
    use crate::datalog::query::{query, KnowledgeStatus};
    use crate::datalog::parser::parse_program;

    const PROGRAM: &str = r#"
        role(w1, analyst).
        role(w2, admin).
        role(w3, engineer).
        permitted(analyst, analyze_code).
        permitted(analyst, read_logs).
        permitted(admin, manage_users).
        permitted(admin, deploy_code).
        permitted(engineer, write_code).
        permitted(engineer, review_code).
        authorized(A, T) :- role(A, R), permitted(R, T).
    "#;

    fn build_kb() -> KnowledgeBase {
        let parsed = parse_program(PROGRAM).unwrap();
        let mut kb = KnowledgeBase::new(Some("auth"));
        for fact in &parsed.facts {
            kb.add_fact(fact.clone(), "asserted");
        }
        for (head, body, _) in &parsed.rules {
            kb.add_rule(head.clone(), body.clone(), "").unwrap();
        }
        kb
    }

    #[test]
    fn test_authorization_derived() {
        let mut kb = build_kb();
        let q = Atom::new("authorized", vec![Term::const_("w1"), Term::const_("analyze_code")]);
        let result = query(&mut kb, &q);
        assert!(result.is_true());
    }

    #[test]
    fn test_authorization_admin() {
        let mut kb = build_kb();
        let q = Atom::new("authorized", vec![Term::const_("w2"), Term::const_("deploy_code")]);
        let result = query(&mut kb, &q);
        assert!(result.is_true());
    }

    #[test]
    fn test_authorization_unauthorized() {
        let mut kb = build_kb();
        let q = Atom::new("authorized", vec![Term::const_("w3"), Term::const_("manage_users")]);
        let result = query(&mut kb, &q);
        assert!(!result.is_true());
    }

    #[test]
    fn test_authorization_all_engineer_tasks() {
        let mut kb = build_kb();
        let q = Atom::new("authorized", vec![Term::const_("w3"), Term::var("T")]);
        let result = query(&mut kb, &q);
        assert!(result.is_true());
        let tasks: Vec<&str> = result.bindings.iter()
            .filter_map(|b| b.get("T").map(|s| s.as_str()))
            .collect();
        assert!(tasks.contains(&"write_code"));
        assert!(tasks.contains(&"review_code"));
    }

    #[test]
    fn test_rule_safety() {
        let mut kb = build_kb();
        let rules = kb.rules();
        for r in &rules {
            assert!(r.body.is_empty() || {
                let head_vars: std::collections::HashSet<&str> = r.head.variables().iter().map(|v| v.0.as_str()).collect();
                let body_vars: std::collections::HashSet<&str> = r.body.iter()
                    .flat_map(|a| a.variables())
                    .map(|v| v.0.as_str())
                    .collect();
                head_vars.iter().all(|v| body_vars.contains(v))
            });
        }
    }
}
