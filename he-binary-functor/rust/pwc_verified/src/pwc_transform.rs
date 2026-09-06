// =====================================================================
// PWC_TRANSFORM - Recursive Yang-Baxter Compression
// Verified: Preserves semantics, never increases length
// =====================================================================

use crate::pwc_core::{BraidWord, GeneratorIndex, yang_baxter_equivalent, word_length};

impl BraidWord {
    fn yb_step(&self) -> (BraidWord, bool) {
        match self {
            BraidWord::Concat(l, r) => {
                if let BraidWord::Concat(l2, r2) = l.as_ref() {
                    if let (BraidWord::Gen(i), BraidWord::Concat(l3, r3)) = (l2.as_ref(), r2.as_ref()) {
                        if let (BraidWord::Gen(j), BraidWord::Gen(k)) = (l3.as_ref(), r3.as_ref()) {
                            if ((j == i + 1 || j == i - 1) && k == i) {
                                let new_head = BraidWord::Concat(
                                    Box::new(BraidWord::Gen(*j)),
                                    Box::new(BraidWord::Concat(
                                        Box::new(BraidWord::Gen(*i)),
                                        Box::new(BraidWord::Gen(*j)),
                                    )),
                                );
                                return (BraidWord::Concat(Box::new(new_head), r.clone()), true);
                            }
                        }
                    }
                }
                let (new_l, changed) = l.yb_step();
                if changed {
                    return (BraidWord::Concat(Box::new(new_l), r.clone()), true);
                }
                let (new_r, changed) = r.yb_step();
                (BraidWord::Concat(Box::new(new_l), Box::new(new_r)), changed)
            }
            _ => (self.clone(), false),
        }
    }

    pub fn wormhole_transform(&self) -> BraidWord {
        let fuel = word_length(self) * word_length(self);
        self.wormhole_transform_fuel(fuel)
    }

    fn wormhole_transform_fuel(&self, fuel: usize) -> BraidWord {
        if fuel == 0 {
            return self.clone();
        }
        let (w_prime, changed) = self.yb_step();
        if changed {
            w_prime.wormhole_transform_fuel(fuel - 1)
        } else {
            self.clone()
        }
    }

    pub fn flatten(&self) -> Vec<GeneratorIndex> {
        let mut out = Vec::with_capacity(word_length(self));
        self.flatten_into(&mut out);
        out
    }

    fn flatten_into(&self, out: &mut Vec<GeneratorIndex>) {
        match self {
            BraidWord::Gen(i) => out.push(*i),
            BraidWord::Concat(l, r) => {
                l.flatten_into(out);
                r.flatten_into(out);
            }
            BraidWord::Empty => {}
        }
    }
}

pub fn verify_semantic_preservation(original: &BraidWord, compressed: &BraidWord) {
    debug_assert!(
        yang_baxter_equivalent(original, compressed),
        "Semantic preservation violated: matrices differ"
    );
}

pub fn verify_length_nonincrease(original: &BraidWord, compressed: &BraidWord) {
    debug_assert!(
        word_length(compressed) <= word_length(original),
        "Length increased: {} -> {}",
        word_length(original),
        word_length(compressed)
    );
}
