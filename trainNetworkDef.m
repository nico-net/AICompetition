% Spectrogram Segmentation using U‑Net / DeepLab with optional Attention Gates
% -------------------------------------------------------------------------
% This fully‑commented script trains a semantic‑segmentation network that
% classifies 256×256 RGB spectrogram tiles into 5 classes:
%   0 – Unknown (noise / AWGN)
%  16 – WLAN
%  32 – ZigBee
%  64 – Bluetooth
% 128 – SmartBAN
% 
% KEY FEATURES
%   • Plug‑and‑play choice of network architecture:
%       - UNet (default) with a ResNet‑18 or ResNet‑50 encoder
%       - DeepLab v3+ with a ResNet‑18 or ResNet‑50 encoder
%   • Optional additive Attention Gates on the UNet skip connections
%   • Simple switch of training environment: GPU / multi‑GPU / CPU / auto
%   • Weighted cross‑entropy + Dice loss (configurable)
%   • Checkpointing and automatic time‑stamped exports of nets & logs
% 
% -------------------------------------------------------------------------
% CONFIGURATION BLOCK –‑–– edit only this section –‑––
% -------------------------------------------------------------------------
netChoice          = "unet";      % "unet" | "deeplab"
encoderChoice      = "resnet18";  % "resnet18" | "resnet50"
useAttentionGates  = true;        % true | false  (only used with UNet)

execEnv            = "multi-gpu"; % "gpu" | "multi-gpu" | "cpu" | "auto"

initialLearnRate   = 8e-4;
maxEpochs          = 25;
miniBatchSize      = 32;

checkpointDir      = fullfile(pwd, "checkpoints");
outputDir          = fullfile(pwd, "trainedNets");
mkdir(checkpointDir); mkdir(outputDir);
% -------------------------------------------------------------------------

%% 0. House‑keeping
close all; clc; clearvars -except netChoice encoderChoice useAttentionGates execEnv ...
                               initialLearnRate maxEpochs miniBatchSize ...
                               checkpointDir outputDir;

%% 1. Dataset definition ---------------------------------------------------
numClasses  = 5;
classNames  = ["Unknown", "WLAN", "ZigBee", "Bluetooth", "SmartBAN"];
pixelLabelID = uint8([0 16 32 64 128]);   % values stored in .mat label masks

% Folder that contains PNG images and matching .mat masks (same filename)
dataFolder = fullfile(pwd, "NicolasTears", "MixedDatasetOfNoisyInterf");

% --- imageDatastore for PNG spectrograms
imds = imageDatastore(dataFolder, ...
    FileExtensions={".png"}, IncludeSubfolders=false);

% --- pixelLabelDatastore for bit‑mask labels stored as .mat files
matFiles  = dir(fullfile(dataFolder, "*.mat"));
matPaths  = fullfile({matFiles.folder}, {matFiles.name})';

pxds = pixelLabelDatastore(matPaths, ...
    classNames, pixelLabelID, ...
    ReadFcn=@readGroundTruthMatFile, ...
    FileExtensions=".mat");

% --- Combine (image, label) pairs into a single datastore for fast I/O
pximds = pixelLabelImageDatastore(imds, pxds);

%% 2. Train / Val / Test split -------------------------------------------
[imdsTrain, pxdsTrain, imdsVal, pxdsVal, imdsTest, pxdsTest] = ...
    helperSpecSensePartitionData(imds, pxds, [70 10 20]);
cdsTrain = combine(imdsTrain, pxdsTrain);
cdsVal   = combine(imdsVal,   pxdsVal);
cdsTest  = combine(imdsTest,  pxdsTest);

%% 3. Class‑imbalance handling --------------------------------------------
labelTbl      = countEachLabel(pxdsTrain);
labelFreq     = labelTbl.PixelCount / sum(labelTbl.PixelCount);
classWeights  = median(labelFreq) ./ labelFreq;  % ↑ weight rare classes

%% 4. Network construction -------------------------------------------------
inputSize = [256 256 3];   % spectrogram tile size

switch lower(netChoice)
    case "unet"
        % --- Build UNet backbone with selected ResNet encoder
        [encNet, ~] = pretrainedEncoderNetwork(encoderChoice, 4);
        lgraph = unet(inputSize, numClasses, ...
            "EncoderNetwork",  encNet, ...
            "EncoderDepth",    4);

        % Optionally enhance skip connections with Attention Gates
        if useAttentionGates
            skipLayers   = ["encoderDecoderSkipConnectionCrop4", ...
                           "encoderDecoderSkipConnectionCrop3", ...
                           "encoderDecoderSkipConnectionCrop2", ...
                           "encoderDecoderSkipConnectionCrop1"];
            gateLayers   = ["Decoder-Stage-4-UpConv", ...
                           "Decoder-Stage-3-UpConv", ...
                           "Decoder-Stage-2-UpConv", ...
                           "Decoder-Stage-1-UpConv"];
            concatLayers = ["encoderDecoderSkipConnectionFeatureMerge4", ...
                           "encoderDecoderSkipConnectionFeatureMerge3", ...
                           "encoderDecoderSkipConnectionFeatureMerge2", ...
                           "encoderDecoderSkipConnectionFeatureMerge1"];
            for i = 1:numel(skipLayers)
                lgraph = addAttentionGate(lgraph, skipLayers(i), gateLayers(i), ...
                                           concatLayers(i), "att"+i);
            end
        end

    case "deeplab"
        % --- DeepLab v3+ with selectable encoder
        lgraph = deeplabv3plus(inputSize, numClasses, encoderChoice);
        % (DeepLab already uses an ASPP head; attention gates optional here)

    otherwise
        error("Unknown netChoice '%s'. Use 'unet' or 'deeplab'.", netChoice);
end

