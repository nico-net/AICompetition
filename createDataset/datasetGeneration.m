close all; clc;
startPos = [0 0 0];
startFreq = 2.402e9;

numFrame = 20000;

btTx = BluetoothTx(startPos, "AWGN", startFreq, 4, "RANDOM");
sbTx = SmartBanTx(startPos, "AWGN", startFreq, 4);
wlanTx = WlanTx(startPos, "AWGN", startFreq, 20);
zbTx = ZigBeeTx(startPos, "AWGN", startFreq, 6, 4);

txBatch = {wlanTx, zbTx, btTx, sbTx};


useGPU = false;
wantPlot = false;
imageSize = {[256,256]};

for index = 1:length(imageSize)
        imgSize = imageSize{index};
        folderName = sprintf('%dx%d', imgSize(1), imgSize(2));
        dirName = fullfile('trainingImages', folderName);
        if ~exist(dirName, 'dir')
            mkdir(dirName);
        end
end
    
signalLabels = containers.Map(...
        {'WLAN', 'ZigBee', 'Bluetooth', 'SmartBAN'}, ...
        [16, 32, 64, 128]); 
sr = 80e6;

for idxFrame = 1:numFrame
    close all;
    sigTypes = currTxSigs;
    waveformsClean = [];
    labels = []; % Initialize labels for storing waveform labels

    for i = 1:numel(sigTypes)
        index = sigTypes(i);
        txBatch{index} = txBatch{index}.randParams(0);
        txBatch{index}.dispProperties;
        label = txBatch{index}.returnLabel;
        wf = txBatch{sigTypes(i)}.getWaveform();
        labels = cat(1, labels, label);
        waveformsClean = cat(2, waveformsClean, wf);
    end

    data_tot = [];
    % Generate labeled spectrogram masks
    for i = 1:size(waveformsClean, 2)
        label = labels(i, :);
        waveform = waveformsClean(:, i);
        [P_matrix, ~, P_rx] = createSpectrogram(waveform, sr, imageSize, useGPU, wantPlot);
        labeledImage = labellingImage(P_matrix, label, signalLabels, imageSize{1}, useGPU, wantPlot);
        data_tot = cat(3, data_tot, labeledImage);
    end

    
    wfFin = mySignalMixerInterf(waveformsClean, 20e-3, 1e-8);
    [~, spectrogramTot] = createSpectrogram(wfFin, sr, imageSize, useGPU, wantPlot);
    overlapLabelledImages(data_tot, idxFrame, dirName, labels, spectrogramTot, signalLabels);


    for i = 1:numel(txBatch)
        txBatch{i} = txBatch{i}.resetFreqs;
    end

end






function data = labellingImage(P_dB, label, signalLabels, imageSize, useGPU, wantPlot)

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
        threshold = max(P_dB_cpu(:)) - min(P_dB_cpu(:)) - 0.5 - 2*((max(P_dB_cpu(:)) - min(P_dB_cpu(:)))>2.5);
        
    else
        threshold = max(P_dB_cpu(:)) - min(P_dB_cpu(:)) - 2 - 4.5*((max(P_dB_cpu(:)) - min(P_dB_cpu(:)))>6.5);
        
    end
    
    mask = P_dB_cpu >= (max(P_dB_cpu(:)) - threshold);
    mask = flipud(mask);  % Align with spectrogram
    if ~strcmp(label, "SmartBAN")
        cc = bwconncomp(mask);  % Find connected regions
    
        % Fill bounding boxes around each component
        for i = 1:cc.NumObjects
            [r, c] = ind2sub(size(mask), cc.PixelIdxList{i});
            rmin = min(r); rmax = max(r);
            cmin = min(c); cmax = max(c);
            mask(rmin:rmax, cmin:cmax) = true;
        end
    end
    data = zeros(size(P_dB_cpu));
    pixelValue = signalLabels(label);
    data(mask) = pixelValue;
    
    data = imresize(data, imageSize, "nearest");

    % Move result back to GPU if requested and input was on GPU
    if useGPU && isa(P_dB, 'gpuArray')
        data = gpuArray(data);
    end

    if wantPlot
        im = imresize(im2uint8(rescale(data)), imageSize, "nearest");
        figure;
        imshow(im);
        title('Spectrogram Mask');
    end
end



function [P, I, P_rx] = createSpectrogram(waveform, sr, imageSize, useGPU, wantPlot)

 % Set default value for useGPU if not provided
    if nargin < 5
        useGPU = false;
    end

    % Declare the fixed scale
    db_min = -160;
    db_max = -60;
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

    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, sr, 'psd');
    
    P = 10 * log10(abs(P') + eps);  % Conversione in dB
   
    %Clipping of outliers
    P_db_clipped = min(max(P, db_min), db_max);

    %Normalization with respect to the fixed scale
    P_norm = (P_db_clipped - db_min) / (db_max - db_min);
    
    %Ensure data is on CPU for image processing
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

    if wantPlot
        %for debug
        figure;
        imshow(I);  % for debug
        colormap(parula(colormap_resolution));
        colorbar('Ticks', linspace(0,1,8), ...
                 'TickLabels', linspace(db_min, db_max, 8));  % scale colorbar to dB range
        title('Power (dB)');
        axis image off;
    end

end




function sigTypes = currTxSigs()

    weights = [0.2 0.25 0.3 0.25];  
    possibleCombinations = [1 2 3 4];
       
    numSignals = randsample(possibleCombinations, 1, true, weights);
    sigTypes = zeros(numSignals, 1);
    for iter = 1:numSignals
        if numSignals ~= 1
            prob = rand(); % 1=WLAN, 2=ZigBee, 3=Bluetooth 4 = SmartBAN
            if prob < 0.20 
                type_signal = 1;
            end
            if prob < 0.45 && prob >= 0.20
                type_signal = 2;
            end
            if prob >= 0.45 && prob < 0.7
                type_signal = 3;
            end
            if prob >= 0.7
                type_signal = 4;
            end
        else
            type_signal = 4;  %only smartban
  
        end
        sigTypes(iter) = type_signal;
    end
end


function overlapLabelledImages(data, idxFrame, dir, labels, spectrogram, label_map)

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
    filename = num2str(idxFrame) + "_" + ...
                        label_combination;
    fname = fullfile(dir, filename);
    
    save(char(fname + "_frame.mat"), 'data_final');
    imwrite(spectrogram, char(fname + "_spectrogram.png"));
end







