// =============================================================================
// fsl/src/crux/ast.rs  –  CRUX Core AST Types
// Formula, Term, Sort, State, Backend, Proof Closure
// Dense ~350 LOC
// =============================================================================

use std::fmt;

// ---------------------------------------------------------------------------
// 1. Identifiers & Literals
// ---------------------------------------------------------------------------

pub type Ident = String;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Literal {
    Number(i64),
    Str(String),
    Bool(bool),
    BitVecLit { value: u64, width: u32 },
    Nil,
    Unit,
}

// ---------------------------------------------------------------------------
// 2. Sorts (types / kinds)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Sort {
    Prop,
    Type,
    Nat,
    Int,
    Bool,
    BitVec(u32),
    List(Box<Sort>),
    Array(Box<Sort>, Box<Sort>),
    Arrow(Box<Sort>, Box<Sort>),
    State,
    Formula,
    Term,
    MIR,
    Core,
    Haskell,
    Rust,
    Z3Expr,
    LeanTerm,
    SASAbs,
    User(Ident),
}

impl fmt::Display for Sort {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Sort::Prop => write!(f, "Prop"),
            Sort::Type => write!(f, "Type"),
            Sort::Nat => write!(f, "Nat"),
            Sort::Int => write!(f, "Int"),
            Sort::Bool => write!(f, "Bool"),
            Sort::BitVec(w) => write!(f, "BitVec {}", w),
            Sort::List(s) => write!(f, "List {}", s),
            Sort::Array(k, v) => write!(f, "Array {} {}", k, v),
            Sort::Arrow(a, b) => write!(f, "{} → {}", a, b),
            Sort::State => write!(f, "State"),
            Sort::Formula => write!(f, "Formula"),
            Sort::Term => write!(f, "Term"),
            Sort::MIR => write!(f, "MIR"),
            Sort::Core => write!(f, "Core"),
            Sort::Haskell => write!(f, "Haskell"),
            Sort::Rust => write!(f, "Rust"),
            Sort::Z3Expr => write!(f, "Z3Expr"),
            Sort::LeanTerm => write!(f, "LeanTerm"),
            Sort::SASAbs => write!(f, "SASAbs"),
            Sort::User(id) => write!(f, "{}", id),
        }
    }
}

// ---------------------------------------------------------------------------
// 3. Terms
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum Term {
    Var(Ident),
    Const(Literal),
    Lambda { param: Ident, sort: Sort, body: Box<Term> },
    App(Box<Term>, Box<Term>),
    BinOp { op: BinOp, lhs: Box<Term>, rhs: Box<Term> },
    Cons(Box<Term>, Box<Term>),
    Nil,
    Concat(Box<Term>, Box<Term>),
    IfThenElse { cond: Box<Formula>, then: Box<Term>, else_: Box<Term> },
    Match { scrutinee: Box<Term>, arms: Vec<MatchArm> },
    Fold { init: Box<Term>, step: Box<Term> },
    Rec { name: Ident, body: Box<Term> },
    Tuple(Vec<Term>),
    Field(Box<Term>, Ident),
    Paren(Box<Term>),
}

