%% -------------------------------------------------------------------------
%%  PRUNING AND QUANTIZATION FOR A RESNET‑50 WITH ATTENTION GATES
%% -------------------------------------------------------------------------
%  DESCRIPTION
%  -----------
%  End‑to‑end pipeline that takes an already‑trained ResNet‑50 + attention‑
%  gated U‑Net segmentation model and progressively:
%    1.  Evaluates its baseline performance.
%    2.  Converts it into a Taylor‑score *prunable* network.
%    3.  Iteratively prunes filters (channels) while fine‑tuning.
%    4.  Re‑trains the pruned network for a few epochs.
%    5.  Post‑training quantizes the re‑trained, pruned network.
%    6.  Compares memory footprint and segmentation accuracy at each stage.
%
%  HOW TO USE
%  ----------
%  • Place the trained network MAT‑file in the MATLAB path (variable
%    `trainedNet` below expects a field `net`).
%  • Edit `dataFolder` so it points to your spectrogram image + label mask
%    dataset (here 128×128 spectrogram crops with matching .mat masks).
%  • Make sure the helper function `helperSpecSensePartitionData`,
%  • Run the script.  It will save three networks:
%       • `dlnet_pruned.mat`            – pruned only
%       • `dlnet_pruned_retrained.mat`  – pruned + fine‑tuned
%       • in‑memory `quantizedNet`      – pruned, fine‑tuned, INT8‑quantized           
%    and print and save a summary table with memory/accuracy deltas.
%
%  NOTES
%  -----
%  • Requires R2024a or newer for `trainnet`, `dlquantizer`, and Taylor
%    pruning APIs.
%  • GPU recommended for Steps 5–10; CPU calibration (Step 11) targets
%    Raspberry Pi deployment (Arm Compute Library).
% -------------------------------------------------------------------------

%% STEP 1: Load the network ------------------------------------------------
trainedNet = load().net;                     % Pre‑trained dlnetwork object

%% STEP 2: Load the dataset ------------------------------------------------
numClasses = 5;                              % # segmentation classes
classes = ["Unknown","WLAN","ZigBee","Bluetooth","SmartBAN"];

pixelLabelID = uint8([0,16,32,64,128]);      % Pixel IDs in ground‑truth masks

dataFolder = fullfile(pwd,"CompleteFunctionContainer", ...
    "trainingImages_Nicola","128x128");     % Path to spectrogram crops

% Build list of .mat label files ------------------------------------------
matFiles = dir(fullfile(dataFolder,'*.mat')); % Locate all mask files
matPaths = fullfile({matFiles.folder},{matFiles.name})';

% Pixel label datastore reading each .mat mask via custom ReadFcn ---------
pxds = pixelLabelDatastore(matPaths,classes,pixelLabelID, ...
    ReadFcn=@readGroundTruthMatFile,FileExtensions=".mat");

%% STEP 3: Split into Train, Validation and Test ---------------------------
%   helperSpecSensePartitionData returns imageDatastore + pixelLabelDatastore
%   splits according to the percentage vector [train val test].
[imdsTrain,pxdsTrain,imdsVal,pxdsVal,imdsTest,pxdsTest] = ...
    helperSpecSensePartitionData(imds,pxds,[70 10 20]);

% Combine paired image/label datastores into a single datastore -----------
cdsTrain = combine(imdsTrain,pxdsTrain);
cdsVal   = combine(imdsVal,pxdsVal);
cdsTest  = combine(imdsTest,pxdsTest);

%% STEP 4: Baseline evaluation (no pruning or projection/ no quantization)-
trainedNetMetrics = evaluateNet(trainedNet,imdsTest,pxdsTest,classes);
trainedNetMetrics.DataSetMetrics               % Display baseline metrics

%% STEP 5: Create prunable wrapper ----------------------------------------
prunableNet = taylorPrunableNetwork(net);      % Wrap for Taylor pruning

% Hyper‑parameters for pruning -------------------------------------------
opts.MaxToPrune             = 16;   % Filters/channel per pruning iter
opts.MaxPruningIterations   = 30;   % Total pruning rounds
opts.MaxMinibatchIterations = 40;   % Fine‑tune batches per round
opts.ValidationFrequency    = 2;    % Validate every 2 rounds
opts.LearnRate              = 3e-4; % LR during pruning fine‑tune
opts.Momentum               = 0.9;  % SGDM momentum

miniBatchSize = 16;                    % Training batch size (GPU‑bound)

%% STEP 6: MiniBatchQueue for GPU training --------------------------------
mbqTrain = minibatchqueue(cdsTrain, ...
    MiniBatchSize      = miniBatchSize, ...
    MiniBatchFcn       = @(img,labels) deal(cat(4,img{:}),cat(4,labels{:})), ...
    OutputAsDlarray    = [1 1], ...    % Convert both outputs to dlarray
    MiniBatchFormat    = ["SSCB" "SSCB"], ...
    OutputEnvironment  = ["gpu" "gpu"]);  % Images & labels on GPU

