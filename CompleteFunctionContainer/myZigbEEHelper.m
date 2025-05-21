function [noisyWf, wfFin] = myZigbEEHelper(spc,numPackets, centerFreq, ChannelType)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

zbCfg = lrwpanOQPSKConfig;
zbCfg.SamplesPerChip = spc;
ISMstartFreq = 2402e6;
timeDuration = 20e-3;

%2405 + 5(k-11) Mhz

nativeSampleRate = zbCfg.SampleRate;
targetSampleRate = 80e6;
packetTimeDuration = 4.2565e-3; %Packet length with PSDU = 127 bytes, 4,2565 ms

switch numPackets
    case 1
        idleTime = 0;
    case {2 3}
        idleTime = 0.0005 + (0.005 - 0.0005) * rand;
    case 4
        minVal = (0.02 - packetTimeDuration * 4)/4;
        maxVal = (0.02 - packetTimeDuration * 4)/3;
        idleTime = minVal + (maxVal - minVal) * rand;
end

[upP, downQ] = rat(targetSampleRate/nativeSampleRate);

wf = lrwpanWaveformGenerator(randi([0 1], zbCfg.PSDULength*8, 1),zbCfg, "NumPackets", numPackets, "IdleTime", idleTime);


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
end

%Make it of correct length
%Cut last IdleTime
wfChan = wfChan(1:end - floor(zbCfg.SampleRate * idleTime));

if (length(wfChan) < zbCfg.SampleRate * timeDuration)
    zerosToAdd = zbCfg.SampleRate * timeDuration - length(wfChan);
    zerosBefore = floor(rand * zerosToAdd);
    zerosAfter = zerosToAdd - zerosBefore;
    wfChan = [zeros(zerosBefore, 1); wfChan; zeros(zerosAfter, 1)];
else 
    wfChan = wfChan(1: zbCfg.SampleRate * timeDuration);
    zerosAfter = 0;
    zerosBefore = 0;
end


wfRes = resample(wfChan, upP, downQ);

if (length(wfRes) > targetSampleRate * timeDuration)
    if (zerosAfter > zerosBefore)
        wfRes = wfRes(1:end - (length(wfRes) - targetSampleRate * timeDuration));
    else
        wfRes = wfRes((length(wfRes)-targetSampleRate * timeDuration) + 1:end);
    end
else 
    wfRes = [wfRes; zeros(targetSampleRate * timeDuration - length(wfRes))];
end




fOff = comm.PhaseFrequencyOffset;
fOff.SampleRate = targetSampleRate;
fOff.FrequencyOffset = centerFreq - ISMstartFreq;

wfFin = fOff(wfRes);
release(fOff);




noisyWf = awgn(wfFin, 20);

end