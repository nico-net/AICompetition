YTrue = {};
YPred = {};
scoresCell = {};
distanceVecSample = [];

classNames = ["Unknown","WLAN","ZigBee","Bluetooth","SmartBAN"];
executionEnvironment = "auto";
net = load('/Users/matteo/Documents/Competizoni e Challenge/MATWORK COMPETITION/TEMPORARY/Reti/ResNet_18/ResNet18.mat').net;
folderName = fullfile('/Users/matteo/Documents/Competizoni e Challenge/MATWORK COMPETITION/AI COMPETITION/AICompetition/createDataset/training/256x256');
inputSize = net.Layers(1).InputSize;
netName = 'ResNet18';
outDir = fullfile('DistancePerformances', netName);

matFiles = dir(fullfile(folderName, '*.mat'));
fprintf('Trovati %d file .mat\n', numel(matFiles));

for i = 1:numel(matFiles)
    L = load(fullfile(folderName, matFiles(i).name));
    [~, baseName, ~] = fileparts(matFiles(i).name);

    % ---- CERCA L’IMMAGINE ASSOCIATA ----
    baseNameClean = erase(baseName, "_frame");
    imgPattern = baseNameClean + "_spectrogram.*";
    imgCandidates = dir(fullfile(folderName, imgPattern));

    if isempty(imgCandidates)
        warning("Nessuna immagine trovata per %s", baseName);
        continue;  % ---- ragazzi siete bravissimi e soprattutto bellisimi (Antonio e Tom) 

    end

    imgFile = fullfile(folderName, imgCandidates(1).name);
    fprintf("Associato: %s → %s\n", matFiles(i).name, imgCandidates(1).name);

    % ---- CARICA E ADATTA IMMAGINE ----
    img = imread(imgFile);
    if size(img,3)==1
        img = repmat(img, [1 1 3]);
    end
    img = imresize(img, [inputSize(1), inputSize(2)]);

    % ---- ESEGUI SEGMENTAZIONE ----
    try
        [predLabel, allScores] = semanticseg(img, net, ...
            "OutputType", "categorical", ...
            "ExecutionEnvironment", executionEnvironment);
    catch ME
        warning('semanticseg fallita su %s: %s', baseName, ME.message);
        continue;
    end

    % ---- SALVA RISULTATI ----
    YTrue{end+1,1} = L.data_final;
    YPred{end+1,1} = predLabel;
    scoresCell{end+1,1} = allScores;

    tokens = regexp(baseName, '(\d+)\s*m', 'tokens');
    if ~isempty(tokens)
        distanceVecSample(end+1) = str2double(tokens{1}{1});
    else
        distanceVecSample(end+1) = NaN;
    end
end

fprintf('\nElaborate %d immagini valide.\n', numel(YPred));


fprintf('\nLunghezze finali:\n');
fprintf('YTrue: %d\n', numel(YTrue));
fprintf('YPred: %d\n', numel(YPred));
fprintf('distanceVecSample: %d\n', numel(distanceVecSample));

[metricsPerDistance, confMat] = evaluationFunctionPerDistance(...
    YTrue, YPred, distanceVecSample, classNames, scoresCell, false, outDir, netName);