%% STEP 7: Custom Taylor pruning loop -------------------------------------
%   pruneNetworkTaylor defined at bottom; returns pruned dlnetwork + logs
[prunableNet, logs] = pruneNetworkTaylor(prunableNet, mbqTrain, ...
    imdsVal, pxdsVal, classes, opts);

%% STEP 8: Save pruned network and evaluate --------------------------------
prunedNet = dlnetwork(prunableNet);            % Cast to plain dlnetwork
save("dlnet_pruned.mat","prunedNet");       % Persist to disk

prunedNetMetrics = evaluateNet(prunedNet,imdsTest,pxdsTest,classes);
prunedNetMetrics.DataSetMetrics              % Show post‑prune metrics

%% STEP 9: Fine‑tune the pruned network -----------------------------------
trainingOptions = trainingOptions("sgdm", ...
    InitialLearnRate     = 1e-4, ...          % Lower LR for fine‑tune
    Momentum             = 0.9, ...
    LearnRateSchedule    = "piecewise", ...   % Drop LR every 2 epochs
    LearnRateDropFactor  = 0.2, ...
    LearnRateDropPeriod  = 2, ...
    MiniBatchSize        = 16, ...
    MaxEpochs            = 8, ...             % Short fine‑tune
    Plots                = "training-progress", ...
    Shuffle              = "every-epoch", ...
    ValidationData       = cdsVal, ...
    ValidationFrequency  = 150, ...           % Validate every 150 iterations
    ExecutionEnvironment = "multi-gpu");      % Use all available GPUs

[prunedNetFinetuned, ~] = trainnet(cdsTrain, prunedNet, trainingOptions);
save("dlnet_pruned_retrained.mat","prunedNetFinetuned");

%% STEP 10: Evaluate fine‑tuned pruned network ----------------------------
prunedNetMetrics = evaluateNet(prunedNetFinetuned,imdsTest,pxdsTest,classes);
prunedNetMetrics.DataSetMetrics              % Show fine‑tuned metrics

% Compare original vs pruned ------------------------------------------------
statsProjected = compareNetworkMetrics(trainedNet,prunedNetFinetuned, ...
    trainedNetMetrics.DataSetMetrics.MeanAccuracy, ...
    prunedNetMetrics.DataSetMetrics.MeanAccuracy, "Pruned Network");

%% STEP 11: Projection network
[fineTunedProjectedNet,~] = projectionFunction(prunedNetFinetuned, mbqTrain, ...
    trainingOptions, cdsTrain);

%% STEP 12: Performance evaluation
projectedNetMetrics = evaluateNet(fineTunedProjectedNet,imdsTest,pxdsTest,classes);
projectedNetMetrics.DataSetMetrics              % Show fine‑tuned metrics

% Compare original vs pruned ------------------------------------------------
statsPruned = compareNetworkMetrics(trainedNet,fineTunedProjectedNet, ...
    trainedNetMetrics.DataSetMetrics.MeanAccuracy, ...
    projectedNetMetrics.DataSetMetrics.MeanAccuracy, "Projected Network");

%% STEP 13: Post‑projection quantization ------------------------------------
eqNet = equalizeLayers(fineTunedProjectedNet);          % (Optional) activation equal.
quantizableNet = dlquantizer(fineTunedProjectedNet,ExecutionEnvironment="CPU");
calibrate(quantizableNet,cdsTrain,MiniBatchSize=16);  % Collect ranges
quantizedNet = quantize(quantizableNet,ExponentScheme="Histogram"); % INT8

%% STEP 14: Evaluate quantized network ------------------------------------
quantizedNetMetrics = evaluateNet(quantizedNet,imdsTest,pxdsTest,classes);
quantizedNetMetrics.DataSetMetrics          % Show INT8 metrics

% Compare original vs quantized -------------------------------------------
statsQuantized = compareNetworkMetrics(trainedNet,quantizedNet, ...
    trainedNetMetrics.DataSetMetrics.MeanAccuracy, ...
    quantizedNetMetrics.DataSetMetrics.MeanAccuracy, "Quantized Network");

%% STEP 15: Summary table --------------------------------------------------
[statsPruned(1:2,:); statsProjected(1:2, :);statsQuantized(2,:)]   % Display combined summary
% ── Save all tables in the same MAT‑file
save("statsComparison.mat","statsPruned", "statsProjected","statsQuantized");

%% STEP 16: Plotting

iouOriginal = trainedNetMetrics.DataSetMetrics.MeanIoU;
iouPruned   = prunedNetMetrics.DataSetMetrics.MeanIoU;
iouProject  = projectedNetMetrics.DataSetMetrics.MeanIoU;
iouQuant    = quantizedNetMetrics.DataSetMetrics.MeanIoU;

