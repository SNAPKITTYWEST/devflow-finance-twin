function phase_op = snapkitty.quantum.phaseOperator(torsion_phase, resonance_index, hbar)
    % Phase operator φ̂ derived from torsion
    %
    % Syntax:
    %   phase_op = snapkitty.quantum.phaseOperator(torsion_phase, resonance_index, hbar)
    %
    % Input Arguments:
    %   torsion_phase    -- Torsion-derived phase φ_t (scalar, radians)
    %   resonance_index  -- Resonance mode index n (integer ≥ 1)
    %   hbar             -- Reduced Planck constant ℏ (scalar, default: 1.054571817e-34 J·s)
    %
    % Output Arguments:
    %   phase_op         -- Phase operator structure with fields:
    %                        torsionPhase, resonanceIndex, hbar, eigenvalue, expectation
    %
    % Description:
    %   Constructs a quantum phase operator from geometric torsion.
    %   The phase operator φ̂ has eigenvalue φ_t and expectation value ⟨φ̂⟩ = φ_t/ℏ.
    %
    %   Eigenvalue: λ = φ_t (phase eigenstate)
    %   Expectation: ⟨φ̂⟩ = φ_t / ℏ
    %   Resonance coupling: n-th harmonic mode
    %
    % Example:
    %   phase_op = snapkitty.quantum.phaseOperator(pi/4, 1, 1.0);
    %   eigenval = phase_op.eigenvalue;
    %   expectation = phase_op.expectation;
    %
    % See also: modeSpectrum, incomingMode, horizonFluctuations

    % ========================================================================
    % SOVEREIGN LEVIATHAN NODE LICENSE
    % License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
    % Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
    % ========================================================================
    % BELESPRIT D'ACCORD COVENANT HEADER
    % Phase operator implementation under Bel Esprit D'Accord covenant.
    % ========================================================================

    % Set default hbar if not provided
    if nargin < 3
        hbar = 1.054571817e-34;  % SI units (J·s)
    end

    % Validate inputs
    if ~isscalar(torsion_phase) || ~isnumeric(torsion_phase)
        error('snapkitty:quantum:phaseOperator:InvalidTorsionPhase', ...
              'torsion_phase must be a numeric scalar.');
    end

    if ~isscalar(resonance_index) || ~isnumeric(resonance_index) || resonance_index < 1 || mod(resonance_index, 1) ~= 0
        error('snapkitty:quantum:phaseOperator:InvalidResonanceIndex', ...
              'resonance_index must be a positive integer.');
    end

    if ~isscalar(hbar) || ~isnumeric(hbar) || hbar <= 0
        error('snapkitty:quantum:phaseOperator:InvalidHbar', ...
              'hbar must be a positive scalar.');
    end

    % Initialize phase operator structure
    phase_op.torsionPhase = torsion_phase;
    phase_op.resonanceIndex = resonance_index;
    phase_op.hbar = hbar;

    % Quantum eigenvalue of phase operator
    phase_op.eigenvalue = torsion_phase;

    % Expectation value ⟨φ̂⟩ = φ_t / ℏ
    phase_op.expectation = torsion_phase / hbar;

    % Uncertainty relation components
    % Δφ Δn ≥ ℏ/2 (phase-number uncertainty)
    phase_op.uncertaintyProduct = hbar / 2;

    % Mode-dependent phase modulation
    phase_op.modePhase = torsion_phase * resonance_index;

    % Extended properties
    phase_op.operatorName = sprintf('φ̂_%d', resonance_index);
    phase_op.isHermitian = true;
    phase_op.eigenspace_dimension = resonance_index;

    % Metadata
    phase_op.metadata.timestamp = datetime('now');
    phase_op.metadata.trust = 'BelEsprit D''Accord Trust';
    phase_op.metadata.quantum_number = resonance_index;
    phase_op.metadata.coupling_strength = 1 / hbar;

end
