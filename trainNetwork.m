%% Spectrogram Segmentation using U-Net with ResNet34 Encoder
clear; close all;clc;

numClasses = 6;
classNames = [ ...
    "AWGN", "WLAN", "ZigBee","Bluetooth", "SmartBAN", "Unknown"];

pixelLabelID = uint8([0, 16, 32, 64, 128, 255]);

% Set your folder path
dataFolder = fullfile(pwd,"CompleteFunctionContainer/trainingImages_Nicola/128x128");
%fileID = '';
%dataFolder = downloadAndUnzipGoogleDrive(fileID, 'trainingImages');

%% STEP 1: Create Image Datastore
imds = imageDatastore(dataFolder, 'FileExtensions', {'.png'}, 'IncludeSubfolders', false);

%% STEP 2: Create Custom Label Datastore for .mat Bitmask Files
matFiles = dir(fullfile(dataFolder, '*.mat'));
matPaths = fullfile({matFiles.folder}, {matFiles.name})';

pxds = pixelLabelDatastore(matPaths, ...
    classNames, pixelLabelID, ...
    ReadFcn=@readMatFile,...
    FileExtensions=".mat");

% Combine into pixelLabelImageDatastore
pximds = pixelLabelImageDatastore(imds, pxds);


%% 
tbl = countEachLabel(pxds); % pxds: pixelLabelDatastore
imageFreq = tbl.PixelCount ./ tbl.ImagePixelCount;
imageFreq(isnan(imageFreq)) = [];
classWeights = median(imageFreq) ./ imageFreq;
classWeights = classWeights/(sum(classWeights)+eps(class(classWeights)));
if length(classWeights) < numClasses
    classWeights = [classWeights; zeros(numClasses-length(classWeights),1)];
end


%% STEP 3: Split into Train, Validation and Test
[imdsTrain,pxdsTrain,imdsVal,pxdsVal,imdsTest,pxdsTest] = ...
  helperSpecSensePartitionData(imds,pxds,[70 10 20]);
cdsTrain = combine(imdsTrain,pxdsTrain);
cdsVal = combine(imdsVal,pxdsVal);
cdsTest = combine(imdsTest,pxdsTest);

%% STEP 4: Define U-Net Network with ResNet34 Encoder
imageSize = [128, 128, 3];
[encoderNet, encoderOutputLayers] = ...
    pretrainedEncoderNetwork('resnet18', 4);
lgraph = unet(imageSize, numClasses, ...
    'EncoderNetwork', encoderNet, ...
    'EncoderDepth', 4);
plot(lgraph);

%% STEP 5: Training Options
options = trainingOptions('adam', ...
    'InitialLearnRate', 7e-4, ...
    'LearnRateSchedule', 'piecewise', ...
    'LearnRateDropFactor', 0.1, ...
    'LearnRateDropPeriod', 10, ...
    'MaxEpochs', 25, ...
    'MiniBatchSize', 32, ...
    'Shuffle', 'every-epoch', ...
    'ValidationData', cdsVal, ...
    'ValidationFrequency', 50, ...
    'VerboseFrequency', 50, ...
    'Plots', 'training-progress', ...
    'CheckpointPath', fullfile(pwd,'savingFolder'), ... 
    'CheckpointFrequency', 1, ...
    'ExecutionEnvironment', 'multi-gpu', ...
    'Metrics','accuracy'); % Save every epoch


%% STEP 6: Train the Network
% [net,trainInfo] = trainnet(cdsTrain, lgraph, ...
%     @(ypred,ytrue) lossFunction(ypred,ytrue,classWeights),options);
[net,trainInfo] = trainnet(cdsTrain, lgraph, ...
   "crossentropy",options);
    save(sprintf('myNet_%s', ...
        datetime('now',format='yyyy_MM_dd_HH_mm')), 'net');

%% STEP 7: Compute metrics and scores
pxdsResults = semanticseg(imdsTest,net,MinibatchSize=32,WriteLocation=tempdir, ...
    Classes=classNames);
metrics = evaluateSemanticSegmentation(pxdsResults,pxdsTest);
cm = confusionchart(metrics.ConfusionMatrix.Variables, ...
  classNames, Normalization='row-normalized');
cm.Title = 'Confusion Matrix';


%% Functions

