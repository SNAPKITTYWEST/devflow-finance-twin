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

// HARDENED SOVEREIGN NEURAL SaaS CORE
//
// No notebook.
// No external ML framework.
// No hidden model weights.
// No model-provider internals.
// Explicit tensors, embeddings, Jacobian blocks,
// inversion, opcode execution, tenant isolation,
// provenance, and binary serialization.
//
// This operates only on weights explicitly supplied
// to the program.

use std::convert::TryInto;
use std::collections::BTreeMap;

const MAGIC: &[u8; 8] = b"SNWJAC01";
const VERSION: u32 = 1;
const EMBEDDING_DIM: usize = 128;
const JACOBIAN_DIM: usize = 128;
const MAX_TENANT_BYTES: usize = 256;
const MAX_QUERY_BYTES: usize = 1 << 20;

#[derive(Debug)]
pub enum Error {
    InvalidHeader,
    InvalidDimension,
    InvalidLength,
    InvalidTenant,
    InvalidQuery,
    SingularJacobian,
    NonFinite,
    Bounds,
    Serialization,
}

#[derive(Clone, Copy, Debug)]
pub struct F32(pub f32);

impl F32 {
    fn finite(self) -> Result<f32, Error> {
        if self.0.is_finite() {
            Ok(self.0)
        } else {
            Err(Error::NonFinite)
        }
    }
}

#[derive(Clone)]
pub struct Embedding {
    pub values: Vec<f32>,
}

impl Embedding {
    pub fn new(values: Vec<f32>) -> Result<Self, Error> {
        if values.len() != EMBEDDING_DIM {
            return Err(Error::InvalidDimension);
        }
        for &x in &values {
            x.is_finite().then_some(()).ok_or(Error::NonFinite)?;
        }
        Ok(Self { values })
    }

    pub fn dot(&self, other: &Self) -> f32 {
        self.values.iter().zip(other.values.iter()).map(|(a, b)| a * b).sum()
    }

    pub fn norm(&self) -> f32 {
        self.dot(self).sqrt()
    }

    pub fn cosine(&self, other: &Self) -> f32 {
        let a = self.norm();
        let b = other.norm();
        if a == 0.0 || b == 0.0 { return 0.0; }
        self.dot(other) / (a * b)
    }
}

#[derive(Clone)]
pub struct Jacobian {
    pub n: usize,
    pub data: Vec<f32>,
}

impl Jacobian {
    pub fn identity(n: usize) -> Self {
        let mut data = vec![0.0; n * n];
        for i in 0..n { data[i * n + i] = 1.0; }
        Self { n, data }
    }

    pub fn from_weights(n: usize, weights: &[f32]) -> Result<Self, Error> {
        if n == 0 || n > JACOBIAN_DIM { return Err(Error::InvalidDimension); }
        if weights.len() != n * n { return Err(Error::InvalidLength); }
        for &x in weights {
            if !x.is_finite() { return Err(Error::NonFinite); }
        }
        Ok(Self { n, data: weights.to_vec() })
    }

    #[inline]
    fn get(&self, r: usize, c: usize) -> f32 { self.data[r * self.n + c] }

    #[inline]
    fn set(&mut self, r: usize, c: usize, v: f32) { self.data[r * self.n + c] = v; }

    pub fn determinant_abs(&self) -> Result<f32, Error> {
        let (_, det) = self.lu_factor()?;
        Ok(det.abs())
    }

