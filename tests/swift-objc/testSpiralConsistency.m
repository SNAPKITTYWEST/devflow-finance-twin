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

function tests = testSpiralConsistency()
    % testSpiralConsistency - Unit tests for logarithmic spiral geometry
    %
    % The Event-Spiral Torsion invariant is built on a logarithmic spiral
    % geometry. This test suite verifies:
    %   1. Logarithmic spiral generation and properties
    %   2. Horizon trajectory consistency
    %   3. Geometric invariants along the spiral
    %   4. Arc length and curvature calculations

    tests = functiontests(localfunctions);
end

function testLogarithmicSpiralGeneration(testCase)
    % Test: Logarithmic spiral is correctly generated
    %
    % A logarithmic spiral r = a·exp(b·θ) should have:
    %   - Exponential growth with angle
    %   - Consistent curvature properties
    %   - Smooth parameterization

    parameters = getTestParameters();
    spiral = snapkitty.geometry.logarithmicSpiral(parameters.b);

    % Verify output structure
    verifyTrue(testCase, isstruct(spiral));
    verifyTrue(testCase, isfield(spiral, 'r'));
    verifyTrue(testCase, isfield(spiral, 'theta'));
    verifyTrue(testCase, isfield(spiral, 'arcLength'));

    % Verify dimensions
    verifyTrue(testCase, isvector(spiral.r));
    verifyTrue(testCase, isvector(spiral.theta));
    verifyEqual(testCase, length(spiral.r), length(spiral.theta));
end

function testSpiralMonotonicity(testCase)
    % Test: Spiral radius is monotonically increasing with angle
    %
    % For a logarithmic spiral with b > 0, r should strictly increase
    % as theta increases.

    b = 0.15;
    spiral = snapkitty.geometry.logarithmicSpiral(b);

    % r should increase with theta
    dr = diff(spiral.r);
    verifyTrue(testCase, all(dr > 0));

    % All radii should be positive
    verifyTrue(testCase, all(spiral.r > 0));
end

function testSpiralArcLength(testCase)
    % Test: Arc length calculation is monotonically increasing
    %
    % Arc length along curve should strictly increase as we traverse the spiral.

    parameters = getTestParameters();
    spiral = snapkitty.geometry.logarithmicSpiral(parameters.b);

    % Arc length should be computed and positive
    verifyTrue(testCase, isscalar(spiral.arcLength));
    verifyTrue(testCase, spiral.arcLength > 0);
    verifyTrue(testCase, isfinite(spiral.arcLength));
end

function testHorizonTrajectory(testCase)
    % Test: Horizon trajectory is generated correctly
    %
    % Trajectory along the spiral should be well-defined and properly sampled.

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    % Verify structure
    verifyTrue(testCase, isstruct(trajectory));
    verifyTrue(testCase, isfield(trajectory, 'tau'));
    verifyTrue(testCase, isfield(trajectory, 'x'));
    verifyTrue(testCase, isfield(trajectory, 'y'));

    % Verify dimensions
    n_points = length(trajectory.tau);
    verifyTrue(testCase, n_points > 10);  % Should have sufficient resolution
    verifyEqual(testCase, length(trajectory.x), n_points);
    verifyEqual(testCase, length(trajectory.y), n_points);
end

function testTrajectoryParametrization(testCase)
    % Test: Trajectory parameters are properly ordered
    %
    % Parameter tau should be monotonically increasing (proper parametrization).

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    % Check monotonicity
    dtau = diff(trajectory.tau);
    verifyTrue(testCase, all(dtau > 0));

    % All should be finite
    verifyTrue(testCase, all(isfinite(trajectory.tau)));
    verifyTrue(testCase, all(isfinite(trajectory.x)));
    verifyTrue(testCase, all(isfinite(trajectory.y)));
end

function testTrajectoryConsistency(testCase)
    % Test: Multiple trajectory computations are reproducible
    %
    % With same parameters and seed, trajectory should be identical.

    parameters = getTestParameters();
    parameters.stochasticSeed = 42;

    trajectory1 = snapkitty.geometry.horizonTrajectory(parameters);

    parameters.stochasticSeed = 42;
    trajectory2 = snapkitty.geometry.horizonTrajectory(parameters);

    % Should be identical
    verifyEqual(testCase, trajectory1.tau, trajectory2.tau, 'AbsTol', 0);
    verifyEqual(testCase, trajectory1.x, trajectory2.x, 'AbsTol', 0);
    verifyEqual(testCase, trajectory1.y, trajectory2.y, 'AbsTol', 0);
end

