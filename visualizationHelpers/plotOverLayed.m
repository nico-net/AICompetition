function plotOverLayed(img,mask, alpha)
% plotOverLayed overlays a colormapped matrix onto an image
%
% Inputs:
%   - img: HxW (grayscale) or HxWx3 (RGB) image
%   - mask: HxW numeric matrix to visualize with colormap (e.g., output or heatmap)
%   - alpha: transparency value between 0 and 1 (default: 0.5)
%
% Output:
%   - overlayedImg: RGB image with overlay applied

labelColors = [
    0.6 0.8 1.0;   % Light Blue
    1.0 0.6 0.8;   % Pink
    0.6 0.0 0.8;   % Purple
    1.0 0.5 0.0    % Orange
    1.0 0.0 0.0;   % Red
];

cmap = labelColors;

if nargin < 3
    alpha = 0.5;
end
% Ensure img is RGB
if size(img,3) == 1
    img = repmat(img, 1, 1, 3);
end
img = im2double(img);

figure;
imshow(img);
hold on;

mask = reAllignLabels(mask);
% Overlay the label mask using imagesc
h = imagesc(mask);
colormap(cmap); 


% Set transparency
set(h, 'AlphaData', alpha);  % Adjust transparency (0 = fully transparent, 1 = opaque)

title('Label Mask Overlayed on Base Image');

end
