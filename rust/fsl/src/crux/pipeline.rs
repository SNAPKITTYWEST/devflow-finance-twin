// =============================================================================
// fsl/src/crux/pipeline.rs  –  Full CRUX Pipeline Driver
// RussianSyntax → RecursiveStateIR → Backend → OMEGA → ProofClosure → Result
// Dense ~200 LOC
// =============================================================================

use crate::crux::ast::*;
use crate::crux::russian::parse_russian;
use crate::crux::omega::{OmegaSmasher, OmegaResult, omega_smash_pipeline};
use crate::crux::pcc::{CertifiedState, SilaDerivation};

use std::fmt;

// ---------------------------------------------------------------------------
// 1. Pipeline stages
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct CruxPipeline {
    pub input: String,
    pub stages: Vec<PipelineStage>,
}

#[derive(Clone, Debug)]
pub enum PipelineStage {
    Parsed(RussianForm),
    Lowered { state: State, formula: Formula },
    BackendSelected(Backend),
    OmegaSmashed(OmegaResult),
    ProofClosed(ProofClosure),
    Final(CruxResult),
}

#[derive(Clone, Debug, PartialEq)]
pub enum CruxResult {
    Sat,
    Unsat,
    Model(Vec<(Ident, Term)>),
    Proved,
    Unknown,
    Timeout,
    Alarm { location: Ident, formula: Formula },
    Error(String),
}

impl CruxResult {
    pub fn to_final(&self) -> FinalResult {
        match self {
            CruxResult::Sat => FinalResult::Sat,
            CruxResult::Unsat => FinalResult::Unsat,
            CruxResult::Model(m) => FinalResult::Model(m.clone()),
            CruxResult::Proved => FinalResult::Proved,
            CruxResult::Unknown => FinalResult::Unknown,
            CruxResult::Timeout => FinalResult::Timeout,
            CruxResult::Alarm { location, formula } => FinalResult::Alarm {
                location: location.clone(),
                formula: formula.clone(),
            },
            CruxResult::Error(e) => FinalResult::Unknown,
        }
    }
}

impl fmt::Display for CruxResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CruxResult::Sat => write!(f, "SAT"),
            CruxResult::Unsat => write!(f, "UNSAT"),
            CruxResult::Model(m) => {
                write!(f, "MODEL{{ ")?;
                for (i, (name, val)) in m.iter().enumerate() {
                    if i > 0 { write!(f, ", ")?; }
                    write!(f, "{} = {:?}", name, val)?;
                }
                write!(f, " }}")
            }
            CruxResult::Proved => write!(f, "PROVED"),
            CruxResult::Unknown => write!(f, "UNKNOWN"),
            CruxResult::Timeout => write!(f, "TIMEOUT"),
            CruxResult::Alarm { location, formula } => write!(f, "ALARM at {}: {:?}", location, formula),
            CruxResult::Error(e) => write!(f, "ERROR: {}", e),
        }
    }
}

// ---------------------------------------------------------------------------
// 2. Pipeline execution
// ---------------------------------------------------------------------------

pub fn run_crux_pipeline(input: &str) -> CruxPipelineResult {
    let mut stages = Vec::new();

    // Stage 1: Parse Russian syntax
    let russian_form = match parse_russian(input) {
        Ok(f) => f,
        Err(e) => return CruxPipelineResult {
            stages,
            result: CruxResult::Error(format!("parse error: {}", e)),
        },
    };
    stages.push(PipelineStage::Parsed(russian_form.clone()));

    // Stage 2: Lower to State + Formula
    let (state, formula, backend) = lower_russian_form(&russian_form);
    stages.push(PipelineStage::Lowered { state: state.clone(), formula: formula.clone() });
    stages.push(PipelineStage::BackendSelected(backend.clone()));

    // Stage 3: OMEGA SMASHER
    let (omega_result, closure) = omega_smash_pipeline(backend, state.clone(), formula.clone());
    stages.push(PipelineStage::OmegaSmashed(omega_result.clone()));
    stages.push(PipelineStage::ProofClosed(closure));

    // Stage 4: Final result
    let result = omega_result_to_crux(&omega_result);
    stages.push(PipelineStage::Final(result.clone()));

    CruxPipelineResult { stages, result }
}

