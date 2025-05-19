% Number of labels = 9
% AWGN = 0   
% WLAN = 31.8750   
% ZIGBEE = 63.7500  
% WLAN + ZIGBEE = 95.6250 
% BLUETOOTH = 127.5000 
% WLAN + BLUETOOTH = 159.3750 
% BLUETOOTH + ZIGBEE = 191.2500 
% BLUETOOTH + ZIGBEE + WLAN = 223.1250 
% UNKOWN  = 255.0000  (Not labelled)


function creatingTrainingImages(numFrame,label, sr, imageSize)
    numberOfLabels = 9;
    linSpace = linspace(0, 255, numberOfLabels);
    pixelValues = containers.Map(...
    {'WLAN', 'ZIGBEE', 'Bluetooth'}, ...
    [linSpace(2:3), linSpace(5)]);
    %Creating directory  
    %classNames = ["Wlan", "ZigBee", "Bluetooth"];
    imageSize = {[128, 128]};
    for index=1:length(imageSize)
        imgSize = imageSize{index};
        folderName = sprintf('%dx%d',imgSize(1),imgSize(2));
        dirName = fullfile('trainingImages',folderName);
        if ~exist(dirName,'dir')
            mkdir(dirName)
        end
    end
    
    waveforms = [];
    idxFrame = 0;
    numFrame = 1;

    while idxFrame<numFrame

            % randomize the number of signal that have to be created and save
            % them into an array of waveforms 
          
           numIterations = randi(randi(30,1),1);
    
        for i = 1:numIterations
            % Get a number to generate signal waveform
            type_signal = randi(3,1);
        
            % Save the generated waveform
            [noisyWaveform, wfFin] = generateWaveform(type_signal);
        
            % Update waveform 
            waveforms = [waveforms noisyWaveform]; % oppure usa cleanWaveform
        end


       % Creating the spectogram
       %spectrogram = createSpectrogram(waveform, sr);
       data_tot = [];
       %Labelling pixels
       for i = 1:length(waveforms)
           waveform = waveforms(i);
           spectrogram = createSpectrogram(waveform, sr, imageSize);
           data_waveform_singular = labellingImage(spectrogram, label, numberOfLabels, pixelValues);
           data_tot = [data_tot data_waveform_singular];
       end
       overlapLabelledImages(data_tot, idxFrame, dirName);
    end
end


function [P] = createSpectrogram(waveform, sr, imageSize)
    % createSpectogram  It creates signal's spectogram using sr sample rate
    % and imageSize dimension
    imageSize = [1024,1024];
    Nfft = 4096;
    window = hann(256);
    overlap = 10;
    sr = 20e6;

    [~,~,~,P] = spectrogram(waveform,window,overlap,...
    Nfft,sr,'centered','psd');

    % Convert to logarithmic scale
    P = 10*log10(abs(P')+eps);

    % Rescale pixel values to the interval [0,1]. Resize the image to imgSize
    % using nearest-neighbor interpolation.
    im = imresize(im2uint8(rescale(P)),imageSize,"nearest");

    % Convert to RGB image with parula colormap. 
    I = im2uint8(flipud(ind2rgb(im,parula(256))));

    imshow(I);

end


function data = labellingImage(P_dB, label, pixelClassNames, numberOfLabels, pixelValues)
    % Labelling every pixel with a different gray scale colors. The matrix is
    % saved in a directory dir
    soglia = max(P_dB(:)) - 10;
    mask = P_dB >= soglia;

    if ~strcmp(label, "Bluetooth")
        [r, c] = find(mask); % Indici delle righe e colonne dove mask==true
        rmin = min(r); rmax = max(r); % Limiti superiore e inferiore
        cmin = min(c); cmax = max(c); % Limiti sinistro e destro
        % --- 3) Riempie l'intero rettangolo con 1 ---
        mask(rmin:rmax, cmin:cmax) = true;
        data = zeros(size(P_dB));
        % Assegna il valore dalla mappa
        pixelValue = pixelValues(label);
        data(mask) = pixelValue;
    else
        % Se è Bluetooth, riempie i singoli rettangoli dei componenti connessi
        cc = bwconncomp(mask); % Trova componenti connessi
        for i = 1:cc.NumObjects
            % Estrae coordinate dei pixel del componente
            [r, c] = ind2sub(size(mask), cc.PixelIdxList{i});
            % Calcola bounding box per ogni componente
            rmin = min(r); rmax = max(r);
            cmin = min(c); cmax = max(c);
            % Riempie il rettangolo nella maschera
            mask(rmin:rmax, cmin:cmax) = true;
        end
        data = zeros(size(P_dB));
        % Assegna il valore fisso per Bluetooth
        pixelValue = pixelValues('Bluetooth');
        data(mask) = pixelValue;
    end
    % --- 5) Convert to uint8 and resize ---
    im = imresize(im2uint8(rescale(data)), imageSize, "nearest");
    % --- 6) Display ---
    figure;
    imshow(im);
    title('Spectrogram with filled bounding-box');

end



function overlapLabelledImages(data, idxFrame, dir)
    data_final = sum(data, 3);             % Somma lungo la terza dimensione (array di matrici)
    data_final = uint8(data_final);
    filename = label + '_frame_' + num2str(idxFrame);
    fname = fullfile(dir, filename);
    fnameLabels = fname + ".mat";
    
    % Save data in MAT format 
    save(char(fnameLabels), 'data_final');
end


% create a function who runs the script to generate waveform choosen
% between three type of signals (1: ZigBee; 2: WLan; 3: Bluetooth)

function [noisyWf, wfFin] = generateWaveform(numOfSignal)

    % check that the integer is included in the range 1:3
    if ~isscalar(numOfSignal) || ~isnumeric(numOfSignal) || floor(numOfSignal) ~= numOfSignal
        error('L''input deve essere un numero intero');
    end
    if numOfSignal < 1 || numOfSignal > 3
        error('L''input deve essere un numero intero compreso tra 1 e 3');
    end
    
    % Call the corrisponding function to generate the signal
    switch numOfSignal
        case 1
            spc = 4;                % SamplesPerChip
            numPackets = randi(4);  % NumOfPackets choosen randlomly
            centerFreq = 2405e6 + 5e6 * (randi(16) - 11); % CenterFrequency choosen randlomly
            channelTypes = {'Rician', 'Rayleigh', 'AWGN'};
            channelType = channelTypes{randi(length(channelTypes))}; % ChannelType choosen randlomly
            disp(channelType);
            [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, channelType);
            
        case 2
            centerFreq = [2412e6, 2437e6, 2462e6];
            choosenCF = randsample(centerFreq, 1);
            disp(choosenCF)
            channelTypes = {'Rician', 'Rayleigh'};
            channelType = channelTypes{randi(length(channelTypes))}; % ChannelType choosen randlomly
            [noisyWf, wfFin] = myWlanHelper(choosenCF, channelType);
            
        case 3
            channelTypes = {'Rician', 'Rayleigh'};
            channelType = channelTypes{randi(length(channelTypes))}; % ChannelType choosen randlomly
            % packet_type = (how_To_Choose_Packet ?) - I have to find 
            [noisyWf, wfFin] = myBluetoothHelper(PacketType,channelType);
    end

    clear {choosenCF, channelType, centerFreq}; % clear variables to avoid error in the randomic choice of the parameters

end