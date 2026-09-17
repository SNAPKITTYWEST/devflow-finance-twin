function psi_diss = snapkitty.horizon.dissipationOperator(psi_in, projector, phi_hf)
    % Dissipation operator D_hf
    % ψ_diss = D_hf (I - P_res) ψ_in
    %
    % Syntax:
    %   psi_diss = snapkitty.horizon.dissipationOperator(psi_in, projector, phi_hf)
    %
    % Input Arguments:
    %   psi_in     -- Input quantum mode (from incomingMode)
    %   projector  -- Resonance projector P_res ∈ [0,1]
    %   phi_hf     -- Horizon fluctuation field (from horizonFluctuations)
    %
    % Output Arguments:
    %   psi_diss   -- Dissipated quantum mode after horizon coupling
    %
    % Description:
    %   Models energy dissipation via horizon coupling. The operator
    %   D_hf applies off-resonance dissipation (I - P_res) and couples
    %   to stochastic horizon fluctuations φ_hf.
    %
    %   Dissipation amplitude: √(1 - P_res)
    %   Horizon coupling: √suppression_factor
    %   State evolution: ψ → ψ * (1 - P_res) * φ_hf
    %
    %   This realizes energy loss to the black hole background.
    %
    % Example:
    %   psi_in = snapkitty.quantum.incomingMode(U, V, 1.0, 0.5);
    %   projector = 0.95;
    %   params.stochasticSeed = 42;
    %   params.lP = 1.616e-35;
    %   params.r_s = 3000;
    %   phi_hf = snapkitty.horizon.horizonFluctuations(params);
    %   psi_diss = snapkitty.horizon.dissipationOperator(psi_in, projector, phi_hf);
    %
    % See also: incomingMode, horizonFluctuations, outgoingMode

    % ========================================================================
    % SOVEREIGN LEVIATHAN NODE LICENSE
    % License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
    % Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
    % ========================================================================
    % BELESPRIT D'ACCORD COVENANT HEADER
    % Horizon dissipation under Bel Esprit D'Accord covenant.
    % ========================================================================

    % Validate inputs
    if ~isstruct(psi_in)
        error('snapkitty:horizon:dissipationOperator:InvalidInput', ...
              'psi_in must be a quantum mode structure.');
    end

    if ~isscalar(projector) || projector < 0 || projector > 1
        error('snapkitty:horizon:dissipationOperator:InvalidProjector', ...
              'projector must be a scalar in [0, 1].');
    end

    if ~isstruct(phi_hf)
        error('snapkitty:horizon:dissipationOperator:InvalidHorizonFluctuations', ...
              'phi_hf must be a horizon fluctuation structure.');
    end

    % Check required fields in psi_in
    required_mode_fields = {'U', 'V', 'frequency', 'energy', 'amplitude', 'phase', 'stateVector'};
    for i = 1:length(required_mode_fields)
        if ~isfield(psi_in, required_mode_fields{i})
            error('snapkitty:horizon:dissipationOperator:MissingModeField', ...
                  sprintf('psi_in missing field: %s', required_mode_fields{i}));
        end
    end

    % Check required fields in phi_hf
    if ~isfield(phi_hf, 'field') || ~isfield(phi_hf, 'suppression')
        error('snapkitty:horizon:dissipationOperator:MissingHorizonField', ...
              'phi_hf must have field and suppression fields.');
    end

    % Compute dissipation amplitude: √(1 - P_res)
    dissipation_amplitude = 1 - projector;
    dissipation_sqrt = sqrt(dissipation_amplitude);

    % Horizon coupling strength
    coupling = phi_hf.suppression;
    coupling_sqrt = sqrt(coupling);

    % Initialize output structure
    psi_diss.U = psi_in.U;
    psi_diss.V = psi_in.V;
    psi_diss.frequency = psi_in.frequency;

    % Energy after dissipation: E_diss = E_in * (1 - P_res)
    psi_diss.energy = psi_in.energy * dissipation_amplitude;

    % Amplitude after dissipation: a_diss = a_in * √(1-P_res) * √coupling
    psi_diss.amplitude = psi_in.amplitude * dissipation_sqrt * coupling_sqrt;

    % Phase modification by horizon fluctuations
    % Add phase shift from first element of fluctuation field
    phase_shift = angle(phi_hf.field(1));
    psi_diss.phase = psi_in.phase + phase_shift;

    % State vector: ψ_diss = ψ_in * (1 - P_res) * φ_hf
    psi_diss.stateVector = psi_in.stateVector * dissipation_amplitude .* phi_hf.field;

    % Preserve and extend metadata
    if isfield(psi_in, 'metadata')
        psi_diss.metadata = psi_in.metadata;
    else
        psi_diss.metadata = struct();
    end

    % Mark dissipation and record parameters
    psi_diss.metadata.dissipated = true;
    psi_diss.metadata.dissipationTime = datetime('now');
    psi_diss.metadata.dissipationAmplitude = dissipation_amplitude;
    psi_diss.metadata.horizonCoupling = coupling;
    psi_diss.metadata.projector = projector;

    % Energy audit trail
    if isfield(psi_in, 'energy')
        psi_diss.metadata.preDissipatioEnergy = psi_in.energy;
        psi_diss.metadata.postDissipationEnergy = psi_diss.energy;
        psi_diss.metadata.energyLoss = psi_in.energy - psi_diss.energy;
        psi_diss.metadata.energyLossFraction = psi_diss.metadata.energyLoss / psi_in.energy;
    end

    % Horizon parameters for audit
    if isfield(phi_hf, 'schwarzschildRadius')
        psi_diss.metadata.schwarzschildRadius = phi_hf.schwarzschildRadius;
    end

    if isfield(phi_hf, 'planckLength')
        psi_diss.metadata.planckLength = phi_hf.planckLength;
    end

end
