function creatingTrainingImages(numFrame, pixelValue, sr, imageSize, useGPU, wantInterf)
% CREATINGTRAININGIMAGES Generates and saves labeled spectrogram images for training.
%
%   creatingTrainingImages(numFrame, label, sr, imageSize, useGPU) generates
%   'numFrame' labeled spectrogram images for the given signal label (e.g., 'WLAN', 
%   'ZigBee', 'Bluetooth') using a given sampling rate 'sr' and desired image 
%   dimensions 'imageSize'. The images and their label masks are saved into 
%   subfolders under 'trainingImages'.
%
%   Inputs:
%       numFrame   - (integer) Number of images (frames) to generate.
%       label      - (string)  Label of the signal class to generate.
%       sr         - (double)  Sampling rate in Hz.
%       imageSize  - (cell)    Cell array with image size, e.g., {[1024, 1024]}.
%       useGPU     - (logical) True to use GPU acceleration, false for CPU only.
%       wantInterf - (logical) True if the spectrograms should contain
%                    interferent signals
%
%   Output:
%       None. The function saves image files to disk.
%
% =============================================
%  Signal Combination → Linear Label Mapping (5 levels)
% =============================================
%
%  Bitmask | Signal Combination                     | Label
%  --------+----------------------------------------+--------
%    0     | Unknown                                | 0
%    1     | WLAN                                   | 16
%    2     | Bluetooth                              | 32
%    3     | ZigBee                                 | 64
%    4     | SmartBAN                               | 128

    % Set default value for useGPU if not provided
    if nargin < 5
        useGPU = false;
    end
    
    % Check GPU availability if requested
    if useGPU
        try
            gpuDevice();
            fprintf('GPU processing enabled.\n');
        catch ME
            warning('GPU not available or compatible. Falling back to CPU processing.');
            useGPU = false;
        end
    else
        fprintf('CPU processing enabled.\n');
    end

    close all; 
    sr = 80e6;  % Override for test
    imageSize = {[256, 256]};  %Override for test
    pixelValues = containers.Map(...
        {'WLAN', 'ZigBee', 'Bluetooth', 'SmartBAN'}, ...
        [16, 32, 64, 128]);  % Override for test

    % Create output directories for each image size
    for index = 1:length(imageSize)
        imgSize = imageSize{index};
        % folderName = sprintf('%dx%d', imgSize(1), imgSize(2));
        folderName = ("forTesting");
        dirName = fullfile('trainingImages', folderName);
        if ~exist(dirName, 'dir')
            mkdir(dirName);
        end
    end
    
    numFrame = 400;  % Override for test/debug

    % Class mixture probabilities: more likely to have 1 signal
    weights = [0.2 0.25 0.3 0.25];  
    possibleCombinations = [1 2 3 4];
    for snr = 0:1:35
        fprintf("Current SNR = %d dB\n", snr);
        idxFrame = 0;
        while idxFrame < numFrame
            idxFrame = idxFrame + 1;
            waveforms = [];
            waveformsClean = [];
    
            % Reset available WLAN frequencies at the start of each frame
            resetWLANFrequencies();
    
            % Randomly select how many signals to mix (1, 2, 3 or 4)
            numSignals = randsample(possibleCombinations, 1, true, weights);
            labels = [];
                    
            % Generate synthetic signals
            for iter = 1:numSignals
                prob = rand(); % 1=ZigBee, 2=WLAN, 3=Bluetooth 4 = SmartBAN
                if prob < 0.25 
                    type_signal = 1;
                end
                if prob < 0.45 && prob >= 0.25
                    type_signal = 2;
                end
                if prob >= 0.45 && prob < 0.7
                    type_signal = 3;
                end
                if prob >= 0.7
                    type_signal = 4;
                end
                [noisyWaveform, wfClean, label] = generateWaveform(type_signal, useGPU);
                labels = cat(1, labels, label);
                waveformsClean = cat(2, waveformsClean, wfClean);
                waveforms = cat(2, waveforms, noisyWaveform);
            end

            % Move to GPU if requested
            if useGPU
                gpuWaveFormsClean = gpuArray(waveformsClean);
            else
                gpuWaveFormsClean = waveformsClean;
            end
    
            % Array of all the label matrices 
            data_tot = [];
            P_rx_arr = [];
            % Generate labeled spectrogram masks
            for i = 1:size(gpuWaveFormsClean, 2)
                label = labels(i, :);
                waveform = gpuWaveFormsClean(:, i);
                [P_matrix, ~, P_rx] = createSpectrogram(waveform, sr, imageSize, useGPU);
                P_rx_arr = cat(1, P_rx_arr, P_rx);
                labeledImage = labellingImage(P_matrix, label, pixelValues, imageSize{1}, useGPU);
                data_tot = cat(3, data_tot, labeledImage);
            end
            [gpuWaveFormsClean, noisePower, pMax] = adjustRxPower(gpuWaveFormsClean, snr, P_rx_arr, labels, useGPU);
            
            % Mix signals and create final spectrogram
            if useGPU
                waveFormsClean = gather(gpuWaveFormsClean);
                pMax = gather(pMax);
            else
                waveFormsClean = gpuWaveFormsClean;
            end
            
            if wantInterf
                mixedSignal = mySignalMixerInterf(waveFormsClean, 20e-3, noisePower, pMax);
            else
                mixedSignal = mySignalMixer(waveFormsClean, 20e-3, noisePower);
            end
            
            if useGPU
                gpuMixedSignal = gpuArray(mixedSignal);
            else
                gpuMixedSignal = mixedSignal;
            end
            
            [~, spectrogramTot] = createSpectrogram(gpuMixedSignal, sr, imageSize, useGPU);
            % Save the final spectrogram and mask
            overlapLabelledImages(data_tot, idxFrame, dirName, labels, spectrogramTot, pixelValues, snr, numFrame);
            fprintf("\n\n\n");
            close all
        end
    end
