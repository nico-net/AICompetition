function [noisyWf, wfFin] = myWlanHelper(centerFreq,ChannelType)
%myWlanHelper Summary of this function goes here
%   Detailed explanation goes here

sampleRate = 80e6;

fOff = comm.PhaseFrequencyOffset;
fOff.SampleRate = sampleRate;

symbolRate = 20e6;
octetLength = 8;

ISMCenterFreq = 2402e6;

timeSpan = 20e-3;


wlanCfg = wlanHESUConfig;
packetDuration = 180e-6;
idleTime = 20e-6;

numPackets = timeSpan/(packetDuration+idleTime);


wf = wlanWaveformGenerator(randi([0 1], wlanCfg.getPSDULength*octetLength, 1), wlanCfg, ...
    "NumPackets", numPackets, "IdleTime", idleTime);

wf = scalingPower(wf);

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
        wfChan = wf;

end

wfRes = resample(wfChan, 4, 1);

fOff.FrequencyOffset = centerFreq - ISMCenterFreq;
wfFin = fOff(wfRes);
release(fOff);
noisyWf = awgn(wfFin, 20);

end