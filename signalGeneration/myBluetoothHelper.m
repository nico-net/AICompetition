function [noisyWf,finWf] = myBluetoothHelper(PacketType, ChannelType)


timeSimulation = 20e-3; %seconds
slotDuration = 625e-6; %seconds
txCenterFreq = 2441e6;


cfgBt = bluetoothWaveformConfig;
cfgBt.Mode = 'BR';
cfgBt.PacketType = PacketType;
cfgBt.SamplesPerSymbol = 20;
%cfgBt.DeviceAddress = generateBTAddress;

cfgBt.PayloadLength = 18; %TODO: Get packetLength and decide slots length
slotsLength = 1; %TODO: Get slotlength

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
        chan.SammpleRate = sampleRate;
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




end