//! # NraayTensor: Binary Semantic Governance with Temporal Safety
//!
//! A formally verified tensor structure implementing:
//! - Binary Semantic Governance: Contiguity flag (B_layout, B_own)
//! - Virtual Slicing: Zero-copy views with shared Arc<Vec> ownership
//! - Temporal Safety: Use-after-free prevention via reference counting
//! - Materialization: Copy-on-write with COW semantics
//! - Governance Lemmas: Executable proof obligations (Lemma 1–5)
//! - RAW_ROUTE: Memory-region-affine task routing over worker deques
//! - Pure ML: Dense/MLP layers, activations, losses, SGD on NraayTensor
//!
//! The system decouples logical representation (semantic views with axes shifting)
//! from physical representation (strictly contiguous memory) to prevent fragmentation.

pub mod error;
pub mod tensor;
pub mod lemmas;
pub mod raw_route;
pub mod ml;

pub use error::{Result, NraayError};
pub use tensor::NraayTensor;
pub use lemmas::{prove_all, LemmaViolation};
pub use raw_route::{RawRouteRouter, Task, RegionId, WorkerId};
pub use ml::{Activation, Dense, MLP};

/// Prelude for convenient imports
pub mod prelude {
    pub use crate::error::{NraayError, Result};
    pub use crate::tensor::NraayTensor;
    pub use crate::lemmas::{prove_all, LemmaViolation};
    pub use crate::raw_route::{RawRouteRouter, Task};
    pub use crate::ml::{Activation, Dense, MLP};
}