end


function [P, I, P_rx] = createSpectrogram(waveform, sr, imageSize, useGPU)
% CREATESPECTROGRAM Computes the spectrogram of a waveform and returns it as an image.
%
%   [P, I] = createSpectrogram(waveform, sr, imageSize, useGPU) returns both the numeric
%   spectrogram matrix and its RGB image form. The result is resized to match
%   the provided image dimensions.
%
%   Inputs:
%       waveform  - (vector) Time-domain signal waveform.
%       sr        - (double) Sampling rate in Hz.
%       imageSize - (cell)   Cell array specifying target image size.
%       useGPU    - (logical) True to use GPU acceleration, false for CPU only.
%
%   Outputs:
%       P - (matrix) Spectrogram matrix in dB scale.
%       I - (image)  RGB image representation of the spectrogram.

    % Set default value for useGPU if not provided
    if nargin < 4
        useGPU = false;
    end

    % Declare the fixed scale
    db_min = -130;
    db_max = -50;
    Nfft = 4096;
    window = hann(256);
    overlap = 100;
    colormap_resolution = 256;

    % Move data to appropriate processing unit
    if useGPU && ~isa(waveform, 'gpuArray')
        waveform = gpuArray(waveform);
    elseif ~useGPU && isa(waveform, 'gpuArray')
        waveform = gather(waveform);
    end

    P_rx = 10*log10(max(abs(waveform).^2));

    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'centered', 'psd');
    
    P = 10 * log10(abs(P') + eps);  % Conversione in dB
   
    % Clipping of outliers
    P_db_clipped = min(max(P, db_min), db_max);
    
    % Normalization with respect to the fixed scale
    P_norm = (P_db_clipped - db_min) / (db_max - db_min);
    
    % Ensure data is on CPU for image processing
    if isa(P_norm, 'gpuArray')
        P_norm = gather(P_norm);
    end
    
    % Mapping on a 256-value gray scale
    im = imresize(im2uint8(P_norm), imageSize{1}, "nearest");

    % Convert the image in RGB form
    I = im2uint8(flipud(ind2rgb(im, parula(colormap_resolution))));  % RGB flip

    % Ensure P is on the same processing unit as the input
    if useGPU && ~isa(P, 'gpuArray')
        P = gpuArray(P);
    elseif ~useGPU && isa(P, 'gpuArray')
        P = gather(P);
    end

    %for debug
    % figure;
    % imshow(I);  % for debug
    % colormap(parula(colormap_resolution));
    % colorbar('Ticks', linspace(0,1,8), ...
    %          'TickLabels', linspace(db_min, db_max, 8));  % scale colorbar to dB range
    % title('Power (dB)');
    % axis image off;

end


function data = labellingImage(P_dB, label, pixelValues, imageSize, useGPU)
% LABELLINGIMAGE Generates a binary mask for a given signal in the spectrogram.
%
%   data = labellingImage(P_dB, label, pixelValues, imageSize, useGPU) thresholds the
%   spectrogram to locate the signal and fills the bounding box. It then 
%   labels the region with the corresponding intensity value for the signal type.
%
%   Inputs:
%       P_dB        - (matrix) Spectrogram (dB scale).
%       label       - (string) Signal label ('ZigBee', 'WLAN', etc.).
%       pixelValues - (Map)    Mapping from label names to pixel values.
%       imageSize   - (vector) Size of the output mask image.
%       useGPU      - (logical) True to use GPU acceleration, false for CPU only.
%
%   Output:
%       data - (matrix) Binary mask with labeled regions.

    % Set default value for useGPU if not provided
    if nargin < 5
        useGPU = false;
    end

    % Ensure data is on CPU for image processing operations
    if isa(P_dB, 'gpuArray')
        P_dB_cpu = gather(P_dB);
    else
        P_dB_cpu = P_dB;
    end

    if strcmp(label, "SmartBAN")
        threshold = max(P_dB_cpu(:)) - 28;
    else
        threshold = max(P_dB_cpu(:)) - 15;
    end
    
    mask = P_dB_cpu >= threshold;
    mask = flipud(mask);  % Align with spectrogram
    cc = bwconncomp(mask);  % Find connected regions

    % Fill bounding boxes around each component
    for i = 1:cc.NumObjects
        [r, c] = ind2sub(size(mask), cc.PixelIdxList{i});
        rmin = min(r); rmax = max(r);
        cmin = min(c); cmax = max(c);
        mask(rmin:rmax, cmin:cmax) = true;
    end

    data = zeros(size(P_dB_cpu));
    pixelValue = pixelValues(label);
    data(mask) = pixelValue;
    
    data = imresize(data, imageSize, "nearest");

    % Move result back to GPU if requested and input was on GPU
    if useGPU && isa(P_dB, 'gpuArray')
        data = gpuArray(data);
    end

    %im = imresize(im2uint8(rescale(data)), imageSize, "nearest");

    %figure;
    %imshow(im);
    %title('Spectrogram Mask');
end

function overlapLabelledImages(data, idxFrame, dir, labels, spectrogram, label_map, snr, numFramesPerSnr)
% OVERLAPLABELLEDIMAGES Assigns unique label values based on priority, avoiding overlaps.
%
%   Each pixel is assigned a single class value. If there were overlapped signals, the 
%   labels follow this priority order:
%   BT > SmartBAN > ZigBee > WLAN > AWGN (0)
%
%   Inputs:
%       data        - (MxNxL) 3D binary mask (L = number of labels)
%       idxFrame    - (int)   Frame index
%       dir         - (char)  Output directory
%       labels      - (cell)  Cell array of label names, e.g., {'WLAN', ...}
%       spectrogram - (image) Spectrogram image to be saved
%       label_map   - (containers.Map) Mapping from label names (e.g., 'WLAN') to pixel values
%                                     e.g., label_map('WLAN') = 16
%
%   Output:
%       Saves 'data_final' (uint8) and the spectrogram image.

    % Ensure data is on CPU for processing
    if isa(data, 'gpuArray')
        data = gather(data);
    end

    % Define fixed label values and priorities
    priority_order = {"Bluetooth", "SmartBAN", "ZigBee", "WLAN"};  % from highest to lowest
    
    [M, N, ~] = size(data);
    data_final = zeros(M, N, 'uint8');  % Start with AWGN everywhere (value 0)

    for i = 1:length(priority_order)
        label = priority_order{i};
        idx = find(strcmp(labels, label));
        if ~isempty(idx)
            for ii = 1:numel(idx)
                mask = data(:,:,idx(ii));
                to_assign = (data_final == 0) & (mask ~= 0);  % assign only if not yet labeled
                data_final(to_assign) = label_map(label);
            end
            
        end
    end

    % Save label matrix and spectrogram
    label_combination = strjoin(labels', '+');
    filename = num2str(idxFrame + snr*numFramesPerSnr) + "_" + ...
                        label_combination + "_" + snr + "dB";
    fname = fullfile(dir, filename);
    
    save(char(fname + "_frame.mat"), 'data_final');
    imwrite(spectrogram, char(fname + "_spectrogram.png"));
end

function [noisyWf, wfFin, label] = generateWaveform(numOfSignal, useGPU)
% GENERATEWAVEFORM Creates synthetic waveforms for one of the three signal types.
%
%   [noisyWf, wfFin, label] = generateWaveform(numOfSignal, useGPU) generates a noisy
%   and clean version of a ZigBee, WLAN, or Bluetooth signal, with a randomly
%   selected center frequency and channel model.
%
%   Input:
%       numOfSignal - (integer) One of [1, 2, 3], representing:
%                      1 = ZigBee, 2 = WLAN, 3 = Bluetooth, 4 = SmartBAN
%       useGPU      - (logical) True to use GPU acceleration, false for CPU only.
%
%   Output:
%       noisyWf - (vector) Signal with noise added.
%       wfFin   - (vector) Clean signal (without noise).
%       label   - (string) Type of signal generated.

    % Set default value for useGPU if not provided
    if nargin < 2
        useGPU = false;
    end

    if ~isscalar(numOfSignal) || ~isnumeric(numOfSignal) || floor(numOfSignal) ~= numOfSignal
        error('Input must be an integer.');
    end
    if numOfSignal < 1 || numOfSignal > 4
        error('Input must be an integer between 1 and 4.');
    end

    switch uint8(numOfSignal)
        case 1  % ZigBee
            
            spc = 4;
            numPackets = randi(3);
            centerFreq = 2405e6 + 5e6 * (randi(16) - 11);
            channelType = randsample({'Rician', 'Rayleigh', 'AWGN'}, 1);
            txPowerArr = [-3, 0, 8]; %in dBm
            weights = [0.15 0.75 0.1];  
            txPower = randsample(txPowerArr, 1, true, weights);
            [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, channelType{1}, txPower, useGPU);
            label = "ZigBee";

        case 2  % WLAN
            try
                choosenCF = getStaticWLANFrequency();
                label = "WLAN";
            catch ME
                warning(ME.identifier,'%s', ME.message);
                label = "Unknown";
                return;
            end

            txPower = ((rand()- 1/2)*5) + 20.5; %in dBm [18; 23] dBm
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            [noisyWf, wfFin] = myWlanHelper(choosenCF, channelType{1}, txPower, useGPU);

        case 3  % Bluetooth
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            packetTypes = {'FHS', 'DM1', 'DM3', 'DM5', 'DH1', 'DH3', 'DH5', ...
               'HV1', 'HV2', 'HV3', 'DV', 'AUX1', ...
               'EV3', 'EV4', 'EV5', ...
               '2-DH1', '2-DH3', '2-DH5', '3-DH1', '3-DH3', '3-DH5', ...
               '2-EV3', '2-EV5', '3-EV3', '3-EV5'};
            
            txPowerArr = [0, 4, 20]; %in dBm
            weights = [0.03 0.94 0.03];  
            txPower = randsample(txPowerArr, 1, true, weights);
            packetType = packetTypes{randi(length(packetTypes))};
            [noisyWf, wfFin] = myBluetoothHelper(packetType, channelType{1}, txPower, useGPU);
            label = "Bluetooth";
        
        case 4  %SmartBAN
            label = "SmartBAN";
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            centerFrequency = randi([0, 39]) * 2e6;
            centerFrequency = centerFrequency + 2.402e9;
            txPowerArr = [0, 4, 20]; %in dBm
            weights = [0.03 0.94 0.03];  
            %weights = [0.2 0.4 0.2 0.2];  
            txPower = randsample(txPowerArr, 1, true, weights);  %in dBm
            [noisyWf, wfFin] = mySmartBanHelper(channelType{1}, centerFrequency, txPower, useGPU);
    end
    fprintf("Tx Power of %s: %f dBm\n", label, txPower);
    clearvars -except noisyWf wfFin label txPower
end


function choosenCF = getStaticWLANFrequency()
%GETSTATICWLANFREQUENCY Selects a static WLAN center frequency and removes it.
%
% This function returns one randomly selected WLAN center frequency
% from a persistent list of available IEEE 802.11 channels.
% Once a frequency is chosen, it is removed from the list to avoid reuse
% within the same frame.
%
% To reset the list between frames, call resetWLANFrequencies().

    persistent availableFreq

    % Initialize once
    if isempty(availableFreq)
        availableFreq = [2412e6, 2437e6, 2462e6];
    end

    % Check if empty
    if isempty(availableFreq)
        error('No more WLAN center frequencies available.');
    end

    % Sample one frequency randomly
    idx = randi(length(availableFreq));
    choosenCF = availableFreq(idx);

    % Remove it from the list
    availableFreq(idx) = [];
end

function resetWLANFrequencies()
%RESETWLANFREQUENCIES Resets the WLAN frequency list in getStaticWLANFrequency.
%
% This function clears the persistent variable used in getStaticWLANFrequency,
% so that the list of available WLAN center frequencies is restored.
% It should be called at the beginning of each new frame to allow
% frequency reuse across frames.

    clear getStaticWLANFrequency
end


function [waveforms_scaled, noise_power_lin, P_rx_max] = adjustRxPower(waveforms, snr_dB, P_rx_arr, labels, useGPU)
% ADJUSTRXPOWER  Rescale a bank of received waveforms so that their
% peak power meets a target SNR with respect to a fixed AWGN level.
%
% Inputs:
%   waveforms   – Matrix whose columns are signals to be scaled (complex)
%   snr_dB      – Desired SNR (dB) referenced to AWGN noise_power_dB
%   P_rx_arr    – Vector of received-power estimates (dB) for each column
%   labels      – Array of signal labels
%   useGPU      – (logical) True to use GPU acceleration, false for CPU only.
%
% Outputs:
%   waveforms_scaled – Waveforms after amplitude scaling
%   noise_power_lin  – Noise power in linear units (same units as signals)
%   P_rx_max         – Peak received power (dB)

    % Set default value for useGPU if not provided
    if nargin < 5
        useGPU = false;
    end

    % --- Fixed AWGN noise floor -------------------------------------------------
    noise_power_dB  = -30;                       % Noise power in dB (measured with Adalm-Pluto @ 60dB gain)
    noise_power_lin = 10^(noise_power_dB / 10);  % Convert dB → linear

    % --- Peak-power of the received signals -------------------------------------
    P_rx_max = max(P_rx_arr);                    % Highest power across signals (dB)

    % --- Target signal power to achieve the desired SNR -------------------------
    
    P_rx_dB = snr_dB + noise_power_dB;           % Target received power (dB)

    % --- Compute amplitude scaling factor ---------------------------------------
    % Scaling is done in amplitude: 20 log10(scale) = P_rx_target_dB – P_rx_max
    fprintf("P_rx_dB = %.2f  |  P_rx_max = %.2f\n", P_rx_dB, P_rx_max);
    scalingFactor = sqrt( 10^((P_rx_dB - P_rx_max) / 10) );
    fprintf("Scaling factor = %.4f (linear amplitude)\n", scalingFactor);

    
    % -- logical masks --------------------------------------------------------
    zigbeeMask = labels == "ZigBee";
    btMask     = labels == "Bluetooth" | labels == "SmartBAN";
    wlanMask   = labels == "WLAN";
    % -- scaling factors ------------------------------------------------------
    scaleMask               = ones(size(labels));
    if all(wlanMask == 0) && snr_dB >= 15
        scaleMask(zigbeeMask)   = 1/5;                  % Zigbee → ×1/5
        scaleMask(btMask)       = 1/10;                 % Bluetooth or SmartBAN → ×1/10
    end
    % -- apply scaling --------------------------------------------------------
    scalingFactorArr = scalingFactor * scaleMask;     % update in-place
    
    % Move scalingFactorArr to same processing unit as waveforms
    if useGPU && isa(waveforms, 'gpuArray') && ~isa(scalingFactorArr, 'gpuArray')
        scalingFactorArr = gpuArray(scalingFactorArr);
    elseif ~useGPU && isa(scalingFactorArr, 'gpuArray')
        scalingFactorArr = gather(scalingFactorArr);
    end
    
    % --- Apply the scaling factor to all waveforms ------------------------------
    waveforms_scaled = waveforms .* (scalingFactorArr');
end