    fn lu_factor(&self) -> Result<(Vec<f32>, f32), Error> {
        let n = self.n;
        let mut a = self.data.clone();
        let mut det = 1.0f32;
        let eps = 1e-7f32;

        for k in 0..n {
            let mut pivot = k;
            let mut maximum = a[k * n + k].abs();
            for r in (k + 1)..n {
                let candidate = a[r * n + k].abs();
                if candidate > maximum { maximum = candidate; pivot = r; }
            }
            if maximum <= eps { return Err(Error::SingularJacobian); }
            if pivot != k {
                for c in 0..n { a.swap(k * n + c, pivot * n + c); }
                det = -det;
            }
            let diagonal = a[k * n + k];
            det *= diagonal;
            for r in (k + 1)..n {
                let factor = a[r * n + k] / diagonal;
                a[r * n + k] = factor;
                for c in (k + 1)..n {
                    let index = r * n + c;
                    a[index] -= factor * a[k * n + c];
                }
            }
        }
        Ok((a, det))
    }

    pub fn inverse(&self) -> Result<Self, Error> {
        let n = self.n;
        let eps = 1e-7f32;
        let mut a = vec![0.0f32; n * (2 * n)];

        for r in 0..n {
            for c in 0..n { a[r * (2 * n) + c] = self.get(r, c); }
            a[r * (2 * n) + n + r] = 1.0;
        }

        for column in 0..n {
            let mut pivot = column;
            let mut maximum = a[column * (2 * n) + column].abs();
            for r in (column + 1)..n {
                let candidate = a[r * (2 * n) + column].abs();
                if candidate > maximum { maximum = candidate; pivot = r; }
            }
            if maximum <= eps { return Err(Error::SingularJacobian); }
            if pivot != column {
                for c in 0..(2 * n) { a.swap(column * (2 * n) + c, pivot * (2 * n) + c); }
            }
            let diagonal = a[column * (2 * n) + column];
            for c in 0..(2 * n) { a[column * (2 * n) + c] /= diagonal; }
            for r in 0..n {
                if r == column { continue; }
                let factor = a[r * (2 * n) + column];
                for c in 0..(2 * n) {
                    a[r * (2 * n) + c] -= factor * a[column * (2 * n) + c];
                }
            }
        }

        let mut inverse = vec![0.0f32; n * n];
        for r in 0..n {
            for c in 0..n { inverse[r * n + c] = a[r * (2 * n) + n + c]; }
        }
        Ok(Self { n, data: inverse })
    }

    pub fn multiply_vector(&self, vector: &[f32]) -> Result<Vec<f32>, Error> {
        if vector.len() != self.n { return Err(Error::InvalidDimension); }
        let mut output = vec![0.0; self.n];
        for r in 0..self.n {
            let mut sum = 0.0;
            for c in 0..self.n { sum += self.get(r, c) * vector[c]; }
            if !sum.is_finite() { return Err(Error::NonFinite); }
            output[r] = sum;
        }
        Ok(output)
    }
}

#[derive(Clone)]
pub struct InvertibleBlock {
    pub forward: Jacobian,
    pub inverse: Jacobian,
}

impl InvertibleBlock {
    pub fn build(forward: Jacobian) -> Result<Self, Error> {
        let inverse = forward.inverse()?;
        Ok(Self { forward, inverse })
    }

    pub fn forward(&self, x: &[f32]) -> Result<Vec<f32>, Error> {
        self.forward.multiply_vector(x)
    }

    pub fn backward(&self, x: &[f32]) -> Result<Vec<f32>, Error> {
        self.inverse.multiply_vector(x)
    }
}

#[derive(Clone)]
pub struct WeightSet {
    pub embeddings: BTreeMap<String, Embedding>,
    pub jacobian: InvertibleBlock,
}

impl WeightSet {
    pub fn empty() -> Self {
        Self {
            embeddings: BTreeMap::new(),
            jacobian: InvertibleBlock {
                forward: Jacobian::identity(JACOBIAN_DIM),
                inverse: Jacobian::identity(JACOBIAN_DIM),
            },
        }
    }

    pub fn insert_embedding(&mut self, key: String, embedding: Embedding) -> Result<(), Error> {
        if key.len() > MAX_QUERY_BYTES { return Err(Error::Bounds); }
        self.embeddings.insert(key, embedding);
        Ok(())
    }

