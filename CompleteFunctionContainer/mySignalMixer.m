function wfFin = mySignalMixer(waveforms, timeDuration, noisePower)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

srTotal = 80e6;
wfFin = zeros(timeDuration*srTotal,1);
for i=1:size(waveforms, 2)
    fprintf("rx power: %.4f\n", 10*log10(max((abs(waveforms(:,i))).^2)));
    wfFin = wfFin + waveforms(:, i);
end

noise = sqrt(noisePower/2) * (randn(size(wfFin)) + 1i * randn(size(wfFin)));

fprintf("noise power: %.4f\n", 10*log10(mean((abs(noise)).^2)));
wfFin = wfFin + noise;

end