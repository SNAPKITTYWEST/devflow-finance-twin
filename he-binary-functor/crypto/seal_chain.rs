use crate::kernel::{BraidStateTransition, TransitionResult};

const FNV_OFFSET: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

fn fnv1a(mut h: u64, bytes: &[u8]) -> u64 {
    for &b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(FNV_PRIME);
    }
    h
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SealedStep {
    pub epoch: u64,
    pub generator: i8,
    pub state_vector: u64,
    pub relation_mask: u32,
    pub prev_seal: u64,
    pub seal: u64,
}

impl SealedStep {
    fn compute_seal(&self) -> u64 {
        let mut h = FNV_OFFSET;
        h = fnv1a(h, &self.epoch.to_le_bytes());
        h = fnv1a(h, &[self.generator as u8]);
        h = fnv1a(h, &self.state_vector.to_le_bytes());
        h = fnv1a(h, &self.relation_mask.to_le_bytes());
        h = fnv1a(h, &self.prev_seal.to_le_bytes());
        h
    }

    pub fn verify(&self) -> bool {
        self.seal == self.compute_seal()
    }
}

#[derive(Clone, Debug, Default)]
pub struct SealChain {
    pub steps: Vec<SealedStep>,
    pub head: u64,
}

impl SealChain {
    pub fn new() -> Self {
        Self {
            steps: Vec::new(),
            head: FNV_OFFSET,
        }
    }

    pub fn step(
        &mut self,
        state: &mut BraidStateTransition,
        generator: i8,
    ) -> TransitionResult {
        let r = state.evaluate_step(generator);
        if r != TransitionResult::Accepted {
            return r;
        }

        let mut rec = SealedStep {
            epoch: state.epoch_tick,
            generator: state.braid_generator,
            state_vector: state.state_vector,
            relation_mask: state.relation_mask,
            prev_seal: self.head,
            seal: 0,
        };
        rec.seal = rec.compute_seal();
        self.head = rec.seal;
        state.worm_seal = rec.seal;
        self.steps.push(rec);
        TransitionResult::Accepted
    }

    pub fn apply_word(
        &mut self,
        state: &mut BraidStateTransition,
        word: &[i8],
    ) -> Result<usize, usize> {
        for (i, &g) in word.iter().enumerate() {
            if self.step(state, g) == TransitionResult::RejectedMalformed {
                return Err(i);
            }
        }
        Ok(word.len())
    }

    pub fn verify_chain(&self) -> bool {
        let mut prev = FNV_OFFSET;
        for s in &self.steps {
            if s.prev_seal != prev || !s.verify() {
                return false;
            }
            prev = s.seal;
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kernel::BraidStateTransition;

    #[test]
    fn seal_chain_ok() {
        let mut state = BraidStateTransition::initial();
        let mut chain = SealChain::new();
        assert_eq!(chain.apply_word(&mut state, &[1, -2, 3]), Ok(3));
        assert!(chain.verify_chain());
        assert_eq!(chain.steps.len(), 3);
        assert_eq!(state.worm_seal, chain.head);
    }

    #[test]
    fn tamper_detected() {
        let mut state = BraidStateTransition::initial();
        let mut chain = SealChain::new();
        chain.apply_word(&mut state, &[1, 2]).unwrap();
        chain.steps[0].state_vector ^= 1;
        assert!(!chain.verify_chain());
    }
}
