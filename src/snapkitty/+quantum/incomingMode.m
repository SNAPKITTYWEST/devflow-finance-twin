function psi = snapkitty.quantum.incomingMode(U, V, frequency, amplitude, varargin)
    % Generate incoming quantum mode in Kruskal-Szekeres coordinates
    % ψ_in(U, V, ω)
    %
    % Syntax:
    %   psi = snapkitty.quantum.incomingMode(U, V, frequency, amplitude)
    %   psi = snapkitty.quantum.incomingMode(U, V, frequency, amplitude, Name=Value)
    %
    % Input Arguments:
    %   U          -- Kruskal-Szekeres U coordinate (scalar or array)
    %   V          -- Kruskal-Szekeres V coordinate (scalar or array)
    %   frequency  -- Angular frequency ω (scalar, rad/s)
    %   amplitude  -- Initial amplitude a_0 (scalar)
    %
    % Name-Value Arguments:
    %   phase      -- Initial phase φ_0 (default: 0)
    %   seed       -- Random seed for reproducibility (default: 0)
    %
    % Output Arguments:
    %   psi        -- Quantum mode structure with fields:
    %                  U, V, frequency, energy, amplitude, phase, stateVector, metadata
    %
    % Description:
    %   Generates an incoming quantum mode in Kruskal-Szekeres coordinates.
    %   The mode is represented as a Gaussian wave packet with exponential phase.
    %
    % Example:
    %   U = linspace(-1, 1, 100);
    %   V = linspace(-1, 1, 100);
    %   psi = snapkitty.quantum.incomingMode(U, V, 1.0, 0.5, phase=pi/4);
    %
    % See also: outgoingMode, modeSpectrum

    % ========================================================================
    % SOVEREIGN LEVIATHAN NODE LICENSE
    % License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
    % Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
    % ========================================================================
    % BELESPRIT D'ACCORD COVENANT HEADER
    % This quantum implementation carries the trust seal of Bel Esprit D'Accord.
    % ========================================================================

    p = inputParser;
    addParameter(p, 'phase', 0);
    addParameter(p, 'seed', 0);
    parse(p, varargin{:});

    % Validate inputs
    if ~isnumeric(U) || ~isnumeric(V) || ~isscalar(frequency) || ~isscalar(amplitude)
        error('snapkitty:quantum:incomingMode:InvalidInput', ...
              'U, V must be numeric; frequency and amplitude must be scalars.');
    end

    % Ensure U and V have the same size
    if ~isequal(size(U), size(V))
        error('snapkitty:quantum:incomingMode:SizeMismatch', ...
              'U and V must have the same dimensions.');
    end

    % Set random seed if specified
    if p.Results.seed > 0
        rng(p.Results.seed);
    end

    % Mode structure initialization
    psi.U = U;
    psi.V = V;
    psi.frequency = frequency;
    psi.energy = frequency;  % E = ℏω (units: ℏ=1)
    psi.amplitude = amplitude;
    psi.phase = p.Results.phase;

    % State vector: Gaussian wave packet with exponential phase
    % ψ(U,V) = a_0 * exp(-(U² + V²)/(2σ²)) * exp(i*(ω(U+V) + φ_0))
    sigma = 0.1;  % Gaussian width parameter
    gaussian_envelope = exp(-(U.^2 + V.^2) / (2*sigma^2));
    phase_factor = exp(1i * (frequency * (U + V) + p.Results.phase));

    psi.stateVector = amplitude * gaussian_envelope .* phase_factor;

    % Metadata and trust information
    psi.metadata.timestamp = datetime('now');
    psi.metadata.trust = 'BelEsprit D''Accord Trust';
    psi.metadata.energy = psi.energy;
    psi.metadata.amplitude = amplitude;
    psi.metadata.gaussianWidth = sigma;

end
