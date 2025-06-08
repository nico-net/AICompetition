
function helperVisualizationPredictedAndTrueLabels(folderName, net, numSamples, classNames, varargin)
% HELPERVISUALIZATIONPREDICTEDANDTRUELABELS Visualize predictions vs ground truth labels
%
% This function loads random samples from a dataset, performs semantic
% segmentation using a trained neural network, and displays the comparison
% between true labels and predicted labels.
%
% Syntax:
%   helperVisualizationPredictedAndTrueLabels(folderName, net, numSamples, classNames)
%   helperVisualizationPredictedAndTrueLabels(folderName, net, numSamples, classNames, Name, Value)
%
% Input Arguments:
%   folderName  - String or char array specifying the path to the folder
%                containing the dataset files
%   net         - Trained neural network for semantic segmentation
%   numSamples  - Number of random samples to visualize (positive integer)
%   classNames  - String array containing the class names for visualization
%
% Name-Value Pair Arguments:
%   'ImageSize'     - Size to resize images [height, width] (default: [128, 128])
%   'OldValues'     - Array of original label values (default: [0, 16, 32, 64, 128, 255])
%   'NewValues'     - Array of mapped label values (default: [1, 2, 3, 4, 5, 6])
%   'AutoPause'     - Logical flag to pause between visualizations (default: true)
%   'FilePattern'   - Pattern for label files (default: '*_frame_*.mat')
%   'LabelVarName'  - Variable name in .mat files containing labels (default: 'data_final')
%   'ImageSuffix'   - Suffix for image files (default: '_spectogram.png')
%
% Example:
%   % Basic usage
%   classNames = ["AWGN", "WLAN", "ZigBee", "Bluetooth", "SmartBAN", "Unknown"];
%   helperVisualizationPredictedAndTrueLabels('path/to/data', net, 10, classNames);
%
%   % With custom parameters
%   helperVisualizationPredictedAndTrueLabels('path/to/data', net, 5, classNames, ...
%       'ImageSize', [256, 256], 'AutoPause', false);
%
% See also: helperSpecSenseDisplayResults, predict, ismember

% Parse input arguments
p = inputParser;
addRequired(p, 'folderName', @(x) ischar(x) || isstring(x));
addRequired(p, 'net', @(x) isa(x, 'SeriesNetwork') || isa(x, 'DAGNetwork') || isa(x, 'dlnetwork'));
addRequired(p, 'numSamples', @(x) isnumeric(x) && x > 0 && x == round(x));
addRequired(p, 'classNames', @(x) isstring(x) || iscellstr(x));

addParameter(p, 'ImageSize', [128, 128], @(x) isnumeric(x) && length(x) == 2);
addParameter(p, 'OldValues', uint8([0, 16, 32, 64, 128, 255]), @isnumeric);
addParameter(p, 'NewValues', [1, 2, 3, 4, 5, 6], @isnumeric);
addParameter(p, 'AutoPause', true, @islogical);
addParameter(p, 'FilePattern', '*_frame_*.mat', @(x) ischar(x) || isstring(x));
addParameter(p, 'LabelVarName', 'data_final', @(x) ischar(x) || isstring(x));
addParameter(p, 'ImageSuffix', '_spectogram.png', @(x) ischar(x) || isstring(x));

parse(p, folderName, net, numSamples, classNames, varargin{:});

% Extract parsed values
imageSize = p.Results.ImageSize;
oldValues = uint8(p.Results.OldValues);
newValues = p.Results.NewValues;
autoPause = p.Results.AutoPause;
filePattern = p.Results.FilePattern;
labelVarName = p.Results.LabelVarName;
imageSuffix = p.Results.ImageSuffix;

% Validate inputs
if length(oldValues) ~= length(newValues)
    error('Length of OldValues must match length of NewValues');
end

if length(classNames) ~= length(newValues)
    error('Number of class names must match number of mapped values');
end

% List all .mat files containing label masks
matFiles = dir(fullfile(folderName, filePattern));

if isempty(matFiles)
    error('No files found matching pattern "%s" in folder "%s"', filePattern, folderName);
end

if numSamples > length(matFiles)
    warning('Requested %d samples but only %d files available. Using all available files.', ...
            numSamples, length(matFiles));
    numSamples = length(matFiles);
end

% Randomly select files
randIdx = randperm(length(matFiles), numSamples);
selectedFiles = matFiles(randIdx);

fprintf('Visualizing %d random samples from %s\n', numSamples, folderName);
fprintf('Image size: %dx%d\n', imageSize(1), imageSize(2));
fprintf('Classes: %s\n', strjoin(classNames, ', '));

