%% Spectrogram Segmentation using U-Net with ResNet34 Encoder

classNames = '';

% Set your folder path
fileID = '';
dataFolder = downloadAndUnzipGoogleDrive(fileID, 'trainingImages');

%% STEP 1: Create Image Datastore
imds = imageDatastore(dataFolder, 'FileExtensions', {'.png'}, 'IncludeSubfolders', false);

%% STEP 2: Create Custom Label Datastore for .mat Bitmask Files
matFiles = dir(fullfile(dataFolder, '*.mat'));
matPaths = fullfile({matFiles.folder}, {matFiles.name})';

numClasses = length(classNames);
pixelLabelID = 0:16:240;

% FileDatastore for label masks
pxds = fileDatastore(matPaths, ...
    classNames, pixelLabelID,   ...
    FileExtensions = ".mat");

% Combine into pixelLabelImageDatastore
pximds = pixelLabelImageDatastore(imds, pxds);

%% STEP 4: Split into Train and Validation
[trainDS, valDS] = partition(pximds, 0.8);

%% STEP 5: Define U-Net Network with ResNet34 Encoder
imageSize = [128 128 3];
numClasses = 16;
lgraph = unet('resnet34', imageSize, numClasses);

%% STEP 6: Training Options
options = trainingOptions('adam', ...
    'InitialLearnRate',1e-4, ...
    'MaxEpochs',25, ...
    'MiniBatchSize',8, ...
    'Shuffle','every-epoch', ...
    'ValidationData',valDS, ...
    'VerboseFrequency',10, ...
    'Plots','training-progress');

%% STEP 7: Train the Network
net = trainNetwork(trainDS, lgraph, options);

%% STEP 8: Test Prediction on One Image
testImage = readimage(imds, 1);
if size(testImage, 3) == 1
    testImage = repmat(testImage, 1, 1, 3);
end
predicted = semanticseg(testImage, net);

figure;
imshow(labeloverlay(testImage, predicted));
title('Predicted Segmentation');


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
