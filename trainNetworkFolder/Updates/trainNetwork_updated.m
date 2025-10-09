netChoice          = "deeplab";      % "unet" | "deeplab"
encoderChoice      = "resnet18";  % "resnet18" | "resnet50"
useAttentionGates  = true;        % true | false  (only used with UNet)

execEnv            = "multi-gpu"; % "gpu" | "multi-gpu" | "cpu" | "auto"

initialLearnRate   = 0.0008;
maxEpochs          = 25;
miniBatchSize      = 32;


checkpointDir      = fullfile(pwd, "checkpoints");
outputDir          = fullfile(pwd, "trainedNets");
if ~exist("checkpointDir", "dir")
    mkdir(checkpointDir);
end
if ~exist("outputDir", "dir")
     mkdir(outputDir);
end


close all; clc; clearvars -except netChoice encoderChoice useAttentionGates execEnv ...
                               initialLearnRate maxEpochs miniBatchSize ...
                               checkpointDir outputDir net;

% Loss choice: "crossentropy", "dice", "combo"
lossChoice         = "combo";

% **** DO NOT TOUCH THESE FIELDS! ****
numClasses  = 5;
classNames  = ["Unknown", "WLAN", "ZigBee", "Bluetooth", "SmartBAN"];
pixelLabelID = uint8([0 16 32 64 128]);   % values stored in .mat label masks


% Folder that contains PNG images and matching .mat masks (same filename)
dataFolder = fullfile("/home/ngallucci/polimi/SMARTBANPROJ/AICompetition/createDataset/trainingImages/256x256");
if ~exist(dataFolder, "dir")
    error("Folder does not exist. Be sure to have the folder with the dataset!");
end


% --- imageDatastore for PNG spectrograms
imds = imageDatastore(dataFolder, ...
    FileExtensions=".png", IncludeSubfolders=false);

% --- pixelLabelDatastore for bit‑mask labels stored as .mat files
matFiles  = dir(fullfile(dataFolder, "*.mat"));
matPaths  = fullfile({matFiles.folder}, {matFiles.name})';

pxds = pixelLabelDatastore(matPaths, ...
    classNames, pixelLabelID, ...
    ReadFcn=@readGroundTruthMatFile, ...
    FileExtensions=".mat");

% --- Combine (image, label) pairs into a single datastore for fast I/O
pximds = pixelLabelImageDatastore(imds, pxds);


[imdsTrain, pxdsTrain, imdsVal, pxdsVal, imdsTest, pxdsTest] = ...
    helperSpecSensePartitionData(imds, pxds, [70 10 20]);
cdsTrain = combine(imdsTrain, pxdsTrain);
cdsVal   = combine(imdsVal,   pxdsVal);
cdsTest  = combine(imdsTest,  pxdsTest);



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
    case "trained"
        load("myNet_2025_07_03_17_05.mat","net");
        lgraph = net;

    otherwise
        error("Unknown netChoice '%s'. Use 'unet' or 'deeplab'.", netChoice);
end



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




switch lower(lossChoice)
    case "crossentropy"
        [net, trainInfo] = trainnet(cdsTrain, lgraph, "crossentropy", options);
    case "dice"
        [net, trainInfo] = trainnet(cdsTrain, lgraph, @diceLossFcn, options);
    case "combo"
        [net, trainInfo] = trainnet(cdsTrain, lgraph, @comboLossFcn, options);
    otherwise
        error("Unknown lossChoice '%s'. Use 'crossentropy', 'dice', or 'combo'.", lossChoice);
end


timeTag = string(datetime("now"));
save(fullfile(outputDir, "net_" + timeTag +".mat"),       "net",       "-v7.3");
save(fullfile(outputDir, "trainInfo_" + timeTag + ".mat"), "trainInfo", "-v7.3");


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



%% helperSpecSensePartitionData : consistent 70/10/20 split ---------------
function [imdsTr, pxdsTr, imdsVa, pxdsVa, imdsTe, pxdsTe] = ...
        helperSpecSensePartitionData(imds, pxds, parts)
