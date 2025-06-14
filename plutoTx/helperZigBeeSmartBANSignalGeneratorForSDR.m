function helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, carrierFrequency)
% helperZigBeeSmartBANSignalGeneratorForSDR   Generate and transmit ZigBee or SmartBAN signals using PlutoSDR
%
%   This function randomly decides whether to transmit a signal or remain idle.
%   If transmission occurs, it generates either a ZigBee or SmartBAN waveform,
%   plots its spectrogram, normalizes it, and sends it to the PlutoSDR transmitter.
%
%   Inputs:
%       tx               - PlutoSDR transmitter System object
%       frameDuration    - Duration of the generated frame in seconds (positive scalar)
%       sr               - Sampling rate in Hz (positive scalar)
%       imageSize        - Cell array specifying spectrogram image size {rows, cols}
%       carrierFrequency - Carrier frequency in Hz (positive scalar)

    % --- Input validation ---
    if ~isa(tx, 'matlab.system.System') && ~isa(tx, 'comm.SDRTxPluto')
        error('tx must be a PlutoSDR transmitter System object or a function handle.');
    end
    if ~isscalar(frameDuration) || ~isnumeric(frameDuration) || frameDuration <= 0
        error('frameDuration must be a positive numeric scalar.');
    end
    if ~isscalar(sr) || ~isnumeric(sr) || sr <= 0
        error('sr (sample rate) must be a positive numeric scalar.');
    end
    if ~iscell(imageSize) || numel(imageSize) ~= 1 && numel(imageSize) ~= 2
        error('imageSize must be a cell array with 1 or 2 elements.');
    end
    if ~isnumeric(carrierFrequency) || any(carrierFrequency <= 0)
    error('carrierFrequency must be a numeric vector with all positive values.');
    end


    close all;  % Close all figures to keep UI clean

    transmissionProbability = 1;  % Probability to transmit a signal
    u = rand();  % Generate a random number between 0 and 1
    
    if u < transmissionProbability
        % Randomly select signal type: 1 for ZigBee, 2 for SmartBAN
        typeOfSignal = randi([1, 2]);

        centFreq = carrierFrequency(typeOfSignal);
        % Generate waveform for selected signal type
        wfClean = generateWaveform(typeOfSignal, frameDuration, sr);

        % Generate and display spectrogram of the waveform
        createSpectrogram(wfClean, sr, imageSize, centFreq, frameDuration);

        % Normalize waveform amplitude to avoid saturation on PlutoSDR
        wfCleanNorm = wfClean / max(abs(wfClean));
        
        % Transmit normalized waveform via PlutoSDR
        tx.CenterFrequency = centFreq;
        tx(wfCleanNorm);
    else
        fprintf('Sleep mode!\n');
    end
end





function wfFin = generateWaveform(numOfSignal, frameDuration, sr)
% generateWaveform   Generate synthetic ZigBee or SmartBAN waveform
%
%   wfFin = generateWaveform(numOfSignal, frameDuration, sr)
%
%   Inputs:
%       numOfSignal   - Signal type: 1 = ZigBee, 2 = SmartBAN
%       frameDuration - Duration of generated frame (s)
%       sr            - Sampling rate (Hz)
%
%   Output:
%       wfFin         - Generated waveform

    % Input validation
    if ~isscalar(numOfSignal) || ~isnumeric(numOfSignal) || floor(numOfSignal) ~= numOfSignal
        error('Input numOfSignal must be an integer scalar.');
    end
    if numOfSignal < 1 || numOfSignal > 2
        error('numOfSignal must be either 1 (ZigBee) or 2 (SmartBAN).');
    end

    % Generate waveform according to type
    switch numOfSignal
        case 1  % ZigBee
            spc = 4; % Samples per chip
            numPackets = randi(3); % Random number of ZigBee packets
            wfFin = helperZigBeeSDR(spc, numPackets, frameDuration, sr);

        case 2  % SmartBAN
            wfFin = helperSmartBANSDR(sr, frameDuration);
    end
end



function createSpectrogram(waveform, sr, imageSize, fc, frameDuration)
% createSpectrogram   Compute and plot spectrogram with physical axes
%
%   [P, I] = createSpectrogram(waveform, sr, imageSize, fc, frameDuration)
%
%   Inputs:
%       waveform      - Input time-domain signal
%       sr            - Sampling rate (Hz)
%       imageSize     - Cell array {rows, columns} for output image size
%       fc            - Center frequency (Hz)
%       frameDuration - Total frame duration (s)
%
%   Outputs:
%       None

    % Spectrogram parameters
    db_min = -130;
    db_max = -50;
    Nfft = 4096;
    window = hann(256);
    overlap = 10;
    colormap_resolution = 256;

    % Compute spectrogram
    [~, F, ~, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'centered', 'psd');
    P = 10 * log10(abs(P') + eps); % Convert to dB

    % Clip outliers
    P_clipped = min(max(P, db_min), db_max);

    % Normalize to [0,1]
    P_norm = (P_clipped - db_min) / (db_max - db_min);

    % Map to grayscale and resize
    im = imresize(im2uint8(P_norm), imageSize{1}, "nearest");

    % Convert to RGB
    I = im2uint8(flipud(ind2rgb(im, parula(colormap_resolution)))); 

    % Plot spectrogram with physical axes
    figure;
    imagesc(I);
    axis on;
    ax = gca;

    %% X-axis (Frequency in GHz)
    freq_vector = F + fc; % Map to absolute frequency
    freq_vector_GHz = freq_vector / 1e9;

    % Interpolate to image size
    freq_interp = linspace(min(freq_vector_GHz), max(freq_vector_GHz), size(I,2));

    nTicksX = 5;
    tick_idx_X = round(linspace(1, size(I,2), nTicksX));
    tick_labels_X = freq_interp(tick_idx_X);

    ax.XTick = tick_idx_X;
    ax.XTickLabel = sprintfc('%.3f', tick_labels_X);
    xlabel('Frequency (GHz)');

    %% Y-axis (Time in s)
    nTimeBins = size(I,1);
    time_vector = linspace(0, frameDuration, nTimeBins);

    nTicksY = 5;
    tick_idx_Y = round(linspace(1, nTimeBins, nTicksY));
    tick_labels_Y = time_vector(tick_idx_Y);

    ax.YTick = tick_idx_Y;
    ax.YTickLabel = sprintfc('%.3f', tick_labels_Y);
    ylabel('Time (s)');

    title('Spectrogram');
end

