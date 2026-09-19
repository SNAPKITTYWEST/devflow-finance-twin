/*
 * polyglot_builder.rs
 *
 * Unified Rust implementation of polyglot AST builder.
 * Implements fail-closed validation with compile-time safety guarantees.
 * Mirrors C header interface but with Rust idioms (Result, ownership, no unsafe).
 */

use std::collections::{HashMap, HashSet};
use std::fmt;

/* ============================================================
 * ERROR TYPES & CODES (Universal)
 * ============================================================ */

pub const SUCCESS: i32 = 0x00000000;
pub const ERR_INVALID_MAGIC: i32 = 0xE0000001;
pub const ERR_INVALID_VERSION: i32 = 0xE0000002;
pub const ERR_VALIDATION_FAIL: i32 = 0xE0000003;
pub const ERR_UNSAFE_VARIABLE: i32 = 0xE0000004;
pub const ERR_UNDEFINED_PRED: i32 = 0xE0000005;
pub const ERR_NEGATIVE_CYCLE: i32 = 0xE0000006;
pub const ERR_AGGREGATE_INVALID: i32 = 0xE0000007;
pub const ERR_TYPE_MISMATCH: i32 = 0xE0000008;
pub const ERR_BOUNDS_VIOLATED: i32 = 0xE0000009;
pub const ERR_MEMORY_ALLOC: i32 = 0xE000000A;
pub const ERR_SERIALIZATION: i32 = 0xE000000B;
pub const ERR_DESERIALIZATION: i32 = 0xE000000C;
pub const ERR_INTEROP_MISMATCH: i32 = 0xE000000D;

/* ============================================================
 * RESULT TYPE (Fail-Closed Pattern)
 * ============================================================ */

#[derive(Debug, Clone)]
pub struct BinaryError {
    pub code: i32,
    pub message: String,
    pub metadata: u64, // Phase | Recovery | Error count | Warning count
}

impl fmt::Display for BinaryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[0x{:08X}] {}", self.code, self.message)
    }
}

impl std::error::Error for BinaryError {}

pub type BinaryResult<T> = Result<T, BinaryError>;

impl BinaryError {
    pub fn new(code: i32, message: impl Into<String>, metadata: u64) -> Self {
        BinaryError {
            code,
            message: message.into(),
            metadata,
        }
    }

    pub fn phase(&self) -> u8 {
        ((self.metadata >> 56) & 0xFF) as u8
    }

    pub fn is_recoverable(&self) -> bool {
        ((self.metadata >> 48) & 0xFF) != 0
    }

    pub fn error_count(&self) -> u16 {
        ((self.metadata >> 32) & 0xFFFF) as u16
    }

    pub fn warning_count(&self) -> u16 {
        (self.metadata & 0xFFFF) as u16
    }

    fn with_phase(mut self, phase: u8) -> Self {
        self.metadata = (self.metadata & 0x00FFFFFFFFFFFFFF) | ((phase as u64) << 56);
        self
    }

    fn with_recovery(mut self, recoverable: bool) -> Self {
        if recoverable {
            self.metadata |= (1u64 << 48);
        } else {
            self.metadata &= !(1u64 << 48);
        }
        self
    }
}

/* ============================================================
 * AST REPRESENTATION (Simplified)
 * ============================================================ */

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum AstKind {
    Module,
    Routine,
    Block,
    Decl,
    Assign,
    If,
    While,
    For,
    Return,
    Exit,
    ExprStmt,
    Parallel,
    Sync,
    Barrier,
    Label,
    Goto,
    Ident,
    Number,
    Binary,
    Unary,
    Call,
    Index,
    Field,
    Based,
    At,
    Cast,
    Cond,
    BitField,
    MacroInv,
}

#[derive(Debug, Clone)]
pub struct Term {
    pub name: String,
    pub children: Vec<Box<Term>>,
}

#[derive(Debug, Clone)]
pub struct Literal {
    pub positive: bool,
    pub atom: String,
    pub args: Vec<Term>,
}

#[derive(Debug, Clone)]
pub struct Rule {
    pub id: u64,
    pub head: Vec<Literal>,
    pub body: Vec<Literal>,
    pub rule_type: RuleType,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleType {
    Normal,
    Choice,
    Constraint,
    Weak,
    Fact,
}

#[derive(Debug, Clone)]
pub struct ValidatedAST {
    pub kind: AstKind,
    pub predicates: HashSet<String>,
    pub rules: Vec<Rule>,
    pub errors: Vec<BinaryError>,
}

/* ============================================================
 * BUILDER STATE (Internal)
 * ============================================================ */

#[derive(Debug)]
struct BuilderState {
    predicates: HashSet<String>,
    defined_preds: HashSet<String>,
    rules: Vec<Rule>,
    errors: Vec<BinaryError>,
    warnings: Vec<String>,
}

impl BuilderState {
    fn new() -> Self {
        BuilderState {
            predicates: HashSet::new(),
            defined_preds: HashSet::new(),
            rules: Vec::new(),
            errors: Vec::new(),
            warnings: Vec::new(),
        }
    }

