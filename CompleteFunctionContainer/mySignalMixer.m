function wfFin = mySignalMixer(waveforms)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

sampleRate = 80e6;
timeDuration = 0.02; % seconds


wfFin = zeros(1600000,1);
for i=1:size(waveforms, 2)
    wfFin = wfFin + waveforms(:, i);
end

wfFin = awgn(wfFin, 20);

end