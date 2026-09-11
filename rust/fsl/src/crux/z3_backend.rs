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

// =============================================================================
// fsl/src/crux/z3_backend.rs  â€“  Z3 SMT Query Builder
// Converts CRUX AST â†’ Z3 SMT-LIB queries, checks satisfiability
// Dense ~200 LOC
// =============================================================================

use crate::crux::ast::*;

// ---------------------------------------------------------------------------
// 1. Z3 Solver wrapper
// ---------------------------------------------------------------------------

pub struct Z3Solver {
    pub context: Z3Context,
}

impl Z3Solver {
    pub fn new() -> Self {
        Self { context: Z3Context::default() }
    }

    pub fn build_query(&self, state: &State, formula: &Formula) -> Z3Query {
        let mut commands = Vec::new();
        let mut vars_used = Vec::new();

        collect_vars(formula, &mut vars_used);
        for v in &vars_used {
            commands.push(Z3Command::DeclareConst {
                name: v.clone(),
                sort: Sort::BitVec(32),
            });
        }

        let z3_expr = formula_to_z3(formula);
        commands.push(Z3Command::Assert(z3_expr));
        commands.push(Z3Command::CheckSat);
        commands.push(Z3Command::GetModel);

        Z3Query { context: self.context.clone(), commands }
    }

    pub fn check(&self, query: &Z3Query) -> Z3CheckResult {
        let smt = self.query_to_smtlib(query);

        // For now, do a simple concrete evaluation fallback
        // In production this would call Z3 via FFI or subprocess
        let _ = smt;

        // Fallback: try concrete model
        Z3CheckResult::Unknown
    }

    fn query_to_smtlib(&self, query: &Z3Query) -> String {
        let mut out = String::from("(set-logic QF_BV)\n");

        if let Some(timeout) = query.context.timeout {
            out.push_str(&format!("(set-option :timeout {})\n", timeout));
        }
        if query.context.model {
            out.push_str("(set-option :produce-models true)\n");
        }
        if query.context.unsat_core {
            out.push_str("(set-option :produce-unsat-cores true)\n");
        }

        for cmd in &query.commands {
            match cmd {
                Z3Command::DeclareConst { name, sort } => {
                    out.push_str(&format!("(declare-const {} {})\n", name, sort_to_smt(sort)));
                }
                Z3Command::DeclareFun { name, arg_sorts, ret_sort } => {
                    let args: Vec<_> = arg_sorts.iter().map(sort_to_smt).collect();
                    out.push_str(&format!("(declare-fun {} ({}) {})\n", name, args.join(" "), sort_to_smt(ret_sort)));
                }
                Z3Command::Assert(expr) => {
                    out.push_str(&format!("(assert {})\n", expr_to_smt(expr)));
                }
                Z3Command::CheckSat => { out.push_str("(check-sat)\n"); }
                Z3Command::GetModel => { out.push_str("(get-model)\n"); }
                Z3Command::GetUnsatCore => { out.push_str("(get-unsat-core)\n"); }
                Z3Command::GetProof => { out.push_str("(get-proof)\n"); }
                Z3Command::Push(n) => { out.push_str(&format!("(push {})\n", n)); }
                Z3Command::Pop(n) => { out.push_str(&format!("(pop {})\n", n)); }
                _ => {}
            }
        }
        out
    }
}

// ---------------------------------------------------------------------------
// 2. AST â†’ Z3 conversion
// ---------------------------------------------------------------------------