    fn add_error(&mut self, error: BinaryError) {
        self.errors.push(error);
    }

    fn add_warning(&mut self, warning: impl Into<String>) {
        self.warnings.push(warning.into());
    }

    fn has_fatal_errors(&self) -> bool {
        self.errors.iter().any(|e| !e.is_recoverable())
    }
}

/* ============================================================
 * BUILDER (Public API)
 * ============================================================ */

pub struct BinaryBuilder {
    state: BuilderState,
    language: LanguageTag,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LanguageTag {
    C,
    Rust,
    Go,
}

impl BinaryBuilder {
    /// Create a new builder for the given language backend.
    pub fn new(language: LanguageTag) -> Self {
        BinaryBuilder {
            state: BuilderState::new(),
            language,
        }
    }

    /// Add a predicate definition (name/arity).
    /// Fluent interface: returns self for chaining.
    pub fn add_predicate(mut self, name: impl Into<String>, arity: i32) -> BinaryResult<Self> {
        let name_str = name.into();

        // Structural validation
        if name_str.is_empty() {
            return Err(BinaryError::new(
                ERR_VALIDATION_FAIL,
                "predicate name cannot be empty",
                0,
            )
            .with_recoverable(true));
        }

        if arity < 0 {
            return Err(BinaryError::new(
                ERR_VALIDATION_FAIL,
                format!("predicate arity cannot be negative: {}", arity),
                0,
            )
            .with_recoverable(true));
        }

        let pred_id = format!("{}/{}", name_str, arity);
        self.state.predicates.insert(pred_id);
        Ok(self)
    }

    /// Add a rule (head :- body).
    /// Fluent interface: accumulates errors but continues.
    pub fn add_rule(mut self, rule: Rule) -> Self {
        // Collect head predicates as defined
        for lit in &rule.head {
            self.state.defined_preds.insert(format!("{}/{}", lit.atom, lit.args.len()));
        }

        // Queue for later semantic validation
        self.state.rules.push(rule);
        self
    }

    /// Add a constraint (:- body).
    pub fn add_constraint(mut self, body: Vec<Literal>) -> Self {
        let constraint = Rule {
            id: u64::MAX, // Special ID for constraints
            head: vec![],
            body,
            rule_type: RuleType::Constraint,
        };
        self.state.rules.push(constraint);
        self
    }

    /// Add a choice rule ({h1; h2} :- body).
    pub fn add_choice_rule(mut self, head: Vec<Literal>, body: Vec<Literal>) -> Self {
        let rule = Rule {
            id: u64::MAX,
            head,
            body,
            rule_type: RuleType::Choice,
        };
        self.state.rules.push(rule);
        self
    }

    /// Complete validation pipeline (fail-closed).
    /// Returns ValidatedAST or first error encountered.
    pub fn finalize(mut self) -> BinaryResult<ValidatedAST> {
        // Phase 1: Structural validation
        if let Err(e) = self.validate_phase_1() {
            return Err(e.with_phase(1));
        }

        // Phase 2: Symbol validation
        if let Err(e) = self.validate_phase_2() {
            return Err(e.with_phase(2));
        }

        // Phase 3: Safety validation
        if let Err(e) = self.validate_phase_3() {
            return Err(e.with_phase(3));
        }

        // Phase 4: Semantics validation
        if let Err(e) = self.validate_phase_4() {
            return Err(e.with_phase(4));
        }

        // Phase 5: Binary validation (trivial for now)
        if let Err(e) = self.validate_phase_5() {
            return Err(e.with_phase(5));
        }

        Ok(ValidatedAST {
            kind: AstKind::Module,
            predicates: self.state.predicates,
            rules: self.state.rules,
            errors: self.state.errors,
        })
    }

    /* ============================================================
     * VALIDATION PHASES (Fail-Closed)
     * ============================================================ */

    fn validate_phase_1(&mut self) -> BinaryResult<()> {
        // Structural: AST kinds, types, basic format
        if self.state.rules.len() > 100_000 {
            return Err(BinaryError::new(
                ERR_MEMORY_ALLOC,
                "rule count exceeds maximum",
                0,
            ));
        }
        Ok(())
    }

