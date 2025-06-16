clear;


rx = sdrrx("Pluto", "RadioID", 'usb:0', ...
    'CenterFrequency', 865e6, 'GainSource','Manual','Gain',50, ...
    'EnableBurstMode',true, 'BasebandSampleRate',40e6, 'OutputDataType','double', 'SamplesPerFrame',16e5);

data = rx();

figure;
spectrogram(data, 256, 128, 4096, 40e6, 'centered', 'psd');
title('SDR 1 Spectrum (centered at 435 MHz)');