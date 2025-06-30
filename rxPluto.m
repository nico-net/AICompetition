%% ========================================================================
%% CLASSIFICATION ON ADALM-PLUTO'S CAPTURES
%% ========================================================================
%
% This MATLAB script performs synchronized IQ data acquisition from two 
% ADALM-Pluto SDR devices operating at different center frequencies using
% parallel processing. The acquired signals are processed, combined, and
% analyzed using AI-based classification with spectrogram visualization.
%
% FEATURES:
%   - Parallel acquisition from two PlutoSDR devices
%   - Synchronized sampling with configurable timing
%   - Frequency shifting and signal combination
%   - AWGN noise addition for realistic scenarios
%   - High-quality spectrogram generation
%   - AI-based signal classification
%   - Automated resource management and cleanup
%
% REQUIREMENTS:
%   - Two ADALM-Pluto SDR devices (usb:0 and usb:1)
%   - Communications Toolbox Support Package for ADALM-Pluto Radio
%   - Parallel Computing Toolbox
%   - Signal Processing Toolbox
%   - Image Processing Toolbox
%   - Deep Learning Toolbox (for AI classification)
%   - Pretrained neural network model (variable: net)
%
% HARDWARE SETUP:
%   - PlutoSDR #1: Connected as 'usb:0', operates at 2.42 GHz
%   - PlutoSDR #2: Connected as 'usb:1', operates at 2.46 GHz
%
% Author: [Your Name]
% Date: [Current Date]
% Version: 2.0
%% ========================================================================

%% --- WORKSPACE INITIALIZATION ---
% Clear workspace while preserving the neural network model
clearvars -except net;
close all;

% Add path to visualization helper functions
% Ensure this path exists and contains required visualization functions
% visualizationPath = '/home/nicola-gallucci/Nicola/Matlab/AICHallenge/AICompetition/visualizationHelpers';
% if exist(visualizationPath, 'dir')
%     addpath(visualizationPath);
%     fprintf('Added visualization helpers path: %s\n', visualizationPath);
% else
%     warning('Visualization helpers path not found: %s', visualizationPath);
% end

% Verify neural network model availability
if ~exist('net', 'var') || isempty(net)
    error('Neural network model ''net'' not found. Please load the model before running this script.');
else
    fprintf('Neural network model loaded and ready.\n');
end

%% --- HARDWARE CONFIGURATION ---
fprintf('=== Configuring PlutoSDR Hardware ===\n');

% Common SDR parameters
commonConfig = struct( ...
    'GainSource', 'Manual', ...
    'Gain', 60, ...                              % Manual gain: 60 dB (high sensitivity)
    'EnableBurstMode', true, ...                 % Single-frame capture mode
    'BasebandSampleRate', 40e6, ...              % 40 MSPS for wide bandwidth
    'OutputDataType', 'double', ...              % High precision data type
    'SamplesPerFrame', 8e5 ...                   % 800k samples (~20ms at 40 MSPS)
);

% Configure PlutoSDR #1 (Lower frequency)
fprintf('Configuring PlutoSDR #1 (usb:0)...\n');
rx1 = sdrrx("Pluto", "RadioID", 'usb:0', ...
    'CenterFrequency', 2.42e9, ...               % 2.42 GHz (WiFi Channel 7)
    'GainSource', commonConfig.GainSource, ...
    'Gain', commonConfig.Gain, ...
    'EnableBurstMode', commonConfig.EnableBurstMode, ...
    'BasebandSampleRate', commonConfig.BasebandSampleRate, ...
    'OutputDataType', commonConfig.OutputDataType, ...
    'SamplesPerFrame', commonConfig.SamplesPerFrame);

fprintf('  - Center Frequency: %.3f GHz\n', 2.42);
fprintf('  - Gain: %d dB\n', commonConfig.Gain);
fprintf('  - Sample Rate: %.1f MSPS\n', commonConfig.BasebandSampleRate/1e6);

