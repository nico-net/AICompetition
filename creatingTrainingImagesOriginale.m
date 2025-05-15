function [imageLabelled] = creatingTrainingImages(numFrame,label, classNames, sr, imageSize)


%Creating directory  
    
    for index=1:length(imageSize)
        imgSize = imageSize{index};
        folderName = sprintf('%dx%d',imgSize(1),imgSize(2));
        dirName = fullfile('wlan',folderName);
        if ~exist(dirName,'dir')
            mkdir(dirName)
        end
    end
    
    idxFrame = 0;
    numFrame = 1;
    
    while idxFrame<numFrame
       lrwpanConfig = lrwpanOQPSKConfig('Band',2450,'PSDULength',127,'SamplesPerChip',4);
       data = randi([0,1],8*127,1);
       waveform = lrwpanWaveformGenerator(data, lrwpanConfig);
       spectrogram = createSpectrogram(waveform, 20e6);
    
    end

    end


function [P] = createSpectrogram(signal, sr, imageSize)
   
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


function labellingImage(P_dB, label, pixelClassNames)

% --- 1) Calcola mask di partenza (ad esempio con soglia su P_dB) ---
soglia = max(P_dB(:)) - 10;
mask = P_dB >= soglia;

% --- 2) Trova il bounding-box dei punti veri (1) in mask ---
[r, c] = find(mask);                % indici delle righe e colonne dove mask==true
rmin   = min(r); rmax = max(r);     % estremo alto e basso
cmin   = min(c); cmax = max(c);     % estremo sinistro e destro

% --- 3) Riempi l’intero rettangolo con 1 ---
mask(rmin:rmax, cmin:cmax) = true;

% --- 4) Continua come prima: crea data e assegna pixelValue solo dentro mask ---
data = zeros(size(P_dB));
pixelValue = floor((find(strcmp(label, pixelClassNames)) - 1) * 255 / numel(pixelClassNames));
data(mask) = pixelValue;

% --- 5) Converti in uint8 e ridimensiona ---
im = imresize(im2uint8(rescale(data)), imageSize, "nearest");

% --- 6) Visualizza ---
figure;
imshow(im);
title('Spettrogramma con bounding-box riempito');



end