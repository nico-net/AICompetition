function [noisyWf, finWf] = myBluetoothHelper(packetType, ChannelType, txPower)
%MYBLUETOOTHHELPER Simulates a Bluetooth transmission with channel effects and hopping
%
%   [noisyWf, finWf] = myBluetoothHelper(packetType, ChannelType, txPower)
%
%   Simulates a Bluetooth waveform transmission of a given packet type
%   over a specified channel model (Rayleigh or Rician), applying power
%   scaling and frequency hopping. The output includes the noisy waveform
%   and the clean waveform before noise.
%
%   Inputs:
%     - packetType:   String specifying the Bluetooth packet type (e.g., 'DH1', '2-DH3', etc.)
%     - ChannelType:  Channel type to simulate ('Rayleigh', 'Rician', or others for no channel)
%     - txPower:      Transmit power in dBm (e.g., 0, 10)
%
%   Outputs:
%     - noisyWf:      The waveform after channel impairments and AWGN
%     - finWf:        The clean transmitted waveform after hopping and power scaling

    % --- Simulation parameters ---
    timeSimulation = 20e-3;        % Total simulation time in seconds
    slotDuration = 625e-6;         % Bluetooth slot duration (625 μs)
    targetSampleRate = 80e6;       % Target sample rate for resampling and alignment

    % --- Configure Bluetooth packet ---
    cfgBt = bluetoothWaveformConfig;
    cfgBt.PacketType = packetType;
    cfgBt.SamplesPerSymbol = 20;

    % Extract properties for this packet type
    [cfgBt.PayloadLength, slotsLength, phyMode, ~, randomProfile] = myBtPacketFinder(packetType);
    currentRandomProfile = randomProfile;
    cfgBt.Mode = phyMode;

    % --- Set up derived parameters ---
    symbolRate = 1e6;                              % 1 Msymbol/s
    sampleRate = symbolRate * cfgBt.SamplesPerSymbol;
    octetLength = 8;
    inputClock = randi([1, 2^28 - 1]);             % Random BT clock init
    numSlots = timeSimulation / slotDuration;      % Total number of 625μs slots

    % --- Frequency hopping setup ---
    btHop = bluetoothFrequencyHop;
    btHop.DeviceAddress = cfgBt.DeviceAddress;

    finWf = [];  % Final clean waveform

    % Optional fade-in/out windowing (unused but precomputed)
    L = 5000;
    fadeIn = hann(2*L); fadeIn = fadeIn(1:L);
    fadeOut = hann(2*L); fadeOut = fadeOut(L+1:end);
    hannWdw = hann(50000);

    % --- Channel model setup ---
    switch ChannelType
        case 'Rician'
            chan = comm.RicianChannel;
            chan.SampleRate = sampleRate;
            chan.PathDelays = [0 50e-9 150e-9 300e-9];
            chan.AveragePathGains = [0 -3 -8 -15];   % Indoor BT model
            chan.KFactor = 8;
            chan.MaximumDopplerShift = 12;           % Walking speed
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
            % No channel applied
    end

    % --- Transmit power scaling ---
    txPower_W = 10^((txPower - 30)/10);      % Convert dBm to Watts
    scalingFactor = sqrt(txPower_W);         % Amplitude scaling

    % --- Generate and transmit packets ---
    i = 0;
    while (i < numSlots)
        if (rand > currentRandomProfile)
            % Generate payload bits and waveform
            dataBits = randi([0 1], cfgBt.PayloadLength * octetLength, 1);
            wf = bluetoothWaveformGenerator(dataBits, cfgBt);
            wf = scalingFactor * wf;  % Apply transmit power

            % Pass through selected channel
            switch ChannelType
                case {'Rician', 'Rayleigh'}
                    wfChan = chan(wf);
                otherwise
                    wfChan = wf;
            end

            % Resample (oversample by 4×)
            wfChan = resample(wfChan, 4, 1);

            % Apply Bluetooth frequency hopping
            ch = btHop.nextHop(inputClock);
            fOff = comm.PhaseFrequencyOffset;
            fOff.FrequencyOffset = ch * 1e6;      % Frequency hop in Hz
            fOff.SampleRate = sampleRate * 4;
            fOffwf = fOff(wfChan);
            release(fOff);

            % Generate slot-compliant signal
            wfCompl = [fOffwf; zeros(slotDuration * targetSampleRate, 1)];

            % Update simulation parameters
            inputClock = inputClock + 2 * slotsLength;
            i = i + slotsLength;
            currentRandomProfile = currentRandomProfile + 0.1;
        else
            % Silent slot (no transmission)
            wfCompl = zeros(targetSampleRate * slotDuration * slotsLength, 1);
            currentRandomProfile = randomProfile;
            inputClock = inputClock + 2 * slotsLength;
            i = i + slotsLength;
        end

        % Append to final waveform
        finWf = [finWf; wfCompl];

        % Trim if we exceeded simulation time
        if i > numSlots
            finWf = finWf(1:timeSimulation * targetSampleRate);
        end
    end

    % Add AWGN (simulating noise floor)
    noisyWf = awgn(finWf, 20);

    % ---------------------------------------------------------------------
    % Helper function to look up packet properties
    % ---------------------------------------------------------------------
    function [payLoadLen, slotNum, phyMode, syncProfile, randomProfile] = myBtPacketFinder(packetType)
        switch packetType
            case 'FHS', payLoadLen = 18; slotNum = 1; phyMode = 'BR'; syncProfile = 'SCO'; randomProfile = 0.8;
            case 'DM1', payLoadLen = 17; slotNum = 1; phyMode = 'BR'; syncProfile = 'SCO'; randomProfile = 0.5;
            case 'DH1', payLoadLen = 27; slotNum = 1; phyMode = 'BR'; syncProfile = 'ACL'; randomProfile = 0.3;
            case 'DM3', payLoadLen = 121; slotNum = 3; phyMode = 'BR'; syncProfile = 'ACL'; randomProfile = 0.3;
            case 'DH3', payLoadLen = 183; slotNum = 3; phyMode = 'BR'; syncProfile = 'ACL'; randomProfile = 0.3;
            case 'DM5', payLoadLen = 224; slotNum = 5; phyMode = 'BR'; syncProfile = 'ACL'; randomProfile = 0.3;
            case 'DH5', payLoadLen = 339; slotNum = 5; phyMode = 'BR'; syncProfile = 'ACL'; randomProfile = 0.3;
            case '2-DH1', payLoadLen = 54; slotNum = 1; phyMode = 'EDR2M'; syncProfile = 'ACL'; randomProfile = 0.3;
            case '2-DH3', payLoadLen = 367; slotNum = 3; phyMode = 'EDR2M'; syncProfile = 'ACL'; randomProfile = 0.3;
            case '2-DH5', payLoadLen = 679; slotNum = 5; phyMode = 'EDR2M'; syncProfile = 'ACL'; randomProfile = 0.3;
            case '3-DH1', payLoadLen = 83; slotNum = 1; phyMode = 'EDR3M'; syncProfile = 'ACL'; randomProfile = 0.5;
            case '3-DH3', payLoadLen = 552; slotNum = 3; phyMode = 'EDR3M'; syncProfile = 'ACL'; randomProfile = 0.3;
            case '3-DH5', payLoadLen = 1021; slotNum = 5; phyMode = 'EDR3M'; syncProfile = 'ACL'; randomProfile = 0.3;
            case 'HV1', payLoadLen = 10; slotNum = 1; phyMode = 'BR'; syncProfile = 'SCO'; randomProfile = 0.1;
            case 'HV2', payLoadLen = 20; slotNum = 1; phyMode = 'BR'; syncProfile = 'SCO'; randomProfile = 0.1;
            case 'HV3', payLoadLen = 30; slotNum = 1; phyMode = 'BR'; syncProfile = 'SCO'; randomProfile = 0.1;
            case 'DV',  payLoadLen = 19; slotNum = 1; phyMode = 'BR'; syncProfile = 'SCO'; randomProfile = 0.5;
            case 'EV3', payLoadLen = 30; slotNum = 1; phyMode = 'BR'; syncProfile = 'eSCO'; randomProfile = 0.1;
            case 'EV4', payLoadLen = 120; slotNum = 3; phyMode = 'BR'; syncProfile = 'eSCO'; randomProfile = 0.2;
            case 'EV5', payLoadLen = 180; slotNum = 3; phyMode = 'BR'; syncProfile = 'eSCO'; randomProfile = 0.2;
            case '2-EV3', payLoadLen = 60; slotNum = 1; phyMode = 'EDR2M'; syncProfile = 'eSCO'; randomProfile = 0.1;
            case '2-EV5', payLoadLen = 360; slotNum = 3; phyMode = 'EDR2M'; syncProfile = 'eSCO'; randomProfile = 0.2;
            case '3-EV3', payLoadLen = 90; slotNum = 1; phyMode = 'EDR3M'; syncProfile = 'eSCO'; randomProfile = 0.1;
            case '3-EV5', payLoadLen = 540; slotNum = 3; phyMode = 'EDR3M'; syncProfile = 'eSCO'; randomProfile = 0.2;
            otherwise,  payLoadLen = 18; slotNum = 1; phyMode = 'BR'; syncProfile = 'eSCO'; randomProfile = 0.8;
        end
    end
end