#[derive(Clone, Debug, PartialEq)]
pub struct MatchArm {
    pub pattern: Pattern,
    pub body: Term,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Pattern {
    Var(Ident),
    Const(Literal),
    Wildcard,
    Cons(Box<Pattern>, Box<Pattern>),
    Tuple(Vec<Pattern>),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BinOp {
    Add, Sub, Mul, Div, Mod,
    Eq, Ne, Lt, Le, Gt, Ge,
}

// ---------------------------------------------------------------------------
// 4. Formulas
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum Formula {
    Atomic(Atomic),
    Not(Box<Formula>),
    And(Vec<Formula>),
    Or(Vec<Formula>),
    Implies(Box<Formula>, Box<Formula>),
    Iff(Box<Formula>, Box<Formula>),
    Forall { var: Ident, sort: Sort, body: Box<Formula> },
    Exists { var: Ident, sort: Sort, body: Box<Formula> },
    Mu { var: Ident, body: Box<Formula> },
    Nu { var: Ident, body: Box<Formula> },
    Eq(Term, Term),
    Sila { state: State, formula: Box<Formula> },
    Paren(Box<Formula>),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Atomic {
    Predicate { name: Ident, args: Vec<Term> },
    Member { elem: Box<Term>, set: Box<Term> },
    Predecessor { less: Box<Term>, greater: Box<Term> },
    True,
    False,
}

// ---------------------------------------------------------------------------
// 5. States (Recursive State IR)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum State {
    S,
    S0,
    Sn(u32),
    Prime(Box<State>),
    Update { base: Box<State>, var: Ident, value: Term },
    Bind { base: Box<State>, binding: Binding },
    Recursive { var: Ident, body: Box<Formula> },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Binding {
    pub var: Ident,
    pub value: Term,
    pub kind: BindingKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindingKind {
    Assign,
    Arrow,
    Let,
}

// ---------------------------------------------------------------------------
// 6. Backends
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum Backend {
    GHC(GHCIR),
    Kani(KaniMIR),
}

#[derive(Clone, Debug, PartialEq)]
pub struct GHCIR {
    pub module_name: Ident,
    pub decls: Vec<GHCDecl>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum GHCDecl {
    Data { name: Ident, constructors: Vec<GHCConstructor> },
    Type { name: Ident, target: Sort },
    Function { name: Ident, sort: Sort, body: Term },
}

#[derive(Clone, Debug, PartialEq)]
pub struct GHCConstructor {
    pub name: Ident,
    pub arg_sorts: Vec<Sort>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct KaniMIR {
    pub name: Ident,
    pub params: Vec<(Ident, Sort)>,
    pub return_sort: Sort,
    pub body: Vec<MIRStatement>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MIRStatement {
    Let { name: Ident, value: Term },
    AssertEq { lhs: Term, rhs: Term },
    Assert { cond: Formula },
    Expr(Term),
    Return(Term),
    IfThenElse { cond: Formula, then: Vec<MIRStatement>, else_: Vec<MIRStatement> },
    Loop(Vec<MIRStatement>),
    Match { scrutinee: Term, arms: Vec<MIRMatchArm> },
    Unsafe(Vec<MIRStatement>),
    KaniProof(Vec<MIRStatement>),
    KaniUnwind(u32),
}

#[derive(Clone, Debug, PartialEq)]
pub struct MIRMatchArm {
    pub pattern: Pattern,
    pub body: Vec<MIRStatement>,
}

// ---------------------------------------------------------------------------
// 7. OMEGA SMASHER
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum OmegaTarget {
    Z3(Z3Query),
    SAS(SASQuery),
    Lean(LeanGoal),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Z3Query {
    pub context: Z3Context,
    pub commands: Vec<Z3Command>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Z3Context {
    pub timeout: Option<u32>,
    pub model: bool,
    pub unsat_core: bool,
    pub proof: bool,
}

impl Default for Z3Context {
    fn default() -> Self {
        Self { timeout: None, model: true, unsat_core: false, proof: false }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Z3Command {
    DeclareConst { name: Ident, sort: Sort },
    DeclareFun { name: Ident, arg_sorts: Vec<Sort>, ret_sort: Sort },
    DefineFun { name: Ident, params: Vec<(Ident, Sort)>, sort: Sort, body: Z3Expr },
    Assert(Z3Expr),
    AssertAndTrack { expr: Z3Expr, label: Ident },
    CheckSat,
    GetModel,
    GetUnsatCore,
    GetProof,
    Push(u32),
    Pop(u32),
    Tactic(Z3Tactic),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Z3Expr {
    Const(Ident),
    Lit { value: i64, sort: Sort },
    App { func: Ident, args: Vec<Z3Expr> },
    And(Vec<Z3Expr>),
    Or(Vec<Z3Expr>),
    Not(Box<Z3Expr>),
    Implies(Box<Z3Expr>, Box<Z3Expr>),
    Ite { cond: Box<Z3Expr>, then: Box<Z3Expr>, else_: Box<Z3Expr> },
    Eq(Box<Z3Expr>, Box<Z3Expr>),
    Distinct(Vec<Z3Expr>),
    Lt(Box<Z3Expr>, Box<Z3Expr>),
    Le(Box<Z3Expr>, Box<Z3Expr>),
    Gt(Box<Z3Expr>, Box<Z3Expr>),
    Ge(Box<Z3Expr>, Box<Z3Expr>),
    BvAdd(Box<Z3Expr>, Box<Z3Expr>),
    BvSub(Box<Z3Expr>, Box<Z3Expr>),
    BvMul(Box<Z3Expr>, Box<Z3Expr>),
    BvAnd(Box<Z3Expr>, Box<Z3Expr>),
    BvOr(Box<Z3Expr>, Box<Z3Expr>),
    BvXor(Box<Z3Expr>, Box<Z3Expr>),
    BvNot(Box<Z3Expr>),
    Select(Box<Z3Expr>, Box<Z3Expr>),
    Store(Box<Z3Expr>, Box<Z3Expr>, Box<Z3Expr>),
    Forall { vars: Vec<(Ident, Sort)>, body: Box<Z3Expr> },
    Exists { vars: Vec<(Ident, Sort)>, body: Box<Z3Expr> },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Z3Tactic {
    pub name: Ident,
    pub params: Vec<(Ident, Z3ParamValue)>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Z3ParamValue {
    Str(String),
    Num(u32),
    Bool(bool),
}

// ---------------------------------------------------------------------------
// 8. SAS (Symbolic Abstract Semantics)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub struct SASQuery {
    pub config: SASConfig,
    pub state: SASState,
    pub property: SASProperty,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SASConfig {
    pub domain: AbsDomain,
    pub widening: Widening,
    pub narrowing: u32,
    pub threshold: u32,
    pub loop_bound: u32,
    pub track_pointers: bool,
    pub track_arrays: bool,
    pub relational: bool,
}

impl Default for SASConfig {
    fn default() -> Self {
        Self {
            domain: AbsDomain::Intervals,
            widening: Widening::Standard,
            narrowing: 1,
            threshold: 16,
            loop_bound: 10,
            track_pointers: true,
            track_arrays: false,
            relational: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum AbsDomain {
    Intervals,
    Octagons,
    Polyhedra,
    Zones,
    Congruences,
    Signs,
    Constants,
    Predicate,
    Shape,
    Heap,
    Combined(Box<AbsDomain>, Box<AbsDomain>),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Widening {
    Standard,
    Delayed(u32),
    Threshold,
    Localized,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SASState {
    pub bindings: Vec<(Ident, AbsVal)>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum AbsVal {
    Interval { low: i64, high: i64 },
    Top,
    Bottom,
    Join(Box<AbsVal>, Box<AbsVal>),
    Meet(Box<AbsVal>, Box<AbsVal>),
    PointsTo(Ident),
    Null,
    Dangling,
}

#[derive(Clone, Debug, PartialEq)]
pub enum SASProperty {
    Safe(Formula),
    Reach(Formula),
    Invariant(Formula),
    Assertion(Formula),
    Termination,
    NonTermination,
}

// ---------------------------------------------------------------------------
// 9. Lean 4 Goal
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub struct LeanGoal {
    pub kind: LeanGoalKind,
    pub name: Ident,
    pub formula: Formula,
    pub tactics: Vec<LeanTactic>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LeanGoalKind {
    Theorem,
    Lemma,
    Example,
}

#[derive(Clone, Debug, PartialEq)]
pub enum LeanTactic {
    Exact(Term),
    Apply(Term),
    Refine(Term),
    Intro(Vec<Ident>),
    Cases(Term),
    Induction(Term),
    Simpl(Vec<SimpArg>),
    SimplAll,
    Rewrite(Vec<RwArg>),
    Ring,
    Linarith,
    Nlinarith,
    Omega,
    Decide,
    NativeDecide,
    Aesop,
    Trivial,
    Constructor,
    Left,
    Right,
    Exfalso,
    Have { name: Ident, formula: Formula, proof: Box<LeanTactic> },
    LetBind { name: Ident, value: Term },
    ByCases { name: Ident, cond: Formula },
    Macro(Ident),
    Focus(Vec<LeanTactic>),
    Seq(Vec<LeanTactic>),
    Try(Box<LeanTactic>),
    Repeat(Box<LeanTactic>),
    AllGoals(Box<LeanTactic>),
    Sorry,
}

#[derive(Clone, Debug, PartialEq)]
pub enum SimpArg {
    Term(Term),
    Neg(Term),
    Star,
}

#[derive(Clone, Debug, PartialEq)]
pub enum RwArg {
    Term(Term),
    Rev(Term),
}

// ---------------------------------------------------------------------------
// 10. Proof Closure
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub struct ProofClosure {
    pub obligations: Vec<Obligation>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Obligation {
    pub id: u32,
    pub formula: Formula,
    pub discharged_by: DischargeMethod,
}

#[derive(Clone, Debug, PartialEq)]
pub enum DischargeMethod {
    Z3Check,
    SASProve,
    LeanTactic(LeanTactic),
    CruxClose,
    Assumption(Ident),
}

// ---------------------------------------------------------------------------
// 11. Final Result
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum FinalResult {
    Sat,
    Unsat,
    Model(Vec<(Ident, Term)>),
    Unknown,
    Timeout,
    Alarm { location: Ident, formula: Formula },
    Proved,
}

impl fmt::Display for FinalResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FinalResult::Sat => write!(f, "SAT"),
            FinalResult::Unsat => write!(f, "UNSAT"),
            FinalResult::Model(bindings) => {
                write!(f, "MODEL{{ ")?;
                for (i, (name, val)) in bindings.iter().enumerate() {
                    if i > 0 { write!(f, ", ")?; }
                    write!(f, "{:?} ↦ {:?}", name, val)?;
                }
                write!(f, " }}")
            }
            FinalResult::Unknown => write!(f, "UNKNOWN"),
            FinalResult::Timeout => write!(f, "TIMEOUT"),
            FinalResult::Alarm { location, formula } => {
                write!(f, "ALARM at {}: {:?}", location, formula)
            }
            FinalResult::Proved => write!(f, "PROVED"),
        }
    }
}

// ---------------------------------------------------------------------------
// 12. Russian Forms (parsed but lowered to AST above)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum RussianForm {
    Ravnostvo(Term, Term),       // равенство(A, B)
    Implikatsiya(Formula, Formula), // импликация(A, B)
    Konyunktsiya(Formula, Formula), // конъюнкция(A, B)
    Dizyunktsiya(Formula, Formula), // дизъюнкция(A, B)
    Otritsanie(Formula),          // отрицание(A)
    DlyaVsekh(Ident, Sort, Formula), // для_всех x : S. P
    Sushchestvuet(Ident, Sort, Formula), // существует x : S. P
    Rekursiya(Ident, Formula),    // рекурсия x. P
    Sostoyanie(State),            // состояние S
    Sila(State, Formula),         // сила(S, P)
    Omega(Backend, State, Formula), // омега(B, S, P)
    Dokazatelstvo(ProofClosure),  // доказательство PC
}

// End of CRUX AST types (~350 lines)
// Covers: sorts, terms, formulas, states, backends (GHC/Kani),
// Z3 SMT, SAS abstract, Lean 4 tactics, proof closure, final results.
