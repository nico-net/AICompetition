function helperSpecSenseDisplayResults(trueLabels, predictedLabels, classNames)
%helperSpecSenseDisplayResults Display spectrogram + true/predicted labels
% helperSpecSenseDisplayResults(TL, PL, CLASSNAMES) displays
% the true and predicted segmentation label masks.

% Define custom mapping values and class names
cmap = cool(numel(classNames)); % or define your own colors

% Use the actual data values as tick positions
ticks = 1:numel(classNames);

% Calcola le dimensioni delle matrici
[Nrows, Ncols] = size(trueLabels);

% Vettori per asse X e Y
xFreq = linspace(2.4, 2.483, Ncols); % in GHz
yTime = linspace(20, 00, Nrows);      % in ms

figure;

% Plot True Labels
subplot(2,1,1);
imagesc(xFreq, yTime, trueLabels);
colormap(gca, cmap);
clim([1, numel(classNames)]);
title("True signal labels");
xlabel('Frequency (GHz)');
ylabel('Time (ms)');
set(gca,'YDir','normal')
colorbar('TickLabels',cellstr(classNames),'Ticks',ticks,...
    'TickLength',0,'TickLabelInterpreter','none');

% Plot Predicted Labels  
subplot(2,1,2);
imagesc(xFreq, yTime, predictedLabels);
colormap(gca, cmap);
clim([1, numel(classNames)]);
title("Predicted signal labels");
xlabel('Frequency (GHz)');
ylabel('Time (ms)');
set(gca,'YDir','normal');
colorbar('TickLabels',cellstr(classNames),'Ticks',ticks,...
    'TickLength',0,'TickLabelInterpreter','none');

end