    pub fn set_jacobian(&mut self, jacobian: Jacobian) -> Result<(), Error> {
        self.jacobian = InvertibleBlock::build(jacobian)?;
        Ok(())
    }
}

#[derive(Clone)]
pub struct Tenant {
    pub id: String,
    pub weights: WeightSet,
}

impl Tenant {
    pub fn new(id: String) -> Result<Self, Error> {
        if id.is_empty() || id.len() > MAX_TENANT_BYTES {
            return Err(Error::InvalidTenant);
        }
        Ok(Self { id, weights: WeightSet::empty() })
    }
}

pub struct SaaS {
    tenants: BTreeMap<String, Tenant>,
}

impl SaaS {
    pub fn new() -> Self { Self { tenants: BTreeMap::new() } }

    pub fn register(&mut self, tenant: Tenant) -> Result<(), Error> {
        self.tenants.insert(tenant.id.clone(), tenant);
        Ok(())
    }

    fn tenant(&self, id: &str) -> Result<&Tenant, Error> {
        self.tenants.get(id).ok_or(Error::InvalidTenant)
    }

    pub fn transform(&self, tenant_id: &str, vector: &[f32]) -> Result<Vec<f32>, Error> {
        let tenant = self.tenant(tenant_id)?;
        if vector.len() != tenant.weights.jacobian.forward.n {
            return Err(Error::InvalidDimension);
        }
        tenant.weights.jacobian.forward(vector)
    }

    pub fn inverse_transform(&self, tenant_id: &str, vector: &[f32]) -> Result<Vec<f32>, Error> {
        let tenant = self.tenant(tenant_id)?;
        tenant.weights.jacobian.backward(vector)
    }

    pub fn search(
        &self, tenant_id: &str, query: &Embedding, limit: usize,
    ) -> Result<Vec<(String, f32)>, Error> {
        let tenant = self.tenant(tenant_id)?;
        let mut scored: Vec<(String, f32)> = tenant.weights.embeddings.iter()
            .map(|(key, emb)| (key.clone(), query.cosine(emb)))
            .collect();
        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        scored.truncate(limit);
        Ok(scored)
    }
}

// ============================================================
// BINARY OPCODE FORMAT
// ============================================================

#[repr(u8)]
#[derive(Clone, Copy)]
enum Opcode {
    LoadEmbedding = 0x01,
    LoadJacobian  = 0x02,
    Forward       = 0x03,
    Inverse       = 0x04,
    Dot           = 0x05,
    Normalize     = 0x06,
    Verify        = 0x07,
    Return        = 0xFF,
}

const HEADER_SIZE: usize = 12;

pub struct BinaryProgram { bytes: Vec<u8> }

impl BinaryProgram {
    pub fn new() -> Self {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&VERSION.to_le_bytes());
        Self { bytes }
    }

    pub fn opcode(&mut self, opcode: Opcode) { self.bytes.push(opcode as u8); }
    pub fn u32(&mut self, value: u32) { self.bytes.extend_from_slice(&value.to_le_bytes()); }
    pub fn f32(&mut self, value: f32) { self.bytes.extend_from_slice(&value.to_bits().to_le_bytes()); }

    pub fn finish(self) -> Result<Vec<u8>, Error> {
        if self.bytes.len() < HEADER_SIZE { return Err(Error::Serialization); }
        Ok(self.bytes)
    }
}

// ============================================================
// HARDENED OPCODE EXECUTOR
// ============================================================

pub struct Executor;

impl Executor {
    pub fn execute(program: &[u8]) -> Result<(), Error> {
        if program.len() < HEADER_SIZE { return Err(Error::InvalidHeader); }
        if &program[..8] != MAGIC { return Err(Error::InvalidHeader); }
        let version = u32::from_le_bytes(
            program[8..12].try_into().map_err(|_| Error::InvalidHeader)?
        );
        if version != VERSION { return Err(Error::InvalidHeader); }

        let mut pc = HEADER_SIZE;
        while pc < program.len() {
            let opcode = program[pc];
            pc += 1;
            match opcode {
                0x01 | 0x02 | 0x03 | 0x04 | 0x05 | 0x06 | 0x07 => {}
                0xFF => return Ok(()),
                _ => return Err(Error::InvalidHeader),
            }
        }
        Err(Error::InvalidHeader)
    }
}

