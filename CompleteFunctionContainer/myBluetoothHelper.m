function [noisyWf,finWf] = myBluetoothHelper(PacketType, ChannelType)


timeSimulation = 20e-3; %seconds
slotDuration = 625e-6; %seconds


cfgBt = bluetoothWaveformConfig;
cfgBt.Mode = 'BR';
cfgBt.PacketType = PacketType;
cfgBt.SamplesPerSymbol = 20;
%cfgBt.DeviceAddress = generateBTAddress;

[cfgBt.PayloadLength, slotsLength] = myBtPacketFinder(PacketType);

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
    case 'Rayleigh'
        chan = comm.RayleighChannel;
        chan.SampleRate = sampleRate;
    otherwise
end


for i = 1:slotsLength:numSlots
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
    finWf = [finWf; fOffwf];
    inputClock = inputClock + 2;
    release(fOff);
end   

noisyWf = awgn(finWf, 10);



    function [payLoadLen, slotNum] = myBtPacketFinder(packetType)

    switch packetType
        case 'FHS' 
            payLoadLen = 18;
            slotNum = 1;    
        case 'DM1'
            payLoadLen = 17;
            slotNum = 1; 
        case 'DH1'
            payLoadLen = 27;
            slotNum = 1; 
        case 'DM3' 
            payLoadLen = 121;
            slotNum = 3;
        case 'DH3'
            payLoadLen = 183;
            slotNum = 3;
        case 'DM5'
            payLoadLen = 224;
            slotNum = 5;
        case 'DH5'
            payLoadLen = 339;
            slotNum = 5;
        case '2-DH1' 
            payLoadLen = 54;
            slotNum = 1; 
        case '2-DH3'
            payLoadLen = 367;
            slotNum = 3;
        case '2-DH5'
            payLoadLen = 679;
            slotNum = 5;
        case '3-DH1'
            payLoadLen = 83;
            slotNum = 1; 
        case '3-DH3'
            payLoadLen = 552;
            slotNum = 3;
        case '3-DH5'
            payLoadLen = 1021;
            slotNum = 5;
        case 'HV1'
            payLoadLen = 10;
            slotNum = 1; 
        case 'HV2'
            payLoadLen = 20;
            slotNum = 1; 
        case 'HV3'
            payLoadLen = 30;
            slotNum = 1; 
        case 'DV'
            payLoadLen = 19;
            slotNum = 1; 
        case 'EV3'
            payLoadLen = 30;
            slotNum = 1; 
        case 'EV4'
            payLoadLen = 120;
            slotNum = 3;
        case 'EV5'
            payLoadLen = 180;
            slotNum = 3;
        case '2-EV3'
            payLoadLen = 60;
            slotNum = 1; 
        case '2-EV5'
            payLoadLen = 360;
            slotNum = 3;
        case '3-EV3'
            payLoadLen = 90;
            slotNum = 1; 
        case '3-EV5'
            payLoadLen = 540;
            slotNum = 3;
        otherwise
            payLoadLen = 18;
            slotNum = 1;
    end

end

end