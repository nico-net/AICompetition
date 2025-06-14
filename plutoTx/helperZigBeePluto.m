function cleanWf = helperZigBeePluto(spc, numPackets, timeDuration, sampleRate)

% Impostazioni ZigBee PHY
zbCfg = lrwpanOQPSKConfig;
zbCfg.SamplesPerChip = spc;

% Calcola sample rate nominale e target
nativeSampleRate = zbCfg.SampleRate;
targetSampleRate = sampleRate;  % fisso come nei tuoi altri script

% Durata pacchetto tipico (PHY + MAC)
packetTimeDuration = 4.2565e-3;

% Idle time dipendente dal numero di pacchetti
switch numPackets
    case 1
        idleTime = 0;
    case {2 3}
        idleTime = 0.0005 + (0.005 - 0.0005) * rand;
    case 4
        minVal = (timeDuration - packetTimeDuration * 4)/4;
        maxVal = (timeDuration - packetTimeDuration * 4)/3;
        idleTime = minVal + (maxVal - minVal) * rand;
end

% Generazione del waveform ZigBee puro
wf = lrwpanWaveformGenerator(randi([0 1], zbCfg.PSDULength*8, 1), zbCfg, ...
    "NumPackets", numPackets, "IdleTime", idleTime);

% Taglio eventuale idle time finale
wf = wf(1:end - floor(zbCfg.SampleRate * idleTime));

% Padding per raggiungere la durata totale desiderata
if (length(wf) < zbCfg.SampleRate * timeDuration)
    zerosToAdd = zbCfg.SampleRate * timeDuration - length(wf);
    zerosBefore = floor(rand * zerosToAdd);
    zerosAfter = zerosToAdd - zerosBefore;
    wf = [zeros(zerosBefore, 1); wf; zeros(zerosAfter, 1)];
else 
    wf = wf(1: zbCfg.SampleRate * timeDuration);
end

% Resampling per portarci a 80 MHz come il resto del tuo sistema
[upP, downQ] = rat(targetSampleRate/nativeSampleRate);
wfRes = resample(wf, upP, downQ);

% Taglio/riempimento per allineare alla durata precisa
if (length(wfRes) > targetSampleRate * timeDuration)
    wfRes = wfRes(1:targetSampleRate * timeDuration);
else
    wfRes = [wfRes; zeros(targetSampleRate * timeDuration - length(wfRes), 1)];
end

% Uscita: banda base pura a 80 MHz
cleanWf = wfRes;

end
