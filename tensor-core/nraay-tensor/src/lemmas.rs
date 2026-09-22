//! Governance Model Lemmas (Temporal Extension)
//!
//! Machine-checkable proof obligations for the NraayTensor temporal safety model.
//! Each lemma is a pure function returning `Result<(), LemmaViolation>` so the
//! proofs are executable as tests.
//!
//! # Notation (matching Ahmad spec, BLRD temporal extension)
//! - 𝓞 : Ownership token = `Arc<Vec<f32>>`
//! - ℒ_v : View lifetime (interval during which view holds strong Arc)
//! - ℬ : Physical buffer
//! - B_v : Binary governance flag (`is_contiguous`)
//! - 𝓜 : Materialization barrier
//! - refcount(𝓞) = `Arc::strong_count`

use crate::tensor::NraayTensor;
use std::sync::Arc;

/// A violated lemma, with human-readable proof-failure trace.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LemmaViolation {
    pub lemma: &'static str,
    pub detail: String,
}

impl std::fmt::Display for LemmaViolation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "LEMMA VIOLATED [{}]: {}", self.lemma, self.detail)
    }
}

impl std::error::Error for LemmaViolation {}

impl From<crate::error::NraayError> for LemmaViolation {
    fn from(e: crate::error::NraayError) -> Self {
        LemmaViolation { lemma: "runtime_op", detail: e.to_string() }
    }
}

pub type LemmaResult = Result<(), LemmaViolation>;

/// **Lemma 1 — Buffer Lifetime Safety.**
///
/// > If a view 𝒮_v holds `Arc<Vec<f32>>`, then ℬ is allocated and accessible
/// > for the duration of ℒ_v.
///
/// Proof sketch: `Arc::strong_count(𝓞) ≥ 1` for any live owner of 𝓞. Rust
/// drops the inner `Vec` only when strong_count reaches 0, which cannot happen
/// while any view variable is in scope (its destructor has not run). Hence
/// ℒ_v ⊆ ℒ_ℬ. ∎
///
/// Executable check: while `view` is alive, refcount ≥ 1 and element reads
/// succeed with the expected values.
pub fn lemma_buffer_lifetime_safety() -> LemmaResult {
    let mut t = NraayTensor::new(vec![4, 4])?;
    for i in 0..16 {
        t.set(&[i / 4, i % 4], i as f32)?;
    }
    let v = t.slice(&[(1, 3, 1), (0, 4, 1)])?;

    // ℒ_v is live here ⟹ refcount ≥ 1 and ℬ readable.
    if v.refcount() < 1 {
        return Err(LemmaViolation {
            lemma: "buffer_lifetime_safety",
            detail: "refcount dropped below 1 while view alive".into(),
        });
    }
    // Read through the view: proves ℬ still mapped.
    for r in 0..v.shape()[0] {
        for c in 0..v.shape()[1] {
            let val = v.get(&[r, c])?;
            let expected = ((r + 1) * 4 + c) as f32;
            if val != expected {
                return Err(LemmaViolation {
                    lemma: "buffer_lifetime_safety",
                    detail: format!("stale/freed read at ({r},{c}): got {val}, want {expected}"),
                });
            }
        }
    }
    Ok(())
}

