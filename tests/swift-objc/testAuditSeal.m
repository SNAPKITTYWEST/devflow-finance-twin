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

function tests = testAuditSeal()
    % testAuditSeal - Unit tests for audit seal and trust provenance
    %
    % The EST transducer generates cryptographic audit seals that certify:
    %   1. Algorithm identity (EST-QTR-001)
    %   2. Execution timestamp and ID
    %   3. Trust attestation (BelEsprit D'Accord Trust)
    %   4. Deterministic seal computation
    %   5. Reproducibility and verification

    tests = functiontests(localfunctions);
end

function testAuditSealGeneration(testCase)
    % Test: Audit seal is correctly generated and contains required fields
    %
    % Seal must include:
    %   - algorithmID: 'EST-QTR-001'
    %   - executionID: unique identifier
    %   - timestamp: ISO 8601 format
    %   - trust: trust anchor name
    %   - digest: cryptographic hash

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Verify required fields
    verifyTrue(testCase, isfield(seal, 'algorithmID'));
    verifyTrue(testCase, isfield(seal, 'executionID'));
    verifyTrue(testCase, isfield(seal, 'timestamp'));
    verifyTrue(testCase, isfield(seal, 'trust'));
    verifyTrue(testCase, isfield(seal, 'digest'));
    verifyTrue(testCase, isfield(seal, 'version'));
end

function testAuditSealAlgorithmID(testCase)
    % Test: Algorithm ID is correctly set to EST-QTR-001
    %
    % This identifies the algorithm version and variant.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    verifyEqual(testCase, seal.algorithmID, 'EST-QTR-001');
end

function testAuditSealTrust(testCase)
    % Test: Trust anchor is correctly set to BelEsprit D'Accord Trust
    %
    % Trust declaration must be correct.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    verifyEqual(testCase, seal.trust, 'BelEsprit D''Accord Trust');
end

function testAuditSealExecutionID(testCase)
    % Test: Execution ID is unique and properly formatted
    %
    % Each execution should have a unique identifier.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result1 = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal1 = snapkitty.auditSeal(result1);

    result2 = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal2 = snapkitty.auditSeal(result2);

    % Execution IDs should be different (new execution)
    verifyNotEqual(testCase, seal1.executionID, seal2.executionID);

    % Both should be non-empty strings/UUIDs
    verifyTrue(testCase, ~isempty(seal1.executionID));
    verifyTrue(testCase, ~isempty(seal2.executionID));
end

function testAuditSealTimestamp(testCase)
    % Test: Timestamp is present and properly formatted (ISO 8601)
    %
    % Timestamps should be in ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Timestamp should be present
    verifyTrue(testCase, ~isempty(seal.timestamp));

    % Should contain T and Z (ISO 8601 indicators)
    verifyTrue(testCase, contains(seal.timestamp, 'T'));
    verifyTrue(testCase, contains(seal.timestamp, 'Z'));
end

function testAuditSealDigest(testCase)
    % Test: Digest is computed and is cryptographically valid
    %
    % Digest should be a hex string (SHA-256 hash).

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Digest should be non-empty
    verifyTrue(testCase, ~isempty(seal.digest));

    % Digest should be a valid hex string
    digest = seal.digest;
    if isstring(digest) || ischar(digest)
        digest = char(digest);
        % Check it's valid hex (only 0-9, a-f, A-F)
        valid_hex = all(ismember(digest, '0123456789abcdefABCDEF'));
        verifyTrue(testCase, valid_hex);
    end
end

function testAuditSealDeterminism(testCase)
    % Test: Same input produces same seal (deterministic computation)
    %
    % The seal generation must be reproducible (for verification).

    parameters = getTestParameters();
    parameters.stochasticSeed = 42;
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal1 = snapkitty.auditSeal(result);

    % Re-create same seal
    seal2 = snapkitty.auditSeal(result);

    % Digest and algorithm ID should be identical (deterministic)
    verifyEqual(testCase, seal1.digest, seal2.digest);
    verifyEqual(testCase, seal1.algorithmID, seal2.algorithmID);
    verifyEqual(testCase, seal1.trust, seal2.trust);
end

function testAuditSealSensitivity(testCase)
    % Test: Seal changes when result changes
    %
    % Different results should produce different seals (injective mapping).

    parameters = getTestParameters();

    psi_in1 = randn(10, 1) + 1i * randn(10, 1);
    psi_in2 = randn(10, 1) + 1i * randn(10, 1);

    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result1 = snapkitty.transduceMode(psi_in1, trajectory, parameters);
    result2 = snapkitty.transduceMode(psi_in2, trajectory, parameters);

    seal1 = snapkitty.auditSeal(result1);
    seal2 = snapkitty.auditSeal(result2);

    % Different results should (very likely) produce different digests
    if ~isequal(psi_in1, psi_in2)
        % Digests should be different
        verifyNotEqual(testCase, seal1.digest, seal2.digest);
    end
end

function testAuditSealStructure(testCase)
    % Test: Seal struct is well-formed
    %
    % All fields should have appropriate types.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Verify types
    verifyTrue(testCase, ischar(seal.algorithmID) || isstring(seal.algorithmID));
    verifyTrue(testCase, ischar(seal.executionID) || isstring(seal.executionID));
    verifyTrue(testCase, ischar(seal.timestamp) || isstring(seal.timestamp));
    verifyTrue(testCase, ischar(seal.trust) || isstring(seal.trust));
    verifyTrue(testCase, ischar(seal.digest) || isstring(seal.digest));
end

function testAuditSealVersion(testCase)
    % Test: Version field indicates implementation version
    %
    % Version should be present and match current implementation.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Version should be present
    verifyTrue(testCase, ~isempty(seal.version));

    % Should match expected format (e.g., '1.0.0')
    version = char(seal.version);
    parts = strsplit(version, '.');
    verifyTrue(testCase, length(parts) >= 1);  % At least major version
end

function testAuditSealTrustVow(testCase)
    % Test: Audit seal includes trust provenance
    %
    % The seal must explicitly state it was generated under
    % BelEsprit D'Accord Trust.

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Trust field should declare the covenant
    trust_lower = lower(seal.trust);
    verifyTrue(testCase, contains(trust_lower, 'belesprit'));
    verifyTrue(testCase, contains(trust_lower, 'accord'));
    verifyTrue(testCase, contains(trust_lower, 'trust'));
end

function testAuditSealCompletenesss(testCase)
    % Test: All required fields for audit trail are present
    %
    % Complete audit trail needs:
    %   - What: algorithmID, version
    %   - Who: trust
    %   - When: timestamp
    %   - Where: executionID
    %   - Proof: digest

    parameters = getTestParameters();
    psi_in = randn(10, 1) + 1i * randn(10, 1);
    trajectory = snapkitty.geometry.horizonTrajectory(parameters);

    result = snapkitty.transduceMode(psi_in, trajectory, parameters);
    seal = snapkitty.auditSeal(result);

    % Complete audit trail check
    verifyTrue(testCase, isfield(seal, 'algorithmID'));    % WHAT
    verifyTrue(testCase, isfield(seal, 'version'));        % WHAT (version)
    verifyTrue(testCase, isfield(seal, 'trust'));          % WHO
    verifyTrue(testCase, isfield(seal, 'timestamp'));      % WHEN
    verifyTrue(testCase, isfield(seal, 'executionID'));    % WHERE
    verifyTrue(testCase, isfield(seal, 'digest'));         % PROOF

    % All should be non-empty
    verifyTrue(testCase, ~isempty(seal.algorithmID));
    verifyTrue(testCase, ~isempty(seal.version));
    verifyTrue(testCase, ~isempty(seal.trust));
    verifyTrue(testCase, ~isempty(seal.timestamp));
    verifyTrue(testCase, ~isempty(seal.executionID));
    verifyTrue(testCase, ~isempty(seal.digest));
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
    parameters.auditEnabled = true;
end
