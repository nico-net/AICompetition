function [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, ChannelType, txPower)
%MYZIGBEEHELPER Simulates ZigBee waveform transmission with channel and noise
%
%   [noisyWf, wfFin] = myZigbEEHelper(spc, numPackets, centerFreq, ChannelType, txPower)
%
%   This function generates an IEEE 802.15.4-compliant ZigBee waveform using OQPSK modulation,
%   applies frequency offset to shift center frequency, simulates channel effects (Rician, Rayleigh, AWGN),
%   resamples to a fixed 80 MHz rate, and injects AWGN.
%
%   Inputs:
%     - spc         : Samples per chip (usually 2, 4, 8, etc.)
%     - numPackets  : Number of ZigBee packets to generate (1 to 4)
%     - centerFreq  : Center frequency of transmission in Hz (e.g., 2.405e9)
%     - ChannelType : 'Rician', 'Rayleigh', or 'AWGN'
%     - txPower     : Transmit power in dBm
%
%   Outputs:
%     - noisyWf     : Final waveform with noise
%     - wfFin       : Clean waveform (post channel and frequency offset)

    % --- Basic Configuration ---
    ISMstartFreq = 2402e6;                 % Start of ISM band for ZigBee
    timeDuration = 20e-3;                  % Total simulation duration (20 ms)
    targetSampleRate = 80e6;               % Final resampled rate
    packetTimeDuration = 4.2565e-3;        % Approx. duration for max ZigBee packet (127 bytes)
    
    % --- ZigBee PHY configuration ---
    zbCfg = lrwpanOQPSKConfig;
    zbCfg.SamplesPerChip = spc;           % Samples per chip (2, 4, 8...)
    nativeSampleRate = zbCfg.SampleRate;

    % --- Idle Time between packets based on number of packets ---
    switch numPackets
        case 1
            idleTime = 0;
        case {2, 3}
            idleTime = 0.0005 + (0.005 - 0.0005) * rand;  % Random delay between 0.5ms and 5ms
        case 4
            minVal = (timeDuration - packetTimeDuration * 4) / 4;
            maxVal = (timeDuration - packetTimeDuration * 4) / 3;
            idleTime = minVal + (maxVal - minVal) * rand;
        otherwise
            error("numPackets must be 1 to 4.");
    end

    % --- Generate baseband ZigBee waveform ---
    bits = randi([0 1], zbCfg.PSDULength * 8, 1);
    wf = lrwpanWaveformGenerator(bits, zbCfg, ...
        "NumPackets", numPackets, ...
        "IdleTime", idleTime);

    % --- Apply Transmit Power ---
    txPower_W = 10^((txPower - 30)/10);       % dBm to Watts
    scalingFactor = sqrt(txPower_W);          % Voltage gain
    wf = scalingFactor * wf;

    % --- Channel model application ---
    switch ChannelType
        case 'Rician'
            chan = comm.RicianChannel;
            chan.SampleRate = nativeSampleRate;
            wfChan = chan(wf);
        case 'Rayleigh'
            chan = comm.RayleighChannel;
            chan.SampleRate = nativeSampleRate;
            wfChan = chan(wf);
        case 'AWGN'
            wfChan = wf;
        otherwise
            error("Unsupported ChannelType.");
    end

    % --- Trim trailing idle time ---
    wfChan = wfChan(1:end - floor(nativeSampleRate * idleTime));

    % --- Time padding: insert at random offset in the 20 ms window ---
    if length(wfChan) < nativeSampleRate * timeDuration
        zerosToAdd = nativeSampleRate * timeDuration - length(wfChan);
        zerosBefore = floor(rand * zerosToAdd);
        zerosAfter = zerosToAdd - zerosBefore;
        wfChan = [zeros(zerosBefore, 1); wfChan; zeros(zerosAfter, 1)];
    else 
        wfChan = wfChan(1:nativeSampleRate * timeDuration);
        zerosBefore = 0;
        zerosAfter = 0;
    end

    % --- Resample to 80 MHz ---
    [upP, downQ] = rat(targetSampleRate / nativeSampleRate);
    wfRes = resample(wfChan, upP, downQ);

    % --- Ensure waveform is exactly 20 ms long after resampling ---
    targetLen = targetSampleRate * timeDuration;
    if length(wfRes) > targetLen
        if zerosAfter > zerosBefore
            wfRes = wfRes(1:end - (length(wfRes) - targetLen));
        else
            wfRes = wfRes((length(wfRes) - targetLen + 1):end);
        end
    else 
        wfRes = [wfRes; zeros(targetLen - length(wfRes), 1)];
    end

    % --- Apply Frequency Offset ---
    fOff = comm.PhaseFrequencyOffset;
    fOff.SampleRate = targetSampleRate;
    fOff.FrequencyOffset = centerFreq - ISMstartFreq;  % relative offset in Hz
    wfFin = fOff(wfRes);
    release(fOff);

    % --- Add white Gaussian noise (SNR = 20 dB) ---
    noisyWf = awgn(wfFin, 20);

end
