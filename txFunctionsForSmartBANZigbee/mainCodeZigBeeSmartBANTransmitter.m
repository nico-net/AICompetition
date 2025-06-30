%% ========================================================================
%% SDR ZigBee SmartBAN Signal Transmission Script
%% ========================================================================
% This script transmits ZigBee SmartBAN signals using an ADALM-Pluto SDR
% The transmission operates in the 2.4 GHz ISM band with configurable
% parameters for research and testing purposes.
%
% Requirements:
%   - Communications Toolbox Support Package for ADALM-Pluto Radio
%   - ADALM-Pluto SDR hardware connected via USB
%   - helperZigBeeSmartBANSignalGeneratorForSDR function
%
% Author: Aragnetti Giacomo, Gallucci Nicola, Malagrinò Matteo
% Version: 1.1
%% ========================================================================

%% --- CONFIGURABLE PARAMETERS ---
% These parameters can be modified to adjust transmission characteristics

% Image processing parameters
imageSize = [1024, 1024];              % Image dimensions [width, height] in pixels
                                       % Used for data payload generation

% RF transmission parameters
gain = -6;                             % Transmission gain in dB
                                       % Negative values reduce transmission power
                                       % Range: typically -89.75 to 0 dB for PlutoSDR

sr = 10e6;                             % Sampling rate in Hz (10 MHz)
                                       % Higher rates provide better signal quality
                                       % but require more processing power

% Timing parameters
frameDuration = 20e-3;                 % Frame duration in seconds (20 ms)
                                       % Duration of each transmitted frame

pauseBetweenFrames = 10;             % Pause between transmissions in seconds (100 μs)
                                       % Prevents hardware overheating and allows
                                       % for receiver processing time

% Frequency configuration
% Generate array of possible carrier frequencies in 2.4 GHz ISM band
possibleCarrierFrequencies = linspace(2.41e9, 2.47e9, 20);  % 20 frequencies from 2.41-2.47 GHz

% Select random carrier frequencies for frequency hopping
% Note: Currently selects 2 specific frequencies instead of random
carrierFrequency = possibleCarrierFrequencies(randi(20, [1, 2]));
carrierFrequency = [2.43e9, 2.44e9];  % Override with specific frequencies (2.43 & 2.44 GHz)
                                       % These are common ZigBee channels 11 & 16

%% --- DISPLAY CONFIGURATION ---
fprintf('=== SDR ZigBee Transmission Configuration ===\n');
fprintf('Image Size: %dx%d pixels\n', imageSize(1), imageSize(2));
fprintf('Transmission Gain: %.1f dB\n', gain);
fprintf('Sampling Rate: %.2f MHz\n', sr/1e6);
fprintf('Frame Duration: %.1f ms\n', frameDuration*1000);
fprintf('Pause Between Frames: %.1f μs\n', pauseBetweenFrames*1e6);
fprintf('Carrier Frequencies: %.3f GHz, %.3f GHz\n', carrierFrequency(1)/1e9, carrierFrequency(2)/1e9);
fprintf('===============================================\n\n');

%% --- SDR TRANSMITTER INITIALIZATION ---
fprintf('Initializing ADALM-Pluto SDR transmitter...\n');

try
    % Create SDR transmitter object for ADALM-Pluto
    tx = sdrtx('Pluto', ...                    % Device type: ADALM-Pluto SDR
               'RadioID', 'usb:0', ...        % USB connection identifier
               'BasebandSampleRate', sr, ...   % Set sampling rate
               'Gain', gain);                  % Set transmission gain
    
    fprintf('SDR transmitter initialized successfully.\n');
    fprintf('Radio ID: usb:0\n');
    fprintf('Starting continuous transmission...\n');
    fprintf('Press Ctrl+C to stop transmission.\n\n');
    
catch initError
    fprintf('Error initializing SDR transmitter: %s\n', initError.message);
    return;
end

%% --- MAIN TRANSMISSION LOOP ---
% Continuous transmission loop - runs until manually stopped
transmissionCount = 0;  % Counter for transmitted frames

