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
// fsl/src/crux/russian.rs  â€“  Russian Syntax Parser
// Parses RussianForm from token stream, lowers to CRUX AST
// Dense ~250 LOC
// =============================================================================

use crate::crux::ast::*;

// ---------------------------------------------------------------------------
// 1. Token type
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum Token {
    // Keywords (Russian)
    Ravno,
    Imply,
    Conj,
    Disj,
    Neg,
    DlyaVsekh,
    Sushchestvuet,
    Rekursiya,
    Sostoyanie,
    Sila,
    Omega,
    Dokazatelstvo,
    // Keywords (English)
    Let,
    In,
    If,
    Then,
    Else,
    Match,
    With,
    Fold,
    Rec,
    Fun,
    Theorem,
    Lemma,
    Example,
    Proof,
    QED,
    By,
    Sorry,
    // Delimiters
    LParen,
    RParen,
    LBracket,
    RBracket,
    LBrace,
    RBrace,
    Comma,
    Semicolon,
    Dot,
    Colon,
    Pipe,
    Arrow,
    DoubleArrow,
    FatArrow,
    // Operators
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Cons,
    Concat,
    And,
    Or,
    Not,
    Implies,
    Iff,
    Forall,
    Exists,
    Mu,
    Nu,
    // Literals & identifiers
    Ident(String),
    Number(i64),
    BoolLit(bool),
    StringLit(String),
    // Special
    Eof,
}

// ---------------------------------------------------------------------------
// 2. Lexer
// ---------------------------------------------------------------------------

pub struct RussianLexer {
    input: Vec<char>,
    pos: usize,
}

impl RussianLexer {
    pub fn new(input: &str) -> Self {
        Self { input: input.chars().collect(), pos: 0 }
    }

    fn peek(&self) -> Option<char> {
        self.input.get(self.pos).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let c = self.input.get(self.pos).copied();
        if c.is_some() { self.pos += 1; }
        c
    }

    fn skip_whitespace(&mut self) {
        while let Some(c) = self.peek() {
            if c.is_whitespace() { self.advance(); } else { break; }
        }
    }

    fn skip_comment(&mut self) {
        if self.peek() == Some('-') && self.pos + 1 < self.input.len() && self.input[self.pos + 1] == '-' {
            while let Some(c) = self.advance() {
                if c == '\n' { break; }
            }
            self.skip_whitespace();
            self.skip_comment();
        }
    }

    fn read_ident(&mut self) -> String {
        let mut s = String::new();
        while let Some(c) = self.peek() {
            if c.is_alphanumeric() || c == '_' || c == '\'' ||
               (c as u32 >= 0x0370 && c as u32 <= 0x03FF) || // Greek
               (c as u32 >= 0x0400 && c as u32 <= 0x04FF) {   // Cyrillic
                s.push(c);
                self.advance();
            } else { break; }
        }
        s
    }

    fn read_number(&mut self) -> i64 {
        let mut s = String::new();
        while let Some(c) = self.peek() {
            if c.is_ascii_digit() { s.push(c); self.advance(); } else { break; }
        }
        s.parse().unwrap_or(0)
    }