% Configure PlutoSDR #2 (Higher frequency)
fprintf('Configuring PlutoSDR #2 (usb:1)...\n');
rx2 = sdrrx("Pluto", "RadioID", 'usb:1', ...
    'CenterFrequency', 2.46e9, ...               % 2.46 GHz (WiFi Channel 11)
    'GainSource', commonConfig.GainSource, ...
    'Gain', commonConfig.Gain, ...
    'EnableBurstMode', commonConfig.EnableBurstMode, ...
    'BasebandSampleRate', commonConfig.BasebandSampleRate, ...
    'OutputDataType', commonConfig.OutputDataType, ...
    'SamplesPerFrame', commonConfig.SamplesPerFrame);

fprintf('  - Center Frequency: %.3f GHz\n', 2.46);
fprintf('Hardware configuration completed.\n\n');

%% --- PARALLEL PROCESSING SETUP ---
fprintf('=== Setting Up Parallel Processing ===\n');

% Check if parallel pool is already active
currentPool = gcp('nocreate');
if isempty(currentPool)
    fprintf('Starting parallel pool with 2 workers...\n');
    parpool(2);  % Two workers for two SDRs
    fprintf('Parallel pool started successfully.\n');
else
    fprintf('Using existing parallel pool with %d workers.\n', currentPool.NumWorkers);
    if currentPool.NumWorkers < 2
        warning('Parallel pool has fewer than 2 workers. Performance may be suboptimal.');
    end
end

%% --- ACQUISITION PARAMETERS ---
fprintf('=== Acquisition Parameters ===\n');

% Timing and synchronization
synchronizationDelay = 2;  % Seconds to wait before starting acquisition
startTime = datetime('now') + seconds(synchronizationDelay);
fprintf('Synchronized start time: %s\n', char(startTime));

% Data processing parameters
originalSampleRate = commonConfig.BasebandSampleRate;  % 40 MHz
oversamplingFactor = 2;  % Upsample by factor of 2
processedSampleRate = originalSampleRate * oversamplingFactor;  % 80 MHz

% Frequency shifting parameters
frequencyShift1 = -20e6;  % -20 MHz shift for SDR #1
frequencyShift2 = +20e6;  % +20 MHz shift for SDR #2
awgnSNR = 50;  % Signal-to-noise ratio in dB

% Acquisition control
frameIndex = 1;
totalFrames = 15;
fprintf('Total frames to acquire: %d\n', totalFrames);

% Spectrogram visualization parameters
spectrogramConfig = struct( ...
    'dbMin', -130, ...                           % Minimum dB level
    'dbMax', -50, ...                            % Maximum dB level
    'nfft', 4096, ...                            % FFT size for high resolution
    'windowSize', 256, ...                       % Hann window size
    'overlap', 10, ...                           % Overlap between windows
    'colormapResolution', 256, ...               % Color resolution
    'imageSize', [256, 256] ...                  % Output image dimensions
);

fprintf('Spectrogram configuration:\n');
fprintf('  - Dynamic range: %.0f to %.0f dB\n', spectrogramConfig.dbMin, spectrogramConfig.dbMax);
fprintf('  - FFT size: %d points\n', spectrogramConfig.nfft);
fprintf('  - Output image size: %dx%d\n', spectrogramConfig.imageSize(1), spectrogramConfig.imageSize(2));
fprintf('Setup completed.\n\n');

%% --- MAIN ACQUISITION AND PROCESSING LOOP ---
fprintf('=== Starting Data Acquisition Loop ===\n');
fprintf('Press Ctrl+C to stop acquisition early.\n\n');

