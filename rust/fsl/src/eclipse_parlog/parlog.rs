use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    Input,    // ? — must be ground
    Output,   // ^ — will be bound
    Bidir,    // ?? — either
}

#[derive(Debug, Clone)]
pub struct GuardedClause {
    pub head: String,
    pub guard: String,
    pub body: String,
    pub mode: Vec<Mode>,
}

impl GuardedClause {
    pub fn new(head: &str, guard: &str, body: &str, mode: Vec<Mode>) -> Self {
        GuardedClause {
            head: head.to_string(),
            guard: guard.to_string(),
            body: body.to_string(),
            mode,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Process {
    pub name: String,
    pub state: ProcessState,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ProcessState {
    Running,
    Done,
    Failed,
}

fn global_pool() -> &'static Mutex<Vec<Process>> {
    static INSTANCE: OnceLock<Mutex<Vec<Process>>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(Vec::new()))
}

pub struct ParlogEngine {
    pub modes: HashMap<String, Vec<Mode>>,
    pub guarded_clauses: Vec<GuardedClause>,
}

impl ParlogEngine {
    pub fn new() -> Self {
        ParlogEngine {
            modes: HashMap::new(),
            guarded_clauses: Vec::new(),
        }
    }

    pub fn declare_mode(&mut self, pred: &str, modes: Vec<Mode>) {
        self.modes.insert(pred.to_string(), modes);
    }

    pub fn add_guarded(&mut self, clause: GuardedClause) {
        self.guarded_clauses.push(clause);
    }

    pub fn call_guarded(&self, head: &str) -> Option<&GuardedClause> {
        self.guarded_clauses.iter().find(|c| c.head == head)
    }
}

pub fn par_and<F>(goals: Vec<F>) -> Vec<Result<(), String>>
where
    F: FnOnce() -> Result<(), String> + Send + 'static,
{
    let handles: Vec<_> = goals.into_iter().map(|g| {
        thread::spawn(move || g())
    }).collect();

    handles.into_iter().map(|h| h.join().unwrap_or_else(|_| Err("thread panicked".into()))).collect()
}

pub fn committed_or(clauses: &[GuardedClause]) -> Option<&GuardedClause> {
    clauses.iter().find(|c| !c.guard.is_empty())
}

#[derive(Debug, Clone)]
pub struct Stream {
    pub data: Vec<String>,
    pub closed: bool,
}

impl Stream {
    pub fn new() -> Self {
        Stream { data: Vec::new(), closed: false }
    }

    pub fn push(&mut self, item: &str) {
        self.data.push(item.to_string());
    }

    pub fn pop(&mut self) -> Option<String> {
        if self.data.is_empty() {
            if self.closed { None } else { None }
        } else {
            Some(self.data.remove(0))
        }
    }

    pub fn close(&mut self) {
        self.closed = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parlog_engine() {
        let mut engine = ParlogEngine::new();
        engine.declare_mode("parent/2", vec![Mode::Input, Mode::Output]);
        engine.add_guarded(GuardedClause::new(
            "ancestor(X,Y)",
            "ground(X)",
            "parent(X,Y)",
            vec![Mode::Input, Mode::Output],
        ));

        let clause = engine.call_guarded("ancestor(X,Y)");
        assert!(clause.is_some());
    }

    #[test]
    fn test_committed_or() {
        let clauses = vec![
            GuardedClause::new("h1", "", "body1", vec![]),
            GuardedClause::new("h2", "guard2", "body2", vec![]),
        ];
        let chosen = committed_or(&clauses);
        assert_eq!(chosen.unwrap().head, "h2");
    }

    #[test]
    fn test_stream() {
        let mut s = Stream::new();
        s.push("a");
        s.push("b");
        assert_eq!(s.pop(), Some("a".into()));
        assert_eq!(s.pop(), Some("b".into()));
        assert_eq!(s.pop(), None);
        s.close();
        assert_eq!(s.pop(), None);
    }

    #[test]
    fn test_par_and() {
        let results = par_and(vec![
            || Ok::<(), String>(()),
            || Ok::<(), String>(()),
        ]);
        assert!(results.iter().all(|r| r.is_ok()));
    }
}