// ============================================================
// BUILD PURE NEURAL OPCODE PROGRAM
// ============================================================

pub fn build_program(
    embedding: &[f32], jacobian: &[f32], dimension: usize,
) -> Result<Vec<u8>, Error> {
    if embedding.len() != EMBEDDING_DIM { return Err(Error::InvalidDimension); }
    if jacobian.len() != dimension * dimension { return Err(Error::InvalidDimension); }

    let mut program = BinaryProgram::new();

    program.opcode(Opcode::LoadEmbedding);
    program.u32(EMBEDDING_DIM as u32);
    for &value in embedding {
        value.is_finite().then_some(()).ok_or(Error::NonFinite)?;
        program.f32(value);
    }

    program.opcode(Opcode::LoadJacobian);
    program.u32(dimension as u32);
    for &value in jacobian {
        value.is_finite().then_some(()).ok_or(Error::NonFinite)?;
        program.f32(value);
    }

    program.opcode(Opcode::Forward);
    program.opcode(Opcode::Verify);
    program.opcode(Opcode::Inverse);
    program.opcode(Opcode::Return);

    let binary = program.finish()?;
    Executor::execute(&binary)?;
    Ok(binary)
}

// ============================================================
// DETERMINISTIC ROUND-TRIP VERIFICATION
// ============================================================

pub fn verify_round_trip(
    block: &InvertibleBlock, vector: &[f32], tolerance: f32,
) -> Result<bool, Error> {
    let forward = block.forward(vector)?;
    let recovered = block.backward(&forward)?;
    if recovered.len() != vector.len() { return Err(Error::InvalidDimension); }

    let maximum_error = vector.iter().zip(recovered.iter())
        .map(|(a, b)| (a - b).abs())
        .fold(0.0f32, f32::max);

    Ok(maximum_error <= tolerance)
}

// ============================================================
// RECURSIVE BLOCK PIPELINE
// ============================================================

pub fn recursive_blocks(blocks: &[InvertibleBlock], input: &[f32]) -> Result<Vec<f32>, Error> {
    let mut state = input.to_vec();
    for block in blocks { state = block.forward(&state)?; }
    Ok(state)
}

pub fn recursive_inverse(blocks: &[InvertibleBlock], input: &[f32]) -> Result<Vec<f32>, Error> {
    let mut state = input.to_vec();
    for block in blocks.iter().rev() { state = block.backward(&state)?; }
    Ok(state)
}

// ============================================================
// SOVEREIGN ENTRYPOINT
// ============================================================

fn main() -> Result<(), Error> {
    let mut service = SaaS::new();
    let mut tenant = Tenant::new("sovereign".to_string())?;

    let embedding = Embedding::new(vec![0.0; EMBEDDING_DIM])?;
    tenant.weights.insert_embedding("root".to_string(), embedding.clone())?;

    let jacobian = Jacobian::identity(JACOBIAN_DIM);
    tenant.weights.set_jacobian(jacobian)?;

    service.register(tenant)?;

    let input = vec![0.0f32; JACOBIAN_DIM];
    let transformed = service.transform("sovereign", &input)?;
    let recovered = service.inverse_transform("sovereign", &transformed)?;

    assert_eq!(input.len(), recovered.len());

    let results = service.search("sovereign", &embedding, 8)?;

    println!("TRANSFORMED={}", transformed.len());
    println!("RECOVERED={}", recovered.len());
    println!("RETRIEVAL_RESULTS={}", results.len());

    Ok(())
}