try
    while frameIndex <= totalFrames
        fprintf('--- Frame %d/%d ---\n', frameIndex, totalFrames);
        
        % Close previous figures to manage memory
        close all;
        
        %% --- PARALLEL DATA ACQUISITION ---
        fprintf('Launching parallel acquisition...\n');
        acquisitionStartTime = tic;
        
        % Launch asynchronous acquisition on both PlutoSDRs
        future1 = parfeval(@acquirePlutoData, 1, rx1, startTime, frameIndex);
        future2 = parfeval(@acquirePlutoData, 1, rx2, startTime, frameIndex);
        
        % Wait for both acquisitions to complete and fetch results
        [completedIndex, firstResult] = fetchNext([future1, future2]);
        [~, secondResult] = fetchNext([future1, future2]);
        
        % Assign data based on which future completed first
        if completedIndex == 1
            data1 = firstResult;  % Data from SDR #1
            data2 = secondResult; % Data from SDR #2
        else
            data1 = secondResult; % Data from SDR #1
            data2 = firstResult;  % Data from SDR #2
        end
        
        acquisitionTime = toc(acquisitionStartTime);
        fprintf('Parallel acquisition completed in %.3f seconds\n', acquisitionTime);
        
        % Validate acquired data
        validateAcquiredData(data1, data2, commonConfig.SamplesPerFrame);
        
        %% --- SIGNAL PROCESSING ---
        fprintf('Processing acquired signals...\n');
        processingStartTime = tic;
        
        % Upsample both signals for frequency shifting
        fprintf('  Upsampling signals by factor of %d...\n', oversamplingFactor);
        dataUpsampled1 = resample(data1, oversamplingFactor, 1);
        dataUpsampled2 = resample(data2, oversamplingFactor, 1);
        
        % Create frequency offset objects
        frequencyOffset1 = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', frequencyShift1, ...
            'SampleRate', processedSampleRate ...
        );
        
        frequencyOffset2 = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', frequencyShift2, ...
            'SampleRate', processedSampleRate ...
        );
        
        % Apply frequency shifts and add AWGN
        fprintf('  Applying frequency shifts: %.1f MHz and %.1f MHz...\n', ...
                frequencyShift1/1e6, frequencyShift2/1e6);
        
        dataShiftedLow = awgn(frequencyOffset1(dataUpsampled1), awgnSNR, 'measured');
        dataShiftedHigh = awgn(frequencyOffset2(dataUpsampled2), awgnSNR, 'measured');
        
        % Combine frequency-shifted signals
        combinedWaveform = dataShiftedLow + dataShiftedHigh;
        
        processingTime = toc(processingStartTime);
        fprintf('Signal processing completed in %.3f seconds\n', processingTime);
        
        % Display signal statistics
        displaySignalStatistics(data1, data2, combinedWaveform);
        
        %% --- SPECTROGRAM GENERATION ---
        fprintf('Generating spectrogram...\n');
        spectrogramStartTime = tic;
        
        [spectrogramImage, powerSpectrum] = generateHighQualitySpectrogram( ...
            combinedWaveform, processedSampleRate, spectrogramConfig);
        
        spectrogramTime = toc(spectrogramStartTime);
        fprintf('Spectrogram generation completed in %.3f seconds\n', spectrogramTime);
        
        %% --- AI-BASED CLASSIFICATION ---
        fprintf('Performing AI classification...\n');
        classificationStartTime = tic;
        
        % Prepare data for neural network
        dlImage = dlarray(double(spectrogramImage), 'SSC');  % Spatial-Spatial-Channel format
        
        % Perform prediction
        prediction = predict(net, double(spectrogramImage));
        [~, predictedLabel] = max(prediction, [], 3);
        
        classificationTime = toc(classificationStartTime);
        fprintf('AI classification completed in %.3f seconds\n', classificationTime);
        
        %% --- VISUALIZATION ---
        fprintf('Creating visualization...\n');
        visualizationStartTime = tic;
        
        % Create main figure for results
        mainFigure = figure('Name', sprintf('Frame %d Analysis', frameIndex), ...
                           'NumberTitle', 'off', 'Position', [100, 100, 1200, 800]);
        
        % Display spectrogram with proper scaling
        figure("Name","Prediction vs Spectrogram")
        subplot(1, 2, 1);
        imshow(spectrogramImage);
        title(sprintf('Frame %d: Combined Signal Spectrogram', frameIndex));
        
        % Add colorbar for power scale
        colormap(parula(spectrogramConfig.colormapResolution));
        clim([spectrogramConfig.dbMin, spectrogramConfig.dbMax]);
        colorbarHandle = colorbar;
        colorbarHandle.Label.String = 'Power (dB)';
        
        % Display classification overlay
        subplot(1, 2, 2);
        plotOverLayed(spectrogramImage, predictedLabel, 1);
        title('AI Classification Overlay');
        
        figure("Other Statistics")
        % Display power spectrum statistics
        subplot(1, 2, 1);
        plotPowerSpectrum(powerSpectrum, processedSampleRate, spectrogramConfig);
        
        % Display acquisition summary
        subplot(1, 2, 2);
        displayAcquisitionSummary(frameIndex, totalFrames, acquisitionTime, ...
                                 processingTime, spectrogramTime, classificationTime);
        
        visualizationTime = toc(visualizationStartTime);
        fprintf('Visualization completed in %.3f seconds\n', visualizationTime);
        
        %% --- FRAME COMPLETION ---
        totalFrameTime = acquisitionTime + processingTime + spectrogramTime + ...
                        classificationTime + visualizationTime;
        fprintf('Frame %d completed in %.3f seconds total\n', frameIndex, totalFrameTime);
        
        % Wait for user input before continuing
        fprintf('Press any key to continue to next frame...\n');
        pause();
        
        frameIndex = frameIndex + 1;
        
        % Update start time for next acquisition
        startTime = datetime('now') + seconds(1);
    end
    
