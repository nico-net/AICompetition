function helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, carrierFrequency)
% helperZigBeeSmartBANSignalGeneratorForSDR   SDR signal generator for ZigBee and SmartBAN
%
%   This function randomly decides whether to transmit a signal or stay idle.
%   If transmission occurs, it generates either a ZigBee or SmartBAN signal,
%   creates its spectrogram, and transmits it via the provided PlutoSDR transmitter.
%
%   Inputs:
%       tx             - PlutoSDR transmitter object
%       frameDuration  - Total duration of the generated frame (s)
%       sr             - Sampling rate (Hz)
%       imageSize      - Cell array {rows, columns} defining image dimensions
%       carrierFrequency - Carrier frequency used (Hz)

    close all;

    % Transmission probability
    transmissionProbability = 0.2; 
    u = rand(); % Generate random number between 0 and 1

    if u < transmissionProbability
        % Randomly select type of signal: 1=ZigBee, 2=SmartBAN
        typeOfSignal = randi([1,2]); 
        
        % Generate waveform
        wfClean = generateWaveform(typeOfSignal, frameDuration, sr);
        
        % Generate and plot spectrogram
        createSpectrogram(wfClean, sr, imageSize, carrierFrequency, frameDuration);
        
        % Normalize for PlutoSDR transmission
        wfCleanNorm = wfClean / max(abs(wfClean));
        
        % Transmit over PlutoSDR
        tx(wfCleanNorm);
    else
        fprintf("Sleep mode!\n");
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
            wfFin = helperZigBeePluto(spc, numPackets, frameDuration, sr);

        case 2  % SmartBAN
            wfFin = helperSmartBANpluto(sr, frameDuration);
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

