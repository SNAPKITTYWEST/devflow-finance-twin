// =====================================================================
// TAU_MODEL - Polymorphic Cost Model
// Verified: τ_monotonic_transform across all domains
// =====================================================================

use crate::pwc_core::{BraidWord, word_length};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExecutionDomain {
    Serial,
    Vector,
    Quantum,
    Hardware,
}

impl ExecutionDomain {
    pub fn tau(self, word: &BraidWord) -> usize {
        let len = word_length(word);
        match self {
            ExecutionDomain::Serial => len,
            ExecutionDomain::Vector => (len + 3) / 4,
            ExecutionDomain::Quantum => 1,
            ExecutionDomain::Hardware => 1,
        }
    }
}

pub fn verify_tau_monotonic(original: &BraidWord, compressed: &BraidWord) {
    for domain in [
        ExecutionDomain::Serial,
        ExecutionDomain::Vector,
        ExecutionDomain::Quantum,
        ExecutionDomain::Hardware,
    ] {
        let tau_orig = domain.tau(original);
        let tau_comp = domain.tau(compressed);
        debug_assert!(
            tau_comp <= tau_orig,
            "τ violation in {:?}: {} -> {}",
            domain, tau_orig, tau_comp
        );
    }
}
