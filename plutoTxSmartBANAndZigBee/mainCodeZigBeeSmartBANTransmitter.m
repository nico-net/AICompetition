% ZigBee/SmartBAN Over-the-Air Transmitter using PlutoSDR
%
% This script initializes a PlutoSDR transmitter and repeatedly transmits
% either a ZigBee or SmartBAN waveform based on a given probability.
% The signal's spectrogram is generated before each transmission.
%
% The carrier frequency is randomly chosen within the 2.4 GHz ISM band.
% This can be used for AI training/testing pipelines that analyze live
% wireless spectrograms.

try
    % --- CONFIGURABLE PARAMETERS ---
    imageSize = {[1024, 1024]};      % Spectrogram image size
    gain = -5;                       % Transmit gain in dB
    sr = 8e6;                        % Sampling rate in Hz
    frameDuration = 4.2565e-3;       % Frame duration in seconds (~ZigBee packet length)
    pauseBetweenFrames = 1e-3;       % Pause between transmissions
    transmissionProbability = 1;     % 1 = always transmit, <1 = transmit with that probability

    % --- RANDOM CENTER FREQUENCY (simulate hopping/interference) ---
    possibleCarrierFrequencies = linspace(2.41e9, 2.47e9, 13); % 13 channels in ISM band
    carrierFrequency = possibleCarrierFrequencies(randi(13));  % Randomly pick one

    % --- SDR TRANSMITTER INITIALIZATION ---
    tx = sdrtx('Pluto', ...
        'RadioID', 'usb:0', ...
        'BasebandSampleRate', sr, ...
        'Gain', gain, ...
        'CenterFrequency', carrierFrequency);

    % --- PRELOAD WAVEFORMS (ZigBee and SmartBAN) ---
    waveforms = [];
    for signal = 1:2
        wfClean = generateWaveform(signal, sr);  % Generate waveform (1=ZigBee, 2=SmartBAN)
        waveforms = [waveforms, wfClean];        % Append to matrix
    end

    % --- TRANSMISSION LOOP ---
    while true
        % Generate waveform, plot spectrogram, and transmit via Pluto
        helperZigBeeSmartBANSignalGeneratorForSDR( ...
            tx, frameDuration, sr, imageSize, waveforms, transmissionProbability);
        
        pause(pauseBetweenFrames);  % Brief pause to prevent hardware overheating
    end

catch ME
    % --- HANDLE CTRL+C OR UNEXPECTED ERRORS ---
    if strcmp(ME.identifier, 'MATLAB:terminatedByUser') || strcmp(ME.identifier, 'MATLAB:OperationTerminated')
        disp('Transmission ended by user.');
    else
        disp('An unexpected error occurred:');
        disp(ME.message);
    end

    % --- ENSURE HARDWARE RESOURCES ARE RELEASED ---
    if exist('tx', 'var')
        release(tx);
    end
end


function wfFin = generateWaveform(numOfSignal, sr)
% generateWaveform   Generate synthetic ZigBee or SmartBAN waveform
%
%   wfFin = generateWaveform(numOfSignal, sr)
%
%   Inputs:
%       numOfSignal   - Signal type: 1 = ZigBee, 2 = SmartBAN
%       sr            - Sampling rate (Hz)
%
%   Output:
%       wfFin         - Complex baseband waveform to transmit
%
%   Description:
%       Depending on the signal type selected, this function calls the
%       appropriate helper function to generate the baseband waveform.

    % --- INPUT VALIDATION ---
    if ~isscalar(numOfSignal) || ~isnumeric(numOfSignal) || floor(numOfSignal) ~= numOfSignal
        error('Input numOfSignal must be an integer scalar.');
    end
    if numOfSignal < 1 || numOfSignal > 2
        error('numOfSignal must be either 1 (ZigBee) or 2 (SmartBAN).');
    end

    % --- SIGNAL GENERATION ---
    switch numOfSignal
        case 1  % ZigBee
            spc = 4;                  % Samples per chip (controls oversampling)
            wfFin = helperZigBeeSDR(spc);

        case 2  % SmartBAN
            wfFin = helperSmartBANSDR(sr);
    end
end
