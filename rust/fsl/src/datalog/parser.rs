use super::terms::{Atom, Term};
use super::errors::ParseError;

#[derive(Debug, Clone)]
pub struct ParsedProgram {
    pub facts: Vec<Atom>,
    pub rules: Vec<(Atom, Vec<Atom>, String)>,
}

fn strip_comments(source: &str) -> String {
    source.lines().map(|line| {
        if let Some(idx) = line.find('%') {
            &line[..idx]
        } else {
            line
        }
    }).collect::<Vec<_>>().join("\n")
}

fn parse_term(tok: &str) -> Result<Term, ParseError> {
    let tok = tok.trim();
    if tok.is_empty() {
        return Err(ParseError("empty term".into()));
    }
    let first = tok.chars().next().unwrap();
    if first.is_uppercase() || first == '_' {
        Ok(Term::var(tok))
    } else {
        Ok(Term::const_(tok))
    }
}

fn parse_atom(text: &str) -> Result<Atom, ParseError> {
    let text = text.trim().trim_end_matches('.');
    let text = text.trim();

    let paren_idx = text.find('(');
    let pred = match paren_idx {
        Some(idx) => text[..idx].trim(),
        None => text,
    };

    if pred.is_empty() {
        return Err(ParseError(format!("invalid atom: {:?}", text)));
    }

    let args = match paren_idx {
        Some(idx) => {
            let args_raw = &text[idx+1..];
            let args_raw = args_raw.trim_end_matches(')').trim();
            if args_raw.is_empty() {
                Vec::new()
            } else {
                split_args(args_raw)
                    .iter()
                    .map(|p| parse_term(p))
                    .collect::<Result<Vec<_>, _>>()?
            }
        }
        None => Vec::new(),
    };

    Ok(Atom::new(pred, args))
}

/// Split by commas, respecting nested parentheses (e.g. f(a, b), c → ["f(a, b)", "c"]).
fn split_args(s: &str) -> Vec<String> {
    let mut results = Vec::new();
    let mut depth = 0;
    let mut current = String::new();
    for c in s.chars() {
        match c {
            '(' => { depth += 1; current.push(c); }
            ')' => { depth -= 1; current.push(c); }
            ',' if depth == 0 => {
                results.push(current.trim().to_string());
                current = String::new();
            }
            _ => current.push(c),
        }
    }
    if !current.trim().is_empty() {
        results.push(current.trim().to_string());
    }
    results
}

fn dispatch_statement(stmt: &str, facts: &mut Vec<Atom>, rules: &mut Vec<(Atom, Vec<Atom>, String)>) -> Result<(), ParseError> {
    let stmt = stmt.split_whitespace().collect::<Vec<_>>().join(" ");

    if let Some(idx) = stmt.find(":-") {
        let head_str = stmt[..idx].trim();
        let body_str = stmt[idx+2..].trim();
        let head = parse_atom(head_str)?;
        let body: Vec<Atom> = split_args(body_str)
            .iter()
            .map(|b| parse_atom(b.trim()))
            .collect::<Result<Vec<_>, _>>()?;
        rules.push((head, body, String::new()));
    } else {
        facts.push(parse_atom(&stmt)?);
    }
    Ok(())
}

pub fn parse_program(source: &str) -> Result<ParsedProgram, ParseError> {
    let source = strip_comments(source);
    let mut facts = Vec::new();
    let mut rules = Vec::new();
    let mut buf = Vec::new();

    for c in source.chars() {
        if c == '.' {
            let stmt: String = buf.iter().collect();
            let stmt = stmt.trim().to_string();
            buf.clear();
            if !stmt.is_empty() {
                dispatch_statement(&stmt, &mut facts, &mut rules)?;
            }
        } else {
            buf.push(c);
        }
    }

    let trailing: String = buf.iter().collect();
    let trailing = trailing.trim().to_string();
    if !trailing.is_empty() {
        return Err(ParseError(format!("statement must end with '.': {:?}", &trailing[..trailing.len().min(60)])));
    }

    Ok(ParsedProgram { facts, rules })
}

pub fn parse_query(source: &str) -> Result<Atom, ParseError> {
    let source = source.trim();
    let source = if source.starts_with("?-") {
        source[2..].trim()
    } else {
        source
    };
    let source = source.trim_end_matches('.').trim();
    parse_atom(source)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_fact() {
        let prog = parse_program("role(w1, analyst).").unwrap();
        assert_eq!(prog.facts.len(), 1);
        assert_eq!(prog.facts[0].predicate, "role");
    }

    #[test]
    fn test_parse_rule() {
        let src = "authorized(A, T) :- role(A, R), permitted(R, T).";
        let prog = parse_program(src).unwrap();
        assert_eq!(prog.rules.len(), 1);
        assert_eq!(prog.rules[0].0.predicate, "authorized");
        assert_eq!(prog.rules[0].1.len(), 2);
    }

    #[test]
    fn test_parse_comments() {
        let src = "% comment\nrole(w1, analyst). % inline\n";
        let prog = parse_program(src).unwrap();
        assert_eq!(prog.facts.len(), 1);
    }

    #[test]
    fn test_parse_query() {
        let atom = parse_query("?- authorized(X, task1).").unwrap();
        assert_eq!(atom.predicate, "authorized");
        assert_eq!(atom.args.len(), 2);
    }
}
