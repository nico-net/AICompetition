function wfFin = mySignalMixerInterf(waveforms, timeDuration, noisePower)

    srTotal = 80e6;  % [Hz] - System sampling rate
    

    wfFin = zeros(timeDuration * srTotal, 1);  % Complex zeros for I/Q data

    for i = 1:size(waveforms, 2)  % Loop over each signal (column)
        
        rxPower_dB = 10 * log10(max((abs(waveforms(:,i))).^2));
        fprintf("Signal %d rx power: %.4f dB\n", i, rxPower_dB);

        wfFin = wfFin + waveforms(:, i);
    end
    

    noiseStdDev = sqrt(noisePower/2);
    

    noiseReal = randn(size(wfFin));      % In-phase component
    noiseImag = randn(size(wfFin));      % Quadrature component
    

    noise = noiseStdDev * (noiseReal + 1i * noiseImag);
    

    actualNoisePower_dB = 10 * log10(mean((abs(noise)).^2));
    fprintf("Actual noise power: %.4f dB\n", actualNoisePower_dB);
    

    numInterf = randi([2 3]);
    fprintf("Adding %d interference source(s)\n", numInterf);

    interf = generateInterference(numInterf);
    

    wfFin = wfFin + interf;
    wfFin = wfFin + noise;
    
end