figure
tiledlayout("flow")

nexttile
bar([iouOriginal iouPruned iouProject iouQuant])
xticklabels(["Original" "Pruned" "Projected" "Quantized"])
ylabel("Mean IoU")
title("Mean IoU")

nexttile
bar([numLearnables(trainedNet) numLearnables(fineTunedProjectedNet) ...
    numLearnables(fineTunedProjectedNet) numLearnables(quantizedNet)])
xticklabels(["Original" "Pruned" "Projected" "Quantized"])
ylabel("Number of Learnables")
title("Number of Learnables")


%% -------------------------------------------------------------------------
%% HELPER FUNCTIONS 
%% -------------------------------------------------------------------------

function data = readGroundTruthMatFile(filename)
    % READGROUNDTRUTHMATFILE  Custom reader for .mat pixel‑label masks.
    %   The function loads a .mat file and returns the first variable
    %   contained in it, assuming the mask is stored as a uint8 matrix.
    
    matData = load(filename);              % Load entire MAT file
    fieldNames = fieldnames(matData);      % Extract variable names
    data = matData.(fieldNames{1});        % Return first variable
end

function ssm = evaluateNet(net,imds,pxdsTruth,classNames,itr)
    % EVALUATENET  Runs semanticseg on imds with 'net' and computes metrics.
    %   Optionally provides unique temporary folder per iteration (itr)

    dirname = tempdir;                     % Default temp folder
    if nargin==5
       dirname = dirname + "val_" + num2str(itr);
       mkdir(dirname);
    end   
    
    % Generate segmentation predictions and save temporary results
    pxdsResults = semanticseg(imds,net, ...
        WriteLocation=dirname, ...
        Classes=classNames, ...
        Verbose=false, ...
        MinibatchSize=8);

    % Compute standard segmentation metrics (mIoU, etc.)
    ssm = evaluateSemanticSegmentation(pxdsResults,pxdsTruth,Verbose=false);
end

function statistics = compareNetworkMetrics(originalNet,compressedNet, ...
    orginalNetAccuracy,compressedNetAccuracy,compressedNetName)
% COMPARENETWORKMETRICS  Build a summary table comparing two networks.
%   Reports learnables, parameter memory and mean accuracy for 3 rows:
%   "Original", custom name (e.g., "Pruned Network"), and % change.

% Estimate FLOPs/learnables for both networks -----------------------------
originalNetMetrics = estimateNetworkMetrics(originalNet);
prunedNetMetrics   = estimateNetworkMetrics(compressedNet);

% Accuracy -----------------------------------------------------------------
perChangeAccu = 100*(compressedNetAccuracy - orginalNetAccuracy)/orginalNetAccuracy;
accuracyForNetworks = [orginalNetAccuracy;compressedNetAccuracy;perChangeAccu];

% Learnables ---------------------------------------------------------------
originalNetLearnables = sum(originalNetMetrics( : ,"NumberOfLearnables").NumberOfLearnables);
prunedNetLearnables   = sum(prunedNetMetrics( : ,"NumberOfLearnables").NumberOfLearnables);
percentageChangeLearnables = 100*(prunedNetLearnables - originalNetLearnables)/originalNetLearnables;
learnablesForNetwork = [originalNetLearnables;prunedNetLearnables;percentageChangeLearnables];

% Parameter memory (MB) ----------------------------------------------------
approxOriginalMemory = sum(originalNetMetrics( : ,"ParameterMemory (MB)").("ParameterMemory (MB)"));
approxPrunedMemory   = sum(prunedNetMetrics( : ,"ParameterMemory (MB)").("ParameterMemory (MB)"));
percentageChangeMemory = 100*(approxPrunedMemory - approxOriginalMemory)/approxOriginalMemory;
networkMemory = [approxOriginalMemory; approxPrunedMemory; percentageChangeMemory];

% Build summary table ------------------------------------------------------
statistics = table(learnablesForNetwork,networkMemory,accuracyForNetworks, ...
    VariableNames=["Network Learnables","Approx. Network Memory (MB)","MeanAccuracy"], ...
    RowNames=["Original Network",compressedNetName,"Percentage Change"]);
end

function [prunableNet, logs] = pruneNetworkTaylor(prunableNet, mbqTrain, ...
    imdsVal, pxdsVal, classes, opts)
