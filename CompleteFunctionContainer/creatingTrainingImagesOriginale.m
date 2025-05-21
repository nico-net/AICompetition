% Number of labels = 9
% AWGN = 0   
% WLAN = 31.8750   
% ZIGBEE = 63.7500  
% WLAN + ZIGBEE = 95.6250 
% BLUETOOTH = 127.5000 
% WLAN + BLUETOOTH = 159.3750 
% BLUETOOTH + ZIGBEE = 191.2500 
% BLUETOOTH + ZIGBEE + WLAN = 223.1250 
% UNKNOWN = 255.0000  (Not labelled)

function creatingTrainingImages(numFrame, label, sr, imageSize)
% CREATINGTRAININGIMAGES Generates and saves labeled spectrogram images for training.
%
%   CREATINGTRAININGIMAGES(numFrame, label, sr, imageSize) generates
%   'numFrame' number of spectrogram images for the specified 'label'
%   (e.g., 'WLAN', 'ZigBee', 'Bluetooth') using the sampling rate 'sr' and
%   image dimensions specified in 'imageSize'. The images are saved in the
%   'trainingImages' directory.
%
%   Inputs:
%       numFrame  - (integer) Number of frames/images to generate.
%       label     - (string)  Label of the signal type.
%       sr        - (double)  Sampling rate in Hz.
%       imageSize - (cell)    Cell array specifying image dimensions, e.g., {[1024, 1024]}.
%
%   Outputs:
%       None. The function saves the generated images to disk.

    numberOfLabels = 9;
    sr = 20e6;
    imageSize = {[1024, 1024]};
    linSpace = linspace(0, 255, numberOfLabels);
    pixelValues = containers.Map(...
        {'WLAN', 'ZigBee', 'Bluetooth'}, ...
        [linSpace(2), linSpace(3), linSpace(5)]);
    
    % Create output directories based on image sizes
    for index = 1:length(imageSize)
        imgSize = imageSize{index};
        folderName = sprintf('%dx%d', imgSize(1), imgSize(2));
        dirName = fullfile('trainingImages', folderName);
        if ~exist(dirName, 'dir')
            mkdir(dirName);
        end
    end
    
    idxFrame = 0;
    numFrame = 1;

    pesi = [0.6 0.3 0.1];    
    valori = [1 2 3];

    while idxFrame < numFrame
        idxFrame = idxFrame + 1;
        waveforms = [];

        % Generate a random number of signals to superimpose (here fixed to 1)
        
        numSignals = randsample(valori, 1, true, pesi);
     
        labels = [];
        for iter = 1:numSignals
            type_signal = randi(3);
            [noisyWaveform, ~, label] = generateWaveform(type_signal);
            labels = cat(1,labels, label)
            waveforms = [waveforms noisyWaveform];
        end

        % Generate labeled spectrograms
        data_tot = [];

        for i = 1:size(waveforms, 2)
            label = labels(i, :);
            waveform = waveforms(:, i);
            [spectrogram,~]= createSpectrogram(waveform, sr, imageSize);
            data_waveform_singular = labellingImage(spectrogram, label, pixelValues, imageSize{1});
            data_tot = cat(3, data_tot, data_waveform_singular);
        end
        mixedSignal = mySignalMixer(waveforms);
        [~, spectrogramTot] = createSpectrogram(mixedSignal, sr, imageSize);
        overlapLabelledImages(data_tot, idxFrame, dirName, labels, spectrogramTot);
        pause(5);
        close all
    end
end


