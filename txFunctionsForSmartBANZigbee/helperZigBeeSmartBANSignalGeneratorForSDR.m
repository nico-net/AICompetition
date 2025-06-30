function helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, carrierFrequency)
%% ========================================================================
%% helperZigBeeSmartBANSignalGeneratorForSDR - ZigBee/SmartBAN Signal Generator
%% ========================================================================
%
% Generate and transmit ZigBee or SmartBAN signals using PlutoSDR with 
% spectrogram visualization and configurable transmission parameters.
%
% This function implements a probabilistic transmission model that can
% either transmit a signal or remain idle, simulating realistic network
% behavior with intermittent transmissions.
%
% SYNTAX:
%   helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, carrierFrequency)
%
% INPUTS:
%   tx               - PlutoSDR transmitter System object (comm.SDRTxPluto)
%   frameDuration    - Duration of the generated frame in seconds (positive scalar)
%                      Typical range: 0.001 to 1.0 seconds
%   sr               - Sampling rate in Hz (positive scalar)
%                      Typical range: 1e6 to 20e6 Hz
%   imageSize        - Vector [rows, cols] or cell array {rows, cols} specifying 
%                      spectrogram image dimensions for visualization
%   carrierFrequency - Carrier frequency vector in Hz (positive values)
%                      Index 1: ZigBee frequency, Index 2: SmartBAN frequency
%
% OUTPUTS:
%   None (function transmits signal via SDR and displays spectrogram)
%
% EXAMPLES:
%   % Basic usage with PlutoSDR
%   tx = sdrtx('Pluto', 'RadioID', 'usb:0');
%   helperZigBeeSmartBANSignalGeneratorForSDR(tx, 0.02, 10e6, [1024, 1024], [2.43e9, 2.44e9]);
%
% DEPENDENCIES:
%   - Communications Toolbox Support Package for ADALM-Pluto Radio
%   - helperZigBeeSDR function (for ZigBee waveform generation)
%   - helperSmartBANSDR function (for SmartBAN waveform generation)
%   - Image Processing Toolbox (for spectrogram visualization)
%
% See also: sdrtx, spectrogram, helperZigBeeSDR, helperSmartBANSDR
%
% Author: [Your Name]
% Date: [Current Date]
% Version: 2.0
%% ========================================================================

    %% --- INPUT VALIDATION ---
    fprintf('Validating input parameters...\n');
    
    % Validate SDR transmitter object
    if ~isa(tx, 'matlab.system.System') && ~isa(tx, 'comm.SDRTxPluto')
        error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidTransmitter', ...
              'tx must be a PlutoSDR transmitter System object (comm.SDRTxPluto).');
    end
    
    % Validate frame duration
    if ~isscalar(frameDuration) || ~isnumeric(frameDuration) || frameDuration <= 0
        error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidFrameDuration', ...
              'frameDuration must be a positive numeric scalar.');
    end
    
    % Validate sampling rate
    if ~isscalar(sr) || ~isnumeric(sr) || sr <= 0
        error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidSampleRate', ...
              'sr (sample rate) must be a positive numeric scalar.');
    end
    
    % Validate and convert image size
    if iscell(imageSize)
        if numel(imageSize) == 1
            imageSize = [imageSize{1}, imageSize{1}];  % Square image
        elseif numel(imageSize) == 2
            imageSize = [imageSize{1}, imageSize{2}];
        else
            error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidImageSize', ...
                  'imageSize must be a vector [rows, cols] or cell array {rows} or {rows, cols}.');
        end
    elseif isnumeric(imageSize)
        if length(imageSize) == 1
            imageSize = [imageSize, imageSize];  % Square image
        elseif length(imageSize) ~= 2
            error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidImageSize', ...
                  'imageSize must be a vector [rows, cols] or cell array {rows} or {rows, cols}.');
        end
    else
        error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidImageSize', ...
              'imageSize must be a numeric vector or cell array.');
    end
    
    % Validate carrier frequency
    if ~isnumeric(carrierFrequency) || any(carrierFrequency <= 0)
        error('helperZigBeeSmartBANSignalGeneratorForSDR:InvalidCarrierFreq', ...
              'carrierFrequency must be a numeric vector with all positive values.');
    end
    
    if length(carrierFrequency) < 2
        error('helperZigBeeSmartBANSignalGeneratorForSDR:InsufficientCarrierFreq', ...
              'carrierFrequency must contain at least 2 frequencies (ZigBee and SmartBAN).');
    end
    
    fprintf('Input validation completed successfully.\n');

    %% --- CONFIGURATION PARAMETERS ---
    % Transmission probability (0 to 1)
    % 1.0 = always transmit, 0.0 = never transmit
    transmissionProbability = 1.0;  % Currently set to always transmit
    
    % Signal type configuration
    % 1 = ZigBee, 2 = SmartBAN
    % Currently fixed to ZigBee for consistent testing
    signalTypeMode = 'fixed';  % Options: 'fixed', 'random'
    fixedSignalType = 2;       % Used when signalTypeMode is 'fixed'
    
    % Close all figures to maintain clean visualization environment
    close all;
    
    %% --- TRANSMISSION DECISION ---
    % Generate random number to determine if transmission should occur
    transmissionDecision = rand();
    
    fprintf('Transmission probability: %.2f\n', transmissionProbability);
    fprintf('Random decision value: %.3f\n', transmissionDecision);
    
    if transmissionDecision < transmissionProbability
        %% --- SIGNAL TYPE SELECTION ---
        if strcmp(signalTypeMode, 'random')
            % Randomly select between ZigBee (1) and SmartBAN (2)
            typeOfSignal = randi([1, 2]);
            fprintf('Randomly selected signal type: %d\n', typeOfSignal);
        else
            % Use fixed signal type
            typeOfSignal = fixedSignalType;
            fprintf('Using fixed signal type: %d\n', typeOfSignal);
        end
        
        % Get corresponding carrier frequency
        if typeOfSignal <= length(carrierFrequency)
            centFreq = carrierFrequency(typeOfSignal);
        else
            centFreq = carrierFrequency(1);  % Fallback to first frequency
            warning('helperZigBeeSmartBANSignalGeneratorForSDR:FrequencyFallback', ...
                    'Signal type index exceeds carrier frequency array length. Using first frequency.');
        end
        
        fprintf('Selected center frequency: %.3f GHz\n', centFreq/1e9);
        
        %% --- WAVEFORM GENERATION ---
        fprintf('Generating waveform...\n');
        tic;  % Start timing waveform generation
        
        wfClean = generateWaveform(typeOfSignal, frameDuration, sr);
        
        generationTime = toc;
        fprintf('Waveform generation completed in %.3f seconds\n', generationTime);
        fprintf('Waveform properties:\n');
        fprintf('  - Length: %d samples\n', length(wfClean));
        fprintf('  - Duration: %.3f ms\n', length(wfClean)/sr * 1000);
        fprintf('  - Peak amplitude: %.3f\n', max(abs(wfClean)));
        fprintf('  - RMS amplitude: %.3f\n', rms(wfClean));
        
        %% --- SPECTROGRAM VISUALIZATION ---
        fprintf('Creating spectrogram visualization...\n');
        tic;  % Start timing spectrogram creation
        
        createSpectrogram(wfClean, sr, imageSize, centFreq, frameDuration, typeOfSignal);
        
        spectrogramTime = toc;
        fprintf('Spectrogram creation completed in %.3f seconds\n', spectrogramTime);
        
        %% --- SDR TRANSMISSION ---
        fprintf('Transmitting signal via PlutoSDR...\n');
        tic;  % Start timing transmission
        
        try
            % Configure SDR center frequency
            tx.CenterFrequency = centFreq;
            
            % Transmit the waveform
            tx(wfClean);
            
            transmissionTime = toc;
            fprintf('Signal transmission completed in %.3f seconds\n', transmissionTime);
            fprintf('Transmission successful!\n');
            
        catch txError
            fprintf('Transmission error: %s\n', txError.message);
            error('helperZigBeeSmartBANSignalGeneratorForSDR:TransmissionFailed', ...
                  'Failed to transmit signal: %s', txError.message);
        end
        
    else
        %% --- IDLE MODE ---
        fprintf('=== SLEEP MODE ACTIVATED ===\n');
        fprintf('No transmission - device in idle state\n');
        fprintf('This simulates realistic network behavior with intermittent activity\n');
    end
    
    fprintf('Function execution completed.\n\n');
