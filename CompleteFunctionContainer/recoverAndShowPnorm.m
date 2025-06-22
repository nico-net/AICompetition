
function recoverAndShowPnorm(folderName)
% RECOVERANDSAVEPNORMBATCH - Process all PNG images in folder and save P_norm from RGB.
%
% INPUT:
%   folderName : string, path to folder containing .png spectrograms
%
% Each image is processed to:
%   - Invert the parula colormap
%   - Recover P_norm
%   - Reconstruct and display P_db
%   - Save P_norm to .mat file with same base name

    % Parameters
    db_min = -130;
    db_max = -50;

    % Get list of PNG images
    imageFiles = dir(fullfile(folderName, '*.png'));

    % Process each image
    for k = 1:length(imageFiles)
        % Full path of the current image
        imagePath = fullfile(folderName, imageFiles(k).name);

        % Read image
        I_rgb = imread(imagePath);  % RGB uint8

        % Invert parula colormap to recover P_norm
        P_norm = invertParulaRGB(I_rgb);

        % Convert P_norm to dB
        P_db_recovered = P_norm * (db_max - db_min) + db_min;

        % Display (optional)
        % figure;
        % imshow(P_db_recovered, []);
        % %colormap(parula);
        % colorbar;
        % axis xy;
        % clim([db_min db_max]);
        % title(['Recovered spectrogram: ', imageFiles(k).name], 'Interpreter', 'none');
        % xlabel('Time (pixels)');
        % ylabel('Frequency (pixels)');
        % 
        % % Close figure to avoid memory overload
        % pause(5);
        % close;

        % Save P_norm to .mat file with same name
        [~, baseName, ~] = fileparts(imageFiles(k).name);
        matFileName = fullfile(folderName, [baseName, '.mat']);
        save(matFileName, 'P_db_recovered');
        
    end
end

function P_norm_est = invertParulaRGB(I)
% INVERTPARULARGB - Estimate normalized power matrix (P_norm) from an RGB image.
%
% This function inverts the RGB representation obtained by applying the parula colormap
% to a normalized spectrogram matrix (P_norm), reconstructing the original grayscale values.
%
% INPUT:
%   I : RGB image [H x W x 3], typically created from ind2rgb(P_norm, parula(256))
%
% OUTPUT:
%   P_norm_est : estimated grayscale matrix [H x W] with values in [0,1]

    cmap = parula(256);         % 256-color colormap used in encoding (double, range [0,1])
    I_double = double(I)/255;   % Normalize RGB values to [0,1]

    [H, W, ~] = size(I);        % Image dimensions

    % Reshape colormap for distance computation
    cmap = reshape(cmap, [256, 3]);

    % Flatten image into Nx3 RGB matrix for efficient processing
    pixels = reshape(I_double, [], 3);

    % Preallocate vector for colormap indices
    idxs = zeros(size(pixels,1), 1);

    % For each pixel, find the closest color in the colormap (Euclidean distance)
    for i = 1:size(pixels,1)
        pixelRGB = pixels(i,:);
        dists = sum((cmap - pixelRGB).^2, 2);
        [~, idx] = min(dists);
        idxs(i) = idx;
    end

    % Convert colormap indices to normalized values in [0,1]
    vals = (idxs - 1) / 255;

    % Reshape back to original image dimensions
    P_norm_est = reshape(vals, H, W);

    % Undo vertical flip applied during original RGB image creation
    P_norm_est = flipud(P_norm_est);
end
