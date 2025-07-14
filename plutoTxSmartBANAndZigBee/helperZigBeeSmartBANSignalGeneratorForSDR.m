function helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, waveforms, transmissionProbability)
% helperZigBeeSmartBANSignalGeneratorForSDR  Generate and transmit ZigBee or SmartBAN signals using PlutoSDR
%
%   helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, waveforms, transmissionProbability)
%
%   This function simulates sporadic wireless activity by randomly choosing 
%   whether to transmit a signal or remain idle, emulating low-duty-cycle 
%   IoT communications. When transmission is selected, it sends either a 
%   ZigBee or SmartBAN waveform via PlutoSDR.
%
%   If a signal is transmitted:
%       - A waveform is selected from the provided matrix.
%       - Its spectrogram is computed and optionally visualized.
%       - The waveform is normalized and transmitted using the PlutoSDR transmitter.
%
%   Inputs:
%       tx                    - PlutoSDR transmitter System object (`comm.SDRTxPluto`) or equivalent
%       frameDuration         - Duration (in seconds) of the transmitted frame (positive scalar)
%       sr                    - Sample rate in Hz (positive scalar)
%       imageSize             - Cell array specifying the desired spectrogram image size, e.g., {rows, cols}
%       waveforms             - Matrix containing time-domain waveforms in columns (each column: a waveform)
%       transmissionProbability - Probability [0,1] of transmitting during each function call
%
%   Notes:
%       - If no transmission occurs, the function displays 'Sleep mode!'.
%       - The `createSpectrogram` function is used internally to process and visualize the signal.

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

    close all;  % Close all figures to keep UI clean

    u = rand();  % Generate a random number between 0 and 1

    if u < transmissionProbability
        % Randomly select signal type: 1 for ZigBee, 2 for SmartBAN
        typeOfSignal = randi([1, 2]);
        typeOfSignal = 2;

        % Extract the waveform
        waveform = waveforms(:, typeOfSignal);

        % Generate and display spectrogram of the waveform
        createSpectrogram(waveform, sr, imageSize, centFreq, frameDuration);
        
        % Transmit normalized waveform via PlutoSDR
        tx(waveform);
    else
        fprintf('Sleep mode!\n');
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
    % figure;
    % imagesc(I);
    % axis on;
    % ax = gca;
    % 
    % %% X-axis (Frequency in GHz)
    % freq_vector = F + fc; % Map to absolute frequency
    % freq_vector_GHz = freq_vector / 1e9;
    % 
    % % Interpolate to image size
    % freq_interp = linspace(min(freq_vector_GHz), max(freq_vector_GHz), size(I,2));
    % 
    % nTicksX = 5;
    % tick_idx_X = round(linspace(1, size(I,2), nTicksX));
    % tick_labels_X = freq_interp(tick_idx_X);
    % 
    % ax.XTick = tick_idx_X;
    % ax.XTickLabel = sprintfc('%.3f', tick_labels_X);
    % xlabel('Frequency (GHz)');
    % 
    % %% Y-axis (Time in s)
    % nTimeBins = size(I,1);
    % time_vector = linspace(0, frameDuration, nTimeBins);
    % 
    % nTicksY = 5;
    % tick_idx_Y = round(linspace(1, nTimeBins, nTicksY));
    % tick_labels_Y = time_vector(tick_idx_Y);
    % 
    % ax.YTick = tick_idx_Y;
    % ax.YTickLabel = sprintfc('%.3f', tick_labels_Y);
    % ylabel('Time (s)');
    % 
    % title('Spectrogram');
end

