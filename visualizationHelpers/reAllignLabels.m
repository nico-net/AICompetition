function mask = reAllignLabels(mask)
%reAllignLabels Takes in input a maks and reassings the labels to make it easier
%               to colormap

mask = double(mask);
oldValues = [16 32 64 128 255];
newValues = [1 2 3 4 5];

for k = 1:length(oldValues)
    mask(mask == oldValues(k)) = newValues(k);
end

mask = floor((mask./5)*255);

end