catch ME
    %% --- ERROR HANDLING ---
    fprintf('\n=== Error Occurred During Acquisition ===\n');
    fprintf('Error: %s\n', ME.message);
    fprintf('Frame: %d/%d\n', frameIndex, totalFrames);
    
    if contains(ME.message, 'PlutoSDR') || contains(ME.message, 'SDR')
        fprintf('SDR hardware error detected. Check connections and drivers.\n');
    elseif contains(ME.message, 'parallel') || contains(ME.message, 'worker')
        fprintf('Parallel processing error. Restarting parallel pool may help.\n');
    end
    
    % Display stack trace for debugging
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
end

%% --- CLEANUP AND RESOURCE MANAGEMENT ---
fprintf('\n=== Performing Cleanup ===\n');

try
    % Shutdown parallel pool
    fprintf('Shutting down parallel pool...\n');
    delete(gcp('nocreate'));
    fprintf('Parallel pool shutdown completed.\n');
    
    % Release SDR resources
    fprintf('Releasing SDR resources...\n');
    if exist('rx1', 'var')
        release(rx1);
        fprintf('SDR #1 resources released.\n');
    end
    
    if exist('rx2', 'var')
        release(rx2);
        fprintf('SDR #2 resources released.\n');
    end
    
    fprintf('All resources released successfully.\n');
    
catch cleanupError
    warning(cleanupError.identifier,'Error during cleanup: %s', cleanupError.message);
end

fprintf('Script execution completed.\n');

%% ========================================================================
%% HELPER FUNCTIONS
%% ========================================================================

function data = acquirePlutoData(rxObject, scheduledStartTime, frameNumber)
% acquirePlutoData - Synchronized data acquisition from PlutoSDR
%
% This function performs synchronized data acquisition by waiting until
% the specified start time before triggering the SDR capture.
%
% INPUTS:
%   rxObject          - PlutoSDR receiver object
%   scheduledStartTime - datetime object specifying when to start
%   frameNumber       - Current frame number (for logging)
%
% OUTPUTS:
%   data             - Acquired IQ samples (complex double array)

    % Wait for synchronized start time
    while datetime('now') < scheduledStartTime
        pause(0.00001);  % Minimal delay to prevent CPU overload
    end
    
    % Acquire data burst
    acquisitionStart = tic;
    data = rxObject();
    acquisitionDuration = toc(acquisitionStart);
    
    % Optional: Log acquisition timing (commented for performance)
    % fprintf('  Worker acquired frame %d in %.3f ms\n', frameNumber, acquisitionDuration*1000);
end

function validateAcquiredData(data1, data2, expectedSamples)
% validateAcquiredData - Validate acquired data integrity
%
% INPUTS:
%   data1, data2     - Acquired data arrays
%   expectedSamples  - Expected number of samples

    % Check data1
    if isempty(data1) || ~isnumeric(data1)
        error('Invalid data acquired from SDR #1');
    end
    
    if length(data1) ~= expectedSamples
        warning('SDR #1: Expected %d samples, got %d', expectedSamples, length(data1));
    end
    
    % Check data2
    if isempty(data2) || ~isnumeric(data2)
        error('Invalid data acquired from SDR #2');
    end
    
    if length(data2) ~= expectedSamples
        warning('SDR #2: Expected %d samples, got %d', expectedSamples, length(data2));
    end
    
    fprintf('  Data validation passed\n');