% Optional sanity plot
% figure; plot(lgraph); title('Network Architecture');

%% 5. Training options -----------------------------------------------------
options = trainingOptions("adam", ...
    InitialLearnRate      = initialLearnRate, ...
    LearnRateSchedule     = "piecewise", ...
    LearnRateDropFactor   = 0.1, ...
    LearnRateDropPeriod   = 10, ...
    MaxEpochs             = maxEpochs, ...
    MiniBatchSize         = miniBatchSize, ...
    Shuffle               = "every-epoch", ...
    ValidationData        = cdsVal, ...
    ValidationFrequency   = 50, ...
    VerboseFrequency      = 50, ...
    Plots                 = "training-progress", ...
    CheckpointPath        = checkpointDir, ...
    CheckpointFrequency   = 1, ...
    ExecutionEnvironment  = execEnv);

%% 6. Train the network ----------------------------------------------------
[net, trainInfo] = trainnet(cdsTrain, lgraph, "crossentropy", options);

timeTag = datetime("now", "yyyy_mm_dd_HH_MM_SS");
save(fullfile(outputDir, "net_"+timeTag+".mat"),       "net",       "-v7.3");
save(fullfile(outputDir, "trainInfo_"+timeTag+".mat"), "trainInfo", "-v7.3");

%% 7. Evaluation -----------------------------------------------------------
pxdsResults = semanticseg(imdsTest, net, ...
    MinibatchSize = miniBatchSize, ...
    WriteLocation = tempdir, ...
    Classes       = classNames);

metrics = evaluateSemanticSegmentation(pxdsResults, pxdsTest);
figure; confusionchart(metrics.ConfusionMatrix.Variables, classNames, ...
    Normalization="row-normalized", ...
    Title="Confusion Matrix – Test Set");

disp(metrics.DataSetMetrics);

disp("\n**************** Training & Evaluation complete ****************");



%% ------------------------------------------------------------------------
% LOCAL FUNCTIONS ----------------------------------------------------------
%% helperSpecSensePartitionData : consistent 70/10/20 split ---------------
function [imdsTr, pxdsTr, imdsVa, pxdsVa, imdsTe, pxdsTe] = ...
        helperSpecSensePartitionData(imds, pxds, parts)
%  Borrowed from Mathwork's code
%   Copyright 2021-2023 The MathWorks, Inc.

    % parts = [train  val  test] as percentage (must sum to 100)
    validateattributes(parts, {"numeric"}, {"size", [1 3]});
    assert(sum(parts)==100, "Sum of parts must be 100");

    rng(0);                 % reproducibility
    numFiles = numel(imds.Files);
    idx      = randperm(numFiles);

    nTrain   = floor(numFiles*parts(1)/100);
    nVal     = floor(numFiles*parts(2)/100);

    imdsTr = subset(imds, idx(1:nTrain));
    imdsVa = subset(imds, idx(nTrain+(1:nVal)));
    imdsTe = subset(imds, idx(nTrain+nVal+1:end));

    pxdsTr = subset(pxds, idx(1:nTrain));
    pxdsVa = subset(pxds, idx(nTrain+(1:nVal)));
    pxdsTe = subset(pxds, idx(nTrain+nVal+1:end));
end

%% readGroundTruthMatFile : parses bitmask matrices -----------------------
function mask = readGroundTruthMatFile(filename)
    % Assumes each .mat file has exactly one variable holding the mask
    data   = load(filename);
    fields = fieldnames(data);
    mask   = data.(fields{1});
    % Cast to uint8 if needed
    if ~isa(mask, "uint8"); mask = uint8(mask); end
end


%% addAttentionGate : plug‑and‑play UNet attention ------------------------
function lgraph = addAttentionGate(lgraph, skipName, gateName, concatName, tag)
    % Build additive attention gating for UNet skip‑connection
    tag = string(tag);

    % --- Layers ----------------------------------------------------------
    layers = [ ...
        convolution2dLayer(1, 64, Padding="same",      Name="q_"+tag) ...
        convolution2dLayer(1, 64, Padding="same",      Name="k_"+tag) ...
        additionLayer(2,   Name="add_"+tag) ...
        reluLayer(Name="relu_"+tag) ...
        convolution2dLayer(1, 1,  Padding="same",      Name="psi_"+tag) ...
        sigmoidLayer(Name="sig_"+tag) ...
        multiplicationLayer(2, Name="mul_"+tag) ...
        functionLayer(@(x)x, Name="gateClone_"+tag) ];

    lgraph = addLayers(lgraph, layers);

    % --- Wiring ----------------------------------------------------------
    % 1) Route encoder skip features (keys) and decoder up‑sampled features (queries)
    lgraph = connectLayers(lgraph, skipName,              "k_"+tag);
    lgraph = connectLayers(lgraph, gateName,              "gateClone_"+tag);
    lgraph = connectLayers(lgraph, "gateClone_"+tag,      "q_"+tag);

    % 2) Key + Query → Attention weights
    lgraph = connectLayers(lgraph, "q_"+tag,              "add_"+tag+"/in1");
    lgraph = connectLayers(lgraph, "k_"+tag,              "add_"+tag+"/in2");
    lgraph = connectLayers(lgraph, "add_"+tag,            "relu_"+tag);
    lgraph = connectLayers(lgraph, "relu_"+tag,           "psi_"+tag);
    lgraph = connectLayers(lgraph, "psi_"+tag,            "sig_"+tag);

    % 3) Multiply skip features by attention map, push to concat
    lgraph = connectLayers(lgraph, skipName,              "mul_"+tag+"/in1");
    lgraph = connectLayers(lgraph, "sig_"+tag,            "mul_"+tag+"/in2");
    lgraph = connectLayers(lgraph, "mul_"+tag,            concatName+"/in1");
end
