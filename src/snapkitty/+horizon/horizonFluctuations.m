function phi_hf = snapkitty.horizon.horizonFluctuations(parameters, stateShape)
    % Horizon fluctuation field φ_hf
    % Stochastic field at horizon radius r = r_s
    %
    % Syntax:
    %   phi_hf = snapkitty.horizon.horizonFluctuations(parameters)
    %   phi_hf = snapkitty.horizon.horizonFluctuations(parameters, stateShape)
    %
    % Input Arguments:
    %   parameters -- Structure with fields:
    %                  .stochasticSeed (integer, use 0 for random)
    %                  .lP  (Planck length)
    %                  .r_s (Schwarzschild radius)
    %   stateShape -- Dimensions of fluctuation field (default: [1, 1000])
    %
    % Output Arguments:
    %   phi_hf     -- Horizon fluctuation structure with fields:
    %                  field, r_s, lP, suppression
    %
    % Description:
    %   Generates a stochastic fluctuation field at the black hole horizon.
    %   Amplitude is suppressed by (l_P / r_s)² due to Planck-scale physics.
    %
    %   φ_hf ~ randn * √(l_P / r_s)²
    %
    %   This models quantum geometry fluctuations at the event horizon,
    %   essential for black hole thermodynamics and information theory.
    %
    % Example:
    %   params.stochasticSeed = 42;
    %   params.lP = 1.616e-35;   % Planck length (m)
    %   params.r_s = 3000;        % Schwarzschild radius (m)
    %   phi_hf = snapkitty.horizon.horizonFluctuations(params, [1, 5000]);
    %
    % See also: dissipationOperator, incomingMode

    % ========================================================================
    % SOVEREIGN LEVIATHAN NODE LICENSE
    % License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
    % Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
    % ========================================================================
    % BELESPRIT D'ACCORD COVENANT HEADER
    % Horizon fluctuations under Bel Esprit D'Accord covenant.
    % ========================================================================

    % Default stateShape if not provided
    if nargin < 2
        stateShape = [1, 1000];
    end

    % Validate parameters structure
    if ~isstruct(parameters)
        error('snapkitty:horizon:horizonFluctuations:InvalidParameters', ...
              'parameters must be a structure.');
    end

    % Check required fields
    required_fields = {'stochasticSeed', 'lP', 'r_s'};
    for i = 1:length(required_fields)
        if ~isfield(parameters, required_fields{i})
            error('snapkitty:horizon:horizonFluctuations:MissingField', ...
                  sprintf('parameters missing required field: %s', required_fields{i}));
        end
    end

    % Validate parameter values
    if ~isscalar(parameters.lP) || parameters.lP <= 0
        error('snapkitty:horizon:horizonFluctuations:InvalidPlanckLength', ...
              'lP must be a positive scalar.');
    end

    if ~isscalar(parameters.r_s) || parameters.r_s <= 0
        error('snapkitty:horizon:horizonFluctuations:InvalidSchwarzchildRadius', ...
              'r_s must be a positive scalar.');
    end

    if ~isnumeric(parameters.stochasticSeed)
        error('snapkitty:horizon:horizonFluctuations:InvalidSeed', ...
              'stochasticSeed must be numeric.');
    end

    % Validate stateShape
    if ~isvector(stateShape) || ~all(stateShape > 0) || ~all(mod(stateShape, 1) == 0)
        error('snapkitty:horizon:horizonFluctuations:InvalidShape', ...
              'stateShape must be a vector of positive integers.');
    end

    % Set random seed for reproducibility
    if parameters.stochasticSeed > 0
        rng(parameters.stochasticSeed);
    end

    % Planck-scale suppression factor
    % Δφ_hf ~ (l_P / r_s)²
    suppression = (parameters.lP / parameters.r_s)^2;

    % Generate stochastic fluctuation field
    % φ_hf(r_s) = η * √suppression, where η ~ N(0,1)
    fluctuation_field = randn(stateShape) * sqrt(suppression);

    % Return structure with field and parameters
    phi_hf = struct();
    phi_hf.field = fluctuation_field;
    phi_hf.r_s = parameters.r_s;
    phi_hf.lP = parameters.lP;
    phi_hf.suppression = suppression;

    % Additional horizon properties
    phi_hf.fieldShape = stateShape;
    phi_hf.fieldMean = mean(fluctuation_field(:));
    phi_hf.fieldStd = std(fluctuation_field(:));

    % Horizon parameters
    phi_hf.schwarzschildRadius = parameters.r_s;
    phi_hf.planckLength = parameters.lP;
    phi_hf.ratioPlanckToHorizon = parameters.lP / parameters.r_s;

    % Metadata
    phi_hf.metadata.timestamp = datetime('now');
    phi_hf.metadata.trust = 'BelEsprit D''Accord Trust';
    phi_hf.metadata.seed = parameters.stochasticSeed;
    phi_hf.metadata.stochasticRealization = true;

end
