
% Assuming the variable is named 'matrix'
target_values = [48, 120, 160];

% Folder
folder = 'testImages';
files = dir(fullfile(folder, '*.mat'));

for k = 1:length(files)
    filename = files(k).name;
    filepath = fullfile(folder, filename);
    
   % Extract signals from "signal1+signal2+..." part
    parts = split(filename, '_');
    signal_str = parts{1};  % the first token before "_frame" or "_spectrogram"
    signal_list = split(signal_str, '+');
    signal_types = intersect(valid_signals, signal_list);

    if numel(signal_types) < 2
        continue  % Skip if not at least two valid signals
    end

    % Load label matrix
    data = load(filepath);
    varname = fieldnames(data);
    label_matrix = data.(varname{1});

    % Process each composite label
    for composite_bitmask = 1:15
        if countbits(composite_bitmask) == 1
            continue  % skip atomic signals
        end

        composite_label = label_map(composite_bitmask);
        mask = (label_matrix == composite_label);

        if ~any(mask, 'all')
            continue
        end

        % Get bits set in bitmask
        bitmask = composite_label / 16;  
        bits = bitget(bitmask, 1:4);    
        present_bits = find(bits);
        % Sort by priority
        bit_priorities = arrayfun(@(b) bit_priority(b), present_bits);
        [~, idx] = min(bit_priorities);  % Find the bit with highest priority (lowest rank)
        shortest_bit = present_bits(idx);
        shortest_bitmask = 2^(shortest_bit - 1);
        new_label = label_map(shortest_bitmask);


        % Replace
        label_matrix(mask) = new_label;
    end

    % Save back to file
    data_final = label_matrix;
    save(filepath, 'data_final');
end

% Helper: count number of bits set to 1
function n = countbits(x)
    n = sum(bitget(x, 1:4));
end
