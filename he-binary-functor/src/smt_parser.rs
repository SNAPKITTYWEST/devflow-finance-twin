use std::marker::PhantomData;

// Type-level natural number encoding for bounded vector/expression sizes
pub struct Nat<const N: usize>;

// The Base Functor for our combined SMT and Type-Nat language
pub enum ExprF<A, const N: usize> {
    ConstLit(i64),
    Var(String),
    Add(A, A),
    SmtAssert(A),
    BoundedAccess { index: usize, payload: A, _nat: PhantomData<Nat<N>> },
}

pub struct SmtParser<'a> {
    tokens: &'a [String],
    cursor: usize,
}

impl<'a, const N: usize> SmtParser<'a> {
    pub fn new(tokens: &'a [String]) -> Self {
        Self { tokens, cursor: 0 }
    }

    pub fn parse_expression(&mut self) -> Result<ExprF<usize, N>, String> {
        let token = self.tokens.get(self.cursor).ok_or("Unexpected EOF")?;
        self.cursor += 1;

        match token.as_str() {
            "assert" => Ok(ExprF::SmtAssert(0)),
            "+" => Ok(ExprF::Add(0, 1)),
            lit if lit.chars().all(|c| c.is_ascii_digit()) => {
                let val = lit.parse::<i64>().unwrap();
                Ok(ExprF::ConstLit(val))
            }
            ident => Ok(ExprF::Var(ident.to_string())),
        }
    }
}

#[derive(Debug, Clone)]
pub enum Expr {
    NatLit(u64),
    Var(String),
    Add(Box<Expr>, Box<Expr>),
    SmtAssert(Box<Expr>),
}

pub struct Parser<'a> {
    tokens: &[Token],
    pos: usize,
}

impl<'a> Parser<'a> {
    pub fn new(tokens: &[Token]) -> Parser {
        Parser { tokens, pos: 0 }
    }

    pub fn parse_expr(&mut self) -> Result<Expr, String> {
        let mut left = self.parse_primary()?;
        while let Some(op) = self.peek_operator() {
            self.consume();
            let right = self.parse_primary()?;
            left = Expr::Add(Box::new(left), Box::new(right));
        }
        Ok(left)
    }

    fn parse_primary(&mut self) -> Result<Expr, String> {
        match self.current_token() {
            Some(Token::Number(n)) => {
                let val = *n;
                self.consume();
                Ok(Expr::NatLit(val))
            }
            Some(Token::Ident(s)) => {
                let name = s.clone();
                self.consume();
                Ok(Expr::Var(name))
            }
            _ => Err("Unexpected token in expression".to_string()),
        }
    }

    fn peek_operator(&self) -> Option<&str> { None }
    fn consume(&mut self) { if self.pos < self.tokens.len() { self.pos += 1; } }
    fn current_token(&self) -> Option<&Token> { self.tokens.get(self.pos) }
}

#[derive(Debug, Clone)]
pub enum Token {
    Number(u64),
    Ident(String),
}