end

function displaySignalStatistics(data1, data2, combinedData)
% displaySignalStatistics - Display signal power and quality metrics

    fprintf('  Signal Statistics:\n');
    fprintf('    SDR #1 - RMS: %.3f, Peak: %.3f\n', rms(data1), max(abs(data1)));
    fprintf('    SDR #2 - RMS: %.3f, Peak: %.3f\n', rms(data2), max(abs(data2)));
    fprintf('    Combined - RMS: %.3f, Peak: %.3f\n', rms(combinedData), max(abs(combinedData)));
end

function [spectrogramImage, powerSpectrum] = generateHighQualitySpectrogram(waveform, sampleRate, config)
% generateHighQualitySpectrogram - Create high-quality spectrogram image

    % Create Hann window
    windowFunction = hann(config.windowSize);
    
    % Compute spectrogram
    [~, ~, ~, powerSpectrum] = spectrogram(waveform, windowFunction, config.overlap, ...
                                          config.nfft, sampleRate, 'centered', 'psd');
    
    % Convert to dB scale
    powerDB = 10 * log10(abs(powerSpectrum') + eps);
    
    % Apply dynamic range clipping
    powerClipped = min(max(powerDB, config.dbMin), config.dbMax);
    
    % Normalize to [0,1] range
    powerNormalized = (powerClipped - config.dbMin) / (config.dbMax - config.dbMin);
    
    % Convert to image and resize
    grayImage = imresize(im2uint8(powerNormalized), config.imageSize, "nearest");
    
    % Convert to RGB using parula colormap
    spectrogramImage = im2uint8(flipud(ind2rgb(grayImage, parula(config.colormapResolution))));
end

function plotPowerSpectrum(powerSpectrum, sampleRate, config)
% plotPowerSpectrum - Plot average power spectrum

    % Compute average power spectrum
    avgPower = mean(abs(powerSpectrum), 2);
    freqVector = linspace(-sampleRate/2, sampleRate/2, length(avgPower)) / 1e6;  % MHz
    
    plot(freqVector, 10*log10(avgPower + eps));
    xlabel('Frequency (MHz)');
    ylabel('Power (dB)');
    title('Average Power Spectrum');
    grid on;
    ylim([config.dbMin, config.dbMax]);
end

function displayAcquisitionSummary(currentFrame, totalFrames, acqTime, procTime, specTime, classTime)
% displayAcquisitionSummary - Display timing summary

    % Create summary text
    summaryText = {
        sprintf('Frame: %d/%d', currentFrame, totalFrames);
        sprintf('Progress: %.1f%%', (currentFrame/totalFrames)*100);
        '';
        'Timing Breakdown:';
        sprintf('Acquisition: %.2f s', acqTime);
        sprintf('Processing: %.2f s', procTime);
        sprintf('Spectrogram: %.2f s', specTime);
        sprintf('Classification: %.2f s', classTime);
        sprintf('Total: %.2f s', acqTime + procTime + specTime + classTime);
    };
    
    % Display as text in subplot
    text(0.1, 0.9, summaryText, 'FontSize', 12, 'FontFamily', 'monospace', ...
         'VerticalAlignment', 'top', 'Units', 'normalized');
    axis off;
    title('Acquisition Summary');
end

%% ========================================================================
%% NOTES AND REQUIREMENTS
%% ========================================================================
%
% EXTERNAL FUNCTION REQUIREMENTS:
%   - plotOverLayed(image, labels, option) - Visualization helper function
%     Must be available in the specified path or MATLAB path
%
% NEURAL NETWORK REQUIREMENTS:
%   - Variable 'net' must contain a trained neural network
%   - Network should accept image input and produce classification output
%   - Compatible with MATLAB's predict() function
%
% HARDWARE REQUIREMENTS:
%   - Two ADALM-Pluto SDR devices
%   - USB 3.0 connections for optimal data throughput
%   - Adequate antennas for 2.4 GHz operation
%
% SOFTWARE REQUIREMENTS:
%   - MATLAB R2020b or later (for improved parallel features)
%   - All specified toolboxes must be licensed and installed
%
%% ========================================================================