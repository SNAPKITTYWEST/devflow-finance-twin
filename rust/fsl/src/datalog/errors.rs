use std::fmt;

#[derive(Debug, Clone)]
pub struct ParseError(pub String);

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "ParseError: {}", self.0)
    }
}

impl std::error::Error for ParseError {}

#[derive(Debug, Clone)]
pub struct UnsafeRuleError {
    pub message: String,
    pub rule_id: String,
}

impl fmt::Display for UnsafeRuleError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "UnsafeRuleError [{}]: {}", self.rule_id, self.message)
    }
}

impl std::error::Error for UnsafeRuleError {}

#[derive(Debug, Clone)]
pub struct StratificationError(pub String);

impl fmt::Display for StratificationError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "StratificationError: {}", self.0)
    }
}

impl std::error::Error for StratificationError {}

#[derive(Debug, Clone)]
pub struct InvalidQueryError(pub String);

impl fmt::Display for InvalidQueryError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "InvalidQueryError: {}", self.0)
    }
}

impl std::error::Error for InvalidQueryError {}

#[derive(Debug, Clone)]
pub struct EvaluationError(pub String);

impl fmt::Display for EvaluationError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "EvaluationError: {}", self.0)
    }
}

impl std::error::Error for EvaluationError {}
