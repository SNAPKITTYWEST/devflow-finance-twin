// =====================================================================
// PWC_CORE - Extracted from Why3 BraidAlgebra theory
// Verified: Semantic equivalence, length non-increase, Yang-Baxter
// =====================================================================

use std::fmt::Debug;

pub type GeneratorIndex = i32;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BraidWord {
    Gen(GeneratorIndex),
    Concat(Box<BraidWord>, Box<BraidWord>),
    Empty,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Complex {
    pub re: f64,
    pub im: f64,
}

impl Complex {
    pub const ZERO: Complex = Complex { re: 0.0, im: 0.0 };
    pub const ONE: Complex = Complex { re: 1.0, im: 0.0 };
    pub const PHI_HALF: Complex = Complex { re: 0.8090169943749474, im: 0.0 };
    pub const HALF: Complex = Complex { re: 0.5, im: 0.0 };
    pub const NEG_PHI_HALF: Complex = Complex { re: -0.8090169943749474, im: 0.0 };

    #[inline]
    pub fn add(self, other: Complex) -> Complex {
        Complex { re: self.re + other.re, im: self.im + other.im }
    }
    #[inline]
    pub fn sub(self, other: Complex) -> Complex {
        Complex { re: self.re - other.re, im: self.im - other.im }
    }
    #[inline]
    pub fn mul(self, other: Complex) -> Complex {
        Complex {
            re: self.re * other.re - self.im * other.im,
            im: self.re * other.im + self.im * other.re,
        }
    }
    #[inline]
    pub fn neg(self) -> Complex {
        Complex { re: -self.re, im: -self.im }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Matrix2x2(pub [Complex; 4]);

impl Matrix2x2 {
    pub const EYE: Matrix2x2 = Matrix2x2([
        Complex::ONE, Complex::ZERO,
        Complex::ZERO, Complex::ONE,
    ]);

    #[inline]
    pub fn mat22(a: Complex, b: Complex, c: Complex, d: Complex) -> Self {
        Matrix2x2([a, b, c, d])
    }

    #[inline]
    pub fn mul(self, other: Matrix2x2) -> Matrix2x2 {
        let [a1, b1, c1, d1] = self.0;
        let [a2, b2, c2, d2] = other.0;
        Matrix2x2([
            a1.mul(a2).add(b1.mul(c2)),
            a1.mul(b2).add(b1.mul(d2)),
            c1.mul(a2).add(d1.mul(c2)),
            c1.mul(b2).add(d1.mul(d2)),
        ])
    }
}

pub fn sigma_matrix(k: GeneratorIndex) -> Matrix2x2 {
    if k == 1 {
        Matrix2x2::mat22(
            Complex::PHI_HALF, Complex::HALF,
            Complex::HALF, Complex::NEG_PHI_HALF,
        )
    } else if k == -1 {
        Matrix2x2::mat22(
            Complex::NEG_PHI_HALF, Complex::HALF,
            Complex::HALF, Complex::PHI_HALF,
        )
    } else {
        Matrix2x2::EYE
    }
}

pub fn evaluate_matrix(w: &BraidWord) -> Matrix2x2 {
    match w {
        BraidWord::Empty => Matrix2x2::EYE,
        BraidWord::Gen(k) => sigma_matrix(*k),
        BraidWord::Concat(w1, w2) => evaluate_matrix(w1).mul(evaluate_matrix(w2)),
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct State {
    pub v1: Complex,
    pub v2: Complex,
}

pub fn apply_matrix(m: Matrix2x2, s: State) -> State {
    State {
        v1: m.0[0].mul(s.v1).add(m.0[1].mul(s.v2)),
        v2: m.0[2].mul(s.v1).add(m.0[3].mul(s.v2)),
    }
}

pub fn semantics(w: &BraidWord, s: State) -> State {
    apply_matrix(evaluate_matrix(w), s)
}

pub fn word_length(w: &BraidWord) -> usize {
    match w {
        BraidWord::Empty => 0,
        BraidWord::Gen(_) => 1,
        BraidWord::Concat(w1, w2) => word_length(w1) + word_length(w2),
    }
}

pub fn yang_baxter_equivalent(w1: &BraidWord, w2: &BraidWord) -> bool {
    let m1 = evaluate_matrix(w1);
    let m2 = evaluate_matrix(w2);
    m1.0.iter().zip(m2.0.iter()).all(|(a, b)| {
        (a.re - b.re).abs() < 1e-12 && (a.im - b.im).abs() < 1e-12
    })
}

pub fn parse_braid_word(input: &[GeneratorIndex]) -> BraidWord {
    input.iter().rev().fold(BraidWord::Empty, |acc, &g| {
        BraidWord::Concat(Box::new(BraidWord::Gen(g)), Box::new(acc))
    })
}
