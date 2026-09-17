function spectrum = snapkitty.quantum.modeSpectrum(psi)
    % Frequency spectrum of quantum mode
    %
    % Syntax:
    %   spectrum = snapkitty.quantum.modeSpectrum(psi)
    %
    % Input Arguments:
    %   psi        -- Quantum mode structure (from incomingMode or outgoingMode)
    %
    % Output Arguments:
    %   spectrum   -- Structure with frequency spectrum data:
    %                  frequencies, power, peakFrequency, energy
    %
    % Description:
    %   Computes the frequency spectrum of a quantum mode via FFT.
    %   Normalizes power spectrum to unit peak.
    %
    %   Power spectrum: |ψ̃(ω)|² normalized to max = 1
    %   Peak frequency: ω_peak = mode center frequency
    %   Energy: E = ℏω (in natural units, ℏ=1)
    %
    % Example:
    %   psi = snapkitty.quantum.incomingMode(U, V, 1.0, 0.5);
    %   spectrum = snapkitty.quantum.modeSpectrum(psi);
    %   semilogy(spectrum.frequencies, spectrum.power);
    %
    % See also: incomingMode, outgoingMode, phaseOperator

    % ========================================================================
    % SOVEREIGN LEVIATHAN NODE LICENSE
    % License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
    % Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
    % ========================================================================
    % BELESPRIT D'ACCORD COVENANT HEADER
    % Spectral analysis under Bel Esprit D'Accord covenant.
    % ========================================================================

    % Validate input
    if ~isstruct(psi)
        error('snapkitty:quantum:modeSpectrum:InvalidInput', ...
              'Input must be a quantum mode structure.');
    end

    if ~isfield(psi, 'stateVector') || ~isfield(psi, 'frequency')
        error('snapkitty:quantum:modeSpectrum:MissingFields', ...
              'Input structure must have stateVector and frequency fields.');
    end

    % Ensure state vector is a column vector for FFT
    state_vec = psi.stateVector(:);
    N = length(state_vec);

    % Compute FFT
    fft_result = fft(state_vec);

    % Compute power spectrum |ψ̃(ω)|²
    power = abs(fft_result).^2;

    % Normalize power spectrum to peak = 1
    if max(power) > 0
        power = power / max(power);
    end

    % Generate frequency array centered at mode frequency
    % Range: [-0.5*f_mode, +0.5*f_mode]
    freq_normalized = linspace(-0.5, 0.5, N);
    frequencies = psi.frequency * freq_normalized;

    % Initialize output structure
    spectrum.frequencies = frequencies;
    spectrum.power = power;
    spectrum.peakFrequency = psi.frequency;
    spectrum.energy = psi.frequency;  % E = ℏω, ℏ=1

    % Additional spectral properties
    spectrum.fftResult = fft_result;
    spectrum.numberSamples = N;

    % Compute bandwidth (FWHM approximation)
    power_threshold = 0.5;  % Half maximum
    indices_above_threshold = find(power > power_threshold);
    if ~isempty(indices_above_threshold)
        bandwidth_indices = indices_above_threshold(end) - indices_above_threshold(1);
        spectrum.bandwidth = (bandwidth_indices / N) * psi.frequency;
    else
        spectrum.bandwidth = 0;
    end

    % Metadata
    spectrum.metadata.timestamp = datetime('now');
    spectrum.metadata.trust = 'BelEsprit D''Accord Trust';
    if isfield(psi, 'metadata')
        spectrum.metadata.sourceMode = psi.metadata;
    end

end
