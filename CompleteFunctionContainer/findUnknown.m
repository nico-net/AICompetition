% Folder
folder = 'testImages';
files = dir(fullfile(folder, '*.mat'));
filesPng = dir(fullfile(foler, '*.png'));
target_values = [48, 80, 96, 112, 144, 192, 208, 224, 250,160, 176, 255];
filenames = {};
for k = 1:length(files)
    filename = files(k).name;
    filepath = fullfile(folder, filename);
    % Extract signals from "signal1+signal2+..." part
    % parts = split(filename, '_');
    % signal_str = parts{1};  % the first token before "_frame" or "_spectrogram"
    % signal_list = split(signal_str, '+');
    % signal_types = intersect(valid_signals, signal_list);
    % 
    % if numel(signal_types) < 2
    %     continue  % Skip if not at least two valid signals
    % end

    % Load label matrix
    data = load(filepath);
    varname = fieldnames(data);
    label_matrix = data.(varname{1});
    found = any(ismember(label_matrix(:), target_values));
    if found
        filenames{end+1} = filename;
    end
end

for i = 1:length(filenames)
    % Original .mat filename
    mat_name = filenames{i};
    
    % Build full path and delete the .mat file
    mat_path = fullfile(folder, mat_name);
    if isfile(mat_path)
        delete(mat_path);
        fprintf('Deleted: %s\n', mat_path);
    end

    % Convert .mat name to corresponding .png name
    % Replace '_frame.mat' with '_spectrogram.png'
    png_name = strrep(mat_name, '_frame.mat', '_spectrogram.png');
    png_path = fullfile(folder, png_name);

    if isfile(png_path)
        delete(png_path);
        fprintf('Deleted: %s\n', png_path);
    end
end
