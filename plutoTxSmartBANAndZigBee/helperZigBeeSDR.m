function cleanWf = helperZigBeeSDR(spc)
% helperZigBeePluto Generate a clean ZigBee waveform at the specified sample rate and duration
%
%   cleanWf = helperZigBeePluto(spc)
%
%   Inputs:
%       spc          - Samples per chip (positive integer)
%
%   Output:
%       cleanWf      - Baseband ZigBee waveform resampled to target sample rate

    % Input validation
    if ~isscalar(spc) || ~isnumeric(spc) || spc <= 0 || floor(spc) ~= spc
        error('spc must be a positive integer scalar.');
    end

    % --- ZigBee PHY Configuration ---
    zbCfg = lrwpanOQPSKConfig;
    zbCfg.SamplesPerChip = spc;

    % --- Generate the clean ZigBee waveform with specified packets and idle time ---
    bits = randi([0 1], zbCfg.PSDULength * 8, 1); % Random bits to modulate
    cleanWf = lrwpanWaveformGenerator(bits, zbCfg);

end
