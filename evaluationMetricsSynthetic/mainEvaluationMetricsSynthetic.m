%% ========================================================================
%  SEMANTIC SEGMENTATION MODEL EVALUATION ACROSS SNR LEVELS
%  ========================================================================
%
% This script performs comprehensive evaluation of a trained semantic segmentation
% network across different Signal-to-Noise Ratio (SNR) conditions. It processes
% spectrogram images and their corresponding ground truth masks to compute
% detailed performance metrics for wireless protocol classification.
%
% WORKFLOW:
% 1. Load pre-trained segmentation network
% 2. Process test images across SNR range (0-35 dB)
% 3. Generate predictions and collect probability scores
% 4. Compute comprehensive evaluation metrics
% 5. Generate visualizations and save results

%% ========================================================================
%  ENVIRONMENT SETUP AND CONFIGURATION
%  ========================================================================

% Clear workspace for clean execution environment
close all;          % Close all figure windows
clc;               % Clear command window
clear;             % Clear workspace variables

%% ========================================================================
%  INPUT PARAMETERS AND CONFIGURATION
%  ========================================================================

% Define data source and model parameters
folderName = "Noise";                                               % Root directory containing test data
net = load("Reti/ResNet_18_deep/myNet_2025_06_28_01_04.mat").net;   % Load trained segmentation network
imageSuffix = "_spectrogram.png";                                   % Image file extension (adjust as needed)

% Define semantic class mapping for wireless protocol classification
classNames = ["Unknown","WLAN","ZigBee","Bluetooth","SmartBAN"];    % Class labels in network output order

% Configure output settings
netName = 'ResNet18Deep';                                           % Network identifier for file naming
outDir = fullfile('Perfomances', netName);                         % Output directory for results

% Ensure output directory exists for saving results
if ~exist(outDir, 'dir')
    mkdir(outDir);                                                  % Create directory if it doesn't exist
end

%% ========================================================================
%  DATA STORAGE ARRAYS INITIALIZATION
%  ========================================================================

% Pre-allocate cell arrays for efficient memory usage during data collection
YTrue = {};         % Cell array to store ground-truth categorical segmentation masks
YPred = {};         % Cell array to store network-predicted categorical masks  
scoresCell = {};    % Cell array to store softmax probability scores (H×W×C tensors)
snrVec = [];        % Numeric vector to store SNR level for each processed sample

%% ========================================================================
%  MAIN DATA PROCESSING LOOP
%  ========================================================================

% Process test data across SNR range from 0 to 35 dB
% This range covers typical wireless communication scenarios from very noisy to clean conditions
for snr = 0:35
    
    %% ====================================================================
    %  FILE DISCOVERY FOR CURRENT SNR LEVEL
    %  ====================================================================
    
    % Construct file pattern to locate ground truth masks for current SNR
    % Expected naming convention: *_[SNR]dB_frame.mat
    filePattern = sprintf('*_%ddB_frame.mat', snr);
    matFiles = dir(fullfile(folderName, filePattern));              % Find all matching .mat files
    
    %% ====================================================================
    %  PROCESS EACH SAMPLE AT CURRENT SNR LEVEL
    %  ====================================================================
    
    for i = 1:numel(matFiles)
        
        %% ================================================================
        %  GROUND TRUTH MASK LOADING
        %  ================================================================
        
        % Load ground truth segmentation mask from .mat file
        % Expected structure: .mat file contains 'data_final' variable with pixel labels
        L = load(fullfile(folderName, matFiles(i).name));
        YTrue{end+1,1} = L.data_final;                              % Store ground truth mask
        
        %% ================================================================
        %  CORRESPONDING IMAGE FILE PREPARATION
        %  ================================================================
        
        % Extract base filename and construct corresponding image path
        [~, baseName, ~] = fileparts(matFiles(i).name);            % Extract filename without extension
        baseName = regexprep(baseName, '_frame$', '');             % Remove '_frame' suffix if present
        
        % Load corresponding spectrogram image for network input
        % Image naming convention: [baseName]_spectrogram.png
        img = imread(fullfile(folderName, baseName + imageSuffix));
        
        %% ================================================================
        %  NEURAL NETWORK FORWARD PASS AND PREDICTION
        %  ================================================================
        
        % Perform semantic segmentation inference on input image
        % semanticseg returns:
        %   - predLabel: categorical image with predicted class for each pixel
        %   - ~: (unused) normalized prediction scores  
        %   - allScores: raw softmax probability scores for all classes (H×W×C)
        [predLabel, ~, allScores] = semanticseg(img, net, ...
            "OutputType", "categorical");                           % Ensure categorical output format
        
        % Store prediction results for later evaluation
        YPred{end+1,1} = predLabel;                                % Store predicted segmentation mask
        scoresCell{end+1,1} = allScores;                           % Store probability scores for AUC calculation
        snrVec(end+1) = snr;                                       % Record SNR level for this sample
        
        %% ================================================================
        %  PROGRESS MONITORING AND LOGGING
        %  ================================================================
        
        % Display processing progress with detailed information
        % Format: SNR level, current sample index, total samples, filename
        fprintf('Processed SNR %2ddB – sample %3d/%3d : %s\n', ...
            snr, i, numel(matFiles), matFiles(i).name);
    end
end

%% ========================================================================
%  COMPREHENSIVE METRICS EVALUATION
%  ========================================================================

% Call comprehensive evaluation function to compute all performance metrics
% This function will:
% - Compute per-SNR metrics (accuracy, IoU, Dice, precision, recall, AUC)
% - Generate confusion matrices
% - Create performance visualizations
% - Save results in multiple formats (CSV, MAT, TXT, PNG, FIG)

[metricsPerSNR, confMat] = evaluateSegmentationMetrics(...
    YTrue, ...              % Ground truth segmentation masks
    YPred, ...              % Network predictions 
    snrVec, ...             % SNR levels for each sample
    classNames, ...         % Semantic class names
    scoresCell, ...         % Softmax probability scores for AUC computation
    false, ...              % ignoreUnknown flag (false = include all classes in metrics)
    outDir, ...             % Output directory for saving results
    netName);               % Network identifier for file naming

%% ========================================================================
%  EVALUATION COMPLETE
%  ========================================================================

% At this point, the following outputs have been generated:
% 
% METRICS FILES:
% - [netName]_metricsPerSNR.csv: Tabular metrics in CSV format
% - [netName]_metricsPerSNR.mat: MATLAB workspace with metrics table
% - [netName]_metricsPerSNR.txt: Human-readable metrics summary
%
% CONFUSION MATRIX FILES:
% - [netName]_confusionMatrix.csv: Numerical confusion matrix
% - [netName]_confusionMatrix.mat: MATLAB confusion matrix variable
%
% VISUALIZATION FILES:
% - Per-class performance plots (Accuracy, IoU, Dice vs SNR)
% - Normalized confusion matrix visualization
% - Both PNG (presentation) and FIG (editable) formats
%
% All files are saved in the specified output directory for further analysis.