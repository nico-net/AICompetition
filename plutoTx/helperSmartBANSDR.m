function [cleanWf] = helperSmartBANSDR(sampleRate, frameDuration)
% helperSmartBANSDR Generate a SmartBAN GMSK waveform for SDR transmission
%
%   cleanWf = helperSmartBANSDR(sampleRate, frameDuration)
%
%   Inputs:
%       sampleRate    - Sample rate in Hz (positive scalar)
%       frameDuration - Duration of the output waveform in seconds (positive scalar)
%
%   Output:
%       cleanWf      - Baseband waveform of SmartBAN beacon and packets

    % --- Input validation ---
    if ~isscalar(sampleRate) || ~isnumeric(sampleRate) || sampleRate <= 0
        error('sampleRate must be a positive numeric scalar.');
    end
    if ~isscalar(frameDuration) || ~isnumeric(frameDuration) || frameDuration <= 0
        error('frameDuration must be a positive numeric scalar.');
    end

    % --- Initialize beacon data bits (MAC + PHY) ---
    dataBeacon = randi([0 1], 248, 1);

    timeDuration = frameDuration;    % seconds
    slotDuration = 0.001250;         % seconds
    bitRate = 1e6;                   % bits per second

    % --- Packet and acknowledgment lengths in bits ---
    dataPacketLength = 64 * 8;       % 64 bytes
    ackPacketLength = 64 + 104;      % sum of bytes (assumed bits?)
    ifs = 0.000150;                  % Interframe spacing in seconds

    % --- Packet loss probability and initialization ---
    missProb = 0.1;
    currentMissProb = missProb;

    % --- Create GMSK modulator object ---
    modulator = comm.GMSKModulator( ...
        "BandwidthTimeProduct", 0.5, ...
        "BitInput", true, ...
        "SamplesPerSymbol", sampleRate / bitRate);

    % --- Modulate the beacon ---
    beaconSignal = modulator(dataBeacon);

    % --- Random start point for beacon within the frame duration ---
    startPoint = floor(rand() * timeDuration * sampleRate);

    % --- Build the full waveform depending on where beacon starts ---
    if (startPoint > timeDuration * sampleRate - length(beaconSignal) + 1)
        % Beacon placed near the end, pad with zeros before beacon
        cleanWf = [zeros(startPoint - 1, 1); beaconSignal];
        cleanWf = cleanWf(1:timeDuration * sampleRate);
    elseif (startPoint > timeDuration * sampleRate - slotDuration * sampleRate + 1)
        % Beacon placed near end of last slot, pad zeros after beacon
        cleanWf = [zeros(startPoint - 1, 1); beaconSignal; zeros(slotDuration * sampleRate - length(beaconSignal), 1)];
        cleanWf = cleanWf(1:timeDuration * sampleRate);
    else
        % Beacon placed early enough; build packets after beacon
        cleanWf = [zeros(startPoint - 1, 1); beaconSignal; zeros(sampleRate * slotDuration - length(beaconSignal), 1)];

        while length(cleanWf) < timeDuration * sampleRate
            dataPacket = randi([0 1], dataPacketLength, 1);
            if rand() > currentMissProb
                % Modulate data packet with reduced power
                packetSignal = modulator(dataPacket) * 0.1;
                numZeros = floor((slotDuration - ifs * 2 - ackPacketLength / bitRate - dataPacketLength / bitRate) * sampleRate);
                cleanWf = [cleanWf; packetSignal; zeros(numZeros, 1)];
                cleanWf = [cleanWf; zeros(floor(ifs * sampleRate), 1)];

                % Generate and modulate acknowledgment packet
                dataAck = randi([0 1], ackPacketLength, 1);
                ackSignal = modulator(dataAck) * 0.1;
                cleanWf = [cleanWf; ackSignal; zeros(floor(ifs * sampleRate), 1)];

                % Increase miss probability after successful transmission
                currentMissProb = currentMissProb + 0.05;
            else
                % Packet missed; insert silence for slot duration
                missedPacket = zeros(sampleRate * slotDuration, 1);
                cleanWf = [cleanWf; missedPacket];

                % Decrease miss probability after missed packet
                currentMissProb = currentMissProb - 0.1;
            end

            % Truncate waveform if it exceeds the target duration
            if length(cleanWf) > timeDuration * sampleRate
                cleanWf = cleanWf(1:timeDuration * sampleRate);
            end
        end
    end
end
