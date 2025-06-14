try
    % --- CONFIGURABLE PARAMETERS ---
    imageSize = {[1024, 1024]};
    gain = -10;
    sr = 10e6;                  % Sampling rate in Hz
    frameDuration = 20e-3;      % Frame duration in seconds
    pauseBetweenFrames = 2;     % Pause between transmissions (seconds)

    % --- SDR TRANSMITTER INITIALIZATION ---
    tx = sdrtx('Pluto', ...
        'BasebandSampleRate', sr, ...
        'Gain', gain);

    % --- TRANSMISSION LOOP ---
    while true
        % Randomize center frequency
        possibleCarrierFrequencies = linspace(2.41e9, 2.47e9, 100);
        carrierFrequency = possibleCarrierFrequencies(randi(100));
        tx.CenterFrequency = carrierFrequency;

        % Generate waveform and transmit
        helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, carrierFrequency);

        pause(pauseBetweenFrames); % Small pause to protect hardware
    end

catch ME
    % --- HANDLE CTRL+C AND OTHER ERRORS ---
    if strcmp(ME.identifier, 'MATLAB:terminatedByUser') || strcmp(ME.identifier, 'MATLAB:OperationTerminated')
        disp('Transmission ended');
    else
        disp('An unexpected error occurred:');
        disp(ME.message);
    end

    % --- ALWAYS RELEASE SDR RESOURCES ---
    if exist('tx', 'var')
        release(tx);
    end
end