try
    while true
        % Increment transmission counter
        transmissionCount = transmissionCount + 1;
        
        % Optional: Randomize carrier frequency for frequency hopping
        % Uncomment the following lines to enable random frequency selection:
        % randomIndex = randi(length(possibleCarrierFrequencies), [1, 2]);
        % carrierFrequency = possibleCarrierFrequencies(randomIndex);
        
        % Generate and transmit ZigBee SmartBAN signal
        % This function should handle:
        % - Signal modulation
        % - Packet formatting
        % - Actual transmission via SDR
        helperZigBeeSmartBANSignalGeneratorForSDR(tx, frameDuration, sr, imageSize, carrierFrequency);
        
        % Display progress every 100 transmissions
        if mod(transmissionCount, 100) == 0
            fprintf('Transmitted %d frames...\n', transmissionCount);
        end
        
        % Pause between transmissions
        % This prevents hardware overheating and allows receiver processing time
        pause(pauseBetweenFrames);
    end
    
catch ME
    %% --- ERROR HANDLING ---
    % Handle different types of errors appropriately
    
    if strcmp(ME.identifier, 'MATLAB:terminatedByUser') || strcmp(ME.identifier, 'MATLAB:OperationTerminated')
        % User pressed Ctrl+C - normal termination
        fprintf('\n=== Transmission Terminated by User ===\n');
        fprintf('Total frames transmitted: %d\n', transmissionCount);
        fprintf('Total transmission time: %.2f seconds\n', transmissionCount * (frameDuration + pauseBetweenFrames));
        
    elseif contains(ME.identifier, 'SDR') || contains(ME.message, 'SDR')
        % SDR-related error
        fprintf('\n=== SDR Hardware Error ===\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('Check SDR connection and driver installation.\n');
        
    else
        % Unexpected error
        fprintf('\n=== Unexpected Error Occurred ===\n');
        fprintf('Error ID: %s\n', ME.identifier);
        fprintf('Error Message: %s\n', ME.message);
        fprintf('Stack trace:\n');
        for i = 1:length(ME.stack)
            fprintf('  File: %s, Function: %s, Line: %d\n', ...
                    ME.stack(i).file, ME.stack(i).name, ME.stack(i).line);
        end
    end
end

%% --- CLEANUP AND RESOURCE RELEASE ---
% Always release SDR resources, even if an error occurred
fprintf('\n=== Cleaning Up Resources ===\n');

if exist('tx', 'var') && ~isempty(tx)
    try
        release(tx);
        fprintf('SDR transmitter resources released successfully.\n');
    catch releaseError
        fprintf('Warning: Error releasing SDR resources: %s\n', releaseError.message);
    end
    clear tx;  % Clear the variable from workspace
else
    fprintf('No SDR resources to release.\n');
end

fprintf('Script execution completed.\n');

%% ========================================================================
%% FUNCTION REQUIREMENTS AND NOTES
%% ========================================================================
% 
% The helperZigBeeSmartBANSignalGeneratorForSDR function should implement:
% 
% 1. ZigBee packet structure generation
% 2. SmartBAN protocol compliance
% 3. OQPSK modulation (typical for ZigBee)
% 4. Proper timing and synchronization
% 5. Error checking and validation
% 
% Expected function signature:
% function helperZigBeeSmartBANSignalGeneratorForSDR(txObj, frameDur, sampleRate, imgSize, carrierFreq)
% 
% Parameters:
%   txObj       - SDR transmitter object
%   frameDur    - Frame duration in seconds
%   sampleRate  - Sampling rate in Hz
%   imgSize     - Image size for payload generation
%   carrierFreq - Array of carrier frequencies in Hz
% 
%% SAFETY AND COMPLIANCE NOTES
%% ========================================================================
% 
% 1. Ensure compliance with local RF regulations
% 2. The 2.4 GHz band is ISM but still has power limitations
% 3. Consider interference with WiFi, Bluetooth, and other devices
% 4. Use appropriate shielding in laboratory environments
% 5. Monitor transmission power levels
% 6. Implement proper error handling for hardware failures
% 
%% ========================================================================