function [P, I] = createSpectrogram(waveform, sr, imageSize)
% CREATESPECTROGRAM Generates a spectrogram from a waveform.
%
%   P = CREATESPECTROGRAM(waveform, sr, imageSize) computes the spectrogram
%   of the input 'waveform' using the sampling rate 'sr' and resizes it to
%   'imageSize'.
%
%   Inputs:
%       waveform  - (vector) Time-domain signal.
%       sr        - (double) Sampling rate in Hz.
%       imageSize - (cell)   Cell array specifying image dimensions, e.g., {[1024, 1024]}.
%
%   Outputs:
%       P - (matrix) Spectrogram in dB scale.

    Nfft = 4096;
    window = hann(256);
    overlap = 10;

    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'centered', 'psd');

    P = 10 * log10(abs(P') + eps);

    im = imresize(im2uint8(rescale(P)), imageSize{1}, "nearest");
    I = im2uint8(flipud(ind2rgb(im, parula(256))));

    imshow(I);
end


function data = labellingImage(P_dB, label, pixelValues, imageSize)
% LABELLINGIMAGE Labels regions in a spectrogram corresponding to a signal.
%
%   data = LABELLINGIMAGE(P_dB, label, pixelValues, imageSize) identifies
%   regions in the spectrogram 'P_dB' that correspond to the specified
%   'label' and assigns pixel values based on 'pixelValues'. The result is
%   resized to 'imageSize'.
%
%   Inputs:
%       P_dB        - (matrix) Spectrogram in dB scale.
%       label       - (string) Label of the signal type.
%       pixelValues - (Map)    Mapping of labels to pixel intensity values.
%       imageSize   - (vector) Desired image size, e.g., [1024, 1024].
%
%   Outputs:
%       data - (matrix) Labeled image matrix.

    % Thresholding and bounding-box filling
    threshold = max(P_dB(:)) - 13;
    mask = P_dB >= threshold;
    mask = flipud(mask);
    cc = bwconncomp(mask);

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
    title('Spectogram Mask');
end


function overlapLabelledImages(data, idxFrame, dir, labels, spectogram)
% OVERLAPLABELLEDIMAGES Combines labeled images and saves the result.
%
%   OVERLAPLABELLEDIMAGES(data, idxFrame, dir, label) sums the labeled
%   images in 'data' to create a composite image and saves it in the
%   specified directory 'dir' with a filename based on 'label' and
%   'idxFrame'.
%
%   Inputs:
%       data     - (3D matrix) Stack of labeled images.
%       idxFrame - (integer)   Frame index number.
%       dir      - (string)    Directory path to save the image.
%       label    - (string)    Label of the signal type.
%
%   Outputs:
%       None. The function saves the composite image to disk.

    data_final = sum(data, 3);
    data_final = uint8(data_final);

    label = strjoin(labels', '+');
    filename =label + '_frame_' + num2str(idxFrame);
    fname = fullfile(dir, filename);
    fnameLabels = fname + ".mat";

    save(char(fnameLabels), 'data_final');

    filename_spect = filename + "_spectogram.png";
    fname = fullfile(dir, filename_spect);
    imwrite(spectogram, fname);

end


function [noisyWf, wfFin, label] = generateWaveform(numOfSignal)
% GENERATEWAVEFORM Generates a synthetic waveform for a specified signal type.
%
%   [noisyWf, wfFin, label] = GENERATEWAVEFORM(numOfSignal) generates a
%   waveform corresponding to the signal type specified by 'numOfSignal':
%       1 - ZigBee
%       2 - WLAN
%       3 - Bluetooth
%
%   Inputs:
%       numOfSignal - (integer) Signal type identifier (1 to 3).
%
%   Outputs:
%       noisyWf - (vector) Generated waveform with noise.
%       wfFin   - (vector) Clean (noise-free) waveform.
%       label   - (string) Label of the signal type.

    if ~isscalar(numOfSignal) || ~isnumeric(numOfSignal) || floor(numOfSignal) ~= numOfSignal
        error('Input must be an integer.');
    end
    if numOfSignal < 1 || numOfSignal > 3
        error('Input must be an integer between 1 and 3.');
    end

    switch numOfSignal
        case 1
            spc = 4;
            numPackets = randi(3);
            centerFreq = 2405e6 + 5e6 * (randi(16) - 11);
            channelTypes = {'Rician', 'Rayleigh', 'AWGN'};
            channelType = channelTypes{randi(length(channelTypes))};
            [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, channelType);
            label = "ZigBee";

        case 2
            centerFreq = [2412e6, 2437e6, 2462e6];
            choosenCF = randsample(centerFreq, 1);
            channelTypes = {'Rician', 'Rayleigh'};
            channelType = channelTypes{randi(length(channelTypes))};
            [noisyWf, wfFin] = myWlanHelper(choosenCF, channelType);
            label = "WLAN";

        case 3
            channelTypes = {'Rician', 'Rayleigh'};
            channelType = channelTypes{randi(length(channelTypes))};
            packetType = 'FHS';
            [noisyWf, wfFin] = myBluetoothHelper(packetType, channelType);
            label = "Bluetooth";
    end

    clearvars -except noisyWf wfFin label
end
