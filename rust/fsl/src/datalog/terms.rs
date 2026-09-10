use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Variable(pub String);

impl Variable {
    pub fn new(name: &str) -> Self {
        Variable(name.to_string())
    }

    pub fn is_wildcard(&self) -> bool {
        self.0.starts_with('_')
    }
}

impl fmt::Display for Variable {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Constant(pub String);

impl Constant {
    pub fn new(value: &str) -> Self {
        Constant(value.to_string())
    }
}

impl fmt::Display for Constant {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Term {
    Variable(Variable),
    Constant(Constant),
}

impl Term {
    pub fn var(name: &str) -> Self {
        Term::Variable(Variable::new(name))
    }

    pub fn const_(value: &str) -> Self {
        Term::Constant(Constant::new(value))
    }

    pub fn is_var(&self) -> bool {
        matches!(self, Term::Variable(_))
    }

    pub fn is_const(&self) -> bool {
        matches!(self, Term::Constant(_))
    }

    pub fn as_var(&self) -> Option<&Variable> {
        match self {
            Term::Variable(v) => Some(v),
            _ => None,
        }
    }

    pub fn as_const(&self) -> Option<&Constant> {
        match self {
            Term::Constant(c) => Some(c),
            _ => None,
        }
    }
}

impl fmt::Display for Term {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Term::Variable(v) => write!(f, "{}", v),
            Term::Constant(c) => write!(f, "{}", c),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Atom {
    pub predicate: String,
    pub args: Vec<Term>,
}

impl Atom {
    pub fn new(predicate: &str, args: Vec<Term>) -> Self {
        Atom {
            predicate: predicate.to_string(),
            args,
        }
    }

    pub fn arity(&self) -> usize {
        self.args.len()
    }

    pub fn is_ground(&self) -> bool {
        self.args.iter().all(|a| a.is_const())
    }

    pub fn variables(&self) -> Vec<&Variable> {
        self.args.iter().filter_map(|a| a.as_var()).collect()
    }

    pub fn into_ground(self) -> Option<Self> {
        if self.is_ground() {
            Some(self)
        } else {
            None
        }
    }
}

impl fmt::Display for Atom {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        if self.args.is_empty() {
            write!(f, "{}", self.predicate)
        } else {
            let args: Vec<String> = self.args.iter().map(|a| a.to_string()).collect();
            write!(f, "{}({})", self.predicate, args.join(", "))
        }
    }
}

pub type Substitution = std::collections::HashMap<Variable, Term>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_variable() {
        let v = Variable::new("X");
        assert_eq!(v.to_string(), "X");
        assert!(!v.is_wildcard());
        let w = Variable::new("_Y");
        assert!(w.is_wildcard());
    }

    #[test]
    fn test_atom() {
        let a = Atom::new("role", vec![Term::var("X"), Term::const_("analyst")]);
        assert_eq!(a.arity(), 2);
        assert!(!a.is_ground());
        assert_eq!(a.variables().len(), 1);
    }

    #[test]
    fn test_atom_ground() {
        let a = Atom::new("role", vec![Term::const_("w1"), Term::const_("analyst")]);
        assert!(a.is_ground());
    }
}
