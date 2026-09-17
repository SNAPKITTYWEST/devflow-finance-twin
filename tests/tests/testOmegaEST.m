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

function tests = testOmegaEST()
    % testOmegaEST - Unit tests for Event-Spiral Torsion Invariant calculation
    %
    % The Omega_EST = 8π/b invariant is the fundamental frequency of the
    % event-spiral transducer. This test suite verifies:
    %   1. Correct calculation of Ω_EST from parameter b
    %   2. Invariance properties across different b values
    %   3. Numerical stability and precision

    tests = functiontests(localfunctions);
end

function testOmegaESTCalculation(testCase)
    % Test: Ω_EST = 8π/b calculation is precise
    %
    % The formula Ω_EST = 8π/b must hold to at least 14 decimal places
    % of precision, ensuring quantum resonance computation correctness.

    b = 0.15;
    omega = snapkitty.omegaEST(b);
    expected = 8 * pi / b;

    verifyEqual(testCase, omega, expected, 'RelTol', 1e-14);
end

function testOmegaESTProperties(testCase)
    % Test: Ω_EST scales inversely with b (vectorized)
    %
    % For multiple b values [0.1, 0.15, 0.2], verify that the calculation
    % maintains precision across the range of typical parameters.

    b_values = [0.1, 0.15, 0.2];
    omegas = snapkitty.omegaEST(b_values);
    expected = 8 * pi ./ b_values;

    verifyEqual(testCase, omegas, expected, 'RelTol', 1e-14);
end

function testOmegaESTBoundaryValues(testCase)
    % Test: Ω_EST handles extreme (but valid) parameter values
    %
    % Verify behavior at physical boundaries:
    %   - Small b (high frequency): b = 0.01 → Ω ≈ 2513.27
    %   - Large b (low frequency): b = 1.0  → Ω ≈ 25.13

    % Very small b
    omega_small = snapkitty.omegaEST(0.01);
    expected_small = 8 * pi / 0.01;
    verifyEqual(testCase, omega_small, expected_small, 'RelTol', 1e-14);

    % Large b
    omega_large = snapkitty.omegaEST(1.0);
    expected_large = 8 * pi / 1.0;
    verifyEqual(testCase, omega_large, expected_large, 'RelTol', 1e-14);
end

function testOmegaESTNumericalStability(testCase)
    % Test: Ω_EST computation is numerically stable
    %
    % Repeated calculations should be idempotent (produce identical results)
    % within machine precision limits.

    b = 0.15;
    omega1 = snapkitty.omegaEST(b);
    omega2 = snapkitty.omegaEST(b);
    omega3 = snapkitty.omegaEST(b);

    % All three calls must produce bitwise-identical results
    verifyEqual(testCase, omega1, omega2, 'AbsTol', 0);
    verifyEqual(testCase, omega2, omega3, 'AbsTol', 0);
end

function testOmegaESTOutputType(testCase)
    % Test: Ω_EST returns correct data types
    %
    % - Scalar b → scalar Ω
    % - Vector b → vector Ω of same shape

    % Scalar case
    b_scalar = 0.15;
    omega_scalar = snapkitty.omegaEST(b_scalar);
    verifyTrue(testCase, isscalar(omega_scalar));
    verifyTrue(testCase, isnumeric(omega_scalar));

    % Vector case
    b_vector = [0.1, 0.15, 0.2];
    omega_vector = snapkitty.omegaEST(b_vector);
    verifyTrue(testCase, isvector(omega_vector));
    verifyEqual(testCase, size(omega_vector), size(b_vector));
end

function testOmegaESTMonotonicity(testCase)
    % Test: Ω_EST is strictly monotonically decreasing with increasing b
    %
    % Since Ω = 8π/b, larger b values must yield smaller Ω values

    b_values = linspace(0.05, 0.5, 10);
    omegas = snapkitty.omegaEST(b_values);

    % Check that each successive element is strictly less than the previous
    for i = 2:length(omegas)
        verifyGreaterThan(testCase, omegas(i-1), omegas(i));
    end
end

function testOmegaESTRealValuedOutput(testCase)
    % Test: Ω_EST returns real-valued (not complex) results
    %
    % All output values must be real, positive, and finite

    b_values = [0.05, 0.1, 0.15, 0.2, 0.5];
    omegas = snapkitty.omegaEST(b_values);

    for omega = omegas
        verifyTrue(testCase, isreal(omega));
        verifyTrue(testCase, omega > 0);
        verifyTrue(testCase, isfinite(omega));
    end
end
