// =============================================================================
// fsl/src/crux/lean_monad_stack.rs  –  Lean 4 Monad Stack Reference Types
// MetaM / TacticM / MacroM / MonadQuotation / Recursive TacticLayer
// Dense ~300 LOC — Rust-side type definitions matching the Lean 4 grammar
// =============================================================================

use crate::crux::ast::*;

// ---------------------------------------------------------------------------
// 1. Monad Hierarchy (Lean 4 stack positions)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MonadLayer {
    CoreM,
    MetaM,
    ElabM,
    TermElabM,
    TacticM,
    CommandElabM,
    MacroM,
    MacroT,
    QuotationM,
    IO,
}

// ---------------------------------------------------------------------------
// 2. MetaM API surface — key operations
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct MVarId(pub u32);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FVarId(pub u32);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BinderInfo {
    Default,
    Implicit,
    StrictImplicit,
    Instance,
    OutParam,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LeanExpr {
    Sort(u32),
    Const(String, Vec<LeanLevel>),
    App(Box<LeanExpr>, Box<LeanExpr>),
    Lambda(String, Box<LeanExpr>, Box<LeanExpr>),
    Pi(String, Box<LeanExpr>, Box<LeanExpr>),
    Let(String, Box<LeanExpr>, Box<LeanExpr>, Box<LeanExpr>),
    MVar(MVarId),
    FVar(FVarId),
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum LeanLevel {
    Zero,
    Succ(Box<LeanLevel>),
    Max(Box<LeanLevel>, Box<LeanLevel>),
    Param(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransparencyMode {
    All,
    Default,
    Reducible,
    Instances,
    None,
}

#[derive(Clone, Debug)]
pub enum LOption<T> {
    None,
    Some(T),
    Undef,
}

#[derive(Clone, Debug, Default)]
pub struct LocalContext {
    pub decl_names: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct MetavarContext {
    pub mvar_count: usize,
}

// ---------------------------------------------------------------------------
// 3. TacticM — state, context, config
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct TacticState {
    pub goals: Vec<MVarId>,
    pub aux_goals: Vec<MVarId>,
}

#[derive(Clone, Debug)]
pub struct TacticContext {
    pub main: Option<MVarId>,
    pub elaborator: String,
    pub recover: bool,
    pub config: TacticConfig,
}

#[derive(Clone, Debug)]
pub struct TacticConfig {
    pub transparent: TransparencyMode,
    pub new_goals: NewGoals,
    pub location: TacticLocation,
}

impl Default for TacticConfig {
    fn default() -> Self {
        Self {
            transparent: TransparencyMode::Default,
            new_goals: NewGoals::GoalsFirst,
            location: TacticLocation::Everywhere,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NewGoals {
    GoalsFirst,
    GoalsLast,
    GoalsIndep,
}

#[derive(Clone, Debug, PartialEq)]
pub enum TacticLocation {
    Everywhere,
    Target,
    Hypotheses,
    Wildcard,
}

// ---------------------------------------------------------------------------
// 4. Lean tactic operations (user-facing enum)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub enum LeanTacticOp {
    GetGoals,
    SetGoals(Vec<MVarId>),
    GetMainGoal,
    GetMainTarget,
    ReplaceMainGoal(Vec<MVarId>),
    Done,
    Intro(String),
    IntroN(usize),
    Intros,
    Apply(LeanExpr),
    Exact(LeanExpr),
    Assumption,
    Cases(LeanExpr),
    Induction(LeanExpr),
    Simp,
    SimpAll,
    Left,
    Right,
    Constructor,
    Exfalso,
    Decide,
    Omega,
    Ring,
    Focus(Box<LeanTacticOp>),
    AllGoals(Box<LeanTacticOp>),
    Try(Box<LeanTacticOp>),
    Repeat(Box<LeanTacticOp>),
    Seq(Vec<LeanTacticOp>),
    Failure,
}

// ---------------------------------------------------------------------------
// 5. MacroM — hygiene engine
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct MacroScope(pub u64);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct HygienicName {
    pub base: String,
    pub scopes: Vec<MacroScope>,
}

// ---------------------------------------------------------------------------
// 6. Recursive goal stack
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct RecGoal {
    pub id: MVarId,
    pub parent: Option<MVarId>,
    pub children: Vec<MVarId>,
    pub layer: usize,
    pub tag: String,
}

#[derive(Clone, Debug, Default)]
pub struct RecTacticState {
    pub root_goals: Vec<RecGoal>,
    pub focus_path: Vec<MVarId>,
    pub depth: usize,
    pub aux: Vec<MVarId>,
}

// ---------------------------------------------------------------------------
// 7. Lean tactic macro definitions (from grammar)
// ---------------------------------------------------------------------------

pub fn lean_tactic_macros() -> Vec<(&'static str, &'static str, &'static str)> {
    vec![
        ("sila_tac", "tactic",
         "withMainContext do let goal <- getMainTarget; let goal' <- liftMetaM (DUP goal); evalTactic (<- `(tactic| DUP <;> sila_auto <;> try omega))"),
        ("crux_tac", "tactic",
         "withFreshMacroScope do `(tactic| sila_tac <;> crux_dup <;> try z3_decide <;> try aesop)"),
        ("dup_at", "tactic",
         "evalTactic (<- `(tactic| DUP at loc))"),
        ("let!", "term",
         "do let x <- mkFreshIdent x; `(let $x := $v; $body)"),
        ("have!", "tactic",
         "withFreshMacroScope do let n <- mkFreshIdent n; `(tactic| have $n : $t := $v)"),
        ("quote_hygienic", "term",
         "do let stx <- Quote.quote t; let stx' <- withFreshMacroScope (quote stx); elabTerm stx'"),
    ]
}

// ---------------------------------------------------------------------------
// 8. MetaM key operations (reference surface)
// ---------------------------------------------------------------------------

pub fn meta_m_operations() -> Vec<(&'static str, &'static str)> {
    vec![
        ("getLCtx", "MetaM LocalContext"),
        ("withLCtx", "LocalContext -> MetaM a -> MetaM a"),
        ("mkFreshExprMVar", "Option Expr -> MetaM Expr"),
        ("assignExprMVar", "MVarId -> Expr -> MetaM Unit"),
        ("isDefEq", "Expr -> Expr -> MetaM Bool"),
        ("whnf", "Expr -> MetaM Expr"),
        ("reduce", "Expr -> MetaM Expr"),
        ("inferType", "Expr -> MetaM Expr"),
        ("synthInstance", "Expr -> MetaM Expr"),
        ("isTypeCorrect", "Expr -> MetaM Bool"),
        ("instantiateMVars", "Expr -> MetaM Expr"),
        ("withMVarContext", "MVarId -> MetaM a -> MetaM a"),
        ("getEnv", "MetaM Environment"),
        ("modifyEnv", "(Environment -> Environment) -> MetaM Unit"),
        ("trace", "Name -> (Unit -> MessageData) -> MetaM Unit"),
        ("throwError", "MessageData -> MetaM a"),
        ("orElse", "MetaM a -> (Unit -> MetaM a) -> MetaM a"),
        ("tryCatch", "MetaM a -> (Exception -> MetaM a) -> MetaM a"),
    ]
}

// ---------------------------------------------------------------------------
// 9. TacticM key operations (reference surface)
// ---------------------------------------------------------------------------

pub fn tactic_m_operations() -> Vec<(&'static str, &'static str)> {
    vec![
        ("getGoals", "TacticM (List MVarId)"),
        ("setGoals", "List MVarId -> TacticM Unit"),
        ("getMainGoal", "TacticM MVarId"),
        ("getMainTarget", "TacticM Expr"),
        ("replaceMainGoal", "List MVarId -> TacticM Unit"),
        ("done", "TacticM Unit"),
        ("intro", "Name -> TacticM Unit"),
        ("intros", "TacticM Unit"),
        ("apply", "Expr -> TacticM Unit"),
        ("exact", "Expr -> TacticM Unit"),
        ("assumption", "TacticM Unit"),
        ("cases", "Expr -> TacticM Unit"),
        ("induction", "Expr -> TacticM Unit"),
        ("simp", "SimpConfig -> List SimpArg -> Location -> TacticM Unit"),
        ("left", "TacticM Unit"),
        ("right", "TacticM Unit"),
        ("constructor", "TacticM Unit"),
        ("exfalso", "TacticM Unit"),
        ("decide", "TacticM Unit"),
        ("omega", "TacticM Unit"),
        ("ring", "TacticM Unit"),
        ("allGoals", "TacticM Unit -> TacticM Unit"),
        ("anyGoals", "TacticM Unit -> TacticM Unit"),
        ("focus", "TacticM a -> TacticM a"),
        ("try", "TacticM a -> TacticM (Option a)"),
        ("repeat'", "TacticM Unit -> TacticM Unit"),
        ("first", "List (TacticM a) -> TacticM a"),
        ("liftMetaM", "MetaM a -> TacticM a"),
        ("liftMetaTactic", "(MVarId -> MetaM (List MVarId)) -> TacticM Unit"),
        ("evalTactic", "Syntax -> TacticM Unit"),
        ("withMainContext", "TacticM a -> TacticM a"),
    ]
}

// ---------------------------------------------------------------------------
// 10. MonadQuotation operations
// ---------------------------------------------------------------------------

pub fn monad_quotation_operations() -> Vec<(&'static str, &'static str)> {
    vec![
        ("getCurrMacroScope", "m MacroScope"),
        ("getMainModule", "m Name"),
        ("withFreshMacroScope", "m a -> m a"),
        ("quote", "Syntax -> m Syntax"),
        ("quoteTerm", "Expr -> m Syntax"),
        ("mkIdent", "Name -> m Syntax"),
        ("mkFreshIdent", "Syntax -> m Syntax"),
        ("withAntiquote", "m a -> m a"),
        ("withRef", "Syntax -> m a -> m a"),
    ]
}

// End of Lean 4 Monad Stack types (~300 lines)
// Covers: Monad hierarchy, MetaM ops, TacticM state/context/config,
// Tactic ops, MacroM hygiene, Recursive goal stack,
// tactic/macro/quotation operation reference tables.
