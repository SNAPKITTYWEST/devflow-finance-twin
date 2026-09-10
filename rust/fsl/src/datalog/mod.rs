pub mod terms;
pub mod unify;
pub mod kb;
pub mod query;
pub mod parser;
pub mod errors;
pub mod examples;

pub use terms::{Variable, Constant, Term, Atom};
pub use unify::{unify, apply_subst, UnifyError};
pub use kb::{KnowledgeBase, Fact, Rule, EvaluationStats};
pub use query::{query as query_kb, QueryResult, KnowledgeStatus, ProofNode};
pub use parser::{parse_program, parse_query, ParsedProgram};
pub use errors::{ParseError, UnsafeRuleError, EvaluationError};