fn formula_to_z3(f: &Formula) -> Z3Expr {
    match f {
        Formula::Atomic(Atomic::True) => Z3Expr::Const("true".into()),
        Formula::Atomic(Atomic::False) => Z3Expr::Const("false".into()),
        Formula::Not(inner) => Z3Expr::Not(Box::new(formula_to_z3(inner))),
        Formula::And(fs) => Z3Expr::And(fs.iter().map(formula_to_z3).collect()),
        Formula::Or(fs) => Z3Expr::Or(fs.iter().map(formula_to_z3).collect()),
        Formula::Implies(a, b) => {
            Z3Expr::Implies(Box::new(formula_to_z3(a)), Box::new(formula_to_z3(b)))
        }
        Formula::Iff(a, b) => {
            let la = formula_to_z3(a);
            let lb = formula_to_z3(b);
            Z3Expr::And(vec![
                Z3Expr::Implies(Box::new(la.clone()), Box::new(lb.clone())),
                Z3Expr::Implies(Box::new(lb), Box::new(la)),
            ])
        }
        Formula::Eq(a, b) => {
            Z3Expr::Eq(Box::new(term_to_z3(a)), Box::new(term_to_z3(b)))
        }
        Formula::Forall { var, sort, body } => {
            Z3Expr::Forall {
                vars: vec![(var.clone(), sort.clone())],
                body: Box::new(formula_to_z3(body)),
            }
        }
        Formula::Exists { var, sort, body } => {
            Z3Expr::Exists {
                vars: vec![(var.clone(), sort.clone())],
                body: Box::new(formula_to_z3(body)),
            }
        }
        Formula::Paren(inner) => formula_to_z3(inner),
        Formula::Sila { formula, .. } => formula_to_z3(formula),
        Formula::Mu { var, body } | Formula::Nu { var, body } => {
            // Fixed points â†’ unfold as recursive predicate
            Z3Expr::App { func: var.clone(), args: vec![formula_to_z3(body)] }
        }
        _ => Z3Expr::Const("true".into()),
    }
}

fn term_to_z3(t: &Term) -> Z3Expr {
    match t {
        Term::Var(name) => Z3Expr::Const(name.clone()),
        Term::Const(Literal::Number(n)) => {
            Z3Expr::Lit { value: *n, sort: Sort::BitVec(32) }
        }
        Term::Const(Literal::Bool(true)) => Z3Expr::Const("true".into()),
        Term::Const(Literal::Bool(false)) => Z3Expr::Const("false".into()),
        Term::BinOp { op, lhs, rhs } => {
            let l = term_to_z3(lhs);
            let r = term_to_z3(rhs);
            match op {
                BinOp::Add => Z3Expr::BvAdd(Box::new(l), Box::new(r)),
                BinOp::Sub => Z3Expr::BvSub(Box::new(l), Box::new(r)),
                BinOp::Mul => Z3Expr::BvMul(Box::new(l), Box::new(r)),
                BinOp::Eq => Z3Expr::Eq(Box::new(l), Box::new(r)),
                BinOp::Ne => Z3Expr::Distinct(vec![l, r]),
                BinOp::Lt => Z3Expr::Lt(Box::new(l), Box::new(r)),
                BinOp::Le => Z3Expr::Le(Box::new(l), Box::new(r)),
                BinOp::Gt => Z3Expr::Gt(Box::new(l), Box::new(r)),
                BinOp::Ge => Z3Expr::Ge(Box::new(l), Box::new(r)),
                BinOp::Div => Z3Expr::App { func: "bvudiv".into(), args: vec![l, r] },
                BinOp::Mod => Z3Expr::App { func: "bvurem".into(), args: vec![l, r] },
            }
        }
        Term::App(func, arg) => {
            Z3Expr::App {
                func: format!("{:?}", func),
                args: vec![term_to_z3(arg)],
            }
        }
        Term::Paren(inner) => term_to_z3(inner),
        _ => Z3Expr::Const("nil".into()),
    }
}

// ---------------------------------------------------------------------------
// 3. SMT-LIB serialization
// ---------------------------------------------------------------------------

fn sort_to_smt(s: &Sort) -> &'static str {
    match s {
        Sort::Bool => "Bool",
        Sort::Int => "Int",
        Sort::BitVec(32) => "(_ BitVec 32)",
        Sort::BitVec(64) => "(_ BitVec 64)",
        _ => "(_ BitVec 32)",
    }
}

