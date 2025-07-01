function [metricsPerSNR, confMat] = evaluateSegmentationMetrics(...
            YTrue, YPred, snrVec, classNames, scoresCell, ignoreUnknown, folderName, netName)
% EVALUATESEGMENTATIONMETRICS - Comprehensive pixel-wise segmentation performance evaluation
%
% This function evaluates semantic segmentation model performance across different
% Signal-to-Noise Ratio (SNR) levels, computing multiple classification metrics
% and generating visualizations for analysis.
%
% --- INPUTS --------------------------------------------------------------
%   YTrue         : cell array [N×1] of ground-truth label images (categorical)
%   YPred         : cell array [N×1] of predicted label images (categorical)
%   snrVec        : numeric vector [N×1] with SNR (dB) of each image
%   classNames    : string array listing class names in order
%   scoresCell    : (optional) cell array of softmax probability tensors (H×W×C)
%   ignoreUnknown : logical flag to exclude "Unknown" class from metrics
%   folderName    : string path for saving results
%   netName       : string identifier for output file naming
%
% --- OUTPUTS -------------------------------------------------------------
%   metricsPerSNR : table containing all computed metrics per SNR level
%   confMat       : overall confusion matrix across all test samples

%% ========================================================================
%  INPUT VALIDATION AND INITIALIZATION
%  ========================================================================

% Verify input consistency - all arrays must have matching dimensions
assert(numel(YTrue)==numel(YPred) && numel(YTrue)==numel(snrVec), ...
    'Input arrays YTrue, YPred, and snrVec must have identical lengths');

% Extract key parameters from inputs
C = numel(classNames);              % Total number of semantic classes
allSNR = unique(snrVec);            % Extract unique SNR values from dataset
allSNR = sort(allSNR(:), 'ascend'); % Sort SNR levels for consistent ordering
numSNR = numel(allSNR);             % Count of distinct SNR levels to evaluate

%% ========================================================================
%  METRIC STORAGE ARRAYS INITIALIZATION
%  ========================================================================

% Initialize scalar metrics arrays (one value per SNR level)
acc     = nan(numSNR,1);    % Overall pixel accuracy
mpa     = nan(numSNR,1);    % Mean per-class pixel accuracy
miou    = nan(numSNR,1);    % Mean Intersection over Union
mdice   = nan(numSNR,1);    % Mean Dice coefficient
wiou    = nan(numSNR,1);    % Weighted IoU (class-frequency weighted)
prec    = nan(numSNR,1);    % Binary detection precision
rec     = nan(numSNR,1);    % Binary detection recall
pd_val  = nan(numSNR,1);    % Probability of detection (alias for recall)
pfa_val = nan(numSNR,1);    % Probability of false alarm
auc_val = nan(numSNR,1);    % Area Under ROC Curve

% Initialize per-class metric matrices (rows=SNR levels, columns=classes)
perClassAccMat  = nan(numSNR, C);  % Per-class accuracy across SNR levels
perClassIoUMat  = nan(numSNR, C);  % Per-class IoU across SNR levels
perClassDiceMat = nan(numSNR, C);  % Per-class Dice across SNR levels

% Initialize global confusion matrix for aggregated performance analysis
confMat = zeros(C, C);

%% ========================================================================
%  MAIN EVALUATION LOOP - PROCESS EACH SNR LEVEL
%  ========================================================================