    fn validate_phase_2(&mut self) -> BinaryResult<()> {
        // Symbol: predicate definitions, scoping
        for rule in &self.state.rules {
            // Check all body predicates are defined or builtin
            for lit in &rule.body {
                let pred_id = format!("{}/{}", lit.atom, lit.args.len());

                // Builtin check
                if self.is_builtin(&lit.atom) {
                    continue;
                }

                // User-defined check
                if !self.state.defined_preds.contains(&pred_id) {
                    return Err(BinaryError::new(
                        ERR_UNDEFINED_PRED,
                        format!("undefined predicate: {}", pred_id),
                        0,
                    )
                    .with_recoverable(false));
                }
            }
        }
        Ok(())
    }

    fn validate_phase_3(&mut self) -> BinaryResult<()> {
        // Safety: variable safety, type consistency, memory bounds
        for rule in &self.state.rules {
            // Collect head variables
            let mut head_vars: HashSet<String> = HashSet::new();
            for lit in &rule.head {
                self.collect_variables(&lit.args, &mut head_vars);
            }

            // Collect positive body variables
            let mut positive_body_vars: HashSet<String> = HashSet::new();
            for lit in &rule.body {
                if lit.positive {
                    self.collect_variables(&lit.args, &mut positive_body_vars);
                }
            }

            // Check head vars ⊆ positive body vars
            for var in head_vars {
                if var != "_" && !positive_body_vars.contains(&var) {
                    return Err(BinaryError::new(
                        ERR_UNSAFE_VARIABLE,
                        format!("variable '{}' in head not in positive body", var),
                        0,
                    )
                    .with_recoverable(false));
                }
            }
        }
        Ok(())
    }

    fn validate_phase_4(&mut self) -> BinaryResult<()> {
        // Semantics: negative cycles, aggregates, recursion
        if let Err(e) = self.detect_negative_cycles() {
            return Err(e);
        }
        Ok(())
    }

    fn validate_phase_5(&mut self) -> BinaryResult<()> {
        // Binary: hash verification, encoding alignment
        Ok(())
    }

    /* ============================================================
     * VALIDATION PREDICATES (Internal)
     * ============================================================ */

    fn is_builtin(&self, name: &str) -> bool {
        matches!(
            name,
            "=" | "!="
                | "<"
                | ">"
                | "<="
                | ">="
                | "is"
                | "true"
                | "false"
                | "fail"
                | "!"
                | "\\+"
        )
    }

    fn collect_variables(&self, terms: &[Term], vars: &mut HashSet<String>) {
        for term in terms {
            if term.name.chars().next().map_or(false, |c| c.is_uppercase()) {
                vars.insert(term.name.clone());
            }
            self.collect_variables(&term.children, vars);
        }
    }

    fn detect_negative_cycles(&self) -> BinaryResult<()> {
        // Build dependency graph
        let mut graph: HashMap<String, Vec<(String, bool)>> = HashMap::new();

        for rule in &self.state.rules {
            if rule.head.is_empty() {
                continue; // Constraint
            }

            for head_lit in &rule.head {
                let head_pred = format!("{}/{}", head_lit.atom, head_lit.args.len());

                for body_lit in &rule.body {
                    let body_pred = format!("{}/{}", body_lit.atom, body_lit.args.len());
                    graph
                        .entry(head_pred.clone())
                        .or_insert_with(Vec::new)
                        .push((body_pred, body_lit.positive));
                }
            }
        }

        // DFS to detect negative cycles
        let mut visited: HashSet<String> = HashSet::new();
        let mut rec_stack: HashSet<String> = HashSet::new();

        for node in graph.keys() {
            if !visited.contains(node) {
                self.dfs_cycle_detection(node, &graph, &mut visited, &mut rec_stack)?;
            }
        }

        Ok(())
    }

    fn dfs_cycle_detection(
        &self,
        node: &str,
        graph: &HashMap<String, Vec<(String, bool)>>,
        visited: &mut HashSet<String>,
        rec_stack: &mut HashSet<String>,
    ) -> BinaryResult<()> {
        visited.insert(node.to_string());
        rec_stack.insert(node.to_string());

        if let Some(edges) = graph.get(node) {
            for (edge, positive) in edges {
                if !visited.contains(edge) {
                    self.dfs_cycle_detection(edge, graph, visited, rec_stack)?;
                } else if rec_stack.contains(edge) && !positive {
                    // Negative edge in cycle
                    return Err(BinaryError::new(
                        ERR_NEGATIVE_CYCLE,
                        format!("negative cycle detected: {} -> {}", node, edge),
                        0,
                    )
                    .with_recoverable(false));
                }
            }
        }

        rec_stack.remove(node);
        Ok(())
    }

