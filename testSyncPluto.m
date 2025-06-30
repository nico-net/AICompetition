
% This MATLAB script performs parallel IQ data acquisition from two PlutoSDR devices operating at 
% different center frequencies. It uses the Parallel Computing Toolbox to acquire 
% synchronized samples via parfeval, processes the received signals with
% frequency shifts and AWGN, combines them into a single waveform, and
% visualizes the resulting spectrogram. The script supports multiple acquisition 
% frames and performs resource cleanup at the end.


clearvars -except net; close all;  % Clear workspace and close all figures
addpath '/home/nicola-gallucci/Nicola/Matlab/AICHallenge/AICompetition/visualizationHelpers'
% === PlutoSDR Receiver Configuration ===
% Configure the first PlutoSDR (connected at usb:0)
rx1 = sdrrx("Pluto", "RadioID", 'usb:0', ...
    'CenterFrequency', 2.42e9, ...               % Center frequency: 2.42 GHz
    'GainSource', 'Manual', 'Gain', 60, ...      % Manual gain: 40 dB
    'EnableBurstMode', true, ...                 % Enable burst mode for single-frame capture
    'BasebandSampleRate', 40e6, ...              % Baseband sampling rate: 40 MSPS
    'OutputDataType', 'double', ...
    'SamplesPerFrame', 8e5);                     % Capture 800,000 samples per frame (~0.1 s)

% Configure the second PlutoSDR (connected at usb:1)
rx2 = sdrrx("Pluto", "RadioID", 'usb:1', ...
    'CenterFrequency', 2.46e9, ...
    'GainSource', 'Manual', 'Gain', 60, ...
    'EnableBurstMode', true, ...
    'BasebandSampleRate', 40e6, ...
    'OutputDataType', 'double', ...
    'SamplesPerFrame', 8e5);

% === Start Parallel Pool (2 Workers Required) ===
% Start a parallel pool if one is not already active
if isempty(gcp('nocreate'))
    parpool(2);  % Two parallel workers (one per SDR)
end

% Define start time with slight delay to allow both SDRs to sync
startTime = datetime('now') + seconds(2);

% === Acquisition Parameters ===
sampleRate = 40e6;      % Sample rate (Hz)
numSamples = 8e5;       % Number of samples per acquisition frame
gain = 40;              % Manual gain setting

idxFrame = 1;           % Frame index
numFrames = 15;          % Total number of acquisition iterations
colormap_resolution = 256;
imageSize = [256,256];
% === Main Acquisition Loop ===
while idxFrame < numFrames
    close all;
    % Launch asynchronous acquisition on both PlutoSDRs
    f1 = parfeval(@acquirePluto, 1, rx1, startTime);
    f2 = parfeval(@acquirePluto, 1, rx2, startTime);
    
    % Wait for both acquisitions to finish and fetch their outputs
    [rx1Idx, rx1Data] = fetchNext([f1, f2]);
    [~, rx2Data] = fetchNext([f1, f2]);
    
    % Determine which future returned first and assign data correctly
    if rx1Idx == 1
        data1 = rx1Data;
        data2 = rx2Data;
    else
        data1 = rx2Data;
        data2 = rx1Data;
    end
    
    fprintf('Acquisition complete.\n');  % Notify user

    % === Signal Processing Section ===

    % Resample both signals to double the sample rate (for frequency shifting)
    dataResample1 = resample(data1, 2, 1);
    dataResample2 = resample(data2, 2, 1);
    
    % Apply frequency offset of -20 MHz to the first signal
    foff1 = comm.PhaseFrequencyOffset( ...
        'FrequencyOffset', -20e6, ...
        'SampleRate', sampleRate * 2 ...
    );
    dataLow = awgn(foff1(dataResample1), 50);  % Add AWGN (SNR = 50 dB)
    
    % Apply frequency offset of +20 MHz to the second signal
    foff2 = comm.PhaseFrequencyOffset( ...
        'FrequencyOffset', 20e6, ...
        'SampleRate', sampleRate * 2 ...
    );
    dataHigh = awgn(foff2(dataResample2), 50);
    
    % Combine the two frequency-shifted signals into one
    waveform = dataLow + dataHigh;

    % === Spectrogram Visualization ===
    db_min = -130;
    db_max = -50;
    Nfft = 4096;                    % FFT size
    window = hann(256);            % Window for spectrogram
    overlap = 10;                  % Overlap between windows
    colormap_resolution = 256;

    figure;
    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, 80e6, 'centered', 'psd');

    P = 10 * log10(abs(P') + eps);  % Conversione in dB
    
   
    % Clipping of outliers
    P_db_clipped = min(max(P, db_min), db_max);
    
    % Normalization with respect to the fixed scale
    P_norm = (P_db_clipped - db_min) / (db_max - db_min);
    
    % Mapping on a 256-value gray scale
    im = imresize(im2uint8(P_norm), imageSize, "nearest");
    
    % Convert the image in RGB form
    I = im2uint8(flipud(ind2rgb(im, parula(colormap_resolution))));  % RGB flip
    
    imshow(I);  % Per debug
    colormap(parula(colormap_resolution));  % Imposta la colormap per la colorbar
    clim([db_min db_max]);                 % Definisce range dB per colorbar
    c = colorbar;
    c.Label.String = 'Potenza [dB]';

    %fig = figure('Visible', 'off');  % Invisible figure for automation
    % Capture the image content as an RGB array
    % frame = getframe(gca);  % Capture current axis
    % I = frame.cdata;        % Extract RGB image data as uint8 matrix
    % close(fig);  % Optional: close figure
    % figure;
    %imshow(I);
    %I = imresize(I, imageSize);
    dlImg = dlarray(double(I), 'SSC'); % 'SSC' = Spatial, Spatial, Channel
    prediction = predict(net, double(I));
    [~, predictedLabel] = max(prediction, [], 3);

    plotOverLayed(I, predictedLabel, 1);
    
    pause();  % Wait for user to continue before next acquisition
    idxFrame = idxFrame + 1;  % Increment frame counter
end

% === Cleanup Section ===
disp("Cleanup in progress...");
delete(gcp('nocreate'));  % Shut down parallel pool
release(rx1);             % Release PlutoSDR resources
release(rx2);



% === Parallel Acquisition Function ===
% This function is executed in parallel by each worker
function data = acquirePluto(rx, startTime)
    % Wait until the specified start time (for synchronization)
    while datetime('now') < startTime
        pause(0.00001);  % Tiny delay to avoid CPU overload
    end
    data = rx();  % Capture a single burst of data
end