end

%% ========================================================================
%% HELPER FUNCTION: generateWaveform
%% ========================================================================
function wfFin = generateWaveform(numOfSignal, frameDuration, sr)
% generateWaveform - Generate synthetic ZigBee or SmartBAN waveform
%
% This function creates realistic waveforms for either ZigBee or SmartBAN
% protocols with configurable transmission power levels and packet structures.
%
% SYNTAX:
%   wfFin = generateWaveform(numOfSignal, frameDuration, sr)
%
% INPUTS:
%   numOfSignal   - Signal type identifier (integer)
%                   1 = ZigBee (IEEE 802.15.4)
%                   2 = SmartBAN (IEEE 802.15.6)
%   frameDuration - Duration of generated frame in seconds (positive scalar)
%   sr            - Sampling rate in Hz (positive scalar)
%
% OUTPUTS:
%   wfFin         - Generated complex baseband waveform (column vector)
%
% PROTOCOL DETAILS:
%   ZigBee (IEEE 802.15.4):
%     - Uses OQPSK modulation in 2.4 GHz band
%     - Typical power levels: -3, 0, 8 dBm
%     - Variable packet count (1-3 packets per frame)
%     - 4 samples per chip (configurable)
%
%   SmartBAN (IEEE 802.15.6):
%     - Body Area Network protocol
%     - Typical power levels: 0, 4, 20 dBm
%     - Optimized for low-power medical applications

    %% --- INPUT VALIDATION ---
    if ~isscalar(numOfSignal) || ~isnumeric(numOfSignal) || floor(numOfSignal) ~= numOfSignal
        error('generateWaveform:InvalidSignalType', ...
              'numOfSignal must be an integer scalar.');
    end
    
    if numOfSignal < 1 || numOfSignal > 2
        error('generateWaveform:UnsupportedSignalType', ...
              'numOfSignal must be either 1 (ZigBee) or 2 (SmartBAN).');
    end
    
    if ~isscalar(frameDuration) || ~isnumeric(frameDuration) || frameDuration <= 0
        error('generateWaveform:InvalidFrameDuration', ...
              'frameDuration must be a positive numeric scalar.');
    end
    
    if ~isscalar(sr) || ~isnumeric(sr) || sr <= 0
        error('generateWaveform:InvalidSampleRate', ...
              'sr must be a positive numeric scalar.');
    end
    
    %% --- SIGNAL GENERATION ---
    fprintf('  Signal type: ');
    
    switch numOfSignal
        case 1  % ZigBee (IEEE 802.15.4)
            fprintf('ZigBee (IEEE 802.15.4)\n');
            
            % ZigBee-specific parameters
            spc = 4;  % Samples per chip (affects bandwidth and quality)
            numPackets = randi([1, 3]);  % Random number of packets (1-3)
            
            % Realistic transmission power distribution for ZigBee devices
            txPowerArr = [-3, 0, 8];  % Available power levels in dBm
            weights = [0.15, 0.75, 0.10];  % Probability weights (most common: 0 dBm)
            txPower = randsample(txPowerArr, 1, true, weights);
            
            fprintf('  - Samples per chip: %d\n', spc);
            fprintf('  - Number of packets: %d\n', numPackets);
            fprintf('  - Transmission power: %d dBm\n', txPower);
            
            % Generate ZigBee waveform using helper function
            wfFin = helperZigBeeSDR(spc, numPackets, frameDuration, sr, txPower);
            
        case 2  % SmartBAN (IEEE 802.15.6)
            fprintf('SmartBAN (IEEE 802.15.6)\n');
            
            % SmartBAN-specific parameters
            % Realistic transmission power distribution for body area networks
            txPowerArr = [0, 4, 20];  % Available power levels in dBm
            weights = [0.03, 0.94, 0.03];  % Probability weights (most common: 4 dBm)
            txPower = randsample(txPowerArr, 1, true, weights);
            
            fprintf('  - Transmission power: %d dBm\n', txPower);
            fprintf('  - Protocol: Body Area Network optimized\n');
            
            % Generate SmartBAN waveform using helper function
            wfFin = helperSmartBANSDR(sr, frameDuration, txPower);
            
        otherwise
            error('generateWaveform:UnknownSignalType', ...
                  'Unknown signal type: %d', numOfSignal);
    end
    
    %% --- WAVEFORM POST-PROCESSING ---
    % Ensure waveform is a column vector
    if isrow(wfFin)
        wfFin = wfFin.';
    end
    
    % Validate generated waveform
    if isempty(wfFin)
        error('generateWaveform:EmptyWaveform', ...
              'Generated waveform is empty.');
    end
    
    if ~isnumeric(wfFin)
        error('generateWaveform:InvalidWaveform', ...
              'Generated waveform must be numeric.');
    end
    
    % Apply power scaling based on selected transmission power
    % Convert dBm to linear scale (assuming 50 ohm impedance)
    powerLinear = 10^(txPower/10) * 1e-3;  % Convert dBm to watts
    powerScaling = sqrt(powerLinear);
    wfFin = wfFin * powerScaling;
    
    fprintf('  - Final waveform length: %d samples\n', length(wfFin));
    fprintf('  - Applied power scaling: %.3f\n', powerScaling);
