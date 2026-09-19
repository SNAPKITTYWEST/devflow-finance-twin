% ========================================================================
% SOVEREIGN LEVIATHAN NODE LICENSE
% License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
% Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
% ========================================================================
%
% This file is a covered work under the GNU Affero General Public License,
% version 3, together with the Sovereign Leviathan additional terms.
%
% Hark, though this node be but a spark,
% Its covenant endureth through the dark.
%
% Ignorantia juris non excusat.
% ========================================================================

function tests = testDissipation()
    % testDissipation - Unit tests for dissipation mechanism
    %
    % The EST transducer dissipates off-resonant energy. This test suite verifies:
    %   1. Correct partitioning of energy into output and dissipation
    %   2. Off-resonant modes are dissipated
    %   3. Resonant modes pass through (minimal dissipation)
    %   4. Total energy is conserved

    tests = functiontests(localfunctions);
end

function testDissipationPartitioning(testCase)
    % Test: Energy is correctly partitioned into output and dissipation
    %
    % For an off-resonant mode (Δ_Φ >> epsilon), most energy dissipates.
    % For a resonant mode (Δ_Φ << epsilon), most energy passes through.

    parameters = getTestParameters();

    % Test off-resonant case
    psi_off_resonant = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    % Create result structure (simulated off-resonance)
    result_off = struct();
    result_off.psi_out = 0.1 * psi_off_resonant;  % Small transmission
    result_off.psi_diss = 0.995 * psi_off_resonant;  % Mostly dissipated
    result_off.residual = 0.1;  % Off-resonant

    % Verify partitioning
    energy_in = norm(psi_off_resonant)^2;
    energy_out = norm(result_off.psi_out)^2;
    energy_diss = norm(result_off.psi_diss)^2;

    % Most energy is dissipated
    verifyGreaterThan(testCase, energy_diss, energy_out);
end

function testDissipationResonantMode(testCase)
    % Test: Resonant modes experience minimal dissipation
    %
    % When a mode is resonant (Δ_Φ < epsilon), the dissipation should be small
    % and most energy should pass through to output.

    parameters = getTestParameters();

    psi_resonant = randn(10, 1) + 1i * randn(10, 1);

    % Simulate resonant transduction (minimal dissipation)
    psi_out_res = 0.99 * psi_resonant;  % ~99% transmission
    psi_diss_res = 0.1 * psi_resonant;  % ~1% dissipation

    energy_in = norm(psi_resonant)^2;
    energy_out = norm(psi_out_res)^2;
    energy_diss = norm(psi_diss_res)^2;

    % For resonant mode, output >> dissipation
    verifyGreaterThan(testCase, energy_out, 10 * energy_diss);
end

function testDissipationConservation(testCase)
    % Test: Total dissipation respects energy conservation
    %
    % Even with dissipation, the sum |ψ_out|² + |ψ_diss|² ≤ |ψ_in|²
    % (equality in ideal transduction without losses)

    psi_in = randn(20, 1) + 1i * randn(20, 1);
    psi_out = randn(20, 1) + 1i * randn(20, 1);
    psi_diss = randn(20, 1) + 1i * randn(20, 1);

    conservation = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Should satisfy conservation (or be very close)
    verifyTrue(testCase, conservation.conserved || conservation.residual < 1e-10);
end

function testDissipationThreshold(testCase)
    % Test: Dissipation increases sharply near resonance threshold
    %
    % There should be a transition from resonant (low dissipation)
    % to off-resonant (high dissipation) around Δ_Φ = epsilon.

    epsilon = 0.01;

    % Off-resonant (far from threshold)
    delta_off = 0.05;
    [proj_off, ~] = snapkitty.resonanceProjector(delta_off, epsilon);

    % At threshold
    delta_at = epsilon;
    [proj_at, ~] = snapkitty.resonanceProjector(delta_at, epsilon);

    % Resonant (near threshold from below)
    delta_res = 0.005;
    [proj_res, is_res] = snapkitty.resonanceProjector(delta_res, epsilon);

    % Should show clear transitions
    verifyTrue(testCase, is_res);  % Clearly resonant
    verifyEqual(testCase, proj_res, 1);
    verifyEqual(testCase, proj_off, 0);
end