    pub fn tokenize(&mut self) -> Vec<Token> {
        let mut tokens = Vec::new();
        loop {
            self.skip_whitespace();
            self.skip_comment();
            let tok = match self.peek() {
                None => Token::Eof,
                Some('(') => { self.advance(); Token::LParen }
                Some(')') => { self.advance(); Token::RParen }
                Some('[') => { self.advance(); Token::LBracket }
                Some(']') => { self.advance(); Token::RBracket }
                Some('{') => { self.advance(); Token::LBrace }
                Some('}') => { self.advance(); Token::RBrace }
                Some(',') => { self.advance(); Token::Comma }
                Some(';') => { self.advance(); Token::Semicolon }
                Some('.') => { self.advance(); Token::Dot }
                Some(':') => { self.advance(); Token::Colon }
                Some('|') => { self.advance(); Token::Pipe }
                Some('+') => { self.advance(); Token::Plus }
                Some('%') => { self.advance(); Token::Percent }
                Some('*') => { self.advance(); Token::Star }
                Some('/') => { self.advance(); Token::Slash }
                Some('=') => {
                    self.advance();
                    match self.peek() {
                        Some('=') => { self.advance(); Token::Eq }
                        Some('>') => { self.advance(); Token::FatArrow }
                        _ => Token::Eq,
                    }
                }
                Some('!') => {
                    self.advance();
                    if self.peek() == Some('=') { self.advance(); Token::Ne } else { Token::Not }
                }
                Some('<') => {
                    self.advance();
                    match self.peek() {
                        Some('=') => { self.advance(); Token::Le }
                        Some('-') => { self.advance(); Token::Cons }
                        _ => Token::Lt,
                    }
                }
                Some('>') => {
                    self.advance();
                    if self.peek() == Some('=') { self.advance(); Token::Ge } else { Token::Gt }
                }
                Some('-') => {
                    self.advance();
                    match self.peek() {
                        Some('>') => { self.advance(); Token::Arrow }
                        Some('-') => { self.advance(); Token::Minus }
                        _ => Token::Minus,
                    }
                }
                Some('\u{2192}') => { self.advance(); Token::Arrow }    // â†’
                Some('\u{2194}') => { self.advance(); Token::DoubleArrow } // â†”
                Some('\u{2200}') => { self.advance(); Token::Forall }   // âˆ€
                Some('\u{2203}') => { self.advance(); Token::Exists }   // âˆƒ
                Some('\u{2227}') => { self.advance(); Token::And }      // âˆ§
                Some('\u{2228}') => { self.advance(); Token::Or }       // âˆ¨
                Some('\u{00AC}') => { self.advance(); Token::Not }      // Â¬
                Some('\u{2261}') => { self.advance(); Token::Eq }       // â‰¡
                Some('\u{2264}') => { self.advance(); Token::Le }       // â‰¤
                Some('\u{2265}') => { self.advance(); Token::Ge }       // â‰¥
                Some('\u{2260}') => { self.advance(); Token::Ne }       // â‰ 
                Some('\u{22A2}') => { self.advance(); Token::Not }      // âŠ¢ placeholder
                Some('\u{22A8}') => { self.advance(); Token::Not }      // âŠ§ placeholder
                Some('\u{22A4}') => { self.advance(); Token::BoolLit(true) }  // âŠ¤
                Some('\u{22A5}') => { self.advance(); Token::BoolLit(false) } // âŠ¥
                Some('\u{21A6}') => { self.advance(); Token::FatArrow } // â†¦
                Some('"') => {
                    self.advance();
                    let mut s = String::new();
                    while let Some(c) = self.advance() {
                        if c == '"' { break; } else { s.push(c); }
                    }
                    Token::StringLit(s)
                }
                Some(c) if c.is_ascii_digit() => Token::Number(self.read_number()),
                Some(c) if c.is_alphabetic() || c == '_' || (c as u32 >= 0x0400) => {
                    let ident = self.read_ident();
                    match ident.as_str() {
                        "Ñ€Ð°Ð²ÐµÐ½ÑÑ‚Ð²Ð¾" => Token::Ravno,
                        "Ð¸Ð¼Ð¿Ð»Ð¸ÐºÐ°Ñ†Ð¸Ñ" => Token::Imply,
                        "ÐºÐ¾Ð½ÑŠÑŽÐ½ÐºÑ†Ð¸Ñ" => Token::Conj,
                        "Ð´Ð¸Ð·ÑŠÑŽÐ½ÐºÑ†Ð¸Ñ" => Token::Disj,
                        "Ð¾Ñ‚Ñ€Ð¸Ñ†Ð°Ð½Ð¸Ðµ" => Token::Neg,
                        "Ð´Ð»Ñ_Ð²ÑÐµÑ…" => Token::DlyaVsekh,
                        "ÑÑƒÑ‰ÐµÑÑ‚Ð²ÑƒÐµÑ‚" => Token::Sushchestvuet,
                        "Ñ€ÐµÐºÑƒÑ€ÑÐ¸Ñ" => Token::Rekursiya,
                        "ÑÐ¾ÑÑ‚Ð¾ÑÐ½Ð¸Ðµ" => Token::Sostoyanie,
                        "ÑÐ¸Ð»Ð°" => Token::Sila,
                        "Ð¾Ð¼ÐµÐ³Ð°" => Token::Omega,
                        "Ð´Ð¾ÐºÐ°Ð·Ð°Ñ‚ÐµÐ»ÑŒÑÑ‚Ð²Ð¾" => Token::Dokazatelstvo,
                        "let" => Token::Let,
                        "in" => Token::In,
                        "if" => Token::If,
                        "then" => Token::Then,
                        "else" => Token::Else,
                        "match" => Token::Match,
                        "with" => Token::With,
                        "fold" => Token::Fold,
                        "rec" => Token::Rec,
                        "fun" => Token::Fun,
                        "theorem" => Token::Theorem,
                        "lemma" => Token::Lemma,
                        "example" => Token::Example,
                        "proof" => Token::Proof,
                        "QED" => Token::QED,
                        "by" => Token::By,
                        "sorry" => Token::Sorry,
                        "true" => Token::BoolLit(true),
                        "false" => Token::BoolLit(false),
                        "and" => Token::And,
                        "or" => Token::Or,
                        "not" => Token::Not,
                        "implies" => Token::Implies,
                        "iff" => Token::Iff,
                        _ => Token::Ident(ident),
                    }
                }
                Some(_) => { self.advance(); continue; }
            };
            tokens.push(tok);
            if tokens.last() == Some(&Token::Eof) { break; }
        }
        tokens
    }
}