for k = 1:numSNR
    thisSNR = allSNR(k);                    % Current SNR level being processed
    idx = (snrVec == thisSNR);              % Find all images at this SNR level
    
    % Skip if no images found at this SNR level
    if ~any(idx)
        continue;
    end
    
    % Initialize SNR-specific confusion matrix and binary classification arrays
    confMatSNR = zeros(C, C);               % Confusion matrix for current SNR
    allBinaryLabels = [];                   % Binary ground truth for AUC calculation
    allScores = [];                         % Prediction scores for AUC calculation
    
    i = 1;  % Counter for processing images at current SNR level
    
    %% ====================================================================
    %  IMAGE-LEVEL PROCESSING WITHIN CURRENT SNR
    %  ====================================================================
    
    for ii = find(idx)
        % Extract ground truth and prediction for current image
        gt = YTrue{i};      % Ground truth segmentation mask
        pred = YPred{i};    % Model prediction mask
        
        % Convert numeric labels to categorical with consistent class mapping
        % Ground truth: numeric values [0,16,32,64,128] → classNames
        gt = categorical(gt, [0,16,32,64,128], classNames);
        
        % Predictions: categorical values ["C1","C2","C3","C4","C5"] → classNames
        oldValues = categorical(["C1", "C2", "C3", "C4", "C5"]);
        pred = categorical(pred, oldValues, classNames);

        % Flatten 2D images to 1D vectors for confusion matrix computation
        gtVec = gt(:);      % Vectorized ground truth
        predVec = pred(:);  % Vectorized predictions
        
        % Compute and accumulate confusion matrix for this image
        cmThis = confusionmat(gtVec, predVec);
        confMatSNR = confMatSNR + cmThis;
        
        %% Binary Classification Preparation for AUC Calculation
        % If probability scores are available, prepare binary classification data
        if ~isempty(scoresCell)
            scoreImg = scoresCell{i};                           % Softmax scores (H×W×C)
            fgScore = max(scoreImg(:,:,2:end), [], 3);         % Max foreground probability
            binGT = (gtVec ~= classNames(1));                  % Binary mask (background=0, foreground=1)
            allBinaryLabels = [allBinaryLabels; binGT(:)];     % Accumulate binary labels
            allScores = [allScores; fgScore(:)];               % Accumulate prediction scores
        end
        
        i = i + 1;  % Increment image counter
    end
    
    % Accumulate current SNR confusion matrix into global matrix
    confMat = confMat + confMatSNR;
    
    %% ====================================================================
    %  METRIC COMPUTATION FROM CONFUSION MATRIX
    %  ====================================================================
    
    % Overall pixel accuracy: fraction of correctly classified pixels
    totalPixels = sum(confMatSNR(:));
    acc(k) = trace(confMatSNR) / totalPixels;
    
    % Extract key components from confusion matrix
    diagVals = diag(confMatSNR);        % True positives for each class
    rowSums = sum(confMatSNR, 2);       % Actual class frequencies
    colSums = sum(confMatSNR, 1)';      % Predicted class frequencies
    
    % Determine which classes to include in mean calculations
    if ignoreUnknown
        incIdx = 2:C;   % Exclude first class (typically "Unknown" or background)
    else
        incIdx = 1:C;   % Include all classes
    end
    
    %% Per-Class Accuracy Computation
    % Per-class accuracy = diagonal / row sum (recall for each class)
    perClassAcc = diagVals ./ (rowSums + eps);  % eps prevents division by zero
    mpa(k) = mean(perClassAcc(incIdx));         % Mean across included classes
    
    %% IoU and Dice Coefficient Computation
    iouVals = zeros(C,1);   % Per-class Intersection over Union
    diceVals = zeros(C,1);  % Per-class Dice coefficient
    
    for c = 1:C
        % Extract confusion matrix components for class c
        tp = confMatSNR(c,c);           % True positives
        fp = colSums(c) - tp;           % False positives
        fn = rowSums(c) - tp;           % False negatives
        
        % Compute IoU: TP / (TP + FP + FN)
        iouVals(c) = tp / (tp + fp + fn + eps);
        
        % Compute Dice: 2*TP / (2*TP + FP + FN)
        diceVals(c) = (2*tp) / (2*tp + fp + fn + eps);
    end
    
    % Compute mean metrics across included classes
    miou(k) = mean(iouVals(incIdx));
    mdice(k) = mean(diceVals(incIdx));

    % Store per-class metrics in matrices for visualization
    perClassAccMat(k,:)  = perClassAcc;
    perClassIoUMat(k,:)  = iouVals;
    perClassDiceMat(k,:) = diceVals;

    %% ====================================================================
    %  BINARY DETECTION METRICS (Background vs Foreground)
    %  ====================================================================
    
    % Treat segmentation as binary detection: background (class 1) vs all others
    TP = sum(sum(confMatSNR(2:end, 2:end))); % Foreground correctly classified as foreground
    FP = sum(confMatSNR(1, 2:end));          % Background incorrectly classified as foreground
    FN = sum(confMatSNR(2:end, 1));          % Foreground incorrectly classified as background
    TN = confMatSNR(1,1);                    % Background correctly classified as background
    
    % Compute binary classification metrics
    prec(k) = TP / (TP + FP + eps);     % Precision: TP / (TP + FP)
    rec(k) = TP / (TP + FN + eps);      % Recall: TP / (TP + FN)
    pd_val(k) = rec(k);                 % Probability of detection (alias for recall)
    pfa_val(k) = FP / (FP + TN + eps);  % Probability of false alarm: FP / (FP + TN)
    
    %% ====================================================================
    %  WEIGHTED IoU COMPUTATION
    %  ====================================================================
    
    % Weight IoU by class frequency (more frequent classes have higher weight)
    classWeights = rowSums;                 % Use actual class frequencies as weights
    
    if ignoreUnknown
        classWeights(1) = 0;                % Set background weight to zero if ignored
    end
    
    % Compute weighted average, handling edge case of all weights being zero
    if sum(classWeights) == 0
        wiou(k) = NaN;                      % Undefined when all classes are ignored
    else
        wiou(k) = sum(iouVals .* classWeights) / sum(classWeights);
    end

    %% ====================================================================
    %  AUC CALCULATION (if probability scores available)
    %  ====================================================================
    
    % Compute Area Under ROC Curve for binary foreground detection
    if ~isempty(scoresCell) && ~isempty(allBinaryLabels)
        [~,~,~,auc_val(k)] = perfcurve(allBinaryLabels, allScores, 1);
    end
