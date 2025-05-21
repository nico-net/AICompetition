function txWaveform = scalingPower(waveform)
%scalingPower Decreases transmitting power of the signals
%   Inputs:
%      waveform - (column vector) Input signal
%   Outputs:
%      txWaveform - (column vector) Attenuated signal

    desiredTxPower_dBm = randi([5, 15])
    scaling_factor = 10^(-desiredTxPower_dBm / 20);
    txWaveform = scaling_factor * waveform;

end