% Process each selected file
for i = 1:numSamples
    try
        fprintf('Processing sample %d/%d: %s\n', i, numSamples, selectedFiles(i).name);
        
        % Load label mask
        labelFile = load(fullfile(folderName, selectedFiles(i).name));
        
        % Get the label data using the specified variable name
        if isfield(labelFile, labelVarName)
            trueLabel = labelFile.(labelVarName);
        else
            % Try to find the variable automatically
            fieldNames = fieldnames(labelFile);
            if length(fieldNames) == 1
                trueLabel = labelFile.(fieldNames{1});
                warning('Variable "%s" not found. Using "%s" instead.', labelVarName, fieldNames{1});
            else
                error('Variable "%s" not found in %s. Available variables: %s', ...
                      labelVarName, selectedFiles(i).name, strjoin(fieldNames, ', '));
            end
        end
        
        % Build image filename from label filename
        [~, baseName, ~] = fileparts(selectedFiles(i).name);
        imageFilename = fullfile(folderName, baseName + imageSuffix);
        
        % Check if image file exists
        if ~isfile(imageFilename)
            warning('Image file not found: %s. Skipping sample %d.', imageFilename, i);
            continue;
        end
        
        % Load and preprocess image
        img = imread(imageFilename);
        
        % Display original image
        figure('Name', sprintf('Sample %d/%d - Original Image', i, numSamples));
        imshow(img);
        title(sprintf('Original Image: %s', baseName), 'Interpreter', 'none');
        
        % Resize image
        img = imresize(img, imageSize);
        img = double(img);
        
        % Prepare image for network prediction
        dlImg = dlarray(img, 'SSC'); % 'SSC' = Spatial, Spatial, Channel
        
        % Perform prediction
        predictions = predict(net, dlImg);
        [~, predictedLabel] = max(predictions, [], 3);
        predictedLabel = extractdata(predictedLabel);
        
        % Map true labels from old values to new values
        [~, idx] = ismember(trueLabel, oldValues);
        
        % Handle unmapped values
        unmappedMask = (idx == 0);
        if any(unmappedMask(:))
            uniqueUnmapped = unique(trueLabel(unmappedMask));
            warning('Found unmapped values in true labels: %s. Setting to class 1.', ...
                    mat2str(uniqueUnmapped));
            idx(unmappedMask) = 1; % Map unmapped values to first class
        end
        
        trueLabels_mapped = uint8(newValues(idx));
        
        % Display results comparison
        helperSpecSenseDisplayResults(trueLabels_mapped, predictedLabel, classNames);
        
        % Pause between samples if requested
        if autoPause && i < numSamples
            fprintf('Press any key to continue to next sample...\n');
            pause();
            close all;
        end
        
    catch ME
        warning('Error processing sample %d (%s): %s', i, selectedFiles(i).name, ME.message);
        continue;
    end
end

fprintf('Visualization complete!\n');

end







% clear; close all;
% load('/home/nicola-gallucci/Nicola/Matlab/AICHallenge/AICompetition/SuccesfulNets/SuccesfulNets/ResNet18_Unet_080625/ResNet18_Unet_080625.mat')
% numClasses = 6;
% classNames = [ ...
%     "AWGN", "WLAN", "ZigBee","Bluetooth", "SmartBAN", "Unknown"];
% 
% folder = "CompleteFunctionContainer/trainingImages_Nicola/128x128";
% 
% % List all .mat files (assumed to contain label masks)
% matFiles = dir(fullfile(folder, '*_frame_*.mat'));
% 
% % Randomly select 10 files
% numSamples = 10;
% randIdx = randperm(length(matFiles), numSamples);
% selectedFiles = matFiles(randIdx);
% 
% % Create the mapping
% oldValues = uint8([0, 16, 32, 64, 128, 255]);
% newValues = [1, 2, 3, 4, 5, 6];
% 
% 
% 
% % Preallocate storage
% images = zeros(128, 128, 3, numSamples);      % assuming RGB images
% labels = zeros(128, 128, numSamples);         % assuming 2D label masks
% 
% for i = 1:numSamples
%     % Load label mask
%     labelFile = load(fullfile(folder, selectedFiles(i).name));
%     labels(:, :, i) = double(labelFile.data_final);  % adjust var name if needed
% 
%     % Build image filename from label filename
%     [~, baseName, ~] = fileparts(selectedFiles(i).name);
%     imageFilename = fullfile(folder, baseName + "_spectogram.png");
%     matFile = load(fullfile(folder, baseName));
%     trueLabel = matFile.data_final;
%     % Load and resize image
%     img = imread(imageFilename);
%     figure;
%     imshow(img);
%     img = imresize(img, [128 128]);
%     img = double(img);
%     dlImg = dlarray(img, 'SSC');  % 'SSC' = Spatial, Spatial, Channel (batch size = 1)
%     predictions = predict(net, dlImg);
% 
%     [~, predictedLabel] = max(predictions, [], 3);
%     predictedLabel = extractdata(predictedLabel);
% 
%     [~, idx] = ismember(trueLabel, oldValues);
%     trueLabels_mapped = uint8(newValues(idx));
%     helperSpecSenseDisplayResults(trueLabels_mapped, predictedLabel, classNames);
%     pause();
%     close all;
% end