// =====================================================================
// PWC_TESTS - Compiled Why3 Proof Obligations
// =====================================================================

#[cfg(test)]
mod tests {
    use crate::pwc_core::{BraidWord, GeneratorIndex, semantics, State, Complex, yang_baxter_equivalent, parse_braid_word};
    use crate::pwc_transform::{verify_semantic_preservation, verify_length_nonincrease};
    use crate::tau_model::{verify_tau_monotonic, ExecutionDomain};
    use crate::pwc_hardware::hw_execute_transform_timed;

    #[test]
    fn test_yang_baxter_sigma1_sigma2_sigma1() {
        let word = BraidWord::Concat(
            Box::new(BraidWord::Gen(1)),
            Box::new(BraidWord::Concat(
                Box::new(BraidWord::Gen(2)),
                Box::new(BraidWord::Gen(1)),
            )),
        );
        let compressed = word.wormhole_transform();

        verify_semantic_preservation(&word, &compressed);
        verify_length_nonincrease(&word, &compressed);
        verify_tau_monotonic(&word, &compressed);
    }

    #[test]
    fn test_semantic_equivalence_all_states() {
        let word = BraidWord::Concat(
            Box::new(BraidWord::Gen(1)),
            Box::new(BraidWord::Concat(
                Box::new(BraidWord::Gen(2)),
                Box::new(BraidWord::Gen(1)),
            )),
        );
        let compressed = word.wormhole_transform();

        let states = [
            State { v1: Complex::ONE, v2: Complex::ZERO },
            State { v1: Complex::ZERO, v2: Complex::ONE },
            State { v1: Complex { re: 0.707, im: 0.0 }, v2: Complex { re: 0.707, im: 0.0 } },
        ];

        for s in states {
            let s1 = semantics(&word, s);
            let s2 = semantics(&compressed, s);
            assert!((s1.v1.re - s2.v1.re).abs() < 1e-12);
            assert!((s1.v1.im - s2.v1.im).abs() < 1e-12);
            assert!((s1.v2.re - s2.v2.re).abs() < 1e-12);
            assert!((s1.v2.im - s2.v2.im).abs() < 1e-12);
        }
    }

    #[test]
    fn test_hardware_tau_one_cycle() {
        let input = vec![1, 2, 1, 2, 1];
        let result = hw_execute_transform_timed(&input);

        assert_eq!(result.cycles, 1, "τ_hardware must be 1 cycle");
        assert!(result.compressed.len() <= input.len());
    }

    #[test]
    fn test_tau_model_all_domains() {
        let word = BraidWord::Concat(
            Box::new(BraidWord::Gen(1)),
            Box::new(BraidWord::Concat(
                Box::new(BraidWord::Gen(2)),
                Box::new(BraidWord::Gen(1)),
            )),
        );
        let compressed = word.wormhole_transform();

        for domain in [
            ExecutionDomain::Serial,
            ExecutionDomain::Vector,
            ExecutionDomain::Quantum,
            ExecutionDomain::Hardware,
        ] {
            let tau_orig = domain.tau(&word);
            let tau_comp = domain.tau(&compressed);
            assert!(tau_comp <= tau_orig, "{:?}: {} -> {}", domain, tau_orig, tau_comp);
        }
    }

    #[test]
    fn test_full_pipeline() {
        let input = vec![1, 2, 1, 2, 1, 2, 1];
        let result = hw_execute_transform_timed(&input);

        assert_eq!(result.cycles, 1);
        assert!(result.compressed.len() <= input.len());

        let original = parse_braid_word(&input);
        let compressed = parse_braid_word(&result.compressed);

        let test_state = State {
            v1: Complex { re: 0.6, im: 0.2 },
            v2: Complex { re: -0.3, im: 0.8 },
        };

        let s1 = semantics(&original, test_state);
        let s2 = semantics(&compressed, test_state);

        assert!((s1.v1.re - s2.v1.re).abs() < 1e-10);
        assert!((s1.v2.re - s2.v2.re).abs() < 1e-10);
    }
}
