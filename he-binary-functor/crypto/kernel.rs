pub const MAX_GEN: i8 = 4;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransitionResult {
    Accepted,
    RejectedMalformed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BraidStateTransition {
    pub epoch_tick: u64,
    pub relation_mask: u32,
    pub braid_generator: i8,
    pub state_vector: u64,
    pub worm_seal: u64,
}

impl BraidStateTransition {
    pub const fn initial() -> Self {
        Self {
            epoch_tick: 0,
            relation_mask: 0,
            braid_generator: 0,
            state_vector: 0,
            worm_seal: 0xcbf29ce484222325,
        }
    }

    #[inline(always)]
    pub const fn valid_generator(g: i8) -> bool {
        let a = if g < 0 { -g } else { g };
        a >= 1 && a <= MAX_GEN
    }

    #[inline]
    pub fn evaluate_step(&mut self, next_generator: i8) -> TransitionResult {
        if !Self::valid_generator(next_generator) {
            return TransitionResult::RejectedMalformed;
        }

        self.epoch_tick = self.epoch_tick.wrapping_add(1);
        self.braid_generator = next_generator;

        let g = next_generator as i32;
        let gsq = (g * g) as u64;
        self.state_vector = self
            .state_vector
            .wrapping_mul(31)
            .wrapping_add(gsq)
            .wrapping_add(self.epoch_tick << 1);

        let idx = (next_generator.unsigned_abs() - 1) as u32;
        self.relation_mask |= 1u32 << idx;
        if next_generator < 0 {
            self.relation_mask |= 1u32 << (16 + idx);
        }

        TransitionResult::Accepted
    }

    pub fn evaluate_word(&mut self, word: &[i8]) -> Result<usize, usize> {
        for (i, &g) in word.iter().enumerate() {
            if self.evaluate_step(g) == TransitionResult::RejectedMalformed {
                return Err(i);
            }
        }
        Ok(word.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reject_zero_and_oob() {
        let mut s = BraidStateTransition::initial();
        assert_eq!(s.evaluate_step(0), TransitionResult::RejectedMalformed);
        assert_eq!(s.evaluate_step(5), TransitionResult::RejectedMalformed);
        assert_eq!(s.evaluate_step(-5), TransitionResult::RejectedMalformed);
        assert_eq!(s.epoch_tick, 0);
    }

    #[test]
    fn accept_valid() {
        let mut s = BraidStateTransition::initial();
        assert_eq!(s.evaluate_step(1), TransitionResult::Accepted);
        assert_eq!(s.evaluate_step(-2), TransitionResult::Accepted);
        assert_eq!(s.evaluate_step(4), TransitionResult::Accepted);
        assert_eq!(s.epoch_tick, 3);
        assert_ne!(s.state_vector, 0);
    }

    #[test]
    fn deterministic() {
        let word = [1i8, -2, 3, -4, 1];
        let mut a = BraidStateTransition::initial();
        let mut b = BraidStateTransition::initial();
        assert_eq!(a.evaluate_word(&word), Ok(5));
        assert_eq!(b.evaluate_word(&word), Ok(5));
        assert_eq!(a.state_vector, b.state_vector);
        assert_eq!(a.relation_mask, b.relation_mask);
    }

    #[test]
    fn word_stops_on_bad() {
        let mut s = BraidStateTransition::initial();
        assert_eq!(s.evaluate_word(&[1, 2, 0, 3]), Err(2));
        assert_eq!(s.epoch_tick, 2);
    }
}