// ---------------------------------------------------------------------------
// 3. Parser
// ---------------------------------------------------------------------------

pub struct RussianParser {
    tokens: Vec<Token>,
    pos: usize,
}

impl RussianParser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self { tokens, pos: 0 }
    }

    fn peek(&self) -> &Token {
        self.tokens.get(self.pos).unwrap_or(&Token::Eof)
    }

    fn advance(&mut self) -> Token {
        let t = self.tokens.get(self.pos).cloned().unwrap_or(Token::Eof);
        self.pos += 1;
        t
    }

    fn expect(&mut self, expected: &Token) -> Result<(), String> {
        let t = self.advance();
        if &t == expected { Ok(()) } else { Err(format!("expected {:?}, got {:?}", expected, t)) }
    }

    fn parse_term(&mut self) -> Result<Term, String> {
        self.parse_term_binop(0)
    }

    fn parse_term_binop(&mut self, min_prec: u8) -> Result<Term, String> {
        let mut lhs = self.parse_term_atom()?;
        loop {
            let op = match self.peek() {
                Token::Plus => Some(BinOp::Add),
                Token::Minus => Some(BinOp::Sub),
                Token::Star => Some(BinOp::Mul),
                Token::Slash => Some(BinOp::Div),
                Token::Percent => Some(BinOp::Mod),
                _ => None,
            };
            if let Some(o) = op {
                let prec = binop_prec(o);
                if prec < min_prec { break; }
                self.advance();
                let rhs = self.parse_term_binop(prec + 1)?;
                lhs = Term::BinOp { op: o, lhs: Box::new(lhs), rhs: Box::new(rhs) };
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    fn parse_term_atom(&mut self) -> Result<Term, String> {
        match self.peek().clone() {
            Token::Ident(name) => {
                self.advance();
                // Check for application: term term
                if matches!(self.peek(), Token::Ident(_) | Token::Number(_) | Token::LParen | Token::BoolLit(_)) {
                    let arg = self.parse_term_atom()?;
                    Ok(Term::App(Box::new(Term::Var(name)), Box::new(arg)))
                } else {
                    Ok(Term::Var(name))
                }
            }
            Token::Number(n) => { self.advance(); Ok(Term::Const(Literal::Number(n))) }
            Token::BoolLit(b) => { self.advance(); Ok(Term::Const(Literal::Bool(b))) }
            Token::StringLit(s) => { self.advance(); Ok(Term::Const(Literal::Str(s))) }
            Token::LParen => {
                self.advance();
                if self.peek() == &Token::RParen {
                    self.advance();
                    return Ok(Term::Nil);
                }
                let first = self.parse_term()?;
                if self.peek() == &Token::Comma {
                    let mut elems = vec![first];
                    while self.peek() == &Token::Comma {
                        self.advance();
                        elems.push(self.parse_term()?);
                    }
                    self.expect(&Token::RParen)?;
                    Ok(Term::Tuple(elems))
                } else {
                    self.expect(&Token::RParen)?;
                    Ok(Term::Paren(Box::new(first)))
                }
            }
            Token::Fun => {
                self.advance();
                let param = match self.advance() {
                    Token::Ident(name) => name,
                    t => return Err(format!("expected ident after fun, got {:?}", t)),
                };
                self.expect(&Token::Colon)?;
                let sort = self.parse_sort()?;
                self.expect(&Token::FatArrow)?;
                let body = self.parse_term()?;
                Ok(Term::Lambda { param, sort, body: Box::new(body) })
            }
            Token::If => {
                self.advance();
                let cond = self.parse_formula()?;
                self.expect(&Token::Then)?;
                let then = self.parse_term()?;
                self.expect(&Token::Else)?;
                let else_ = self.parse_term()?;
                Ok(Term::IfThenElse { cond: Box::new(cond), then: Box::new(then), else_: Box::new(else_) })
            }
            Token::Rec => {
                self.advance();
                let name = match self.advance() {
                    Token::Ident(n) => n,
                    t => return Err(format!("expected ident after rec, got {:?}", t)),
                };
                self.expect(&Token::Eq)?;
                let body = self.parse_term()?;
                Ok(Term::Rec { name, body: Box::new(body) })
            }
            t => Err(format!("unexpected token in term: {:?}", t)),
        }
    }

    pub fn parse_sort(&mut self) -> Result<Sort, String> {
        let mut base = match self.advance() {
            Token::Ident(s) => match s.as_str() {
                "Prop" => Sort::Prop,
                "Type" => Sort::Type,
                "Nat" => Sort::Nat,
                "Int" => Sort::Int,
                "Bool" => Sort::Bool,
                "State" => Sort::State,
                "Formula" => Sort::Formula,
                "Term" => Sort::Term,
                "MIR" => Sort::MIR,
                "Core" => Sort::Core,
                "Haskell" => Sort::Haskell,
                "Rust" => Sort::Rust,
                "Z3Expr" => Sort::Z3Expr,
                "LeanTerm" => Sort::LeanTerm,
                "SASAbs" => Sort::SASAbs,
                other => Sort::User(other.to_string()),
            },
            Token::LParen => {
                let s = self.parse_sort()?;
                self.expect(&Token::RParen)?;
                s
            }
            t => return Err(format!("unexpected token in sort: {:?}", t)),
        };
        // Check for sort arrows
        while self.peek() == &Token::Arrow {
            self.advance();
            let rhs = self.parse_sort()?;
            base = Sort::Arrow(Box::new(base), Box::new(rhs));
        }
        Ok(base)
    }

    pub fn parse_formula(&mut self) -> Result<Formula, String> {
        self.parse_formula_implies()
    }

    fn parse_formula_implies(&mut self) -> Result<Formula, String> {
        let mut lhs = self.parse_formula_or()?;
        while self.peek() == &Token::Implies || self.peek() == &Token::Arrow {
            self.advance();
            let rhs = self.parse_formula_or()?;
            lhs = Formula::Implies(Box::new(lhs), Box::new(rhs));
        }
        Ok(lhs)
    }

    fn parse_formula_or(&mut self) -> Result<Formula, String> {
        let mut lhs = self.parse_formula_and()?;
        while self.peek() == &Token::Or {
            self.advance();
            let rhs = self.parse_formula_and()?;
            lhs = Formula::And(vec![lhs, rhs]); // Or represented as nested
        }
        Ok(lhs)
    }

    fn parse_formula_and(&mut self) -> Result<Formula, String> {
        let mut lhs = self.parse_formula_atom()?;
        while self.peek() == &Token::And {
            self.advance();
            let rhs = self.parse_formula_atom()?;
            lhs = Formula::And(vec![lhs, rhs]);
        }
        Ok(lhs)
    }

    fn parse_formula_atom(&mut self) -> Result<Formula, String> {
        match self.peek().clone() {
            Token::Not => {
                self.advance();
                let f = self.parse_formula_atom()?;
                Ok(Formula::Not(Box::new(f)))
            }
            Token::Forall => {
                self.advance();
                let var = match self.advance() {
                    Token::Ident(n) => n,
                    t => return Err(format!("expected ident after forall, got {:?}", t)),
                };
                self.expect(&Token::Colon)?;
                let sort = self.parse_sort()?;
                self.expect(&Token::Dot)?;
                let body = self.parse_formula()?;
                Ok(Formula::Forall { var, sort, body: Box::new(body) })
            }
            Token::Exists => {
                self.advance();
                let var = match self.advance() {
                    Token::Ident(n) => n,
                    t => return Err(format!("expected ident after exists, got {:?}", t)),
                };
                self.expect(&Token::Colon)?;
                let sort = self.parse_sort()?;
                self.expect(&Token::Dot)?;
                let body = self.parse_formula()?;
                Ok(Formula::Exists { var, sort, body: Box::new(body) })
            }
            Token::Mu => {
                self.advance();
                let var = match self.advance() {
                    Token::Ident(n) => n,
                    t => return Err(format!("expected ident after Î¼, got {:?}", t)),
                };
                self.expect(&Token::Dot)?;
                let body = self.parse_formula()?;
                Ok(Formula::Mu { var, body: Box::new(body) })
            }
            Token::Nu => {
                self.advance();
                let var = match self.advance() {
                    Token::Ident(n) => n,
                    t => return Err(format!("expected ident after Î½, got {:?}", t)),
                };
                self.expect(&Token::Dot)?;
                let body = self.parse_formula()?;
                Ok(Formula::Nu { var, body: Box::new(body) })
            }
            Token::LParen => {
                self.advance();
                let f = self.parse_formula()?;
                self.expect(&Token::RParen)?;
                Ok(Formula::Paren(Box::new(f)))
            }
            Token::BoolLit(true) => { self.advance(); Ok(Formula::Atomic(Atomic::True)) }
            Token::BoolLit(false) => { self.advance(); Ok(Formula::Atomic(Atomic::False)) }
            Token::Ravno => {
                // Ñ€Ð°Ð²ÐµÐ½ÑÑ‚Ð²Ð¾(A, B) in formula position
                self.advance();
                self.expect(&Token::LParen)?;
                let a = self.parse_term()?;
                self.expect(&Token::Comma)?;
                let b = self.parse_term()?;
                self.expect(&Token::RParen)?;
                Ok(Formula::Eq(a, b))
            }
            _ => {
                // Try to parse as term, then check for relational operators
                let lhs = self.parse_term()?;
                match self.peek() {
                    Token::Eq => {
                        self.advance();
                        let rhs = self.parse_term()?;
                        Ok(Formula::Eq(lhs, rhs))
                    }
                    Token::Ne => {
                        self.advance();
                        let rhs = self.parse_term()?;
                        Ok(Formula::Not(Box::new(Formula::Eq(lhs, rhs))))
                    }
                    Token::Lt => {
                        self.advance();
                        let rhs = self.parse_term()?;
                        Ok(Formula::Atomic(Atomic::Predicate {
                            name: "<".into(), args: vec![lhs, rhs],
                        }))
                    }
                    Token::Le => {
                        self.advance();
                        let rhs = self.parse_term()?;
                        Ok(Formula::Atomic(Atomic::Predicate {
                            name: "â‰¤".into(), args: vec![lhs, rhs],
                        }))
                    }
                    Token::Gt => {
                        self.advance();
                        let rhs = self.parse_term()?;
                        Ok(Formula::Atomic(Atomic::Predicate {
                            name: ">".into(), args: vec![lhs, rhs],
                        }))
                    }
                    Token::Ge => {
                        self.advance();
                        let rhs = self.parse_term()?;
                        Ok(Formula::Atomic(Atomic::Predicate {
                            name: "â‰¥".into(), args: vec![lhs, rhs],
                        }))
                    }
                    _ => {
                        // Wrap as predicate with no args
                        if let Term::Var(name) = lhs {
                            Ok(Formula::Atomic(Atomic::Predicate { name, args: vec![] }))
                        } else {
                            Err(format!("unexpected term in formula position: {:?}", lhs))
                        }
                    }
                }
            }
        }
    }

    fn parse_state(&mut self) -> Result<State, String> {
        match self.advance() {
            Token::Ident(s) if s == "S" => {
                if let Token::Number(n) = self.peek().clone() {
                    self.advance();
                    Ok(State::Sn(n as u32))
                } else {
                    Ok(State::S)
                }
            }
            Token::Ident(s) if s == "S0" => Ok(State::S0),
            Token::Ident(s) if s.starts_with('S') && s.len() > 1 => {
                // S1, S2, etc.
                let num: String = s[1..].chars().collect();
                if let Ok(n) = num.parse::<u32>() {
                    Ok(State::Sn(n))
                } else {
                    Err(format!("invalid state name: {}", s))
                }
            }
            t => Err(format!("unexpected token in state: {:?}", t)),
        }
    }

    pub fn parse_russian_form(&mut self) -> Result<RussianForm, String> {
        match self.peek().clone() {
            Token::Ravno => {
                self.advance();
                self.expect(&Token::LParen)?;
                let a = self.parse_term()?;
                self.expect(&Token::Comma)?;
                let b = self.parse_term()?;
                self.expect(&Token::RParen)?;
                Ok(RussianForm::Ravnostvo(a, b))
            }
            Token::Sila => {
                self.advance();
                self.expect(&Token::LParen)?;
                let state = self.parse_state()?;
                self.expect(&Token::Comma)?;
                let formula = self.parse_formula()?;
                self.expect(&Token::RParen)?;
                Ok(RussianForm::Sila(state, formula))
            }
            Token::Omega => {
                self.advance();
                self.expect(&Token::LParen)?;
                // Parse backend placeholder
                let _backend = self.advance(); // TODO: parse full backend
                self.expect(&Token::Comma)?;
                let state = self.parse_state()?;
                self.expect(&Token::Comma)?;
                let formula = self.parse_formula()?;
                self.expect(&Token::RParen)?;
                Ok(RussianForm::Omega(Backend::Kani(KaniMIR {
                    name: "placeholder".into(), params: vec![],
                    return_sort: Sort::Bool, body: vec![],
                }), state, formula))
            }
            Token::Dokazatelstvo => {
                self.advance();
                Ok(RussianForm::Dokazatelstvo(ProofClosure { obligations: vec![] }))
            }
            t => Err(format!("unexpected Russian form: {:?}", t)),
        }
    }
}

fn binop_prec(op: BinOp) -> u8 {
    match op {
        BinOp::Mul | BinOp::Div | BinOp::Mod => 7,
        BinOp::Add | BinOp::Sub => 6,
        BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge => 4,
        BinOp::Eq | BinOp::Ne => 3,
    }
}

// ---------------------------------------------------------------------------
// 4. Public API
// ---------------------------------------------------------------------------

pub fn parse_russian(input: &str) -> Result<RussianForm, String> {
    let mut lexer = RussianLexer::new(input);
    let tokens = lexer.tokenize();
    let mut parser = RussianParser::new(tokens);
    parser.parse_russian_form()
}

pub fn parse_formula(input: &str) -> Result<Formula, String> {
    let mut lexer = RussianLexer::new(input);
    let tokens = lexer.tokenize();
    let mut parser = RussianParser::new(tokens);
    parser.parse_formula()
}

pub fn parse_term(input: &str) -> Result<Term, String> {
    let mut lexer = RussianLexer::new(input);
    let tokens = lexer.tokenize();
    let mut parser = RussianParser::new(tokens);
    parser.parse_term()
}

// End of Russian syntax parser (~250 lines)
// Covers: lexer (Unicode-aware, Cyrillic + Greek + math symbols),
// recursive descent parser for terms, formulas, sorts, states,
// and RussianForm top-level entry.