fn expr_to_smt(e: &Z3Expr) -> String {
    match e {
        Z3Expr::Const(name) => name.clone(),
        Z3Expr::Lit { value, sort: Sort::BitVec(w) } => format!("(_ bv{} {})", value, w),
        Z3Expr::Lit { value, .. } => format!("{}", value),
        Z3Expr::And(es) => format!("(and {})", es.iter().map(expr_to_smt).collect::<Vec<_>>().join(" ")),
        Z3Expr::Or(es) => format!("(or {})", es.iter().map(expr_to_smt).collect::<Vec<_>>().join(" ")),
        Z3Expr::Not(e) => format!("(not {})", expr_to_smt(e)),
        Z3Expr::Implies(a, b) => format!("(=> {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::Eq(a, b) => format!("(= {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::Distinct(es) => format!("(distinct {})", es.iter().map(expr_to_smt).collect::<Vec<_>>().join(" ")),
        Z3Expr::Lt(a, b) => format!("(bvult {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::Le(a, b) => format!("(bvule {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::Gt(a, b) => format!("(bvugt {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::Ge(a, b) => format!("(bvuge {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvAdd(a, b) => format!("(bvadd {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvSub(a, b) => format!("(bvsub {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvMul(a, b) => format!("(bvmul {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvAnd(a, b) => format!("(bvand {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvOr(a, b) => format!("(bvor {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvXor(a, b) => format!("(bvxor {} {})", expr_to_smt(a), expr_to_smt(b)),
        Z3Expr::BvNot(a) => format!("(bvnot {})", expr_to_smt(a)),
        Z3Expr::Ite { cond, then, else_ } => {
            format!("(ite {} {} {})", expr_to_smt(cond), expr_to_smt(then), expr_to_smt(else_))
        }
        Z3Expr::App { func, args } => {
            let arg_strs: Vec<_> = args.iter().map(expr_to_smt).collect();
            format!("({} {})", func, arg_strs.join(" "))
        }
        Z3Expr::Select(a, i) => format!("(select {} {})", expr_to_smt(a), expr_to_smt(i)),
        Z3Expr::Store(a, i, v) => format!("(store {} {} {})", expr_to_smt(a), expr_to_smt(i), expr_to_smt(v)),
        Z3Expr::Forall { vars, body } => {
            let bindings: Vec<_> = vars.iter()
                .map(|(n, s)| format!("({} {})", n, sort_to_smt(s)))
                .collect();
            format!("(forall ({}) {})", bindings.join(" "), expr_to_smt(body))
        }
        Z3Expr::Exists { vars, body } => {
            let bindings: Vec<_> = vars.iter()
                .map(|(n, s)| format!("({} {})", n, sort_to_smt(s)))
                .collect();
            format!("(exists ({}) {})", bindings.join(" "), expr_to_smt(body))
        }
    }
}

// ---------------------------------------------------------------------------
// 4. Variable collection
// ---------------------------------------------------------------------------

fn collect_vars(f: &Formula, vars: &mut Vec<Ident>) {
    match f {
        Formula::Atomic(Atomic::Predicate { args, .. }) => {
            for a in args { collect_term_vars(a, vars); }
        }
        Formula::Not(inner) => collect_vars(inner, vars),
        Formula::And(fs) | Formula::Or(fs) => {
            for f in fs { collect_vars(f, vars); }
        }
        Formula::Implies(a, b) => {
            collect_vars(a, vars);
            collect_vars(b, vars);
        }
        Formula::Iff(a, b) => {
            collect_vars(a, vars);
            collect_vars(b, vars);
        }
        Formula::Eq(a, b) => {
            collect_term_vars(a, vars);
            collect_term_vars(b, vars);
        }
        Formula::Forall { var, .. } | Formula::Exists { var, .. }
        | Formula::Mu { var, .. } | Formula::Nu { var, .. } => {
            vars.push(var.clone());
        }
        Formula::Sila { formula, .. } => collect_vars(formula, vars),
        Formula::Paren(inner) => collect_vars(inner, vars),
        _ => {}
    }
}

fn collect_term_vars(t: &Term, vars: &mut Vec<Ident>) {
    match t {
        Term::Var(name) => {
            if !vars.contains(name) { vars.push(name.clone()); }
        }
        Term::BinOp { lhs, rhs, .. } => {
            collect_term_vars(lhs, vars);
            collect_term_vars(rhs, vars);
        }
        Term::App(func, arg) => {
            collect_term_vars(func, vars);
            collect_term_vars(arg, vars);
        }
        Term::Paren(inner) => collect_term_vars(inner, vars),
        _ => {}
    }
}

// ---------------------------------------------------------------------------
// 5. Z3 Check result
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum Z3CheckResult {
    Sat,
    Unsat,
    Model(Vec<(Ident, Term)>),
    Unknown,
    Timeout,
}

// End of Z3 SMT backend (~200 lines)
// Covers: query building, SMT-LIB serialization, variable collection,
// formula/term â†’ Z3Expr conversion, check result types.
