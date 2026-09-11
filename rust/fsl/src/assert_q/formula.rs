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

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum FormulaOp {
    And,
    Or,
    Not,
    Implies,
    Iff,
    Eq,
    Neq,
    Lt,
    Gt,
    Le,
    Ge,
    Domain,
    In,
    AllDifferent,
    Element,
    Sum,
    Count,
    Forall,
    Exists,
    Atomic,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ConstraintOp {
    Alldifferent,
    Element,
    Sum,
    Count,
}

#[derive(Debug, Clone, PartialEq)]
pub enum FormulaArg {
    Var(String),
    Num(i64),
    Bool(bool),
    List(Vec<FormulaArg>),
    Func(String, Vec<Box<Formula>>),
    Formula(Box<Formula>),
}

impl FormulaArg {
    pub fn var(name: &str) -> Self {
        FormulaArg::Var(name.to_string())
    }

    pub fn num(n: i64) -> Self {
        FormulaArg::Num(n)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Formula {
    pub op: FormulaOp,
    pub args: Vec<FormulaArg>,
}

impl Formula {
    pub fn new(op: FormulaOp, args: Vec<FormulaArg>) -> Self {
        Formula { op, args }
    }
}

// Builder functions (Scallion-style combinators)
pub fn fand(forms: Vec<Formula>) -> Formula {
    Formula::new(FormulaOp::And, forms.into_iter().map(|f| FormulaArg::Formula(Box::new(f))).collect())
}

pub fn for_(forms: Vec<Formula>) -> Formula {
    Formula::new(FormulaOp::Or, forms.into_iter().map(|f| FormulaArg::Formula(Box::new(f))).collect())
}

pub fn fnot(f: Formula) -> Formula {
    Formula::new(FormulaOp::Not, vec![FormulaArg::Formula(Box::new(f))])
}

pub fn implies(a: Formula, b: Formula) -> Formula {
    Formula::new(FormulaOp::Implies, vec![
        FormulaArg::Formula(Box::new(a)),
        FormulaArg::Formula(Box::new(b)),
    ])
}

pub fn iff(a: Formula, b: Formula) -> Formula {
    Formula::new(FormulaOp::Iff, vec![
        FormulaArg::Formula(Box::new(a)),
        FormulaArg::Formula(Box::new(b)),
    ])
}

pub fn feq(a: FormulaArg, b: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Eq, vec![a, b])
}

pub fn fneq(a: FormulaArg, b: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Neq, vec![a, b])
}

pub fn flt(a: FormulaArg, b: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Lt, vec![a, b])
}

pub fn fgt(a: FormulaArg, b: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Gt, vec![a, b])
}

pub fn fle(a: FormulaArg, b: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Le, vec![a, b])
}

pub fn fge(a: FormulaArg, b: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Ge, vec![a, b])
}

pub fn forall(vars: Vec<String>, body: Formula) -> Formula {
    Formula::new(FormulaOp::Forall, vec![
        FormulaArg::List(vars.into_iter().map(FormulaArg::Var).collect()),
        FormulaArg::Formula(Box::new(body)),
    ])
}

pub fn exists(vars: Vec<String>, body: Formula) -> Formula {
    Formula::new(FormulaOp::Exists, vec![
        FormulaArg::List(vars.into_iter().map(FormulaArg::Var).collect()),
        FormulaArg::Formula(Box::new(body)),
    ])
}

pub fn alldifferent(vars: Vec<String>) -> Formula {
    Formula::new(FormulaOp::AllDifferent, vars.into_iter().map(FormulaArg::Var).collect())
}

pub fn domain(var: &str, lo: i64, hi: i64) -> Formula {
    Formula::new(FormulaOp::Domain, vec![
        FormulaArg::Var(var.to_string()),
        FormulaArg::Num(lo),
        FormulaArg::Num(hi),
    ])
}

pub fn fin(var: &str, values: Vec<i64>) -> Formula {
    Formula::new(FormulaOp::In, vec![
        FormulaArg::Var(var.to_string()),
        FormulaArg::List(values.into_iter().map(FormulaArg::Num).collect()),
    ])
}

pub fn sum(vars: Vec<String>, coeffs: Vec<i64>, result: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Sum, vec![
        FormulaArg::List(vars.into_iter().map(FormulaArg::Var).collect()),
        FormulaArg::List(coeffs.into_iter().map(FormulaArg::Num).collect()),
        result,
    ])
}

pub fn count(vars: Vec<String>, val: FormulaArg, result: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Count, vec![
        FormulaArg::List(vars.into_iter().map(FormulaArg::Var).collect()),
        val,
        result,
    ])
}

pub fn element(idx: FormulaArg, vec: Vec<i64>, val: FormulaArg) -> Formula {
    Formula::new(FormulaOp::Element, vec![
        idx,
        FormulaArg::List(vec.into_iter().map(FormulaArg::Num).collect()),
        val,
    ])
}

pub fn pretty(f: &Formula) -> String {
    match f.op {
        FormulaOp::And => {
            let parts: Vec<String> = f.args.iter().map(|a| match a {
                FormulaArg::Formula(sub) => pretty(sub),
                _ => format!("{:?}", a),
            }).collect();
            format!("({})", parts.join(" âˆ§ "))
        }
        FormulaOp::Or => {
            let parts: Vec<String> = f.args.iter().map(|a| match a {
                FormulaArg::Formula(sub) => pretty(sub),
                _ => format!("{:?}", a),
            }).collect();
            format!("({})", parts.join(" âˆ¨ "))
        }
        FormulaOp::Not => {
            if let Some(FormulaArg::Formula(sub)) = f.args.first() {
                format!("Â¬{}", pretty(sub))
            } else {
                format!("Â¬{:?}", f.args)
            }
        }
        FormulaOp::Implies => {
            let a = match f.args.first() {
                Some(FormulaArg::Formula(sub)) => pretty(sub),
                _ => format!("{:?}", f.args.get(0)),
            };
            let b = match f.args.get(1) {
                Some(FormulaArg::Formula(sub)) => pretty(sub),
                _ => format!("{:?}", f.args.get(1)),
            };
            format!("({} â†’ {})", a, b)
        }
        FormulaOp::Eq => format!("{:?} = {:?}", f.args.get(0), f.args.get(1)),
        FormulaOp::AllDifferent => {
            let vars: Vec<String> = f.args.iter().map(|a| match a {
                FormulaArg::Var(v) => v.clone(),
                _ => format!("{:?}", a),
            }).collect();
            format!("alldifferent({})", vars.join(", "))
        }
        _ => format!("{:?}({:?})", f.op, f.args),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_formula_construction() {
        let f = feq(FormulaArg::var("x"), FormulaArg::num(1));
        assert_eq!(f.op, FormulaOp::Eq);
    }

    #[test]
    fn test_pretty_and() {
        let f = fand(vec![
            feq(FormulaArg::var("a"), FormulaArg::num(1)),
            feq(FormulaArg::var("b"), FormulaArg::num(2)),
        ]);
        let p = pretty(&f);
        assert!(p.contains("âˆ§"));
    }

    #[test]
    fn test_pretty_not() {
        let f = fnot(feq(FormulaArg::var("x"), FormulaArg::num(0)));
        let p = pretty(&f);
        assert!(p.contains("Â¬"));
    }
}
