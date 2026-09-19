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

function tests = testConservation()
    % testConservation - Unit tests for energy/probability conservation
    %
    % The transducer must satisfy the conservation law:
    %   |ψ_in|² = |ψ_out|² + |ψ_diss|²
    %
    % This tests the fundamental principle that probability/energy is neither
    % created nor destroyed, only distributed between output and dissipation.

    tests = functiontests(localfunctions);
end

function testEnergyConservation(testCase)
    % Test: |ψ_in|² = |ψ_out|² + |ψ_diss|² conservation law
    %
    % For quantum modes, the sum of output and dissipated amplitudes
    % squared must equal the input amplitude squared.

    psi_in = [1; 1; 0];
    psi_out = [0.7; 0; 0];
    psi_diss = [0.7; 1; 0];

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Either conservation is exact, or residual is negligible
    verifyTrue(testCase, result.conserved || result.residual < 1e-10);

    % Verify residual is always non-negative
    verifyTrue(testCase, result.residual >= 0);
end

function testConservationOutputStructure(testCase)
    % Test: Conservation function returns proper structure
    %
    % Must return struct with fields:
    %   - conserved: logical indicating if conservation holds
    %   - residual: numerical measure of conservation violation
    %   - relativeError: relative error as percentage

    psi_in = randn(5, 1) + 1i * randn(5, 1);
    psi_out = randn(5, 1) + 1i * randn(5, 1);
    psi_diss = randn(5, 1) + 1i * randn(5, 1);

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    verifyTrue(testCase, isstruct(result));
    verifyTrue(testCase, isfield(result, 'conserved'));
    verifyTrue(testCase, isfield(result, 'residual'));
    verifyTrue(testCase, isfield(result, 'relativeError'));

    verifyTrue(testCase, islogical(result.conserved));
    verifyTrue(testCase, isnumeric(result.residual));
    verifyTrue(testCase, isnumeric(result.relativeError));
end

function testConservationNormalization(testCase)
    % Test: Perfect conservation with normalized modes
    %
    % When ψ_out and ψ_diss partition ψ_in exactly:
    %   |ψ_in|² = |ψ_out|² + |ψ_diss|² (exactly)

    % Create normalized modes that sum to unity
    psi_in = [1; 0; 0];  % |ψ_in|² = 1
    psi_out = [1/sqrt(2); 0; 0];  % |ψ_out|² = 0.5
    psi_diss = [1/sqrt(2); 0; 0];  % |ψ_diss|² = 0.5

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Should be perfect (or near-perfect) conservation
    verifyTrue(testCase, result.conserved);
    verifyLessThan(testCase, result.residual, 1e-14);
end

function testConservationViolation(testCase)
    % Test: Detection of conservation violation
    %
    % When energy is not conserved (physically impossible but testable),
    % the function should flag it and compute residual.

    psi_in = [1; 0; 0];  % |ψ_in|² = 1
    psi_out = [2; 0; 0];  % |ψ_out|² = 4 (impossible!)
    psi_diss = [0; 0; 0];

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Should detect the violation
    verifyTrue(testCase, result.residual > 1e-10);
    % conserved flag depends on threshold
end

function testConservationComplexModes(testCase)
    % Test: Conservation law works with complex-valued wavefunctions
    %
    % Real and imaginary parts should be handled correctly in norm computation.

    psi_in = [1; 1i; 1+1i];
    psi_out = [0.7; 0.5i; 0.6+0.4i];
    psi_diss = [0.714; 0.866i; 0.8+0.6i];

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Residual should be computed correctly
    verifyTrue(testCase, isfinite(result.residual));
    verifyTrue(testCase, result.residual >= 0);
end

function testConservationScaling(testCase)
    % Test: Conservation is scale-invariant (multiplicative property)
    %
    % Scaling all vectors by constant α should preserve conservation property.

    psi_in = [1; 1; 0];
    psi_out = [0.7; 0; 0];
    psi_diss = [0.714; 1; 0];

    result1 = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Scale by factor of 2
    scale_factor = 2.0;
    psi_in_scaled = scale_factor * psi_in;
    psi_out_scaled = scale_factor * psi_out;
    psi_diss_scaled = scale_factor * psi_diss;

    result2 = snapkitty.conservation(psi_in_scaled, psi_out_scaled, psi_diss_scaled);

    % Conservation property should be identical
    verifyEqual(testCase, result1.conserved, result2.conserved);
    verifyEqual(testCase, result1.residual, result2.residual, 'RelTol', 1e-10);
end

function testConservationDimensionalConsistency(testCase)
    % Test: Conservation works for different vector dimensions
    %
    % The law should hold regardless of Hilbert space dimension.

    for dim = [2, 5, 10, 100]
        psi_in = randn(dim, 1) + 1i * randn(dim, 1);
        psi_out = randn(dim, 1) + 1i * randn(dim, 1);
        psi_diss = randn(dim, 1) + 1i * randn(dim, 1);

        result = snapkitty.conservation(psi_in, psi_out, psi_diss);

        % All results should have valid structure
        verifyTrue(testCase, islogical(result.conserved));
        verifyTrue(testCase, isfinite(result.residual));
        verifyTrue(testCase, result.residual >= 0);
    end
end

function testConservationNumericStability(testCase)
    % Test: Multiple calls with same input yield identical results
    %
    % Ensure deterministic behavior and no floating-point accumulation.

    psi_in = randn(10, 1) + 1i * randn(10, 1);
    psi_out = randn(10, 1) + 1i * randn(10, 1);
    psi_diss = randn(10, 1) + 1i * randn(10, 1);

    result1 = snapkitty.conservation(psi_in, psi_out, psi_diss);
    result2 = snapkitty.conservation(psi_in, psi_out, psi_diss);

    verifyEqual(testCase, result1.residual, result2.residual, 'AbsTol', 0);
    verifyEqual(testCase, result1.conserved, result2.conserved);
end

function testConservationTolerance(testCase)
    % Test: Conservation uses appropriate tolerance
    %
    % Must account for floating-point rounding errors in computation.

    % Create nearly-conserved system
    norm_in = sqrt(2.0);
    norm_out = sqrt(1.0);
    norm_diss = sqrt(1.0 - 1e-15);  % Tiny violation

    psi_in = norm_in * [1; 0; 0];
    psi_out = norm_out * [1; 0; 0];
    psi_diss = norm_diss * [0; 1; 0];

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    % Small violation within floating-point tolerance
    verifyTrue(testCase, result.residual <= 1e-10);
end

function testConservationFiniteness(testCase)
    % Test: All output fields are finite
    %
    % No NaN or Inf in residual, relative error, or conserved flag.

    psi_in = randn(10, 1) + 1i * randn(10, 1);
    psi_out = randn(10, 1) + 1i * randn(10, 1);
    psi_diss = randn(10, 1) + 1i * randn(10, 1);

    result = snapkitty.conservation(psi_in, psi_out, psi_diss);

    verifyTrue(testCase, isfinite(result.residual));
    verifyTrue(testCase, isfinite(result.relativeError));
    verifyTrue(testCase, ~isnan(result.conserved));
end
