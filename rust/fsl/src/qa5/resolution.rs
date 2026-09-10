use std::collections::HashSet;
use super::clause::{Clause, Literal, LitArg, Substitution, make_clause};
use super::unification::{unify_args, apply_subst_lit};

pub struct Resolvent {
    pub lits: Vec<Literal>,
    pub parents: Vec<usize>,
    pub subst: Substitution,
}

pub fn resolve(c1: &Clause, c2: &Clause) -> Vec<Resolvent> {
    let mut resolvents = Vec::new();

    for l1 in &c1.lits {
        for l2 in &c2.lits {
            if l1.pred == l2.pred && l1.sign != l2.sign {
                let mut subst = Substitution::new();
                if unify_args(&l1.args, &l2.args, &mut subst) {
                    let remaining1: Vec<&Literal> = c1.lits.iter()
                        .filter(|l| *l != l1)
                        .collect();
                    let remaining2: Vec<&Literal> = c2.lits.iter()
                        .filter(|l| *l != l2)
                        .collect();

                    let mut new_lits: Vec<Literal> = Vec::new();
                    for l in remaining1 {
                        new_lits.push(apply_subst_lit(&subst, l));
                    }
                    for l in remaining2 {
                        new_lits.push(apply_subst_lit(&subst, l));
                    }

                    // Remove duplicates
                    let mut seen = HashSet::new();
                    new_lits.retain(|l| seen.insert(l.clone()));

                    if !tautology_p(&new_lits) {
                        resolvents.push(Resolvent {
                            lits: new_lits,
                            parents: vec![c1.id, c2.id],
                            subst,
                        });
                    }
                }
            }
        }
    }

    resolvents
}

pub fn tautology_p(lits: &[Literal]) -> bool {
    for (i, l1) in lits.iter().enumerate() {
        for l2 in lits.iter().skip(i + 1) {
            if l1.pred == l2.pred
                && l1.sign != l2.sign
                && l1.args == l2.args
            {
                return true;
            }
        }
    }
    false
}

pub fn make_resolvent_clause(r: &Resolvent) -> Clause {
    make_clause(r.lits.clone(), Some(r.parents.clone()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::clause::{Sign, make_clause};

    #[test]
    fn test_resolve_basic() {
        // ~man(x) | mortal(x)  +  man(socrates)
        let c1 = make_clause(
            vec![
                Literal::neg("man", vec![LitArg::Var("x".into())]),
                Literal::pos("mortal", vec![LitArg::Var("x".into())]),
            ],
            None,
        );
        let c2 = make_clause(
            vec![Literal::pos("man", vec![LitArg::Sym("socrates".into())])],
            None,
        );

        let resolvents = resolve(&c1, &c2);
        assert_eq!(resolvents.len(), 1);
        assert_eq!(resolvents[0].lits.len(), 1);
        assert_eq!(resolvents[0].lits[0].pred, "mortal");
    }

    #[test]
    fn test_tautology_detection() {
        let lits = vec![
            Literal::pos("p", vec![]),
            Literal::neg("p", vec![]),
        ];
        assert!(tautology_p(&lits));

        let lits2 = vec![
            Literal::pos("p", vec![]),
            Literal::pos("q", vec![]),
        ];
        assert!(!tautology_p(&lits2));
    }
}
