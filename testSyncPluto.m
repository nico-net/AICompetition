
clear;


rx1 = sdrrx("Pluto", "RadioID", 'usb:0', ...
    'CenterFrequency', 2655e6, 'GainSource','Manual','Gain',40, ...
    'EnableBurstMode',true, 'BasebandSampleRate',10e6, 'OutputDataType','double', 'SamplesPerFrame',16e5);
rx2 = sdrrx("Pluto", "RadioID", 'usb:1', ...
    'CenterFrequency', 2655e6, 'GainSource','Manual','Gain',40, ...
    'EnableBurstMode',true, 'BasebandSampleRate',10e6, 'OutputDataType','double', 'SamplesPerFrame',16e5);



% Start parallel pool if not already active
if isempty(gcp('nocreate'))
    parpool(2); % Two workers, one per SDR
end

startTime = datetime('now') + seconds(2);
% Parameters
sampleRate = 10e6;
numSamples = 16e5; % 0.1 seconds of data at 40 MSPS
gain = 40;

% Function to be run in parallel
function data = acquirePluto(rx, startTime)
    while datetime('now') < startTime
        pause(0.0001); % small sleep to reduce CPU usage
    end
    data = rx(); % capture one burst
end

% Launch acquisition on both SDRs using parfeval
f1 = parfeval(@acquirePluto, 1, rx1, startTime);
f2 = parfeval(@acquirePluto, 1, rx2, startTime);

% Wait for both to complete and fetch outputs
[rx1Idx, rx1Data] = fetchNext([f1, f2]);
[rx2Idx, rx2Data] = fetchNext([f1, f2]);

% Reorder based on which future returned first
if rx1Idx == 1
    data1 = rx1Data;
    data2 = rx2Data;
else
    data1 = rx2Data;
    data2 = rx1Data;
end

% Done: now data1 and data2 contain your IQ samples
fprintf('Acquisition complete.\n');

% Optional: visualize power spectrum
figure;
subplot(2,1,1);
spectrogram(data1, 256, 128, 4096, 10e6, 'centered', 'psd');
title('SDR 1 Spectrum (centered at 435 MHz)');

subplot(2,1,2);
spectrogram(data2, 256, 128, 4096, 10e6, 'centered', 'psd');
title('SDR 2 Spectrum (centered at 435 MHz)');

delete(gcp('nocreate'));

release(rx1);
release(rx2);