use crate::zeros::{N_ZEROS, T};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CriticalPoint {
    pub t: f64,
    pub upper: bool,
}

impl CriticalPoint {
    pub fn rho(t: f64) -> Self { Self { t, upper: true } }
    pub fn rho_bar(t: f64) -> Self { Self { t, upper: false } }
}

#[derive(Clone, Debug)]
pub struct ZeroOrbit {
    pub n: usize,
    pub t: f64,
    pub rho: CriticalPoint,
    pub rho_bar: CriticalPoint,
    pub orbit: Vec<CriticalPoint>,
    pub seal: u64,
}

const FNV_OFFSET: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

fn fnv1a_u64(mut h: u64, bytes: &[u8]) -> u64 {
    for &b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(FNV_PRIME);
    }
    h
}

fn fnv1a_f64(h: u64, x: f64) -> u64 {
    fnv1a_u64(h, &x.to_le_bytes())
}

fn digest_mod(digest: &[u8], m: usize) -> usize {
    if m == 0 { return 0; }
    let mut acc: u128 = 0;
    for &b in digest {
        acc = (acc << 8) | (b as u128);
        if acc > (u128::MAX >> 8) { acc %= m as u128; }
    }
    (acc % m as u128) as usize
}

fn shift_from_window(digest: &[u8], window: usize) -> f64 {
    let start = (window * 8) % digest.len().max(1);
    let mut buf = [0u8; 8];
    for i in 0..8 { buf[i] = digest[(start + i) % digest.len().max(1)]; }
    let v = u64::from_le_bytes(buf);
    (v as f64) / (u64::MAX as f64)
}

pub const ORBIT_PAIRS: usize = 3;
pub const MAX_SHIFT: f64 = 0.5;

pub fn map_digest(digest: &[u8]) -> ZeroOrbit {
    let n = 1 + digest_mod(digest, N_ZEROS);
    let t = T[n - 1];
    let rho = CriticalPoint::rho(t);
    let rho_bar = CriticalPoint::rho_bar(t);

    let mut orbit = Vec::with_capacity(2 + 2 * ORBIT_PAIRS);
    orbit.push(rho);
    orbit.push(rho_bar);
    for k in 0..ORBIT_PAIRS {
        let frac = shift_from_window(digest, k + 1);
        let delta = (frac * 2.0 - 1.0) * MAX_SHIFT;
        let t2 = t + delta;
        let t2_abs = t2.abs();
        orbit.push(CriticalPoint::rho(t2_abs));
        orbit.push(CriticalPoint::rho_bar(t2_abs));
    }

    let mut h = FNV_OFFSET;
    h = fnv1a_u64(h, &(n as u64).to_le_bytes());
    h = fnv1a_f64(h, t);
    for p in &orbit {
        h = fnv1a_f64(h, p.t);
        h = fnv1a_u64(h, &[p.upper as u8]);
    }

    ZeroOrbit { n, t, rho, rho_bar, orbit, seal: h }
}

pub fn map_digest32(d: &[u8; 32]) -> ZeroOrbit {
    map_digest(d)
}
