function cleanWf = helperZigBeeSDR(spc, numPackets, timeDuration, sampleRate)
% helperZigBeePluto Generate a clean ZigBee waveform at the specified sample rate and duration
%
%   cleanWf = helperZigBeePluto(spc, numPackets, timeDuration, sampleRate)
%
%   Inputs:
%       spc          - Samples per chip (positive integer)
%       numPackets   - Number of ZigBee packets to generate (integer in [1..4])
%       timeDuration - Total desired duration of the output waveform in seconds (positive scalar)
%       sampleRate   - Target output sample rate in Hz (positive scalar)
%
%   Output:
%       cleanWf      - Baseband ZigBee waveform resampled to target sample rate

    % Input validation
    if ~isscalar(spc) || ~isnumeric(spc) || spc <= 0 || floor(spc) ~= spc
        error('spc must be a positive integer scalar.');
    end

    if ~isscalar(numPackets) || ~isnumeric(numPackets) || floor(numPackets) ~= numPackets || ...
            numPackets < 1 || numPackets > 4
        error('numPackets must be an integer scalar between 1 and 4.');
    end

    if ~isscalar(timeDuration) || ~isnumeric(timeDuration) || timeDuration <= 0
        error('timeDuration must be a positive numeric scalar.');
    end

    if ~isscalar(sampleRate) || ~isnumeric(sampleRate) || sampleRate <= 0
        error('sampleRate must be a positive numeric scalar.');
    end

    % --- ZigBee PHY Configuration ---
    zbCfg = lrwpanOQPSKConfig;
    zbCfg.SamplesPerChip = spc;

    % --- Sample rates ---
    nativeSampleRate = zbCfg.SampleRate;   % Original sample rate of ZigBee PHY
    targetSampleRate = sampleRate;          % Target sample rate for output waveform

    % --- Typical packet duration (PHY + MAC layers) ---
    packetTimeDuration = 4.2565e-3; % seconds

    % --- Compute idle time between packets based on numPackets ---
    switch numPackets
        case 1
            idleTime = 0;
        case {2, 3}
            idleTime = 0.0005 + (0.005 - 0.0005) * rand; % random idle time in [0.0005, 0.005] s
        case 4
            % Calculate idle time such that total duration fits in timeDuration
            minVal = (timeDuration - packetTimeDuration * 4) / 4;
            maxVal = (timeDuration - packetTimeDuration * 4) / 3;
            idleTime = minVal + (maxVal - minVal) * rand;
    end

    % --- Generate the clean ZigBee waveform with specified packets and idle time ---
    bits = randi([0 1], zbCfg.PSDULength * 8, 1); % Random bits to modulate
    wf = lrwpanWaveformGenerator(bits, zbCfg, ...
        "NumPackets", numPackets, "IdleTime", idleTime);

    % --- Remove trailing samples corresponding to idle time ---
    wf = wf(1:end - floor(zbCfg.SampleRate * idleTime));

    % --- Pad waveform with zeros to reach the desired total duration ---
    targetLength = floor(zbCfg.SampleRate * timeDuration);
    if length(wf) < targetLength
        zerosToAdd = targetLength - length(wf);
        zerosBefore = floor(rand * zerosToAdd);
        zerosAfter = zerosToAdd - zerosBefore;
        wf = [zeros(zerosBefore, 1); wf; zeros(zerosAfter, 1)];
    else
        wf = wf(1:targetLength);
    end

    % --- Resample waveform to target sample rate ---
    [upP, downQ] = rat(targetSampleRate / nativeSampleRate);
    wfRes = resample(wf, upP, downQ);

    % --- Adjust length again to exactly match desired duration at target sample rate ---
    finalLength = floor(targetSampleRate * timeDuration);
    if length(wfRes) > finalLength
        wfRes = wfRes(1:finalLength);
    else
        wfRes = [wfRes; zeros(finalLength - length(wfRes), 1)];
    end

    % --- Output clean baseband waveform at target sample rate ---
    cleanWf = wfRes;

end
