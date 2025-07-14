function wfFin = mySignalMixerInterf(waveforms, timeDuration, noisePower, pMax)
% MYSIGNALMIXERINTERF Combines multiple wireless signals with interference and noise
%
%   wfFin = mySignalMixerInterf(waveforms, timeDuration, noisePower, pMax)
%   This function creates a realistic wireless environment by:
%   1. Combining multiple input signal waveforms
%   2. Adding random interference signals
%   3. Adding complex white Gaussian noise (AWGN)
%
%   The function simulates a typical RF environment where multiple wireless
%   protocols (WLAN, Bluetooth, ZigBee, SmartBAN) coexist in the same spectrum
%   with various sources of interference and background noise.
%
%   INPUTS:
%       waveforms    - (complex matrix) Each column contains a different signal waveform
%                      Size: [N_samples x N_signals] where N_samples = timeDuration * srTotal
%       timeDuration - (double) Duration of the output signal in seconds (e.g., 20e-3 for 20ms)
%       noisePower   - (double) Power of additive white Gaussian noise in linear scale
%                      This represents thermal noise and other background noise sources
%       pMax         - (double) Maximum received power among input signals in dB
%                      Used as reference for scaling interference signals
%
%   OUTPUTS:
%       wfFin        - (complex vector) Final mixed signal containing:
%                      - All input signals combined
%                      - Random interference signals
%                      - Complex white Gaussian noise
%                      Size: [N_samples x 1] where N_samples = timeDuration * srTotal
%
%   SIGNAL PROCESSING DETAILS:
%   - Sampling Rate: Fixed at 80 MHz (suitable for 2.4 GHz ISM band analysis)
%   - Noise Model: Complex white Gaussian noise with specified power
%   - Interference: Random number (1-2) of additional interfering signals
%   - Power Monitoring: Displays received power of each signal and noise for debugging
%
%   EXAMPLE:
%       % Mix 3 signals for 20ms duration with -30dB noise power
%       waveforms = [signal1, signal2, signal3];  % 3 columns of signal data
%       mixedSignal = mySignalMixerInterf(waveforms, 20e-3, 1e-3, -10);
%
%   See also: generateInterference, randn, fprintf

    % =========================================================================
    % SYSTEM PARAMETERS
    % =========================================================================
    
    % Fixed sampling rate for the entire system (80 MHz)
    % This high sampling rate is chosen to:
    % - Capture wideband signals in the 2.4 GHz ISM band
    % - Provide sufficient bandwidth for multiple coexisting protocols
    % - Enable accurate spectral analysis and interference detection
    srTotal = 80e6;  % [Hz] - System sampling rate
    
    % =========================================================================
    % OUTPUT SIGNAL INITIALIZATION
    % =========================================================================
    
    % Pre-allocate output vector for computational efficiency
    % Size calculation: timeDuration [seconds] × srTotal [samples/second]
    % Example: 20ms × 80MHz = 1,600,000 samples
    wfFin = zeros(timeDuration * srTotal, 1);  % Complex zeros for I/Q data
    
    % =========================================================================
    % SIGNAL COMBINATION PHASE
    % =========================================================================
    
    % Iterate through each input signal and combine them linearly
    % This simulates the superposition principle in RF environments where
    % multiple signals occupy the same frequency spectrum simultaneously
    for i = 1:size(waveforms, 2)  % Loop over each signal (column)
        
        % Calculate and display the received power of current signal
        % Power calculation: P_rx = max(|signal|²) in linear scale
        % Conversion to dB: P_dB = 10 × log₁₀(P_linear)
        rxPower_dB = 10 * log10(max((abs(waveforms(:,i))).^2));
        fprintf("Signal %d rx power: %.4f dB\n", i, rxPower_dB);
        
        % Superposition: Add current signal to the mixed output
        % This represents the linear combination of electromagnetic waves
        % at the receiver antenna
        wfFin = wfFin + waveforms(:, i);
    end
    
    % =========================================================================
    % NOISE GENERATION AND ADDITION
    % =========================================================================
    
    % Generate complex white Gaussian noise (AWGN)
    % Real and imaginary parts are generated independently with equal variance
    % to model thermal noise and other wideband noise sources in RF systems
    
    % Noise power distribution:
    % - Total noise power = noisePower (linear scale)
    % - Split equally between I and Q channels: noisePower/2 each
    % - Standard deviation = √(power/2) for each Gaussian component
    noiseStdDev = sqrt(noisePower/2);
    
    % Generate independent Gaussian random variables for I and Q channels
    noiseReal = randn(size(wfFin));      % In-phase component
    noiseImag = randn(size(wfFin));      % Quadrature component
    
    % Combine I and Q components to form complex noise
    noise = noiseStdDev * (noiseReal + 1i * noiseImag);
    
    % Calculate and display actual noise power for verification
    % Mean power = E[|noise|²] ≈ (1/N) × Σ|noise[n]|²
    actualNoisePower_dB = 10 * log10(mean((abs(noise)).^2));
    fprintf("Actual noise power: %.4f dB\n", actualNoisePower_dB);
    
    % =========================================================================
    % INTERFERENCE GENERATION AND ADDITION
    % =========================================================================
    
    % Generate random number of interference sources (1 or 2)
    % This simulates realistic RF environments where unknown interferers
    % may be present (e.g., microwave ovens, other wireless devices)
    numInterf = randi(2);  % Randomly select 1 or 2 interferers
    fprintf("Adding %d interference source(s)\n", numInterf);
    
    % Generate interference signals with power relative to maximum signal power
    % The interference level is scaled based on pMax to ensure realistic
    % interference-to-signal ratios
    interf = generateInterference(numInterf, pMax);
    
    % Add interference to the mixed signal
    % This represents unwanted signals that may degrade system performance
    wfFin = wfFin + interf;
    
    % =========================================================================
    % FINAL SIGNAL ASSEMBLY
    % =========================================================================
    
    % Add noise as the final step
    % In real RF systems, noise is always present and represents the
    % fundamental limit for signal detection and demodulation
    wfFin = wfFin + noise;
    
    % Final output contains:
    % wfFin = Σ(desired_signals) + interference + noise
    % This represents a realistic received signal in a multi-user,
    % multi-protocol wireless environment
    
    % =========================================================================
    % SIGNAL CHARACTERISTICS SUMMARY
    % =========================================================================
    % The output signal wfFin has the following characteristics:
    % - Sampling Rate: 80 MHz
    % - Duration: timeDuration seconds
    % - Content: Multiple wireless protocol signals + interference + noise
    % - Format: Complex baseband (I/Q) representation
    % - Applications: Spectrum sensing, signal classification, interference analysis
    
end