clearvars -except net; close all;
addpath '/home/nicola-gallucci/Nicola/Matlab/AICHallenge/AICompetition/visualizationHelpers'

imageSize = [256,256];
rx = sdrrx("Pluto", "RadioID", 'usb:0', ...
    'CenterFrequency', 2.44e9, 'GainSource','Manual','Gain',65, ...
    'EnableBurstMode',true, 'BasebandSampleRate',40e6, 'OutputDataType','double', 'SamplesPerFrame',32e5);

waveform = rx();

db_min = -130;
db_max = -50;
Nfft = 4096;                    % FFT size
window = hann(256);            % Window for spectrogram
overlap = 10;                  % Overlap between windows
colormap_resolution = 256;

    figure;
    [~, ~, ~, P] = spectrogram(waveform, window, overlap, Nfft, 40e6, 'centered', 'psd');

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

    dlImg = dlarray(double(I), 'SSC'); % 'SSC' = Spatial, Spatial, Channel
    prediction = predict(net, double(I));
    [~, predictedLabel] = max(prediction, [], 3);

    plotOverLayed(I, predictedLabel, 1);
    