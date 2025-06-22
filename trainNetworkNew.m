%% Spectrogram Segmentation using U-Net with ResNet34 Encoder
clear; close all;clc;

numClasses = 6;
classNames = [ ...
    "AWGN", "WLAN", "ZigBee","Bluetooth", "SmartBAN", "Unknown"];

pixelLabelID = uint8([0, 16, 32, 64, 128, 255]);

% Set your folder path
dataFolder = fullfile(pwd,"CompleteFunctionContainer/trainingImages_Nicola/128x128");


%% STEP 1: Create Images Datastore
%imds = imageDatastore(dataFolder, 'FileExtensions', {'.png'}, 'IncludeSubfolders', false);
fds = fileDatastore(dataFolder, ...
    'ReadFcn', @(x) loadPnormMat(x), ...
    'FileExtensions', '.mat', ...
    'IncludeSubfolders', false);

%% STEP 2: Create Custom Label Datastore for .mat Bitmask Files
matFiles = dir(fullfile(dataFolder, '*.mat'));
matPaths = fullfile({matFiles.folder}, {matFiles.name})';

pxds = pixelLabelDatastore(matPaths, ...
    classNames, pixelLabelID, ...
    ReadFcn=@readGroundTruthMatFile,...
    FileExtensions=".mat");

% Combine into pixelLabelImageDatastore
%pximds = pixelLabelImageDatastore(imds, pxds);
cds = combine(fds, pxds);


%% STEP 3: Evaluate Class Imbalances
tbl = countEachLabel(pxds); % pxds: pixelLabelDatastore
imageFreq = tbl.PixelCount ./ tbl.ImagePixelCount;
imageFreq(isnan(imageFreq)) = [];
classWeights = median(imageFreq) ./ imageFreq;
classWeights = classWeights/(sum(classWeights)+eps(class(classWeights)));
if length(classWeights) < numClasses
    classWeights = [classWeights; zeros(numClasses-length(classWeights),1)];
end


%% STEP 4: Split into Train, Validation and Test
[imdsTrain,pxdsTrain,imdsVal,pxdsVal,imdsTest,pxdsTest] = ...
  helperSpecSensePartitionData(fds,pxds,[70 10 20]);
cdsTrain = combine(imdsTrain,pxdsTrain);
cdsVal = combine(imdsVal,pxdsVal);
cdsTest = combine(imdsTest,pxdsTest);

%% STEP 5: Define U-Net Network with ResNet34 Encoder
inputSize = [256, 256, 3];
[encoderNet, encoderOutputLayers] = ...
    pretrainedEncoderNetwork('resnet18', 4);
lgraph = unet(inputSize, numClasses, ...
    'EncoderNetwork', encoderNet, ...
    'EncoderDepth', 4);
%plot(lgraph);

%% STEP 6: Training Options
options = trainingOptions('adam', ...
    'InitialLearnRate', 8e-4, ...
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


%% STEP 7: Train the Network
[net,trainInfo] = trainnet(cdsTrain, lgraph, ...
    @(ypred,ytrue) lossFunction(ypred,ytrue,classWeights),options);
% [net,trainInfo] = trainnet(cdsTrain, lgraph, ...
%    "crossentropy",options);
    save(sprintf('myNet_%s', ...
        datetime('now',format='yyyy_MM_dd_HH_mm')), 'net');
    save("imdsTest", 'imdsTest');
    save("pxdsTest", 'pxdsTest');
    
%% STEP 8: Compute metrics and scores
pxdsResults = semanticseg(imdsTest,net,MinibatchSize=32,WriteLocation=tempdir, ...
    Classes=classNames);
metrics = evaluateSemanticSegmentation(pxdsResults,pxdsTest);
cm = confusionchart(metrics.ConfusionMatrix.Variables, ...
  classNames, Normalization='row-normalized');
cm.Title = 'Confusion Matrix';


%% Functions
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


function imgOut = loadPnormMat(filename)
% LOADPNORMMAT Loads the P_norm matrix from a .mat file
%
%   data = loadPnormMat(filename) loads the variable 'P_norm' stored in the
%   .mat file specified by filename and returns it as a matrix repeated on
%   the third dimension to adapt it to the resnet.
%
%   Input:
%       filename - string, path to the .mat file
%
%   Output:
%       imgOut     - matrix (e.g., 256x256x3) containing P_norm values

    tmp = load(filename);
    data = tmp.P_norm; 
    imgOut = repmat(data, [1, 1, 3]);    % {size}x3
end


function data = readGroundTruthMatFile(filename)
    % Load the .mat file
    matData = load(filename);
    
    % Extract your data - modify this based on your .mat file structure
    % Common variable names in .mat files:
    fieldNames = fieldnames(matData);
    % If there's only one variable, use it
    data = matData.(fieldNames{1});
end



function loss = lossFunction(ypred, ytrue, classWeights, useDice)
% LOSSFUNCTION Computes weighted cross-entropy loss, optionally combined with Dice loss
%
%   loss = lossFunction(ypred, ytrue, classWeights, useDice)
%
%   Inputs:
%     ypred        - Predicted probabilities [H W C N], values in [0,1]
%     ytrue        - Ground truth one-hot labels [H W C N]
%     classWeights - Vector of class weights [C x 1]
%     useDice      - (optional) boolean, whether to include Dice loss (default = true)
%
%   Output:
%     loss - Combined scalar loss

    if nargin < 4
        useDice = true;
    end

    numClasses = size(ypred, 3);
    epsVal = 1e-8;

    % --- Weighted Cross-Entropy Loss ---
    ypredClipped = max(min(ypred, 1 - epsVal), epsVal);
    ceLoss = -sum(ytrue .* log(ypredClipped), 3);               % [H W N]
    weightsPerPixel = sum(ytrue .* reshape(classWeights, 1, 1, []), 3);  % [H W N]
    ceLossWeighted = weightsPerPixel .* ceLoss;
    crossEntropy = mean(ceLossWeighted(:));

    % --- Dice Loss (optional) ---
    if useDice
        diceLoss = 0;
        for c = 1:numClasses
            ypredC = ypred(:,:,c,:);
            ytrueC = ytrue(:,:,c,:);
            intersection = sum(ypredC(:) .* ytrueC(:));
            denom = sum(ypredC(:)) + sum(ytrueC(:)) + epsVal;
            dice = 2 * intersection / denom;
            diceLoss = diceLoss + (1 - dice);  % Dice loss = 1 - Dice coefficient
        end
        diceLoss = diceLoss / numClasses;
    else
        diceLoss = 0;
    end

    % --- Final Loss ---
    alpha = 0.7 ; % Set to <1 if you want to include Dice loss
    loss = alpha * crossEntropy + (1 - alpha) * diceLoss;
end
