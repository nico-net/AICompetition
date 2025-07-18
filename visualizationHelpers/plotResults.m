function plotResults(net, spectrImg, spectrMask)
% plotResults - Displays ground truth and predicted segmentation over a spectrogram image.
%
% Syntax:
%   plotResults(net, spectrImg, spectrMask)
%
% Description:
%   This function runs semantic segmentation on a spectrogram image using a 
%   trained neural network, and displays two visualizations:
%     1. The original image with the ground truth mask overlaid.
%     2. The original image with the predicted mask overlaid.
%
%   It checks whether the input image and mask sizes match before proceeding 
%   with the ground truth overlay. If dimensions mismatch, it skips the real 
%   mask plot and issues a warning.
%
% Inputs:
%   net        - Trained semantic segmentation neural network.
%   spectrImg  - Input spectrogram image (grayscale or RGB).
%   spectrMask - Ground truth label mask (2D, class indices).
%
% Notes:
%   - The function assumes `plotOverLayed(img, mask, alpha)` exists to 
%     overlay a mask on an image with a specified transparency (`alpha`).
%   - The input image is converted to a `dlarray` with format 'SSC' (Spatial, Spatial, Channel).
%   - The predicted mask is obtained by taking the `argmax` over the third dimension 
%     of the prediction output.
%
% Example:
%   plotResults(trainedNet, testImage, testLabelMask);

realImg = spectrImg;
realImg = double(realImg);
realImgSize = size(realImg);

trueMask = spectrMask;
trueMaskSize = size(trueMask);
trueMaskSize = trueMaskSize(1:2);

if (realImgSize(1) ~= trueMaskSize(1) || realImgSize(2) ~= trueMaskSize(1))
    warning('Mask size differs from the .png size, will not plot real mask.\nImage size [%s] x [%s]\nMask size [%s] x [%s]', ...
        realImgSize(1), realImgSize(2), trueMaskSize(1), trueMaskSize(2));
end

% Prepare image for network prediction
dlImg = dlarray(realImg, 'SSC'); % 'SSC' = Spatial, Spatial, Channel


% Perform prediction
predictions = predict(net, dlImg);
[~, predictedLabel] = max(predictions, [], 3);
predictedLabel = extractdata(predictedLabel);

% Ground truth
imagesc(spectrMask)
title('Ground Truth');

pause();

% Prediction
imagesc(predictedLabel)
title('Predicted Segmentation');

end

