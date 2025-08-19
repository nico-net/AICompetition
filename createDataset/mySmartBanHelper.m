function [noisyWf, finWf] = mySmartBanHelper(Channel, centerFreq, txPower)
%MYSMARTBANHELPER Simulates a SmartBAN transmission scenario
%
%   [noisyWf, finWf] = mySmartBanHelper(Channel, centerFreq, txPower)
%
%   This function generates a SmartBAN-like GMSK-modulated signal,
%   applies fading (Rayleigh/Rician), frequency offset, and transmits
%   periodic data packets and acknowledgments, preceded by a beacon.
%   To simulate the signal we based our estimates on the Technical Reports
%   released publicly by ETSI SmartBAN group and on already existing MAC
%   simulations. More information about it can be found in the report.
%
%   Inputs:
%     - Channel      : Channel type to use ('Rayleigh', 'Rician', or none)
%     - centerFreq   : Carrier frequency in Hz (used for frequency offset)
%     - txPower      : Transmit power in dBm
%
%   Outputs:
%     - noisyWf      : Final waveform with AWGN
%     - finWf        : Channel and frequency shifted waveform (no noise)

    % --- Parameters ---
    ISMSstart = 2.402e9;                     % ISM band reference frequency
    timeDuration = 0.02;                     % Total signal duration (20 ms)
    slotDuration = 0.001250;                 % Slot duration (1.25 ms)
    bitRate = 1e6;                           % SmartBAN nominal bitrate (1 Mbps)
    sampleRate = 80e6;                       % Final sample rate
    ifs = 150e-6;                            % Interframe spacing (150 µs)

    dataPacketLength = 64 * 8;              % Payload: 64 bytes
    ackPacketLength = 64 + 104;             % ACK: MAC + PHY bits
    beaconLength = 248;                     % Beacon bits (MAC + PHY)
    missProb = 0.1;                         % Initial probability to miss a transmission
    currentMissProb = missProb;

    % --- TX Power Conversion ---
    txPower_W = 10^((txPower - 30)/10);      % Convert dBm to Watts
    scalingFactor = sqrt(txPower_W);         % Linear amplitude scaling

    % --- Frequency Offset Configuration ---
    fOff = comm.PhaseFrequencyOffset;
    fOff.SampleRate = sampleRate;
    fOff.FrequencyOffset = centerFreq - ISMSstart;

    % --- GMSK Modulator Configuration ---
    modulator = comm.GMSKModulator( ...
        "BandwidthTimeProduct", 0.5, ...
        "BitInput", true, ...
        "SamplesPerSymbol", sampleRate / bitRate);

    % --- Channel Selection ---
    switch Channel
        case 'Rician'
            chan = comm.RicianChannel;
            chan.SampleRate = sampleRate;
            chan.PathDelays = [0 50e-9 150e-9 300e-9];
            chan.AveragePathGains = [0 -3 -8 -15];
            chan.KFactor = 8;
            chan.MaximumDopplerShift = 12;
            chan.DopplerSpectrum = doppler('Jakes');
            chan.NormalizePathGains = true;
        case 'Rayleigh'
            chan = comm.RayleighChannel;
            chan.SampleRate = sampleRate;
            chan.PathDelays = [0 50e-9 150e-9 300e-9];
            chan.AveragePathGains = [0 -3 -8 -15];
            chan.MaximumDopplerShift = 12;
            chan.DopplerSpectrum = doppler('Jakes');
        otherwise
            % No channel effects applied
    end

    % --- Beacon Generation ---
    dataBeacon = randi([0 1], beaconLength, 1);
    beaconSignal = modulator(dataBeacon);
    beaconSignal = scalingFactor * beaconSignal;

    % Beacon always passes through Rician channel
    beaconchan = comm.RicianChannel;
    beaconchan.SampleRate = sampleRate;
    beaconchan.PathDelays = [0 50e-9 150e-9 300e-9];
    beaconchan.AveragePathGains = [0 -3 -8 -15];
    beaconchan.KFactor = 8;
    beaconchan.MaximumDopplerShift = 12;
    beaconchan.DopplerSpectrum = doppler('Jakes');
    beaconchan.NormalizePathGains = true;
    beaconSignal = beaconchan(beaconSignal);

    % --- Start Simulation: Randomly place beacon ---
    maxSigLen = ceil((beaconLength + dataPacketLength + ackPacketLength)/bitRate * sampleRate ...
                 + slotDuration*sampleRate);  % rough upper bound
    maxStart = timeDuration * sampleRate - maxSigLen;
    startPoint = randi([1, maxStart], 1);


    if (startPoint > timeDuration * sampleRate - length(beaconSignal) + 1)
        finWf = [zeros(startPoint - 1, 1); beaconSignal];
        finWf = finWf(1:timeDuration * sampleRate);
    elseif (startPoint > timeDuration * sampleRate - slotDuration * sampleRate + 1)
        % Pad beacon to fill the slot
        finWf = [zeros(startPoint - 1, 1); beaconSignal; ...
                 zeros(slotDuration * sampleRate - length(beaconSignal), 1)];
        finWf = finWf(1:timeDuration * sampleRate);
    else
        % Place beacon and continue with packet/ACK traffic
        finWf = [zeros(startPoint - 1, 1); beaconSignal; ...
                 zeros(sampleRate * slotDuration - length(beaconSignal), 1)];

        % --- Begin packet/ACK loop ---
        while length(finWf) < timeDuration * sampleRate
            dataPacket = randi([0 1], dataPacketLength, 1);

            if rand() > currentMissProb
                % Transmit data packet
                packetSignal = modulator(dataPacket) * 0.1 * scalingFactor;
                packetSignal = chan(packetSignal);

                % Pad time to fill slot with IFS, ACK, etc.
                padding = zeros(floor((slotDuration - 2*ifs - ...
                    ackPacketLength / bitRate - dataPacketLength / bitRate)) * ...
                    sampleRate, 1);

                finWf = [finWf; packetSignal; padding];

                % Interframe space
                finWf = [finWf; zeros(floor(ifs * sampleRate), 1)];

                % Transmit ACK
                dataAck = randi([0 1], ackPacketLength, 1);
                ackSignal = modulator(dataAck) * 0.1 * scalingFactor;
                ackSignal = chan(ackSignal);

                finWf = [finWf; ackSignal; zeros(floor(ifs * sampleRate), 1)];

                currentMissProb = currentMissProb + 0.05;
            else
                % Drop (simulate packet miss)
                missedPacket = zeros(sampleRate * slotDuration, 1);
                finWf = [finWf; missedPacket];
                currentMissProb = currentMissProb - 0.1;
            end

            % Truncate if signal exceeds time duration
            if length(finWf) > timeDuration * sampleRate
                finWf = finWf(1:timeDuration * sampleRate);
            end
        end
    end

    % --- Apply frequency offset and noise ---
    finWf = fOff(finWf);
    noisyWf = awgn(finWf, 20);  % Add AWGN with 20 dB SNR

end
