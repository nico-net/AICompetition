function plotResults(net, spectrImg, spectrMask)
%PLOTRESULTS function to aid the evaluation of net results
%   plotResults takes in input a trained net, an image of an ISM Band 
%   (2.40 - 2.48 Ghz) spectrogram and its relative ground truth. 
%   It then computes the predicted mask and plots both correct and
%   predicted label values above the spectrogram image;
%
%   net -------------------- trained network
%   spectrImg -------------- img of trained network (square)
%   spectrMask ------------- spectrMask

realImg = spectrImg;
realImg = double(realImg);
realImgSize = size(realImg);

trueMask = spectrMask;
trueMaskSize = size(trueMask);
trueMaskSize = trueMaskSize(1:2);

useMask = true;

if (realImgSize(1) ~= trueMaskSize(1) || realImgSize(2) ~= trueMaskSize(1))
    warning('Mask size differs from the .png size, will not plot real mask.\nImage size [%s] x [%s]\nMask size [%s] x [%s]', ...
        realImgSize(1), realImgSize(2), trueMaskSize(1), trueMaskSize(2));
    useMask = false;
end

% Prepare image for network prediction
dlImg = dlarray(realImg, 'SSC'); % 'SSC' = Spatial, Spatial, Channel


% Perform prediction
predictions = predict(net, dlImg);
[~, predictedLabel] = max(predictions, [], 3);
predictedLabel = extractdata(predictedLabel);

% Ground truth
plotOverLayed(spectrImg, trueMask, 0.3);
title('Ground Truth');

% Prediction
plotOverLayed(spectrImg, predictedLabel, 0.3)
title('Predicted Segmentation');



end

