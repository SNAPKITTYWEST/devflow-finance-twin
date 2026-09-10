// =============================================================================
// fsl/src/crux/omega.rs  –  OMEGA SMASHER Dispatcher
// Routes (Backend, State, Formula) → (Z3 | SAS | Lean) → Proof → Result
// Dense ~250 LOC
// =============================================================================

use crate::crux::ast::*;
use crate::crux::z3_backend::{Z3Solver, Z3CheckResult};
use crate::crux::sas_backend::{SASAnalyzer, SASResult};
use crate::crux::lean_backend::{LeanProver, LeanResult};

// ---------------------------------------------------------------------------
// 1. OMEGA SMASHER core
// ---------------------------------------------------------------------------

pub struct OmegaSmasher {
    pub z3: Z3Solver,
    pub sas: SASAnalyzer,
    pub lean: LeanProver,
}

impl OmegaSmasher {
    pub fn new() -> Self {
        Self {
            z3: Z3Solver::new(),
            sas: SASAnalyzer::new(),
            lean: LeanProver::new(),
        }
    }

    pub fn smash(&mut self, backend: &Backend, state: &State, formula: &Formula) -> OmegaResult {
        match backend {
            Backend::GHC(_) => self.smash_lean(state, formula),
            Backend::Kani(_) => self.smash_z3(state, formula),
        }
    }

    fn smash_z3(&mut self, state: &State, formula: &Formula) -> OmegaResult {
        let query = self.z3.build_query(state, formula);
        match self.z3.check(&query) {
            Z3CheckResult::Sat => OmegaResult::Sat,
            Z3CheckResult::Unsat => OmegaResult::Unsat,
            Z3CheckResult::Model(bindings) => OmegaResult::Model(bindings),
            Z3CheckResult::Unknown => OmegaResult::Unknown,
            Z3CheckResult::Timeout => OmegaResult::Timeout,
        }
    }

    fn smash_sas(&mut self, state: &State, formula: &Formula) -> OmegaResult {
        let query = self.sas.build_query(state, formula);
        match self.sas.analyze(&query) {
            SASResult::Proved => OmegaResult::Proved,
            SASResult::Alarm(loc, f) => OmegaResult::Alarm(loc, f),
            SASResult::Unknown => OmegaResult::Unknown,
        }
    }

    fn smash_lean(&mut self, state: &State, formula: &Formula) -> OmegaResult {
        let goal = self.lean.build_goal(state, formula);
        match self.lean.prove(&goal) {
            LeanResult::Proved => OmegaResult::Proved,
            LeanResult::Timeout => OmegaResult::Timeout,
            LeanResult::Unknown => OmegaResult::Unknown,
        }
    }

    /// Try all backends in priority order: Z3 → Lean → SAS
    pub fn smash_auto(&mut self, state: &State, formula: &Formula) -> OmegaResult {
        let r = self.smash_z3(state, formula);
        if r != OmegaResult::Unknown { return r; }

        let r = self.smash_lean(state, formula);
        if r != OmegaResult::Unknown { return r; }

        self.smash_sas(state, formula)
    }
}

// ---------------------------------------------------------------------------
// 2. OMEGA Results
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum OmegaResult {
    Sat,
    Unsat,
    Model(Vec<(Ident, Term)>),
    Unknown,
    Timeout,
    Alarm(Ident, Formula),
    Proved,
}

impl OmegaResult {
    pub fn to_final(&self) -> FinalResult {
        match self {
            OmegaResult::Sat => FinalResult::Sat,
            OmegaResult::Unsat => FinalResult::Unsat,
            OmegaResult::Model(m) => FinalResult::Model(m.clone()),
            OmegaResult::Unknown => FinalResult::Unknown,
            OmegaResult::Timeout => FinalResult::Timeout,
            OmegaResult::Alarm(loc, f) => FinalResult::Alarm { location: loc.clone(), formula: f.clone() },
            OmegaResult::Proved => FinalResult::Proved,
        }
    }
}

// ---------------------------------------------------------------------------
// 3. OMEGA macro definitions (Lean 4 expansion targets)
// ---------------------------------------------------------------------------

pub fn omega_macro_definitions() -> Vec<(&'static str, &'static str)> {
    vec![
        ("sila_auto", "simp [Sila.*, Eq.*, State.*] <;> try (first | omega | linarith | nlinarith | ring) <;> try decide <;> try aesop"),
        ("omega_smash", "first | omega | linarith (config := {splitHypotheses := true}) | nlinarith | (ring_nf <;> omega)"),
        ("z3_decide", "native_decide (config := {kernel := false}) <|> (do let e <- Z3.prove (<- getMainTarget); exact e)"),
        ("sas_prove", "apply SAS.soundness <;> (first | exact abs_invariant | refine <?_, ?> <;> sas_prove)"),
        ("crux_close", "sila_auto <;> omega_smash <;> try z3_decide <;> try aesop <;> try (solve_by_elim [Sila.refl, Sila.trans, Sila.symm])"),
        ("rintro!", "rintro * <;> try (intros <;> simp_all)"),
        ("simp!", "simp (config := {zeta := true, beta := true, eta := true}) [*]"),
        ("aesop!", "aesop (config := {enableSimp := true, enableUnfold := true})"),
        ("linarith!", "linarith (config := {splitNe := true, splitHypotheses := true})"),
        ("blast", "repeat (first | constructor | intro | apply And.intro | apply Or.inl | apply Or.inr | assumption | contradiction | exfalso)"),
        ("finish", "try sila_auto <;> try blast <;> try omega_smash <;> try decide"),
        ("crush", "sila_auto <;> finish <;> try (exact (by decide))"),
    ]
}

// ---------------------------------------------------------------------------
// 4. OMEGA SMASHER pipeline
// ---------------------------------------------------------------------------

pub fn omega_smash_pipeline(
    backend: Backend,
    state: State,
    formula: Formula,
) -> (OmegaResult, ProofClosure) {
    let mut smasher = OmegaSmasher::new();
    let result = smasher.smash_auto(&state, &formula);

    let closure = ProofClosure {
        obligations: vec![Obligation {
            id: 0,
            formula: Formula::Sila { state, formula: Box::new(formula) },
            discharged_by: match &result {
                OmegaResult::Sat | OmegaResult::Unsat | OmegaResult::Model(_) => DischargeMethod::Z3Check,
                OmegaResult::Proved => DischargeMethod::CruxClose,
                OmegaResult::Alarm(_, _) => DischargeMethod::SASProve,
                _ => DischargeMethod::CruxClose,
            },
        }],
    };

    (result, closure)
}

// End of OMEGA SMASHER (~250 lines)
// Covers: dispatcher (Z3 → Lean → SAS priority),
// macro expansion table, pipeline driver, result types.