    /* ============================================================
     * INTROSPECTION
     * ============================================================ */

    pub fn error_count(&self) -> u16 {
        self.state.errors.len() as u16
    }

    pub fn get_last_error(&self) -> Option<&BinaryError> {
        self.state.errors.last()
    }

    pub fn get_errors(&self) -> &[BinaryError] {
        &self.state.errors
    }
}

/* ============================================================
 * PUBLIC VALIDATION PREDICATES (Direct Interface)
 * ============================================================ */

pub fn validate_magic_header(magic: u32) -> BinaryResult<()> {
    const MAGIC_TURING: u32 = 0x5455524E; // "TURN"
    if magic != MAGIC_TURING {
        return Err(BinaryError::new(
            ERR_INVALID_MAGIC,
            format!("invalid magic: got 0x{:08X}, want 0x{:08X}", magic, MAGIC_TURING),
            0,
        ));
    }
    Ok(())
}

pub fn validate_version(version: u16) -> BinaryResult<()> {
    const VERSION_CURRENT: u16 = 0x0001;
    if version != VERSION_CURRENT {
        return Err(BinaryError::new(
            ERR_INVALID_VERSION,
            format!(
                "unsupported version: got 0x{:04X}, want 0x{:04X}",
                version, VERSION_CURRENT
            ),
            0,
        ));
    }
    Ok(())
}

pub fn validate_ast_kind(kind: u32) -> BinaryResult<()> {
    const MAX_AST_KIND: u32 = 30;
    if kind > MAX_AST_KIND {
        return Err(BinaryError::new(
            ERR_VALIDATION_FAIL,
            format!("invalid AST kind: {}", kind),
            0,
        ));
    }
    Ok(())
}

pub fn validate_safe_variables(rule: &Rule) -> BinaryResult<()> {
    let mut head_vars: HashSet<String> = HashSet::new();
    for lit in &rule.head {
        collect_term_variables(&lit.args, &mut head_vars);
    }

    let mut positive_body_vars: HashSet<String> = HashSet::new();
    for lit in &rule.body {
        if lit.positive {
            collect_term_variables(&lit.args, &mut positive_body_vars);
        }
    }

    for var in head_vars {
        if var != "_" && !positive_body_vars.contains(&var) {
            return Err(BinaryError::new(
                ERR_UNSAFE_VARIABLE,
                format!("variable '{}' in head not in positive body", var),
                0,
            ));
        }
    }
    Ok(())
}

pub fn validate_type_unification(t1: &Term, t2: &Term) -> BinaryResult<()> {
    // Simplified: just check names match
    if t1.name != t2.name {
        return Err(BinaryError::new(
            ERR_TYPE_MISMATCH,
            format!("type mismatch: {} vs {}", t1.name, t2.name),
            0,
        ));
    }
    Ok(())
}

pub fn validate_sha256(data: &[u8], expected_hash: &[u8; 32]) -> BinaryResult<()> {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(data);
    let hash = hasher.finalize();

    if hash.as_slice() != expected_hash {
        return Err(BinaryError::new(
            ERR_SERIALIZATION,
            "SHA-256 hash mismatch",
            0,
        ));
    }
    Ok(())
}

/* ============================================================
 * HELPER FUNCTIONS
 * ============================================================ */

fn collect_term_variables(terms: &[Term], vars: &mut HashSet<String>) {
    for term in terms {
        if term.name.chars().next().map_or(false, |c| c.is_uppercase()) {
            vars.insert(term.name.clone());
        }
        collect_term_variables(&term.children, vars);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_builder_creation() {
        let builder = BinaryBuilder::new(LanguageTag::Rust);
        assert_eq!(builder.error_count(), 0);
    }

    #[test]
    fn test_add_predicate() {
        let result = BinaryBuilder::new(LanguageTag::Rust)
            .add_predicate("parent", 2)
            .and_then(|b| b.add_predicate("grandparent", 2));
        assert!(result.is_ok());
    }

    #[test]
    fn test_add_predicate_empty_name() {
        let result = BinaryBuilder::new(LanguageTag::Rust).add_predicate("", 2);
        assert!(result.is_err());
    }

    #[test]
    fn test_validate_magic() {
        assert!(validate_magic_header(0x5455524E).is_ok());
        assert!(validate_magic_header(0xDEADBEEF).is_err());
    }

    #[test]
    fn test_validate_version() {
        assert!(validate_version(0x0001).is_ok());
        assert!(validate_version(0x0002).is_err());
    }
}
