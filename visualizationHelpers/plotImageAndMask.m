
function plotImageAndMask(img, mask, spectrogramConfig)
% plotImageAndMask - Visualizes a spectrogram image alongside its labeled mask.
%
% Syntax:
%   plotImageAndMask(img, mask, spectrogramConfig)
%
% Description:
%   This function displays a side-by-side comparison between a spectrogram image 
%   and its corresponding ground truth or predicted label mask. It uses a 
%   discrete colormap for the mask and overlays frequency and time axes 
%   for intuitive interpretation.
%
% Inputs:
%   img               - Spectrogram image, either grayscale or RGB (HxWx1 or HxWx3).
%   mask              - 2D label mask (HxW) with class indices (1-based).
%   spectrogramConfig - Structure with fields:
%                          • dbMin: Minimum dB value for spectrogram scaling.
%                          • dbMax: Maximum dB value for spectrogram scaling.
%                          • colormapResolution: Number of colormap entries for the spectrogram.
%
% Notes:
%   - The function assumes hardcoded class names: "Unknown", "WLAN", "ZigBee", 
%     "Bluetooth", "SmartBAN".
%   - Frequency axis is assumed to range from 2400 MHz to 2480 MHz.
%   - Time axis spans 0 to 20 milliseconds.
%   - The colormap for the label mask is a discrete version of `parula`.
%
% Example:
%   plotImageAndMask(spectrogramImage, predictedMask, configStruct);

    %------------- Hardcoded class names -------------
    classNames = ["Unknown","WLAN","ZigBee","Bluetooth","SmartBAN"];
    N = numel(classNames);

    %------------- Validate input sizes --------------
    [H, W, ~] = size(img);
    assert(isequal(size(mask), [H W]), 'Image and mask dimensions must match');

    %------------- Create discrete parula colormap ----
    cmapLabels = parula(N);

    %------------- Setup figure and layout -----------
    figure('Name','Prediction vs Spectrogram','Position',[100 50 768 768]);
    t = tiledlayout(1,2, 'TileSpacing','compact','Padding','compact');

    %------------- Tile #1: Spectrogram ------------
    ax1 = nexttile(t,1);
    % Use imagesc for consistent axis behavior
    if ndims(img)==3
        % Display true-color RGB image
        imshow(img,'Parent',ax1);
    else
        imagesc(img,'Parent',ax1);
    end
    % Spectrogram colormap and colorbar
    colormap(ax1, parula(spectrogramConfig.colormapResolution));
    clim(ax1, [spectrogramConfig.dbMin, spectrogramConfig.dbMax]);
    cb1 = colorbar(ax1, 'eastoutside');
    cb1.Label.String = 'Power (dB)';

    axis(ax1,'image','on');        % equal aspect ratio, show axes
    title(ax1,'Real Spectrogram Capture');

    %------------- Tile #2: Label mask -------------
    mask = reAllignLabels(mask);
    ax2 = nexttile(t,2);
    imagesc(mask,'Parent',ax2);
    colormap(ax2, cmapLabels);
    clim(ax2,[1 N]);         % center bins on integers
    cb2 = colorbar(ax2,'eastoutside');
    cb2.Ticks = 1:N;
    cb2.TickLabels = classNames;

    axis(ax2,'image','on');        % equal aspect ratio, show axes
    title(ax2,'Label Mask (Discrete Parula)');

    %------------- Add frequency axis labels --------
    fStart = 2400; fEnd = 2480;
    xtickPos  = round(linspace(1, W, 5));
    xtickFreq = linspace(fStart, fEnd, 5);
    for ax = [ax1, ax2]
        set(ax, 'XTick', xtickPos, 'XTickLabel', sprintfc('%.0f', xtickFreq));
        xlabel(ax,'Frequency (MHz)');
    end

    %------------- Add time axis labels -------------
    ytickPos = round(linspace(1, H, 5));    % pixel positions from top
    ytickTime = linspace(0, 20, 5);          % ms values
    for ax = [ax1, ax2]
        set(ax, 'YTick', ytickPos, 'YTickLabel', sprintfc('%.0f', ytickTime));
        ylabel(ax,'Time (ms)');
    end
end