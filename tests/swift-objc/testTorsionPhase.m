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

function tests = testTorsionPhase()
    % testTorsionPhase - Unit tests for torsion phase computation
    %
    % The torsion phase φ_tors encodes the geometric phase accumulated
    % along the event-spiral trajectory. This test suite verifies:
    %   1. Correct computation of φ_tors from trajectory geometry
    %   2. Resonance index n and residual Δ_Φ computation
    %   3. Consistency with spiral geometry

    tests = functiontests(localfunctions);
end

function testTorsionPhaseComputation(testCase)
    % Test: Torsion phase computation returns valid structure
    %
    % For a given trajectory and parameters, the function must return:
    %   - phi_tors: total torsion phase (scalar, real)
    %   - n: resonance index (integer)
    %   - delta_phi: residual phase deviation (non-negative)

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    [phi_tors, n, delta_phi] = snapkitty.torsionPhase(trajectory, parameters);

    % Verify output types
    verifyTrue(testCase, isscalar(phi_tors) && isnumeric(phi_tors));
    verifyTrue(testCase, isscalar(n) && isnumeric(n));
    verifyTrue(testCase, isscalar(delta_phi) && isnumeric(delta_phi));

    % Verify properties
    verifyTrue(testCase, isreal(phi_tors));
    verifyTrue(testCase, delta_phi >= 0);
end

function testTorsionPhaseResonanceIndex(testCase)
    % Test: Resonance index n is a non-negative integer
    %
    % The resonance index counts the number of π rotations in the torsion phase.

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);
    [~, n, ~] = snapkitty.torsionPhase(trajectory, parameters);

    % n should be a non-negative integer
    verifyTrue(testCase, n >= 0);
    verifyTrue(testCase, abs(n - round(n)) < 1e-10);
end

function testTorsionPhaseResidual(testCase)
    % Test: Residual phase Δ_Φ is bounded by π
    %
    % The residual phase is the fractional part of φ_tors / π,
    % so it must lie in [0, π).

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);
    [~, ~, delta_phi] = snapkitty.torsionPhase(trajectory, parameters);

    % Residual should be non-negative and less than π
    verifyTrue(testCase, delta_phi >= 0);
    verifyTrue(testCase, delta_phi < pi);
end

function testTorsionPhaseVariation(testCase)
    % Test: Torsion phase varies smoothly with trajectory parameters
    %
    % Slight changes in trajectory parameters should produce continuous changes
    % in the torsion phase.

    base_params = getTestParameters();
    trajectory1 = snapkitty.geometry.horizonTrajectory(base_params);
    [phi_tors1, ~, ~] = snapkitty.torsionPhase(trajectory1, base_params);

    % Vary parameter slightly
    varied_params = base_params;
    varied_params.r_s = base_params.r_s * 1.01;
    trajectory2 = snapkitty.geometry.horizonTrajectory(varied_params);
    [phi_tors2, ~, ~] = snapkitty.torsionPhase(trajectory2, varied_params);

    % The difference should be small (continuous variation)
    delta = abs(phi_tors2 - phi_tors1);
    verifyTrue(testCase, delta < 0.1 * abs(phi_tors1));
end

function testTorsionPhaseNumericalStability(testCase)
    % Test: Multiple calls with same input produce identical results
    %
    % Ensure reproducibility and numerical stability of torsion computation.

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    [phi1, n1, delta1] = snapkitty.torsionPhase(trajectory, parameters);
    [phi2, n2, delta2] = snapkitty.torsionPhase(trajectory, parameters);

    verifyEqual(testCase, phi1, phi2, 'AbsTol', 0);
    verifyEqual(testCase, n1, n2, 'AbsTol', 0);
    verifyEqual(testCase, delta1, delta2, 'AbsTol', 0);
end

function testTorsionPhaseDecomposition(testCase)
    % Test: φ_tors = n·π + Δ_Φ decomposition is valid
    %
    % The torsion phase must satisfy the constraint:
    %   φ_tors ≈ n·π + Δ_Φ (modulo numerical precision)

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);
    [phi_tors, n, delta_phi] = snapkitty.torsionPhase(trajectory, parameters);

    % Reconstruct from components
    reconstructed = n * pi + delta_phi;

    % Should match the original (within numerical precision)
    verifyEqual(testCase, phi_tors, reconstructed, 'RelTol', 1e-10);
end

function testTorsionPhaseConsistency(testCase)
    % Test: Different trajectory resolutions yield consistent results
    %
    % Increasing trajectory resolution should converge to same torsion phase.

    parameters = getTestParameters();

    % Low resolution
    trajectory_coarse = snapkitty.geometry.horizonTrajectory(parameters);
    [phi_coarse, n_coarse, ~] = snapkitty.torsionPhase(trajectory_coarse, parameters);

    % High resolution
    parameters_fine = parameters;
    parameters_fine.integrationTolerance = 1e-10;
    trajectory_fine = snapkitty.geometry.horizonTrajectory(parameters_fine);
    [phi_fine, n_fine, ~] = snapkitty.torsionPhase(trajectory_fine, parameters_fine);

    % Resonance indices should match
    verifyEqual(testCase, n_coarse, n_fine);

    % Torsion phases should be close
    relative_diff = abs(phi_fine - phi_coarse) / (abs(phi_coarse) + 1e-14);
    verifyTrue(testCase, relative_diff < 1e-6);
end

function testTorsionPhaseFiniteness(testCase)
    % Test: All outputs are finite (not NaN or Inf)
    %
    % Ensure no division by zero or other numerical catastrophes.

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);
    [phi_tors, n, delta_phi] = snapkitty.torsionPhase(trajectory, parameters);

    verifyTrue(testCase, isfinite(phi_tors));
    verifyTrue(testCase, isfinite(n));
    verifyTrue(testCase, isfinite(delta_phi));
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
