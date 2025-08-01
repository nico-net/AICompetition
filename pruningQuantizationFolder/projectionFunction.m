function [fineTunedProjectedNet, info] = projectionFunction( ...
        net, mbqTrain, trainingOptions, cdsTrain)
%PROJECTIONFUNCTION Compresses a neural network with neuron‑PCA
% and fine‑tunes it.
%
%   [fineTunedProjectedNet, info] = projectionFunction(net, mbqTrain, ...
%           trainingOptions, cdsTest)
%
%   INPUTS
%     net             – A trained dlnetwork or LayerGraph to compress.
%     mbqTrain        – minibatchqueue of training data used by neuronPCA
%                       to build principal components.
%     trainingOptions – trainingOptions object for fine‑tuning.
%     cdsTest         – Datastore passed to TRAINNET for fine‑tuning
%                       (double‑check that this is really your **training**
%                       set; otherwise rename to cdsTrain).
%
%   OUTPUTS
%     fineTunedProjectedNet – The compressed network after fine‑tuning.
%     info                  – Training metadata returned by TRAINNET.
%
%   Workflow:
%     1. Run neuronPCA to compute principal directions.
%     2. Project the network, reducing learnable parameters.
%     3. Fine‑tune the projected network.
%     4. Save the final network to disk.

    % ----- 1. Compute neuron PCA ------------------------------------------
    % npca stores PCA directions for each compressible layer.
    % VerbosityLevel="steps" shows progress layer by layer.
    npca = neuronPCA(net, mbqTrain, VerbosityLevel="steps");

    % ----- 2. Project the network, reducing learnables by 60 % ------------
    [netProjected, infoProjection] = compressNetworkUsingProjection( ...
        net, npca, LearnablesReduction = 0.6, VerbosityLevel = "summary");

    % Display the actual reduction in learnable parameters
    disp("Actual LearnablesReduction: " + infoProjection.LearnablesReduction);

    % ----- 3. Fine‑tune the projected network -----------------------------
    % WARNING: You’re training here, so cdsTest must contain *training* data.
    [fineTunedProjectedNet, info] = trainnet( ...
        cdsTrain, netProjected, "crossentropy", trainingOptions);

    % ----- 4. Save the fine‑tuned network ---------------------------------
    save("dlnet_projected_retrained.mat", "fineTunedProjectedNet");
end