% PRUNENETWORKTAYLOR  Taylor‑criterion iterative filter pruning.
%   Returns pruned network + logs of loss/IoU/remaining channels.

    % Initialise bookkeeping ---------------------------------------------------
    pruningIteration = 0;              % External pruning‑round counter
    velocity         = [];             % SGDM momentum buffer
    
    logs.MeanLoss     = zeros(opts.MaxPruningIterations,1);
    logs.WeightedIoU  = zeros(opts.MaxPruningIterations,1);
    logs.NumPrunables = zeros(opts.MaxPruningIterations,1);
    
    monitor = trainingProgressMonitor( ...
        Metrics=["Loss","WeightedIoU","NumPrunables"], ...
        Info="Iteration",XLabel="Pruning Iteration");
    
    % Baseline validation ------------------------------------------------------
    metrics = evaluateNet(prunableNet, imdsVal, pxdsVal, classes);
    disp("Initial IoU (unpruned): " + metrics.DataSetMetrics.WeightedIoU);
    
    % === Main pruning loop ====================================================
    while (prunableNet.NumPrunables > opts.MaxToPrune) && ...
          (pruningIteration < opts.MaxPruningIterations)
    
        pruningIteration = pruningIteration + 1;
        disp("=== Pruning iteration " + pruningIteration + " ===");
    
        reset(mbqTrain);               % Rewind minibatchqueue
        shuffle(mbqTrain);             % Shuffle training order each round
    
        totalLoss  = 0;                % Accumulator for mean loss
        batchCount = 0;                % Mini‑batch counter (per round)
    
        % -- Inner fine‑tuning loop -------------------------------------------
        while hasdata(mbqTrain)
            [dlX, dlY] = next(mbqTrain);               % Fetch next batch
    
            % Forward + backward (dlfeval for dynamic graph) ------------------
            [grads, dGating, gatingOuts, state, loss] = ...
                dlfeval(@modelGradients, prunableNet, dlX, dlY, classes);
            prunableNet.State = state;                 % Update layer states
    
            % SGDM parameter update -------------------------------------------
            [prunableNet, velocity] = sgdmupdate( ...
                prunableNet, grads, velocity, opts.LearnRate, opts.Momentum);
    
            % Accumulate Taylor scores for each gating layer ------------------
            prunableNet = updateScore(prunableNet, dGating, gatingOuts);
    
            % Track loss to compute mean later --------------------------------
            totalLoss  = totalLoss + double(gather(extractdata(loss)));
            batchCount = batchCount + 1;
    
            % Stop inner loop if we hit per‑round budget ----------------------
            if batchCount >= opts.MaxMinibatchIterations
                break;
            end
        end
    
        % -- Prune lowest‑score channels network‑wide -------------------------
        prunableNet = updatePrunables(prunableNet, MaxToPrune=opts.MaxToPrune);
    
        % -- Periodic validation ----------------------------------------------
        if mod(pruningIteration, opts.ValidationFrequency) == 0 || pruningIteration == 1
            metrics = evaluateNet(prunableNet, imdsVal, pxdsVal, classes);
            currentIoU = metrics.DataSetMetrics.WeightedIoU;
        else
            currentIoU = NaN;  % Skip this round
        end
    
        % -- Logging -----------------------------------------------------------
        avgLoss = totalLoss / batchCount;           % Mean training loss
        logs.MeanLoss(pruningIteration)     = avgLoss;
        logs.WeightedIoU(pruningIteration)  = currentIoU;
        logs.NumPrunables(pruningIteration) = prunableNet.NumPrunables;
    
        recordMetrics(monitor, pruningIteration,Loss=avgLoss, ...
            WeightedIoU=currentIoU,NumPrunables=prunableNet.NumPrunables);
        updateInfo(monitor,Iteration=pruningIteration);
    end
end

function [dLossdLearnables, pruningGradient, pruningActivations, state, loss] = ...
    modelGradients(networkPruner, dlX, Y, classNames)
% MODELGRADIENTS  Compute SGDM gradients + Taylor pruning gradients.

% Forward pass -------------------------------------------------------------
[networkOut, state, pruningActivations] = forward(networkPruner, dlX);

% One‑hot encode target labels --------------------------------------------
if isa(Y,'gpuArray'); Y = gather(Y); end           % onehotencode needs CPU
Y = onehotencode(Y,3,'ClassNames',classNames);     % Shape: H×W×C×B
Y(isnan(Y)) = 0;                                   % Ignore class → 0
Y = dlarray(Y,'SSCB');                             % Label format

% Cross entropy (normalised per‑pixel) ------------------------------------
sz = size(networkOut);                             % [H W C B]
numPixels = prod(sz(1:2)) * sz(4);
loss = crossentropy(networkOut,Y) / numPixels;

% Backward: grads w.r.t. learnables + gating activations -------------------
[dLossdLearnables, pruningGradient] = dlgradient(loss, ...
    networkPruner.Learnables, pruningActivations);
end


function N = numLearnables(net)
    N = 0;
    for i = 1:size(net.Learnables,1)
        N = N + numel(net.Learnables.Value{i});
    end
end