end

%% ========================================================================
%  RESULTS COMPILATION AND OUTPUT FORMATTING
%  ========================================================================

% Create comprehensive results table with all computed metrics
metricsPerSNR = table(allSNR, acc, mpa, miou, wiou, mdice, prec, rec, pd_val, pfa_val, auc_val, ...
    'VariableNames', {'SNR','Accuracy','MeanPixelAcc','MeanIoU', 'WeightedIoU','MeanDice',...
    'Precision','Recall','Pd','Pfa','AUC'});

%% ========================================================================
%  CONSOLE OUTPUT AND VISUALIZATION
%  ========================================================================

% Display summary table to console
fprintf('\nSummary metrics (ignoreUnknown = %d):\n', ignoreUnknown);
disp(metricsPerSNR);

%% ====================================================================
%  PER-CLASS METRICS VISUALIZATION
%  ====================================================================

% Create comprehensive per-class performance visualization
figure;
metrics = {'Accuracy','IoU','Dice'};                               % Metrics to plot
dataMat = {perClassAccMat, perClassIoUMat, perClassDiceMat};       % Corresponding data matrices

% Generate subplot for each metric type
for m = 1:numel(metrics)
    subplot(3,1,m); hold on; grid on;
    
    % Plot performance curve for each class
    for c = 1:C
        if ignoreUnknown && c == 1    % Skip background class if requested
            continue;
        end
        plot(allSNR, dataMat{m}(:,c), '-o', 'DisplayName', classNames(c));
    end
    
    % Format subplot
    xlabel('SNR [dB]');
    ylabel(metrics{m});
    title([metrics{m} ' per class vs SNR']);
    legend('Location','bestoutside');
end

%% ====================================================================
%  CONFUSION MATRIX VISUALIZATION
%  ====================================================================

% Generate normalized confusion matrix visualization
figure; 
confusionchart(confMat, classNames, ...
    'RowSummary','row-normalized','ColumnSummary','column-normalized');

%% ========================================================================
%  FILE OUTPUT AND PERSISTENCE
%  ========================================================================

%% Save Metrics Table in Multiple Formats
% CSV format for external analysis tools
csvFile = fullfile(folderName, sprintf('%s_metricsPerSNR.csv', netName));
writetable(metricsPerSNR, csvFile);

% MATLAB format for future processing
matFile = fullfile(folderName, sprintf('%s_metricsPerSNR.mat', netName));
save(matFile, 'metricsPerSNR');

% Text format for human-readable reports
txtFile = fullfile(folderName, sprintf('%s_metricsPerSNR.txt', netName));
fid = fopen(txtFile, 'w');
fprintf(fid, 'Summary metrics (ignoreUnknown = %d):\n', ignoreUnknown);
fprintf(fid, '%s\n', evalc('disp(metricsPerSNR)'));  % Capture console display output
fclose(fid);

%% Save Confusion Matrix Data
% CSV format for confusion matrix
csvConf = fullfile(folderName, sprintf('%s_confusionMatrix.csv', netName));
writematrix(confMat, csvConf);

% MATLAB format for confusion matrix
matConf = fullfile(folderName, sprintf('%s_confusionMatrix.mat', netName));
save(matConf, 'confMat');

%% ====================================================================
%  FIGURE EXPORT AND ARCHIVAL
%  ====================================================================

% Save all generated figures in both raster and vector formats
figHandles = findall(0, 'Type', 'figure');

for kFig = 1:numel(figHandles)
    % Generate meaningful filename from figure title or use sequential numbering
    fName = get(figHandles(kFig), 'Name');
    if isempty(fName)
        fName = sprintf('Figure_%02d', kFig);
    end
    
    % Sanitize filename by removing invalid characters
    fName = regexprep(fName, '[^\w\d_\- ]', '');
    
    % Define output paths
    pngPath = fullfile(folderName, [fName '.png']);    % Raster format for presentations
    figPath = fullfile(folderName, [fName '.fig']);    % Native MATLAB format for editing
    
    % Export figures
    saveas(figHandles(kFig), pngPath);   % High-quality raster image
    savefig(figHandles(kFig), figPath);  % Editable MATLAB figure file
end

% Confirm successful completion
fprintf('Results and visualizations saved to:\n%s\n', folderName);

end