%  Borrowed from Mathwork's code
%   Copyright 2021-2023 The MathWorks, Inc.
% helperSpecSensePartitionData - Partition image and pixel label datastores into training, validation, and test sets.
%
% Syntax:
%   [imdsTr, pxdsTr, imdsVa, pxdsVa, imdsTe, pxdsTe] = ...
%       helperSpecSensePartitionData(imds, pxds, parts)
%
% Description:
%   This helper function randomly partitions a paired image datastore (`imds`) and
%   pixel label datastore (`pxds`) into training, validation, and test subsets
%   according to the specified percentage splits.
%
% Inputs:
%   imds   - ImageDatastore containing input images.
%   pxds   - PixelLabelDatastore containing corresponding pixel labels.
%   parts  - 1x3 numeric vector specifying [train, val, test] split percentages.
%            The values must sum to 100.
%
% Outputs:
%   imdsTr - ImageDatastore for training.
%   pxdsTr - PixelLabelDatastore for training.
%   imdsVa - ImageDatastore for validation.
%   pxdsVa - PixelLabelDatastore for validation.
%   imdsTe - ImageDatastore for testing.
%   pxdsTe - PixelLabelDatastore for testing.
%
% Notes:
%   - Random seed is fixed (rng(0)) for reproducibility.
%   - The number of images in each split is computed using `floor`, so the total
%     number of samples in the output may be slightly less than the original dataset.
%
% Example:
%   [imdsTr, pxdsTr, imdsVa, pxdsVa, imdsTe, pxdsTe] = ...
%       helperSpecSensePartitionData(imds, pxds, [70 15 15]);

    % parts = [train  val  test] as percentage (must sum to 100)
    validateattributes(parts, {'numeric'}, {'size', [1 3]});
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
% addAttentionGate - Inserts an additive attention gate into a U-Net skip connection.
%
% Syntax:
%   lgraph = addAttentionGate(lgraph, skipName, gateName, concatName, tag)
%
% Description:
%   This function implements an additive attention mechanism within a U-Net 
%   architecture by gating encoder skip connection features using decoder 
%   features. The attention gate helps suppress irrelevant features and enhance 
%   relevant ones before concatenation in the decoding path.
%
% Inputs:
%   lgraph      - A layerGraph object representing the current network.
%   skipName    - Name of the skip connection layer from the encoder path (key input).
%   gateName    - Name of the gating signal from the decoder path (query input).
%   concatName  - Name of the layer that concatenates the attention-modulated output.
%   tag         - A unique string identifier used to name layers within the gate.
%
% Output:
%   lgraph      - The updated layer graph with the attention gate added.
%
% Note:
%   The attention gate uses 1x1 convolutions to align feature dimensions, 
%   followed by addition, ReLU, and sigmoid activations to compute the attention 
%   coefficients. These coefficients are then multiplied element-wise with the 
%   skip connection features before being forwarded for concatenation.
    
    tag = string(tag);
    
    % --- Layers ----------------------------------------------------------
    layers = { ...
        convolution2dLayer(1, 64, 'Padding','same','Name',"q_"+tag) ...
        convolution2dLayer(1, 64, 'Padding','same','Name',"k_"+tag) ...
        additionLayer(2,  'Name', "add_"+tag) ...
        reluLayer('Name',"relu_"+tag) ...
        convolution2dLayer(1, 1,  'Padding','same','Name',"psi_"+tag) ...
        sigmoidLayer('Name',"sig_"+tag) ...
        multiplicationLayer(2, 'Name', "mul_"+tag) ...
        functionLayer(@(x)x, 'Name',"gateClone_"+tag) 
        };

    for i = 1:numel(layers)
        lgraph = addLayers(lgraph, layers{i});
    end


    % --- Wiring ----------------------------------------------------------


   % Step 1: Find and disconnect existing connections to concatName
    connections = lgraph.Connections;
    % Disconnect existing skip connection (in2)
    skipConnectionIdx = strcmp(connections.Destination, concatName + "/in2");
    if any(skipConnectionIdx)
        srcLayer = connections.Source{skipConnectionIdx};
        %lgraph = disconnectLayers(lgraph, srcLayer, concatName + "/in2");
    end
    
    % Disconnect existing gate connection (in1) and reconnect through clone
    gateConnectionIdx = strcmp(connections.Destination, concatName + "/in1");
    if any(gateConnectionIdx)
        srcLayer = connections.Source{gateConnectionIdx};
        lgraph = disconnectLayers(lgraph, srcLayer, concatName + "/in1");
        
        % Connect original gate source to clone, then clone to concat/in1
        lgraph = connectLayers(lgraph, srcLayer, "gateClone_" + tag);
        % lgraph = connectLayers(lgraph, "gateClone_" + tag, concatName + "/in1");
    end
    
    % Step 2: Create attention gate connections
    % Connect skip features to key convolution (k_)
    lgraph = connectLayers(lgraph, skipName, "k_" + tag);
    
    % Connect gate features to query convolution (q_) - use the clone to avoid cycles
    lgraph = connectLayers(lgraph, "gateClone_" + tag, "q_" + tag);
    
    % Connect query and key to addition layer
    lgraph = connectLayers(lgraph, "q_" + tag, "add_" + tag + "/in1");
    lgraph = connectLayers(lgraph, "k_" + tag, "add_" + tag + "/in2");
    
    % Connect the attention computation chain
    lgraph = connectLayers(lgraph, "add_" + tag, "relu_" + tag);
    lgraph = connectLayers(lgraph, "relu_" + tag, "psi_" + tag);
    lgraph = connectLayers(lgraph, "psi_" + tag, "sig_" + tag);
    
    % Connect skip features and attention weights to multiplication
    lgraph = connectLayers(lgraph, skipName, "mul_" + tag + "/in1");
    lgraph = connectLayers(lgraph, "sig_" + tag, "mul_" + tag + "/in2");
    
    % Step 3: Connect attention output to concatenation layer
    lgraph = connectLayers(lgraph, "mul_" + tag, concatName + "/in1");  
end