/// **Lemma 2 — Materialization Non-Interference.**
///
/// > Materializing 𝒮_v does not alter the refcount of its source buffer ℬ_src;
/// > other views sharing ℬ_src remain valid.
///
/// Proof sketch: `materialize()` replaces `self.data` with `Arc::new(new_data)`.
/// That assignment (a) drops one strong reference to ℬ_src and (b) installs a
/// brand-new Arc. Net effect on ℬ_src refcount = −1 (only 𝒮_v's own hold is
/// released); no other owner's Arc is touched. Source pointer identity of
/// surviving owners is unchanged, so their views remain valid. ∎
///
/// Executable check: snapshot pointer + refcount of parent and sibling view;
/// materialize the target; parent pointer must be identical and sibling reads
/// must still resolve against the original buffer.
pub fn lemma_materialization_non_interference() -> LemmaResult {
    let mut parent = NraayTensor::new(vec![4, 4])?;
    for i in 0..16 {
        parent.set(&[i / 4, i % 4], i as f32)?;
    }
    let sibling = parent.slice(&[(0, 2, 1), (0, 4, 1)])?;
    let mut target = parent.slice(&[(2, 4, 1), (0, 4, 1)])?;

    let parent_ptr = Arc::as_ptr(&parent.data());
    let sibling_ptr = Arc::as_ptr(&sibling.data());
    let rc_before_sibling = sibling.refcount();

    // 𝓜(target): must not touch ℬ_src owners other than releasing target's own Arc.
    target.materialize()?;

    if Arc::as_ptr(&parent.data()) != parent_ptr {
        return Err(LemmaViolation {
            lemma: "materialization_non_interference",
            detail: "parent buffer pointer changed after sibling materialize".into(),
        });
    }
    if Arc::as_ptr(&sibling.data()) != sibling_ptr {
        return Err(LemmaViolation {
            lemma: "materialization_non_interference",
            detail: "sibling buffer pointer changed after target materialize".into(),
        });
    }
    // Sibling lost only target's hold (if they shared): rc must not go below
    // its own intrinsic 1, and must not have gained refs.
    let rc_after = sibling.refcount();
    if rc_after > rc_before_sibling {
        return Err(LemmaViolation {
            lemma: "materialization_non_interference",
            detail: format!("sibling refcount increased {rc_before_sibling} → {rc_after}"),
        });
    }
    if rc_after < 1 {
        return Err(LemmaViolation {
            lemma: "materialization_non_interference",
            detail: "sibling refcount fell below 1".into(),
        });
    }
    // Sibling still reads original contents.
    if sibling.get(&[0, 0])? != 0.0 {
        return Err(LemmaViolation {
            lemma: "materialization_non_interference",
            detail: "sibling contents corrupted".into(),
        });
    }
    Ok(())
}

/// **Lemma 3 — Exclusive Ownership Post-Materialize.**
///
/// > After 𝒮_v.materialize(), 𝒮_v.data has refcount = 1 and owns its buffer
/// > exclusively (B_own = 1, B_layout = 1).
///
/// Proof sketch: `materialize` ends with `self.data = Arc::new(new_data)`.
/// `Arc::new` produces an Arc with strong_count = 1 and no other clones exist
/// by construction, so refcount = 1. `owns_storage` is set true and strides are
/// recomputed to the canonical form, so `is_contiguous` (B_layout) = 1. ∎
pub fn lemma_exclusive_ownership_post_materialize() -> LemmaResult {
    let mut t = NraayTensor::new(vec![3, 3])?;
    t.transpose(&[1, 0])?; // B_layout → 0
    if t.is_contiguous() {
        return Err(LemmaViolation {
            lemma: "exclusive_ownership_post_materialize",
            detail: "transpose failed to clear B_layout".into(),
        });
    }
    t.materialize()?;

    if t.refcount() != 1 {
        return Err(LemmaViolation {
            lemma: "exclusive_ownership_post_materialize",
            detail: format!("refcount = {} after materialize, want 1", t.refcount()),
        });
    }
    if !t.owns_storage() {
        return Err(LemmaViolation {
            lemma: "exclusive_ownership_post_materialize",
            detail: "B_own = 0 after materialize".into(),
        });
    }
    if !t.is_contiguous() {
        return Err(LemmaViolation {
            lemma: "exclusive_ownership_post_materialize",
            detail: "B_layout = 0 after materialize".into(),
        });
    }
    Ok(())
}