function folderPath = downloadAndUnzipGoogleDrive(fileID, outputFolder)
%DOWNLOADANDUNZIPGOOGLEDRIVE Downloads and extracts a ZIP from Google Drive
%
% Inputs:
%   - fileID: Google Drive File ID (from share link)
%   - outputFolder: Destination folder (optional). Defaults to tempdir.
%
% Output:
%   - folderPath: Full path to the extracted folder

    if nargin < 2 || isempty(outputFolder)
        outputFolder = fullfile(tempdir, 'downloadedSpectrogramData');
    end

    % Create output folder if it doesn't exist
    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    % Construct download URL
    url = ['https://drive.google.com/uc?export=download&id=' fileID];

    % Set zip file path
    zipFile = fullfile(outputFolder, 'data.zip');

    % Download zip
    fprintf('Downloading from Google Drive...\n');
    outFile = websave(zipFile, url);

    % Unzip
    fprintf('Unzipping contents...\n');
    unzip(outFile, outputFolder);

    % Find the unzipped folder (first subfolder or use root)
    contents = dir(outputFolder);
    isDir = [contents.isdir];
    folderNames = contents(isDir);
    folderNames = folderNames(~ismember({folderNames.name}, {'.', '..'}));

    if isscalar(folderNames)
        folderPath = fullfile(outputFolder, folderNames(1).name);
    else
        folderPath = outputFolder;  % use root if no subfolder
    end

    fprintf('Data available in: %s\n', folderPath);
end

function [imdsTrain,pxdsTrain,imdsVal,pxdsVal,imdsTest,pxdsTest] = ...
  helperSpecSensePartitionData(imds,pxds,parts)
%  Borrowed from Mathwork's code
%   Copyright 2021-2023 The MathWorks, Inc.

validateattributes(parts,{'numeric'},{'size',[1 3]}, ...
  'helperSpecSensePartitionData','P',3)
assert(sum(parts)==100, 'Sum of parts must be 100')

% Set initial random state for example reproducibility.
s = RandStream('mt19937ar',Seed=0); 
numFiles = numel(imds.Files);
shuffledIndices = randperm(s,numFiles);

numTrain = floor(numFiles*parts(1)/100);
numVal = floor(numFiles*parts(2)/100);

imdsTrain = subset(imds, shuffledIndices(1:numTrain));
imdsVal = subset(imds, shuffledIndices(numTrain+(1:numVal)));
imdsTest = subset(imds, shuffledIndices(numTrain+numVal+1:end));

pxdsTrain = subset(pxds, shuffledIndices(1:numTrain));
pxdsVal = subset(pxds, shuffledIndices(numTrain+(1:numVal)));
pxdsTest = subset(pxds, shuffledIndices(numTrain+numVal+1:end));

end



function data = readMatFile(filename)
    % Load the .mat file
    matData = load(filename);
    
    % Extract your data - modify this based on your .mat file structure
    % Common variable names in .mat files:
    fieldNames = fieldnames(matData);
    % If there's only one variable, use it
    data = matData.(fieldNames{1});
end



function lossOut = lossFunction(ypred, ytrue, classWeights)
% Combina cross-entropy e Dice loss per segmentazione multiclass
% Ora con gestione NaN e ritorno di valori intermedi per debug

lossOut = struct(); % Struct to return everything for debugging

try
    % Convert ytrue to one-hot if not already [H W C N]
    numClasses = size(ypred, 3);
    ytrueOH = ytrue;

    % ---- Cross-Entropy Loss ----
    epsVal = 1e-8;
    ypredClipped = max(min(ypred, 1 - epsVal), epsVal); % Avoid log(0)
    ceLoss = -sum(ytrueOH .* log(ypredClipped), 3);     % [H W N]
    
    weightsPerPixel = sum(ytrueOH .* reshape(classWeights, 1, 1, []), 3); % [H W N]
    ceLoss = weightsPerPixel .* ceLoss;
    crossEntropy = mean(ceLoss(:));

    % ---- Dice Loss ----
    diceLoss = 0;
    dicePerClass = zeros(1, numClasses);
    for c = 1:numClasses
        ypredC = ypred(:,:,c,:);
        ytrueC = ytrueOH(:,:,c,:);
        
        intersection = sum(ypredC(:) .* ytrueC(:));
        denom = sum(ypredC(:)) + sum(ytrueC(:)) + epsVal;
        dice = 2 * intersection / denom;

        dicePerClass(c) = dice;
        diceLoss = diceLoss + (1 - dice); % Dice loss = 1 - Dice coefficient
    end
    diceLoss = diceLoss / numClasses;

    % ---- Combined Loss ----
    alpha = 1; % Set as needed
    loss = alpha * crossEntropy + (1 - alpha) * diceLoss;

    % ---- NaN Check ----
    if any(isnan([loss, crossEntropy, diceLoss]))
        warning('NaN detected in loss computation. Returning diagnostic output.');
    end

catch ME
    warning('Exception caught during loss computation: %s', ME.message);
    loss = NaN;
    crossEntropy = NaN;
    diceLoss = NaN;
    dicePerClass = NaN(1, numClasses);
end

% ---- Return Diagnostic Output ----
lossOut.loss = loss;
lossOut.crossEntropy = crossEntropy;
lossOut.diceLoss = diceLoss;
lossOut.dicePerClass = dicePerClass;
lossOut.ypred = ypred;
lossOut.ytrue = ytrue;
lossOut.ytrueOH = ytrueOH;
lossOut.classWeights = classWeights;
lossOut.weightsPerPixel = weightsPerPixel;
lossOut.ceLossMap = ceLoss;

end
