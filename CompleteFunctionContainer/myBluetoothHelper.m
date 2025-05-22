function [noisyWf,finWf] = myBluetoothHelper(packetType, ChannelType)


timeSimulation = 20e-3; %seconds
slotDuration = 625e-6; %seconds
targetSampleRate = 80e6;


cfgBt = bluetoothWaveformConfig;
cfgBt.PacketType = packetType;
cfgBt.SamplesPerSymbol = 20;
%cfgBt.DeviceAddress = generateBTAddress;

[cfgBt.PayloadLength, slotsLength, phyMode, syncProfile, randomProfile] = myBtPacketFinder(packetType);
currentRandomProfile = randomProfile;
cfgBt.Mode = phyMode;

symbolRate = 1e6;
sampleRate = symbolRate * cfgBt.SamplesPerSymbol;
octetLength = 8;
inputClock = randi([1, 2^28-1]);


numSlots = timeSimulation/slotDuration;

btHop = bluetoothFrequencyHop;
btHop.DeviceAddress = cfgBt.DeviceAddress;
finWf = [];

L = 5000;
fadeIn = hann(L*2);
fadeIn = fadeIn(1:L);
fadeOut = hann(L*2);
fadeOut = fadeOut(L + 1:end);

hannWdw = hann(50000);
switch ChannelType
    case 'Rician'
        chan = comm.RicianChannel;
        chan.SampleRate = sampleRate;
        chan.PathDelays = [0 50e-9 150e-9 300e-9];
        chan.AveragePathGains = [0 -3 -8 -15]; %Typical model for indoor BT
        chan.KFactor = 8;   % LoS indoor
        chan.MaximumDopplerShift = 12;  % walking speed doppler
        chan.DopplerSpectrum = doppler('Jakes');
        chan.NormalizePathGains = true;
    case 'Rayleigh'
        chan = comm.RayleighChannel;
        chan.SampleRate = sampleRate;
        chan.PathDelays        = [0 50e-9 150e-9 300e-9];    % seconds
        chan.AveragePathGains  = [0 -3  -8   -15   ];       % dB
        % Maximum Doppler shift for ~1 m/s
        fD = (1/3e8)*2.4e9;        % ≈8 Hz
        chan.MaximumDopplerShift = 12;         % e.g. moderate walking speed
        chan.DopplerSpectrum     = doppler('Jakes');


    otherwise
end


for i = 1:slotsLength:numSlots
    if (rand > currentRandomProfile)
        dataBits = randi([0 1], cfgBt.PayloadLength * octetLength, 1);
        wf = bluetoothWaveformGenerator(dataBits, cfgBt);
        switch ChannelType
            case 'Rician'
                wfChan = chan(wf);
            case 'Rayleigh'
                wfChan = chan(wf);
            otherwise
                wfChan = wf;
        end
        %Apply channel
        wfChan = resample(wfChan, 4, 1);
        ch = btHop.nextHop(inputClock);
        fOff = comm.PhaseFrequencyOffset;
        fOff.FrequencyOffset = ch*1e6;
        fOff.SampleRate = sampleRate * 4;
        fOffwf = fOff(wfChan);
        %fOffwf(1:L) = fOffwf(1:L).*fadeIn;
        %fOffwf(end - L + 1:end) = fOffwf(end - L + 1:end).*fadeOut;
        %fOffwf = fOffwf.*hannWdw;
        i = i + 1;
        inputClock = inputClock + 2;
        inputClock = inputClock + 2*slotsLength;
        wfCompl = [fOffwf; zeros(slotDuration * targetSampleRate, 1)];
        release(fOff);
        currentRandomProfile = currentRandomProfile + 0.1
    else
        wfCompl = zeros(targetSampleRate*slotDuration*slotsLength, 1);
        currentRandomProfile = randomProfile
        inputClock = inputClock + 2*slotsLength;
        i = i + slotsLength;
    end
    finWf = [finWf; wfCompl];
end   

noisyWf = awgn(finWf, 20);



    function [payLoadLen, slotNum, phyMode, syncProfile, randomProfile] = myBtPacketFinder(packetType)

    switch packetType
        case 'FHS' 
            payLoadLen = 18;
            slotNum = 1;  
            phyMode = 'BR';
            syncProfile = 'SCO';
            randomProfile = 0.8;
        case 'DM1'
            payLoadLen = 17;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'SCO';
            randomProfile = 0.5;
        case 'DH1'
            payLoadLen = 27;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'ACL';
            randomProfile = 0.3; 
        case 'DM3' 
            payLoadLen = 121;
            slotNum = 3;
            phyMode = 'BR';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case 'DH3'
            payLoadLen = 183;
            slotNum = 3;
            phyMode = 'BR';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case 'DM5'
            payLoadLen = 224;
            slotNum = 5;
            phyMode = 'BR';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case 'DH5'
            payLoadLen = 339;
            slotNum = 5;
            phyMode = 'BR';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case '2-DH1' 
            payLoadLen = 54;
            slotNum = 1; 
            phyMode = 'EDR2M';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case '2-DH3'
            payLoadLen = 367;
            slotNum = 3;
            phyMode = 'EDR2M';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case '2-DH5'
            payLoadLen = 679;
            slotNum = 5;
            phyMode = 'EDR2M';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case '3-DH1'
            payLoadLen = 83;
            slotNum = 1; 
            phyMode = 'EDR3M';
            syncProfile = 'ACL';
            randomProfile = 0.5;
        case '3-DH3'
            payLoadLen = 552;
            slotNum = 3;
            phyMode = 'EDR3M';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case '3-DH5'
            payLoadLen = 1021;
            slotNum = 5;
            phyMode = 'EDR3M';
            syncProfile = 'ACL';
            randomProfile = 0.3;
        case 'HV1'
            payLoadLen = 10;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'SCO';
            randomProfile = 0.1;
        case 'HV2'
            payLoadLen = 20;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'SCO';
            randomProfile = 0.1;
        case 'HV3'
            payLoadLen = 30;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'SCO';
            randomProfile = 0.1;
        case 'DV'
            payLoadLen = 19;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'SCO';
            randomProfile = 0.5;
        case 'EV3'
            payLoadLen = 30;
            slotNum = 1; 
            phyMode = 'BR';
            syncProfile = 'eSCO';
            randomProfile = 0.1;
        case 'EV4'
            payLoadLen = 120;
            slotNum = 3;
            phyMode = 'BR';
            syncProfile = 'eSCO';
            randomProfile = 0.2;
        case 'EV5'
            payLoadLen = 180;
            slotNum = 3;
            phyMode = 'BR';
            syncProfile = 'eSCO';
            randomProfile = 0.2;
        case '2-EV3'
            payLoadLen = 60;
            slotNum = 1; 
            phyMode = 'EDR2M';
            syncProfile = 'eSCO';
            randomProfile = 0.1;
        case '2-EV5'
            payLoadLen = 360;
            slotNum = 3;
            phyMode = 'EDR2M';
            syncProfile = 'eSCO';
            randomProfile = 0.2;
        case '3-EV3'
            payLoadLen = 90;
            slotNum = 1; 
            phyMode = 'EDR3M';
            syncProfile = 'eSCO';
            randomProfile = 0.1;
        case '3-EV5'
            payLoadLen = 540;
            slotNum = 3;
            phyMode = 'EDR3M';
            syncProfile = 'eSCO';
            randomProfile = 0.2;
        otherwise
            payLoadLen = 18;
            slotNum = 1;
            phyMode = 'BR';
            syncProfile = 'eSCO';
            randomProfile = 0.8;
    end

end

end