use std::collections::HashMap;
use super::terms::{Atom, Substitution, Term, Variable};

#[derive(Debug, Clone)]
pub struct UnifyError(pub String);

impl std::fmt::Display for UnifyError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "UnifyError: {}", self.0)
    }
}

impl std::error::Error for UnifyError {}

fn resolve(term: &Term, subst: &Substitution) -> Term {
    let mut t = term.clone();
    let mut seen = std::collections::HashSet::new();
    while let Term::Variable(v) = &t {
        if seen.contains(v) { break; }
        seen.insert(v.clone());
        if let Some(val) = subst.get(v) {
            t = val.clone();
        } else {
            break;
        }
    }
    t
}

fn occurs(var: &Variable, term: &Term, subst: &Substitution) -> bool {
    let resolved = resolve(term, subst);
    match &resolved {
        Term::Variable(v) => v == var,
        Term::Constant(_) => false,
    }
}

fn unify_terms(x: &Term, y: &Term, subst: &mut Substitution) -> Result<(), UnifyError> {
    let x = resolve(x, subst);
    let y = resolve(y, subst);

    if x == y {
        return Ok(());
    }

    match (&x, &y) {
        (Term::Variable(v), _) => {
            if occurs(v, &y, subst) {
                return Err(UnifyError(format!("occurs check: {} in {}", v, y)));
            }
            subst.insert(v.clone(), y);
            Ok(())
        }
        (_, Term::Variable(v)) => {
            if occurs(v, &x, subst) {
                return Err(UnifyError(format!("occurs check: {} in {}", v, x)));
            }
            subst.insert(v.clone(), x);
            Ok(())
        }
        (Term::Constant(a), Term::Constant(b)) => {
            if a == b { Ok(()) } else { Err(UnifyError(format!("mismatch: {} vs {}", a, b))) }
        }
    }
}

pub fn unify(a: &Atom, b: &Atom, subst: Option<&Substitution>) -> Result<Substitution, UnifyError> {
    let mut s = subst.cloned().unwrap_or_default();

    if a.predicate != b.predicate || a.arity() != b.arity() {
        return Err(UnifyError(format!("atom mismatch: {} vs {}", a, b)));
    }

    for (xa, xb) in a.args.iter().zip(b.args.iter()) {
        unify_terms(xa, xb, &mut s)?;
    }

    Ok(s)
}

pub fn apply_subst(atom: &Atom, subst: &Substitution) -> Atom {
    let new_args: Vec<Term> = atom.args.iter().map(|a| {
        let mut t = a.clone();
        let mut seen = std::collections::HashSet::new();
        while let Term::Variable(v) = &t {
            if seen.contains(v) { break; }
            seen.insert(v.clone());
            if let Some(val) = subst.get(v) {
                t = val.clone();
            } else {
                break;
            }
        }
        t
    }).collect();

    Atom::new(&atom.predicate, new_args)
}

pub fn unify_terms_pub(x: &Term, y: &Term, subst: &mut Substitution) -> Result<(), UnifyError> {
    unify_terms(x, y, subst)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_unify_var_const() {
        let a = Atom::new("p", vec![Term::var("X"), Term::const_("a")]);
        let b = Atom::new("p", vec![Term::const_("b"), Term::const_("a")]);
        let s = unify(&a, &b, None).unwrap();
        assert_eq!(s.get(&Variable::new("X")), Some(&Term::const_("b")));
    }

    #[test]
    fn test_unify_fail() {
        let a = Atom::new("p", vec![Term::const_("a")]);
        let b = Atom::new("p", vec![Term::const_("b")]);
        assert!(unify(&a, &b, None).is_err());
    }

    #[test]
    fn test_apply_subst() {
        let mut subst = Substitution::new();
        subst.insert(Variable::new("X"), Term::const_("hello"));
        let atom = Atom::new("p", vec![Term::var("X"), Term::var("Y")]);
        let result = apply_subst(&atom, &subst);
        assert_eq!(result.args[0], Term::const_("hello"));
        assert_eq!(result.args[1], Term::var("Y"));
    }
}
