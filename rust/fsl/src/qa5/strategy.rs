use super::clause::{Clause, Literal};
use super::unification::unify_args;
use super::clause::Substitution;

pub fn unit_clause_p(c: &Clause) -> bool {
    c.lits.len() == 1
}

pub fn pick_clause<'a>(sos: &'a [Clause], _usable: &[Clause]) -> Option<&'a Clause> {
    // Unit preference: prefer unit clauses
    sos.iter().find(|c| unit_clause_p(c))
        .or(sos.first())
}

pub fn subsumes(c1: &Clause, c2: &Clause) -> bool {
    if c1.lits.len() > c2.lits.len() {
        return false;
    }
    c1.lits.iter().all(|l1| {
        c2.lits.iter().any(|l2| lit_matches(l1, l2))
    })
}

fn lit_matches(l1: &Literal, l2: &Literal) -> bool {
    l1.sign == l2.sign && l1.pred == l2.pred && {
        let mut subst = Substitution::new();
        unify_args(&l1.args, &l2.args, &mut subst)
    }
}

pub fn subsumed_by_any(c: &Clause, clauses: &[Clause]) -> bool {
    clauses.iter().any(|e| subsumes(e, c))
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::clause::{LitArg, make_clause};

    #[test]
    fn test_unit_clause() {
        let c = make_clause(vec![Literal::pos("p", vec![])], None);
        assert!(unit_clause_p(&c));

        let c2 = make_clause(vec![
            Literal::pos("p", vec![]),
            Literal::neg("q", vec![]),
        ], None);
        assert!(!unit_clause_p(&c2));
    }

    #[test]
    fn test_pick_clause_prefers_unit() {
        let unit = make_clause(vec![Literal::pos("a", vec![])], None);
        let non_unit = make_clause(vec![
            Literal::pos("b", vec![]),
            Literal::neg("c", vec![]),
        ], None);
        let sos = vec![non_unit.clone(), unit.clone()];

        let picked = pick_clause(&sos, &[]).unwrap();
        assert_eq!(picked.id, unit.id);
    }

    #[test]
    fn test_subsumes() {
        let c1 = make_clause(vec![Literal::pos("p", vec![])], None);
        let c2 = make_clause(vec![
            Literal::pos("p", vec![]),
            Literal::neg("q", vec![]),
        ], None);
        assert!(subsumes(&c1, &c2));
        assert!(!subsumes(&c2, &c1));
    }
}