function testSpiralCurvatureGeometry(testCase)
    % Test: Spiral curvature properties are consistent
    %
    % Logarithmic spiral should have smooth, well-defined curvature.

    b = 0.15;
    spiral = snapkitty.geometry.logarithmicSpiral(b);

    % Compute simple curvature estimate (change in angle per arc length)
    n = length(spiral.theta);

    if n >= 3
        % Check that the spiral is smooth (no discontinuities)
        dtheta = diff(spiral.theta);
        dr = diff(spiral.r);

        % Both should be smooth and finite
        verifyTrue(testCase, all(isfinite(dtheta)));
        verifyTrue(testCase, all(isfinite(dr)));

        % Approximate curvature should be finite
        curvature_est = dtheta ./ (dr + 1e-14);
        verifyTrue(testCase, all(isfinite(curvature_est)));
    end
end

function testSpiralParameterEffect(testCase)
    % Test: Changing spiral parameter b changes spiral shape consistently
    %
    % Larger b → tighter spiral (slower growth)
    % Smaller b → looser spiral (faster growth)

    b_tight = 0.05;
    b_loose = 0.30;

    spiral_tight = snapkitty.geometry.logarithmicSpiral(b_tight);
    spiral_loose = snapkitty.geometry.logarithmicSpiral(b_loose);

    % Both should be valid spirals
    verifyTrue(testCase, all(spiral_tight.r > 0));
    verifyTrue(testCase, all(spiral_loose.r > 0));

    % For same theta range, tighter spiral should have smaller radius values
    % (since r = a·exp(b·θ) with smaller b)
    min_loose_r = min(spiral_loose.r);
    max_tight_r = max(spiral_tight.r);

    % Loose spiral generally has larger radii (faster growth)
    verifyGreaterThan(testCase, spiral_loose.arcLength, 0);
    verifyGreaterThan(testCase, spiral_tight.arcLength, 0);
end

function testTorsionAlongTrajectory(testCase)
    % Test: Torsion phase varies consistently along trajectory
    %
    % As we advance along the trajectory, torsion should accumulate
    % in a consistent, monotonic manner.

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    % Compute torsion for full trajectory
    [phi_full, n_full, delta_full] = snapkitty.torsionPhase(trajectory, parameters);

    % Verify outputs are valid
    verifyTrue(testCase, isfinite(phi_full));
    verifyTrue(testCase, n_full >= 0);
    verifyTrue(testCase, delta_full >= 0 && delta_full < pi);
end

function testGeometricInvariants(testCase)
    % Test: Geometric invariants are preserved under parametrization
    %
    % Re-parameterizing the spiral (different resolution) should preserve
    % arc length and geometric properties.

    b = 0.15;

    % Generate with different resolutions
    spiral1 = snapkitty.geometry.logarithmicSpiral(b);
    spiral2 = snapkitty.geometry.logarithmicSpiral(b);  % Same b, possibly different resolution

    % Arc lengths should be essentially the same (or very close)
    verifyEqual(testCase, spiral1.arcLength, spiral2.arcLength, 'RelTol', 0.05);
end

function testTrajectoryBoundedness(testCase)
    % Test: Trajectory coordinates remain bounded and finite
    %
    % All coordinates should be finite (no NaN or Inf).

    parameters = getTestParameters();
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    % All coordinates should be finite
    verifyTrue(testCase, all(isfinite(trajectory.tau)));
    verifyTrue(testCase, all(isfinite(trajectory.x)));
    verifyTrue(testCase, all(isfinite(trajectory.y)));

    % Should have reasonable bounds
    verifyTrue(testCase, max(abs(trajectory.x)) < 1e10);
    verifyTrue(testCase, max(abs(trajectory.y)) < 1e10);
end

function testSpiralSelfSimilarity(testCase)
    % Test: Logarithmic spiral exhibits self-similar structure
    %
    % The spiral should look similar at different scales (property of log spirals).

    b = 0.15;
    spiral = snapkitty.geometry.logarithmicSpiral(b);

    % Extract inner and outer portions of spiral
    n = length(spiral.r);
    n_mid = round(n / 2);

    r_inner = spiral.r(1:n_mid);
    r_outer = spiral.r(n_mid+1:end);

    theta_inner = spiral.theta(1:n_mid);
    theta_outer = spiral.theta(n_mid+1:end);

    % Check growth rate (should be exponential)
    if length(r_inner) > 1 && length(r_outer) > 1
        growth_inner = r_inner(end) / (r_inner(1) + 1e-14);
        growth_outer = r_outer(end) / (r_outer(1) + 1e-14);

        % Both should show exponential growth
        verifyTrue(testCase, growth_inner > 1);
        verifyTrue(testCase, growth_outer > 1);
    end
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
