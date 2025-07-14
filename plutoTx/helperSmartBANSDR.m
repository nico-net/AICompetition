function [cleanWf] = helperSmartBANSDR(sampleRate)
% helperSmartBANSDR Generate a SmartBAN GMSK waveform for SDR transmission
%
%   cleanWf = helperSmartBANSDR(sampleRate)
%
%   Inputs:
%       sampleRate    - Sample rate in Hz (positive scalar)
%
%   Output:
%       cleanWf      - Baseband waveform of SmartBAN beacon and packets

    % --- Input validation ---
    if ~isscalar(sampleRate) || ~isnumeric(sampleRate) || sampleRate <= 0
        error('sampleRate must be a positive numeric scalar.');
    end

    % --- Initialize beacon data bits (MAC + PHY) ---
    dataBeacon = randi([0 1], 248, 1);

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
    numSamples = 17026;
    cleanWf = [beaconSignal; zeros(sampleRate * slotDuration - length(beaconSignal), 1)];
     while length(cleanWf) < numSamples
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
            if length(cleanWf) > numSamples
                cleanWf = cleanWf(1:numSamples);
            end
     end

end

