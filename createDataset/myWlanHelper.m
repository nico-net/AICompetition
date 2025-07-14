function [noisyWf, wfFin] = myWlanHelper(centerFreq, ChannelType, txPower)
%MYWLANHELPER Simulates a WLAN transmission with frequency offset and channel effects
%
%   [noisyWf, wfFin] = myWlanHelper(centerFreq, ChannelType, txPower)
%
%   This function generates a WLAN HE-SU waveform, applies a frequency
%   offset to shift its center frequency, simulates multipath fading 
%   through a channel model (Rayleigh or Rician), and adds white Gaussian noise.
%
%   Inputs:
%     - centerFreq   : Desired transmit center frequency (Hz), e.g. 2.415e9
%     - ChannelType  : Channel model to simulate ('Rayleigh', 'Rician', or other for flat)
%     - txPower      : Transmit power in dBm
%
%   Outputs:
%     - noisyWf      : Final waveform after channel and AWGN
%     - wfFin        : Clean waveform before noise, but after channel + freq offset

    % --- Basic waveform and simulation parameters ---
    sampleRate = 80e6;                 % Target sample rate (resampled later)
    symbolRate = 20e6;                 % Assumed base WLAN symbol rate (not directly used)
    octetLength = 8;
    ISMCenterFreq = 2402e6;           % Reference ISM band center for offset computation
    timeSpan = 20e-3;                 % Total duration of simulated signal (20 ms)

    % --- WLAN configuration (HE-SU) ---
    wlanCfg = wlanHESUConfig;         % High-Efficiency Single-User config (802.11ax)
    packetDuration = 180e-6;          % Estimated duration of one packet (HE-SU)
    idleTime = 20e-6;                 % Time between packets

    numPackets = timeSpan / (packetDuration + idleTime);  % Total number of packets to generate

    % --- Generate random payload waveform ---
    bits = randi([0 1], wlanCfg.getPSDULength * octetLength, 1);
    wf = wlanWaveformGenerator(bits, wlanCfg, ...
        "NumPackets", numPackets, ...
        "IdleTime", idleTime);

    % --- Apply transmit power scaling ---
    txPower_W = 10^((txPower - 30)/10);  % dBm to Watts
    scalingFactor = sqrt(txPower_W);     % Voltage scale
    wf = scalingFactor * wf;

    % --- Apply multipath fading channel ---
    switch ChannelType
        case 'Rician'
            chan = comm.RicianChannel;
            chan.SampleRate = sampleRate;
            wfChan = chan(wf);
        case 'Rayleigh'
            chan = comm.RayleighChannel;
            chan.SampleRate = sampleRate;
            wfChan = chan(wf);
        otherwise
            wfChan = wf;  % No channel effect
    end

    % --- Resample waveform (oversampling by 4x) ---
    wfRes = resample(wfChan, 4, 1);  % Upsample to 4× original rate

    % --- Apply frequency offset to simulate transmission at centerFreq ---
    fOff = comm.PhaseFrequencyOffset;
    fOff.SampleRate = sampleRate;
    fOff.FrequencyOffset = centerFreq - ISMCenterFreq;  % Relative offset from ISM center
    wfFin = fOff(wfRes);
    release(fOff);

    % --- Add white Gaussian noise ---
    noisyWf = awgn(wfFin, 20);  % 20 dB SNR

end
