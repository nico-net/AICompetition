% =============================================
%  Signal Combination → Linear Label Mapping (6 levels)
% =============================================
%
%  Bitmask | Signal Combination                     | Label
%  --------+----------------------------------------+--------
%    0     | AWGN                                   | 0
%    1     | WLAN                                   | 16
%    2     | Bluetooth                              | 32
%    3     | ZigBee                                 | 64
%    4     | SmartBAN                               | 128
%    5     | Unkwnown                               | 255

function creatingTrainingImages(numFrame, pixelValue, sr, imageSize)
% CREATINGTRAININGIMAGES Generates and saves labeled spectrogram images for training.
%
%   creatingTrainingImages(numFrame, label, sr, imageSize) generates
%   'numFrame' labeled spectrogram images for the given signal label (e.g., 'WLAN', 
%   'ZigBee', 'Bluetooth') using a given sampling rate 'sr' and desired image 
%   dimensions 'imageSize'. The images and their label masks are saved into 
%   subfolders under 'trainingImages'.
%
%   Inputs:
%       numFrame  - (integer) Number of images (frames) to generate.
%       label     - (string)  Label of the signal class to generate.
%       sr        - (double)  Sampling rate in Hz.
%       imageSize - (cell)    Cell array with image size, e.g., {[1024, 1024]}.
%
%   Output:
%       None. The function saves image files to disk.

    close all; 
    sr = 20e6;  % Override for test
    imageSize = {[128, 128]};  %Override for test
    pixelValues = containers.Map(...
        {'WLAN', 'ZigBee', 'Bluetooth', 'SmartBAN'}, ...
        [16, 32, 64, 128]);  % Override for test

    % Create output directories for each image size
    for index = 1:length(imageSize)
        imgSize = imageSize{index};
        folderName = sprintf('%dx%d', imgSize(1), imgSize(2));
        dirName = fullfile('trainingImages', folderName);
        if ~exist(dirName, 'dir')
            mkdir(dirName);
        end
    end
    
    idxFrame = 0;
    numFrame = 2;  % Override for test/debug

    % Class mixture probabilities: more likely to have 1 signal
    weights = [0.3 0.3 0.2 0.2];  
    possibleCombinations = [1 2 3 4];

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
            type_signal = randi(4);  % 1=ZigBee, 2=WLAN, 3=Bluetooth 4 = SmartBAN
            [noisyWaveform, wfClean, label] = generateWaveform(type_signal);
            labels = cat(1, labels, label);
            waveformsClean = cat(2, waveformsClean, wfClean);
            waveforms = cat(2, waveforms, noisyWaveform);
        end

        % Array of all the label matrices 
        data_tot = [];

        % Generate labeled spectrogram masks
        for i = 1:size(waveformsClean, 2)
            label = labels(i, :);
            waveform = waveformsClean(:, i);
            [spectrogram, ~] = createSpectrogram(waveform, sr, imageSize);
            labeledImage = labellingImage(spectrogram, label, pixelValues, imageSize{1});
            data_tot = cat(3, data_tot, labeledImage);
        end
        
        
        % Mix signals and create final spectrogram
        mixedSignal = mySignalMixer(waveforms);
        mixedSignal = scalingPower(mixedSignal);
        [~, spectrogramTot] = createSpectrogram(mixedSignal, sr, imageSize);

        % Save the final spectrogram and mask
        overlapLabelledImages(data_tot, idxFrame, dirName, labels, spectrogramTot, pixelValues);

        pause();
    end
end