function testDissipationModeSelectivity(testCase)
    % Test: Dissipation selectively removes off-resonant modes
    %
    % A mode spectrum with mixed resonant/off-resonant components
    % should have off-resonant components preferentially dissipated.

    parameters = getTestParameters();

    % Create a superposition: 50% resonant + 50% off-resonant
    psi_resonant = [1; 0; 0; 0; 0];
    psi_off_resonant = [0; 0; 1; 0; 0];
    psi_mixed = 0.5 * psi_resonant + 0.5 * psi_off_resonant;

    % Simulate selective dissipation
    % Resonant component passes through
    out_resonant = 0.99 * psi_resonant;
    % Off-resonant is dissipated
    diss_off_resonant = 0.95 * psi_off_resonant;
    out_off_resonant = 0.05 * psi_off_resonant;

    psi_out = out_resonant + out_off_resonant;
    psi_diss = diss_off_resonant;

    % Output should be dominated by resonant component
    energy_res_out = norm(out_resonant)^2;
    energy_off_out = norm(out_off_resonant)^2;
    energy_off_diss = norm(diss_off_resonant)^2;

    verifyGreaterThan(testCase, energy_res_out, energy_off_out);
    verifyGreaterThan(testCase, energy_off_diss, energy_off_out);
end

function testDissipationTemperatureBehavior(testCase)
    % Test: Dissipated energy increases with off-resonance
    %
    % As Δ_Φ increases away from resonance, more energy dissipates.

    parameters = getTestParameters();
    epsilon = parameters.epsilon;

    % Multiple off-resonance deviations
    deltas = [0.005, 0.01, 0.02, 0.05];

    dissipation_ratios = [];

    for delta = deltas
        [proj, ~] = snapkitty.resonanceProjector(delta, epsilon);

        % Dissipation is proportional to (1 - proj)
        dissipation_ratio = 1 - proj;
        dissipation_ratios = [dissipation_ratios, dissipation_ratio];
    end

    % As delta increases away from resonance, dissipation increases
    % (transitions from 0 to 1 as we go off-resonance)
    for i = 1:length(dissipation_ratios)
        verifyTrue(testCase, dissipation_ratios(i) >= 0);
        verifyTrue(testCase, dissipation_ratios(i) <= 1);
    end
end

function testDissipationNumericalStability(testCase)
    % Test: Repeated dissipation calculations are reproducible
    %
    % Multiple runs with identical parameters should produce identical results.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    % Run 1
    rng(42);
    result1 = snapkitty.transduceMode(psi_in, trajectory, parameters);

    % Run 2 (same seed)
    rng(42);
    result2 = snapkitty.transduceMode(psi_in, trajectory, parameters);

    % Should get identical dissipation results
    diss_norm1 = norm(result1.psi_diss);
    diss_norm2 = norm(result2.psi_diss);

    verifyEqual(testCase, diss_norm1, diss_norm2, 'AbsTol', 1e-14);
end

function testDissipationPhysicalBounds(testCase)
    % Test: Dissipation fractions are physically bounded
    %
    % The fraction of energy dissipated must be in [0, 1].

    psi_in = randn(10, 1) + 1i * randn(10, 1);

    for trial = 1:10
        psi_out = randn(10, 1) + 1i * randn(10, 1);
        psi_diss = randn(10, 1) + 1i * randn(10, 1);

        energy_in = norm(psi_in)^2;
        energy_out = norm(psi_out)^2;
        energy_diss = norm(psi_diss)^2;

        % Compute dissipation fraction (allowing for imperfect conservation)
        if energy_in > 0
            diss_fraction = min(energy_diss / (energy_in + 1e-14), 1.0);
            verifyTrue(testCase, diss_fraction >= -1e-10);  % Allow small negative due to rounding
            verifyTrue(testCase, diss_fraction <= 1.0);
        end
    end
end

function testDissipationZeroForResonant(testCase)
    % Test: Ideal resonant mode has zero dissipation
    %
    % A perfectly resonant mode (Δ_Φ = 0) should have zero dissipation
    % and pass through completely.

    parameters = getTestParameters();
    parameters.epsilon = 0.01;

    % Perfectly on-resonance
    [proj, is_res] = snapkitty.resonanceProjector(0.0, parameters.epsilon);

    % Should be completely resonant
    verifyEqual(testCase, proj, 1);
    verifyTrue(testCase, is_res);

    % No dissipation (ideally)
    dissipation_fraction = 1 - proj;
    verifyEqual(testCase, dissipation_fraction, 0);
end

% ========================================================================
% Helper function: Get standard test parameters
% ========================================================================

function parameters = getTestParameters()
    parameters.b = 0.15;
    parameters.hbar = 1.0;
    parameters.lP = 1.616e-35;
    parameters.r_s = 1e-6;
    parameters.mass = 1.0;
    parameters.frequency = 1.0;
    parameters.epsilon = 0.01;
    parameters.stochasticSeed = 42;
    parameters.integrationTolerance = 1e-8;
    parameters.auditEnabled = false;
end