fn lower_russian_form(form: &RussianForm) -> (State, Formula, Backend) {
    match form {
        RussianForm::Ravnostvo(a, b) => {
            (State::S0, Formula::Eq(a.clone(), b.clone()), Backend::Kani(default_kani()))
        }
        RussianForm::Implikatsiya(a, b) => {
            (State::S0, Formula::Implies(Box::new(a.clone()), Box::new(b.clone())), Backend::Kani(default_kani()))
        }
        RussianForm::Konyunktsiya(a, b) => {
            (State::S0, Formula::And(vec![a.clone(), b.clone()]), Backend::Kani(default_kani()))
        }
        RussianForm::Dizyunktsiya(a, b) => {
            (State::S0, Formula::Or(vec![a.clone(), b.clone()]), Backend::Kani(default_kani()))
        }
        RussianForm::Otritsanie(a) => {
            (State::S0, Formula::Not(Box::new(a.clone())), Backend::Kani(default_kani()))
        }
        RussianForm::DlyaVsekh(var, sort, body) => {
            (State::S0, Formula::Forall { var: var.clone(), sort: sort.clone(), body: Box::new(body.clone()) }, Backend::Kani(default_kani()))
        }
        RussianForm::Sushchestvuet(var, sort, body) => {
            (State::S0, Formula::Exists { var: var.clone(), sort: sort.clone(), body: Box::new(body.clone()) }, Backend::Kani(default_kani()))
        }
        RussianForm::Sila(state, formula) => {
            (state.clone(), formula.clone(), Backend::Kani(default_kani()))
        }
        RussianForm::Omega(backend, state, formula) => {
            (state.clone(), formula.clone(), backend.clone())
        }
        RussianForm::Sostoyanie(state) => {
            (state.clone(), Formula::Atomic(Atomic::True), Backend::Kani(default_kani()))
        }
        RussianForm::Rekursiya(var, body) => {
            (State::S0, Formula::Mu { var: var.clone(), body: Box::new(body.clone()) }, Backend::Kani(default_kani()))
        }
        RussianForm::Dokazatelstvo(closure) => {
            (State::S0, Formula::Atomic(Atomic::True), Backend::Kani(default_kani()))
        }
    }
}

fn default_kani() -> KaniMIR {
    KaniMIR {
        name: "harness".into(),
        params: vec![],
        return_sort: Sort::Bool,
        body: vec![],
    }
}

fn omega_result_to_crux(r: &OmegaResult) -> CruxResult {
    match r {
        OmegaResult::Sat => CruxResult::Sat,
        OmegaResult::Unsat => CruxResult::Unsat,
        OmegaResult::Model(m) => CruxResult::Model(m.clone()),
        OmegaResult::Proved => CruxResult::Proved,
        OmegaResult::Unknown => CruxResult::Unknown,
        OmegaResult::Timeout => CruxResult::Timeout,
        OmegaResult::Alarm(loc, f) => CruxResult::Alarm { location: loc.clone(), formula: f.clone() },
    }
}

// ---------------------------------------------------------------------------
// 3. Pipeline result
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct CruxPipelineResult {
    pub stages: Vec<PipelineStage>,
    pub result: CruxResult,
}

impl CruxPipelineResult {
    pub fn report(&self) -> String {
        let mut out = String::new();
        out.push_str("=== CRUX · SILA · OMEGA-SMASHER Pipeline ===\n\n");
        for (i, stage) in self.stages.iter().enumerate() {
            match stage {
                PipelineStage::Parsed(f) => out.push_str(&format!("Stage {}: Parsed → {:?}\n", i, f)),
                PipelineStage::Lowered { state, formula } => {
                    out.push_str(&format!("Stage {}: Lowered → state={:?}, formula={:?}\n", i, state, formula))
                }
                PipelineStage::BackendSelected(b) => out.push_str(&format!("Stage {}: Backend → {:?}\n", i, b)),
                PipelineStage::OmegaSmashed(r) => out.push_str(&format!("Stage {}: OMEGA → {:?}\n", i, r)),
                PipelineStage::ProofClosed(c) => {
                    out.push_str(&format!("Stage {}: ProofClosure → {} obligations\n", i, c.obligations.len()))
                }
                PipelineStage::Final(r) => out.push_str(&format!("Stage {}: Result → {}\n", i, r)),
            }
        }
        out.push_str(&format!("\nFinal: {}\n", self.result.to_final()));
        out
    }
}

// ---------------------------------------------------------------------------
// 4. Direct pipeline (bypasses Russian parsing, takes AST directly)
// ---------------------------------------------------------------------------

pub fn run_crux_direct(state: State, formula: Formula, backend: Backend) -> CruxResult {
    let (omega_result, _closure) = omega_smash_pipeline(backend, state, formula);
    omega_result_to_crux(&omega_result)
}

/// Run with all backends automatically
pub fn run_crux_auto(state: State, formula: Formula) -> CruxResult {
    let mut smasher = OmegaSmasher::new();
    let result = smasher.smash_auto(&state, &formula);
    omega_result_to_crux(&result)
}

// End of CRUX pipeline (~200 lines)
// Covers: 5-stage pipeline (Parse → Lower → Backend → OMEGA → Close),
// Russian form lowering, pipeline reporting, direct/auto entry points.
