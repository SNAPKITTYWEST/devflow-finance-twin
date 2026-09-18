function psi_out = snapkitty.quantum.outgoingMode(psi_in, projector)
    % Generate outgoing mode after transduction
    % ψ_out = P_res ψ_in
    %
    % Syntax:
    %   psi_out = snapkitty.quantum.outgoingMode(psi_in, projector)
    %
    % Input Arguments:
    %   psi_in     -- Input quantum mode structure (from incomingMode)
    %   projector  -- Resonance projector P_res (scalar, 0 ≤ P_res ≤ 1)
    %
    % Output Arguments:
    %   psi_out    -- Output quantum mode after transduction
    %
    % Description:
    %   Applies a resonance projector P_res to an incoming quantum mode.
    %   The projector represents the efficiency of energy transfer and
    %   quantum state transduction.
    %
    %   Energy scaling:  E_out = E_in * P_res
    %   Amplitude scaling: a_out = a_in * √P_res
    %   State vector scaling: ψ_out = ψ_in * P_res
    %
    % Example:
    %   psi_in = snapkitty.quantum.incomingMode(U, V, 1.0, 0.5);
    %   projector = 0.95;
    %   psi_out = snapkitty.quantum.outgoingMode(psi_in, projector);
    %
    % See also: incomingMode, dissipationOperator

    % ========================================================================
    % SOVEREIGN LEVIATHAN NODE LICENSE
    % License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
    % Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
    % ========================================================================
    % BELESPRIT D'ACCORD COVENANT HEADER
    % This quantum transduction implementation carries the trust seal of Bel Esprit D'Accord.
    % ========================================================================

    % Validate inputs
    if ~isstruct(psi_in)
        error('snapkitty:quantum:outgoingMode:InvalidInput', ...
              'psi_in must be a structure (output from incomingMode).');
    end

    if ~isscalar(projector) || projector < 0 || projector > 1
        error('snapkitty:quantum:outgoingMode:InvalidProjector', ...
              'projector must be a scalar in range [0, 1].');
    end

    % Required fields check
    required_fields = {'U', 'V', 'frequency', 'energy', 'amplitude', 'phase', 'stateVector'};
    for i = 1:length(required_fields)
        if ~isfield(psi_in, required_fields{i})
            error('snapkitty:quantum:outgoingMode:MissingField', ...
                  sprintf('Input structure missing required field: %s', required_fields{i}));
        end
    end

    % Initialize output structure with incoming mode data
    psi_out.U = psi_in.U;
    psi_out.V = psi_in.V;
    psi_out.frequency = psi_in.frequency;

    % Apply projector scaling
    psi_out.energy = psi_in.energy * projector;
    psi_out.amplitude = psi_in.amplitude * sqrt(projector);
    psi_out.phase = psi_in.phase;

    % Apply projector to state vector
    psi_out.stateVector = psi_in.stateVector * projector;

    % Preserve and extend metadata
    if isfield(psi_in, 'metadata')
        psi_out.metadata = psi_in.metadata;
    else
        psi_out.metadata = struct();
    end

    % Mark transduction and record projector efficiency
    psi_out.metadata.transduced = true;
    psi_out.metadata.projector = projector;
    psi_out.metadata.transductionTime = datetime('now');
    psi_out.metadata.energyTransferEfficiency = projector;

    % Store energy before and after for audit trail
    if isfield(psi_in, 'energy')
        psi_out.metadata.incomingEnergy = psi_in.energy;
        psi_out.metadata.outgoingEnergy = psi_out.energy;
    end

end