function [P, I] = createSpectrogram(waveform, sr, imageSize)
% CREATESPECTROGRAM Computes the spectrogram of a waveform and returns it as an image.
%
%   [P, I] = createSpectrogram(waveform, sr, imageSize) returns both the numeric
%   spectrogram matrix and its RGB image form. The result is resized to match
%   the provided image dimensions.
%
%   Inputs:
%       waveform  - (vector) Time-domain signal waveform.
%       sr        - (double) Sampling rate in Hz.
%       imageSize - (cell)   Cell array specifying target image size.
%
%   Outputs:
%       P - (matrix) Spectrogram matrix in dB scale.
%       I - (image)  RGB image representation of the spectrogram.

    % Declare the fixed scale
    db_min = -130;
    db_max = -50;
    Nfft = 4096;
    window = hann(256);
    overlap = 10;
    colormap_resolution = 256;

    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'centered', 'psd');

    P = 10 * log10(abs(P') + eps);  % Conversione in dB
    
   
    % Clipping of outliers
    P_db_clipped = min(max(P, db_min), db_max);
    
    % Normalization with respect to the fixed scale
    P_norm = (P_db_clipped - db_min) / (db_max - db_min);
    
    % Mapping on a 256-value gray scale
    im = imresize(im2uint8(P_norm), imageSize{1}, "nearest");
    
    % Convert the image in RGB form
    I = im2uint8(flipud(ind2rgb(im, parula(colormap_resolution))));  % RGB flip
    
    imshow(I);  % Per debug

end


function data = labellingImage(P_dB, label, pixelValues, imageSize)
% LABELLINGIMAGE Generates a binary mask for a given signal in the spectrogram.
%
%   data = labellingImage(P_dB, label, pixelValues, imageSize) thresholds the
%   spectrogram to locate the signal and fills the bounding box. It then 
%   labels the region with the corresponding intensity value for the signal type.
%
%   Inputs:
%       P_dB        - (matrix) Spectrogram (dB scale).
%       label       - (string) Signal label ('ZigBee', 'WLAN', etc.).
%       pixelValues - (Map)    Mapping from label names to pixel values.
%       imageSize   - (vector) Size of the output mask image.
%
%   Output:
%       data - (matrix) Binary mask with labeled regions.

    if strcmp(label, "SmartBAN")
        threshold = max(P_dB(:)) - 28;
    else
        threshold = max(P_dB(:)) - 15;
    end
    mask = P_dB >= threshold;
    mask = flipud(mask);  % Align with spectrogram
    cc = bwconncomp(mask);  % Find connected regions

    % Fill bounding boxes around each component
    for i = 1:cc.NumObjects
        [r, c] = ind2sub(size(mask), cc.PixelIdxList{i});
        rmin = min(r); rmax = max(r);
        cmin = min(c); cmax = max(c);
        mask(rmin:rmax, cmin:cmax) = true;
    end

    data = zeros(size(P_dB));
    pixelValue = pixelValues(label);
    data(mask) = pixelValue;
    
    data = imresize(data, imageSize, "nearest");

    im = imresize(im2uint8(rescale(data)), imageSize, "nearest");

    %figure;
    %imshow(im);
    %title('Spectrogram Mask');
end

function overlapLabelledImages(data, idxFrame, dir, labels, spectrogram, label_map)
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
    filename = num2str(idxFrame) + "_" + label_combination;
    fname = fullfile(dir, filename);
    
    save(char(fname + "_frame.mat"), 'data_final');
    imwrite(spectrogram, char(fname + "_spectrogram.png"));
end

function [noisyWf, wfFin, label] = generateWaveform(numOfSignal)
% GENERATEWAVEFORM Creates synthetic waveforms for one of the three signal types.
%
%   [noisyWf, wfFin, label] = generateWaveform(numOfSignal) generates a noisy
%   and clean version of a ZigBee, WLAN, or Bluetooth signal, with a randomly
%   selected center frequency and channel model.
%
%   Input:
%       numOfSignal - (integer) One of [1, 2, 3], representing:
%                      1 = ZigBee, 2 = WLAN, 3 = Bluetooth
%
%   Output:
%       noisyWf - (vector) Signal with noise added.
%       wfFin   - (vector) Clean signal (without noise).
%       label   - (string) Type of signal generated.

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
            [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, channelType{1});
            label = "ZigBee";

        case 2  % WLAN
            try
                choosenCF = getStaticWLANFrequency();
                label = "WLAN";
            catch ME
                warning(ME.identifier,'%s', ME.message);
                label = "Unkown";
                return;
            end
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            [noisyWf, wfFin] = myWlanHelper(choosenCF, channelType{1});

        case 3  % Bluetooth
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            packetTypes = {'FHS', 'DM1', 'DM3', 'DM5', 'DH1', 'DH3', 'DH5', ...
               'HV1', 'HV2', 'HV3', 'DV', 'AUX1', ...
               'EV3', 'EV4', 'EV5', ...
               '2-DH1', '2-DH3', '2-DH5', '3-DH1', '3-DH3', '3-DH5', ...
               '2-EV3', '2-EV5', '3-EV3', '3-EV5'};

            packetType = packetTypes{randi(length(packetTypes))};
            [noisyWf, wfFin] = myBluetoothHelper(packetType, channelType{1});
            label = "Bluetooth";
        
        case 4  %SmartBAN
            label = "SmartBAN";
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            centerFrequency = randi([0, 39]) * 2e6;
            centerFrequency = centerFrequency + 2.402e9;
            [noisyWf, wfFin] = mySmartBanHelper(channelType{1}, centerFrequency);
    end

    clearvars -except noisyWf wfFin label
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
