
% Label encoding (grayscale values for image masks):
% 0   = AWGN
% 31.8750 = WLAN
% 63.7500 = ZigBee
% 95.6250 = WLAN + ZigBee
% 127.5000 = Bluetooth
% 159.3750 = WLAN + Bluetooth
% 191.2500 = Bluetooth + ZigBee
% 223.1250 = WLAN + ZigBee + Bluetooth
% 255.0000 = UNKNOWN (unlabeled)

function creatingTrainingImages(numFrame, label, sr, imageSize)
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

    close all
    numberOfLabels = 9;
    sr = 20e6;
    imageSize = {[1024, 1024]};
    linSpace = linspace(0, 255, numberOfLabels);
    pixelValues = containers.Map(...
        {'WLAN', 'ZigBee', 'Bluetooth'}, ...
        [linSpace(2), linSpace(3), linSpace(5)]);  % Assign pixel values per label

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
    numFrame = 1;  % Override for test/debug

    % Class mixture probabilities: more likely to have 1 signal
    weights = [0.6 0.3 0.1];    
    possibleCombinations = [1 2 3];

    while idxFrame < numFrame
        idxFrame = idxFrame + 1;
        waveforms = [];

        % Randomly select how many signals to mix (1, 2, or 3)
        numSignals = randsample(possibleCombinations, 1, true, weights);
        labels = [];

        % Generate synthetic signals
        for iter = 1:numSignals
            type_signal = randi(3);  % 1=ZigBee, 2=WLAN, 3=Bluetooth
            [noisyWaveform, ~, label] = generateWaveform(type_signal);
            labels = cat(1, labels, label);
            waveforms = cat(2, waveforms, noisyWaveform);
        end

        data_tot = [];

        % Generate labeled spectrogram masks
        for i = 1:size(waveforms, 2)
            label = labels(i, :);
            waveform = waveforms(:, i);
            [spectrogram, ~] = createSpectrogram(waveform, sr, imageSize);
            labeledImage = labellingImage(spectrogram, label, pixelValues, imageSize{1});
            data_tot = cat(3, data_tot, labeledImage);
        end

        % Mix signals and create final spectrogram
        mixedSignal = mySignalMixer(waveforms);
        mixedSignal = scalingPower(mixedSignal);
        [~, spectrogramTot] = createSpectrogram(mixedSignal, sr, imageSize);

        % Save the final spectrogram and mask
        overlapLabelledImages(data_tot, idxFrame, dirName, labels, spectrogramTot);
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

    min_dB = -100;
    max_dB = -30;
    Nfft = 4096;
    window = hann(256);
    overlap = 10;
    colormap_resolution = 256;

    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'centered', 'psd');

    P = 10 * log10(abs(P') + eps);  % dB conversion
    P_clipped = max(min(P, max_dB), min_dB);  % Clip dynamic range

    % Normalize to [1, 256] for color mapping
    P_idx = round(1 + (P_clipped - min_dB) / (max_dB - min_dB) * (colormap_resolution - 1));
    P_idx = max(min(P_idx, colormap_resolution), 1);

    im = imresize(im2uint8(rescale(P_idx)), imageSize{1}, "nearest");
    I = im2uint8(flipud(ind2rgb(im, parula(colormap_resolution))));  % RGB flip

    imshow(I);  % For debug
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

    threshold = max(P_dB(:)) - 13;
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

    im = imresize(im2uint8(rescale(data)), imageSize, "nearest");

    figure;
    imshow(im);
    title('Spectrogram Mask');
end


function overlapLabelledImages(data, idxFrame, dir, labels, spectrogram)
% OVERLAPLABELLEDIMAGES Merges multiple labeled masks and saves the result.
%
%   overlapLabelledImages(data, idxFrame, dir, labels, spectrogram) sums
%   multiple label masks and stores the output as both .mat and .png files.
%
%   Inputs:
%       data       - (3D matrix) Stack of individual binary label masks.
%       idxFrame   - (integer)   Index of the current image frame.
%       dir        - (string)    Path to the output directory.
%       labels     - (cell)      Cell array of string labels used.
%       spectrogram - (image)    Final spectrogram image to be saved.
%
%   Outputs:
%       None. Files are saved on disk.

    data_final = sum(data, 3);
    data_final = uint8(data_final);

    label = strjoin(labels', '+');
    filename = label + '_frame_' + num2str(idxFrame);
    fname = fullfile(dir, filename);
    save(char(fname + ".mat"), 'data_final');

    imwrite(spectrogram, char(fname + "_spectogram.png"));
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
    if numOfSignal < 1 || numOfSignal > 3
        error('Input must be an integer between 1 and 3.');
    end

    switch numOfSignal
        case 1  % ZigBee
            spc = 4;
            numPackets = randi(3);
            centerFreq = 2405e6 + 5e6 * (randi(16) - 11);
            channelType = randsample({'Rician', 'Rayleigh', 'AWGN'}, 1);
            [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, channelType);
            label = "ZigBee";

        case 2  % WLAN
            centerFreq = [2412e6, 2437e6, 2462e6];
            choosenCF = randsample(centerFreq, 1);
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            [noisyWf, wfFin] = myWlanHelper(choosenCF, channelType);
            label = "WLAN";

        case 3  % Bluetooth
            channelType = randsample({'Rician', 'Rayleigh'}, 1);
            packetType = 'FHS';
            [noisyWf, wfFin] = myBluetoothHelper(packetType, channelType);
            label = "Bluetooth";
    end

    clearvars -except noisyWf wfFin label
end