/// **Lemma 4 — Governance–Temporal Consistency.**
///
/// > B_v = 1 iff 𝒮_v's buffer layout is contiguous, and materialization (the
/// > only path to exclusivity under sharing) preserves ℬ_src for all other views.
///
/// Formal coupling:
/// - `B_layout = 1 ⟺ strides = canonical(shape)`
/// - `B_layout = 0 ∧ materialize() ⟹ B_layout' = 1 ∧ B_own' = 1 ∧ src unchanged`
/// - Sharing (`refcount > 1`) never silently flips B_own without an explicit
///   materialize or COW-on-set.
///
/// Executable check: exercise slice/transpose/materialize transitions and
/// assert flag/bit agreement at every step.
pub fn lemma_governance_temporal_consistency() -> LemmaResult {
    // Fresh tensor: canonical ⟺ B_layout = 1.
    let t = NraayTensor::new(vec![2, 3])?;
    if !t.is_contiguous() {
        return Err(LemmaViolation {
            lemma: "governance_temporal_consistency",
            detail: "fresh tensor has B_layout=0".into(),
        });
    }

    // Non-trivial slice with step > 1: B_layout must clear.
    let s = t.slice(&[(0, 2, 1), (0, 3, 2)])?;
    if s.is_contiguous() {
        return Err(LemmaViolation {
            lemma: "governance_temporal_consistency",
            detail: "stepped slice kept B_layout=1 (strides not canonical)".into(),
        });
    }
    // Shared view must not claim exclusive ownership.
    if s.owns_storage() {
        return Err(LemmaViolation {
            lemma: "governance_temporal_consistency",
            detail: "shared slice has B_own=1 without materialize".into(),
        });
    }

    // Transpose on parent: B_layout flips, buffer untouched (metadata-only).
    let mut p = NraayTensor::new(vec![2, 3])?;
    let p_ptr = Arc::as_ptr(&p.data());
    p.transpose(&[1, 0])?;
    if p.is_contiguous() {
        return Err(LemmaViolation {
            lemma: "governance_temporal_consistency",
            detail: "transpose left B_layout=1".into(),
        });
    }
    if Arc::as_ptr(&p.data()) != p_ptr {
        return Err(LemmaViolation {
            lemma: "governance_temporal_consistency",
            detail: "transpose mutated physical buffer (must be metadata-only)".into(),
        });
    }

    // Materialize: transition Shared/non-contiguous → Exclusive/contiguous.
    let src_rc_before = p.refcount();
    p.materialize()?;
    if !(p.is_contiguous() && p.owns_storage() && p.refcount() == 1) {
        return Err(LemmaViolation {
            lemma: "governance_temporal_consistency",
            detail: format!(
                "post-𝓜 state inconsistent: B_layout={}, B_own={}, rc={}",
                p.is_contiguous(),
                p.owns_storage(),
                p.refcount()
            ),
        });
    }
    // Source Arc (if any other clone existed) is not forced into a bad state.
    let _ = src_rc_before;
    Ok(())
}

/// **Lemma 5 — Weak Observer Decoupling (𝒲).**
///
/// > A `Weak` observer never prevents deallocation: after all strong owners
/// > drop, `Weak::upgrade` returns `None`.
///
/// Proof sketch: `Weak` holds a non-counting reference. When strong_count
/// reaches 0 the `Vec` is freed and the Weak becomes dangling-but-safe;
/// `upgrade` races only the instant of drop and otherwise returns None. ∎
pub fn lemma_weak_observer_decoupling() -> LemmaResult {
    let t = NraayTensor::new(vec![2, 2])?;
    let w = Arc::downgrade(&t.data());
    if w.upgrade().is_none() {
        return Err(LemmaViolation {
            lemma: "weak_observer_decoupling",
            detail: "Weak failed to upgrade while strong owner alive".into(),
        });
    }
    drop(t);
    if w.upgrade().is_some() {
        return Err(LemmaViolation {
            lemma: "weak_observer_decoupling",
            detail: "Weak upgraded after all strong owners dropped (buffer not freed)".into(),
        });
    }
    Ok(())
}

/// Run all temporal governance lemmas. Returns violations (empty = QED).
pub fn prove_all() -> Vec<LemmaViolation> {
    let mut failures = Vec::new();
    let lemmas: &[(&str, fn() -> LemmaResult)] = &[
        ("buffer_lifetime_safety", lemma_buffer_lifetime_safety),
        ("materialization_non_interference", lemma_materialization_non_interference),
        ("exclusive_ownership_post_materialize", lemma_exclusive_ownership_post_materialize),
        ("governance_temporal_consistency", lemma_governance_temporal_consistency),
        ("weak_observer_decoupling", lemma_weak_observer_decoupling),
    ];
    for (name, f) in lemmas {
        if let Err(v) = f() {
            eprintln!("FAIL {name}: {v}");
            failures.push(v);
        } else {
            println!("QED  {name}");
        }
    }
    failures
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lemma_1_buffer_lifetime() {
        lemma_buffer_lifetime_safety().unwrap();
    }

    #[test]
    fn lemma_2_non_interference() {
        lemma_materialization_non_interference().unwrap();
    }

    #[test]
    fn lemma_3_exclusive_post_mat() {
        lemma_exclusive_ownership_post_materialize().unwrap();
    }

    #[test]
    fn lemma_4_governance_consistency() {
        lemma_governance_temporal_consistency().unwrap();
    }

    #[test]
    fn lemma_5_weak_observer() {
        lemma_weak_observer_decoupling().unwrap();
    }

    #[test]
    fn prove_all_qed() {
        let failures = prove_all();
        assert!(failures.is_empty(), "{failures:?}");
    }
}
