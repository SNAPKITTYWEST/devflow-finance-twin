#[derive(Clone, Copy, Debug)]
pub struct Epoch {
    pub iteration: u8,
    pub paradigm: &'static str,
    pub mechanism: &'static str,
    pub bound: &'static str,
}

pub const EVOLUTION: [Epoch; 5] = [
    Epoch {
        iteration: 0,
        paradigm: "Prolog",
        mechanism: "Unification + DFS backtracking",
        bound: "Unbounded heap, trail stack",
    },
    Epoch {
        iteration: 1,
        paradigm: "Custom Logic",
        mechanism: "Directed evaluation graphs",
        bound: "Fixed-width register sets",
    },
    Epoch {
        iteration: 2,
        paradigm: "Datalog",
        mechanism: "Stratified fixpoint / relation closure",
        bound: "Bounded relational arrays",
    },
    Epoch {
        iteration: 3,
        paradigm: "Mercury / ASP",
        mechanism: "Mode-directed compile / stable models",
        bound: "Static memory allocation",
    },
    Epoch {
        iteration: 4,
        paradigm: "Braid-Crypto Fibration",
        mechanism: "Non-Abelian generators + WORM seals",
        bound: "O(1) stack, append-only log",
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matrix_length() {
        assert_eq!(EVOLUTION.len(), 5);
        assert_eq!(EVOLUTION[4].iteration, 4);
    }
}
