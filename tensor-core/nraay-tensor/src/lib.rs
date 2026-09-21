//! # NraayTensor: Binary Semantic Governance with Temporal Safety
//!
//! A formally verified tensor structure implementing:
//! - Binary Semantic Governance: Contiguity flag (B_layout, B_own)
//! - Virtual Slicing: Zero-copy views with shared Arc<Vec> ownership
//! - Temporal Safety: Use-after-free prevention via reference counting
//! - Materialization: Copy-on-write with COW semantics
//!
//! The system decouples logical representation (semantic views with axes shifting)
//! from physical representation (strictly contiguous memory) to prevent fragmentation.

pub mod error;
pub mod tensor;

pub use error::{Result, NraayError};
pub use tensor::NraayTensor;

/// Prelude for convenient imports
pub mod prelude {
    pub use crate::error::{NraayError, Result};
    pub use crate::tensor::NraayTensor;
}