end

%% ========================================================================
%% HELPER FUNCTION: createSpectrogram
%% ========================================================================
function createSpectrogram(waveform, sr, imageSize, fc, frameDuration, signalType)
% createSpectrogram - Compute and visualize signal spectrogram
%
% This function creates a high-quality spectrogram visualization with
% physical frequency and time axes, optimized for RF signal analysis.
%
% SYNTAX:
%   createSpectrogram(waveform, sr, imageSize, fc, frameDuration, signalType)
%
% INPUTS:
%   waveform      - Input complex baseband signal (column vector)
%   sr            - Sampling rate in Hz (positive scalar)
%   imageSize     - Output image dimensions [rows, cols]
%   fc            - Center frequency in Hz (for axis labeling)
%   frameDuration - Total frame duration in seconds
%   signalType    - Signal type (1=ZigBee, 2=SmartBAN) for title
%
% OUTPUTS:
%   None (displays spectrogram figure)
%
% FEATURES:
%   - High-resolution FFT for detailed frequency analysis
%   - Optimized window and overlap parameters
%   - Dynamic range compression for visualization
%   - Physical frequency and time axis labeling
%   - Professional colormap with proper scaling

    %% --- SPECTROGRAM PARAMETERS ---
    % These parameters are optimized for RF signal analysis
    db_min = -130;              % Minimum dB level for display
    db_max = -50;               % Maximum dB level for display
    Nfft = 4096;                % FFT size (high resolution)
    window = hann(256);         % Hann window for good frequency resolution
    overlap = 10;               % Overlap between windows (samples)
    colormap_resolution = 256;  % Color resolution for display
    
    %% --- SPECTROGRAM COMPUTATION ---
    fprintf('  Computing spectrogram...\n');
    
    % Compute spectrogram using MATLAB's built-in function
    [~, F, T, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'centered', 'psd');
    
    % Convert power spectral density to dB scale
    P_dB = 10 * log10(abs(P') + eps);  % Transpose and add small value to avoid log(0)
    
    fprintf('    - Frequency bins: %d\n', length(F));
    fprintf('    - Time bins: %d\n', length(T));
    fprintf('    - Power range: %.1f to %.1f dB\n', min(P_dB(:)), max(P_dB(:)));
    
    %% --- DYNAMIC RANGE PROCESSING ---
    % Clip values to specified dynamic range
    P_clipped = min(max(P_dB, db_min), db_max);
    
    % Normalize to [0,1] range for image processing
    P_normalized = (P_clipped - db_min) / (db_max - db_min);
    
    %% --- IMAGE PROCESSING ---
    fprintf('  Processing spectrogram image...\n');
    
    % Convert to 8-bit image and resize to specified dimensions
    spectrogram_image = imresize(im2uint8(P_normalized), imageSize, "nearest");
    
    % Apply colormap and convert to RGB
    % Using parula colormap for professional appearance
    rgb_image = im2uint8(flipud(ind2rgb(spectrogram_image, parula(colormap_resolution))));
    
    fprintf('    - Output image size: %dx%d pixels\n', size(rgb_image, 1), size(rgb_image, 2));
    
    %% --- VISUALIZATION ---
    % Note: Visualization code is commented out to reduce computational overhead
    % Uncomment the following section if spectrogram display is needed
    
    % Signal type names for display
    signalNames = {'ZigBee', 'SmartBAN'};
    if signalType >= 1 && signalType <= length(signalNames)
        signalName = signalNames{signalType};
    else
        signalName = sprintf('Signal Type %d', signalType);
    end
    
    fprintf('  Spectrogram visualization prepared for %s signal\n', signalName);
    fprintf('  Center frequency: %.3f GHz\n', fc/1e9);
    fprintf('  Bandwidth: %.3f MHz\n', sr/1e6);
    
    % UNCOMMENT BELOW FOR SPECTROGRAM DISPLAY:
    % {
    figure('Name', sprintf('%s Spectrogram', signalName), 'NumberTitle', 'off');
    imagesc(rgb_image);
    axis on;
    ax = gca;

    % Configure frequency axis (X-axis)
    freq_vector = F + fc;  % Convert to absolute frequency
    freq_vector_GHz = freq_vector / 1e9;  % Convert to GHz

    % Create frequency tick labels
    nTicksX = 5;
    freq_ticks = linspace(1, size(rgb_image, 2), nTicksX);
    freq_labels = linspace(min(freq_vector_GHz), max(freq_vector_GHz), nTicksX);

    ax.XTick = freq_ticks;
    ax.XTickLabel = arrayfun(@(x) sprintf('%.3f', x), freq_labels, 'UniformOutput', false);
    xlabel('Frequency (GHz)');

    % Configure time axis (Y-axis)
    nTicksY = 5;
    time_ticks = linspace(1, size(rgb_image, 1), nTicksY);
    time_labels = linspace(0, frameDuration, nTicksY);

    ax.YTick = time_ticks;
    ax.YTickLabel = arrayfun(@(x) sprintf('%.3f', x), time_labels, 'UniformOutput', false);
    ylabel('Time (s)');

    % Add title and formatting
    title(sprintf('%s Signal Spectrogram (fc = %.3f GHz)', signalName, fc/1e9));
    colorbar;
    grid on;
    ax.GridAlpha = 0.3;
    % }
    
    fprintf('  Spectrogram processing completed\n');
end

%% ========================================================================
%% FUNCTION DEPENDENCIES AND REQUIREMENTS
%% ========================================================================
%
% This function requires the following helper functions to be available:
%
% 1. helperZigBeeSDR(spc, numPackets, frameDuration, sr)
%    - Generates IEEE 802.15.4 compliant ZigBee waveforms
%    - Should implement OQPSK modulation
%    - Should handle multiple packet generation
%
% 2. helperSmartBANSDR(sr, frameDuration)
%    - Generates IEEE 802.15.6 compliant SmartBAN waveforms
%    - Should implement body area network specific protocols
%    - Should handle low-power transmission characteristics
%
% MATLAB Toolbox Requirements:
%   - Communications Toolbox (for SDR functions)
%   - Signal Processing Toolbox (for spectrogram)
%   - Image Processing Toolbox (for image manipulation)
%   - Communications Toolbox Support Package for ADALM-Pluto Radio
%
%% ========================================================================