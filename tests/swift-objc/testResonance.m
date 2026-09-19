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

function tests = testResonance()
    % testResonance - Unit tests for resonance detection and projection
    %
    % The resonance projector P_res determines whether a mode excitation is
    % resonant (near zero residual) or off-resonance. This test suite verifies:
    %   1. Correct resonance classification
    %   2. Projector magnitude (0 or 1)
    %   3. Threshold behavior around epsilon

    tests = functiontests(localfunctions);
end

function testResonanceProjector(testCase)
    % Test: Resonance projector correctly classifies residual phase
    %
    % For epsilon = 0.01:
    %   - Δ_Φ < epsilon → resonant (P_res = 1, is_res = true)
    %   - Δ_Φ >= epsilon → off-resonance (P_res = 0, is_res = false)

    epsilon = 0.01;

    % Strongly resonant case
    delta_phi_res = 0.001;
    [proj_res, is_res] = snapkitty.resonanceProjector(delta_phi_res, epsilon);
    verifyEqual(testCase, proj_res, 1);
    verifyTrue(testCase, is_res);

    % Off-resonance case
    delta_phi_off = 0.1;
    [proj_off, is_off] = snapkitty.resonanceProjector(delta_phi_off, epsilon);
    verifyEqual(testCase, proj_off, 0);
    verifyFalse(testCase, is_off);
end

function testResonanceThreshold(testCase)
    % Test: Resonance projector threshold behavior at boundary
    %
    % Values just below and above epsilon should show transition behavior.

    epsilon = 0.01;

    % Just below threshold
    delta_below = epsilon * 0.99;
    [proj_below, is_below] = snapkitty.resonanceProjector(delta_below, epsilon);
    verifyEqual(testCase, proj_below, 1);
    verifyTrue(testCase, is_below);

    % Just above threshold
    delta_above = epsilon * 1.01;
    [proj_above, is_above] = snapkitty.resonanceProjector(delta_above, epsilon);
    verifyEqual(testCase, proj_above, 0);
    verifyFalse(testCase, is_above);
end

function testResonanceProjectorOutputTypes(testCase)
    % Test: Resonance projector returns correct data types
    %
    % - proj: numeric scalar (0 or 1)
    % - is_res: logical scalar (true or false)

    epsilon = 0.01;
    delta_phi = 0.005;

    [proj, is_res] = snapkitty.resonanceProjector(delta_phi, epsilon);

    verifyTrue(testCase, isscalar(proj) && isnumeric(proj));
    verifyTrue(testCase, isscalar(is_res) && islogical(is_res));
end

function testResonanceProjectorBounds(testCase)
    % Test: Projector output is always exactly 0 or 1
    %
    % No intermediate values allowed; the projector is binary.

    epsilon = 0.01;
    delta_values = linspace(0, 0.5, 50);

    for delta in delta_values
        [proj, ~] = snapkitty.resonanceProjector(delta, epsilon);
        verifyTrue(testCase, proj == 0 || proj == 1);
    end
end

function testResonanceConsistency(testCase)
    % Test: is_res flag is consistent with proj value
    %
    % - proj = 1 ⇔ is_res = true
    % - proj = 0 ⇔ is_res = false

    epsilon = 0.01;
    delta_values = [0.001, 0.005, 0.01, 0.05, 0.1, 0.5];

    for delta = delta_values
        [proj, is_res] = snapkitty.resonanceProjector(delta, epsilon);

        if proj == 1
            verifyTrue(testCase, is_res);
        else
            verifyFalse(testCase, is_res);
        end
    end
end

function testResonanceVectorized(testCase)
    % Test: Resonance projector can handle vector inputs
    %
    % Should accept array of Δ_Φ values and return array of projectors.

    epsilon = 0.01;
    delta_phis = [0.001, 0.005, 0.015, 0.05];

    [projs, is_res_array] = snapkitty.resonanceProjector(delta_phis, epsilon);

    % Should return arrays of same size
    verifyEqual(testCase, size(projs), size(delta_phis));
    verifyEqual(testCase, size(is_res_array), size(delta_phis));

    % Each element should be valid
    for i = 1:length(projs)
        verifyTrue(testCase, projs(i) == 0 || projs(i) == 1);
        verifyTrue(testCase, islogical(is_res_array(i)));
    end
end

function testResonanceNumericalStability(testCase)
    % Test: Multiple calls with same input produce identical results
    %
    % Ensure reproducibility of resonance classification.

    epsilon = 0.01;
    delta_phi = 0.005;

    [proj1, is1] = snapkitty.resonanceProjector(delta_phi, epsilon);
    [proj2, is2] = snapkitty.resonanceProjector(delta_phi, epsilon);

    verifyEqual(testCase, proj1, proj2);
    verifyEqual(testCase, is1, is2);
end

function testResonanceEpsilonEffect(testCase)
    % Test: Changing epsilon threshold affects classification correctly
    %
    % For a fixed Δ_Φ, varying epsilon should change classification appropriately.

    delta_phi = 0.01;

    % Tight threshold (Δ_Φ now above)
    eps_tight = 0.005;
    [proj_tight, ~] = snapkitty.resonanceProjector(delta_phi, eps_tight);
    verifyEqual(testCase, proj_tight, 0);

    % Loose threshold (Δ_Φ now below)
    eps_loose = 0.02;
    [proj_loose, ~] = snapkitty.resonanceProjector(delta_phi, eps_loose);
    verifyEqual(testCase, proj_loose, 1);
end

function testResonanceZeroPhase(testCase)
    % Test: Zero residual phase is always resonant
    %
    % A perfect resonance (Δ_Φ = 0) must be classified as resonant
    % for any reasonable epsilon.

    epsilon = 0.01;
    delta_phi = 0.0;

    [proj, is_res] = snapkitty.resonanceProjector(delta_phi, epsilon);

    verifyEqual(testCase, proj, 1);
    verifyTrue(testCase, is_res);
end

function testResonanceLargePhase(testCase)
    % Test: Large phase deviations are always off-resonance
    %
    % Δ_Φ >> epsilon must always be off-resonance regardless of epsilon value.

    epsilon_values = [0.01, 0.05, 0.1];
    delta_phi_large = 1.0;

    for epsilon = epsilon_values
        [proj, is_res] = snapkitty.resonanceProjector(delta_phi_large, epsilon);
        verifyEqual(testCase, proj, 0);
        verifyFalse(testCase, is_res);
    end
end
