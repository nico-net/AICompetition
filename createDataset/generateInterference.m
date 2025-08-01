function interfer = generateInterference(n, pMax)
%GENERATEINTERFERENCE  Generate up to 2 random interferers in 2400–2480 MHz band
%interfer = generateInterference(n)
%     n         - number of interferers (0,1,2)
%     interfer - complex baseband vector of length 1,600,000
%     pMax      - max power of the signal of interest


    fs     = 80e6;            % sample rate (Hz)
    N      = 1.6e6;           % number of samples (20 ms)
    t      = (0:N-1)'/fs;     % time vector (column)
    fCenter= 2.440e9;         % capture center frequency
    interfer = zeros(N,1);    % preallocate output


    min_dB = -30;
    max_dB = -10;
    dBr    = min_dB + (max_dB - min_dB)*rand(1);  % one per interferer
    linRatio = 10^(dBr/10);                        % linear ratio
    Pinterf  = pMax * linRatio;                % target power per interferer
    amp   = sqrt(Pinterf);

    % for each interferer
    for k = 1:n
        % pick a random absolute frequency in [2400,2480] MHz
        f_abs = 2.400e9 + 80e6*rand;
        f_bb  = f_abs - fCenter;   % baseband freq in Hz, in [-40e6, +40e6]

        % pick a random amplitude (low power)
        % amp = 0.02 + 0.08*rand;    % linear scale between 0.02 and 0.10

        % choose a random interferer type
        type = randi(4);
        isFoff = false;
        switch type
            case 1
                fOff = comm.PhaseFrequencyOffset();
                fOff.FrequencyOffset = f_bb;
                bw = 4e6 + 6e6*rand;            % 1–5 MHz
                L  = 128;                       % filter length
                h  = fir1(L, bw/(fs/2));        % bandlimiting FIR
                % generate complex white noise
                noise = filter(h,1,(randn(N,1)+1j*randn(N,1))/sqrt(2));

                % burst envelope: duration 5–15 ms
                burst_dur = 0.5e-3 + 2.5e-3*rand;
                burst_len = round(burst_dur * fs);
                start_pt  = randi([1, N-burst_len+1]);
                env = zeros(N,1);
                env(start_pt:(start_pt+burst_len-1)) = 1;
                currentInterfer = amp * (noise .* env);
                currentInterfer = fOff(currentInterfer);

                interfer = interfer + currentInterfer;

                fprintf("Generating a medium band noise burst\n")
                isFoff = true;

            case 2  % small FM‑modulated tone (voice‑like)
                f_dev = 100e3 * (0.5 + rand*0.5);   % 50–100 kHz deviation
                f_mod = 500 + 1500*rand;            % 0.5–2 kHz mod freq
                modsig = sin(2*pi*f_mod.*t);        % simple sinusoidal modulator
                instantaneous_phase = 2*pi*f_bb*t + (f_dev/fs)*cumsum(modsig);
                interfer = interfer + amp * exp(1j*instantaneous_phase) * 0.1;
                fprintf("Generating small FM-modulated tone\n");
                isFoff = false;

            case 3  % wideband noise burst
                fOff = comm.PhaseFrequencyOffset();
                fOff.FrequencyOffset = f_bb;
                bw = 12e6 + 8e6*rand;              % 10–20 MHz bandwidth
                % generate white noise, band‑limit via FIR
                L = 256;
                h = fir1(L, bw/(fs/2));
                noise = filter(h,1,(randn(N,1)+1j*randn(N,1))/sqrt(2));
                % apply random burst envelope
                burst_dur = 5e-4 + 1.5e-3*rand;       % 0,5 - 2,5 ms
                burst_len = round(burst_dur*fs);
                start_pt  = randi(N-burst_len);
                env = zeros(N,1);
                env(start_pt:(start_pt+burst_len-1)) = 1;
                currentInterfer = amp * (noise.*env);
                currentInterfer = fOff(currentInterfer);
                interfer = interfer + currentInterfer;
                fprintf("Generating wideband noise burst\n")
                isFoff = true;

            case 4  % impulse noise (short wideband pulses)
                fOff = comm.PhaseFrequencyOffset();
                fOff.FrequencyOffset = f_bb;
                num_imp = randi([10,20]);        % # of pulses
                for m=1:num_imp
                    pulse_len = 2000;   % 25 mircoseconds 
                    idx = randi(N-pulse_len);
                    pulse = gausswin(pulse_len);
                    pulse = fOff(pulse);
                    interfer(idx:(idx+pulse_len-1)) = ...
                        interfer(idx:(idx+pulse_len-1)) + amp*pulse * 5;
                end
                
                fprintf("Generating impulse noise\n")
                isFoff = true;
        end

        if (isFoff)
            release(fOff);
        end

    end

    % result is already length N; if n=0 it's all zeros
end
