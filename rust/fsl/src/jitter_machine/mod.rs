pub mod kernel;
pub mod ops;
pub mod bqn_spec;
#[cfg(test)]
mod demo;

pub use kernel::{Kernel, KernelConfig};
pub use ops::{pack, unpack, lcg, Opcodes, Flags};
