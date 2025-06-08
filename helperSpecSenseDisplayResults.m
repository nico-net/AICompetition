function helperSpecSenseDisplayResults(trueLabels, predictedLabels, classNames)
%helperSpecSenseDisplayResults Display spectrogram + true/predicted labels
% helperSpecSenseDisplayResults(TL, PL, CLASSNAMES) displays
% the true and predicted segmentation label masks.

% Define custom mapping values and class names
cmap = cool(numel(classNames)); % or define your own colors

% Use the actual data values as tick positions
ticks = 1:numel(classNames);

figure;

% Plot True Labels
subplot(2,1,1);
img = imagesc(trueLabels);
colormap(gca, cmap);
clim([1, numel(classNames)]);
title("True signal labels");
set(gca,'YDir','normal')
img.Parent.Colormap = cmap;
colorbar('TickLabels',cellstr(classNames),'Ticks',ticks,...
    'TickLength',0,'TickLabelInterpreter','none');

% Plot Predicted Labels  
subplot(2,1,2);
img = imagesc(predictedLabels);
colormap(gca, cmap);
clim([1, numel(classNames)]);
set(gca,'YDir','normal')
img.Parent.Colormap = cmap;
colorbar('TickLabels',cellstr(classNames),'Ticks',ticks,...
    'TickLength',0,'TickLabelInterpreter','none');
end