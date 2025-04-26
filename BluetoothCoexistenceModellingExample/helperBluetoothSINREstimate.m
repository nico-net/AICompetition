function sinr = helperBluetoothSINREstimate(snr,awnTxPower,awnFrequency,...
                                      awnPathloss,iwnConfig,iwnPathloss)
%helperBluetoothSINREstimate Estimates SINR
%   SINR = helperBluetoothSINREstimate(SNR,AWNTXPOWER,AWNFREQUENCY,...
%   AWNPATHLOSS,IWNCONFIG,IWNPATHLOSS) returns the estimated SINR.
%
%   SINR is a scalar or a vector representing the signal to interference
%   plus noise ratio in dB.
%
%   SNR is a scalar representing the signal to noise ratio in dB.
%
%   AWNTXPOWER is a scalar representing the awn transmitter power in dBm.
%
%   AWNFREQUENCY is a scalar representing the awn frequency in Hz.
%
%   AWNPATHLOSS is a scalar representing the awn path loss in dB.
%
%   IWNCONFIG is a configuration object of type <a
%   href="matlab:help('helperIWNConfig')">helperIWNConfig</a> that
%   configures the interference wireless node.
%
%   IWNPATHLOSS is a row vector of size 1-by-N, where N represents the
%   number of interference nodes.

%   Copyright 2021 The MathWorks, Inc.

    linearInterferencePower = 0;
    dBmConverter = 30;

    % Compute interference power for each node
    for i = 1:iwnConfig.NumIWNNodes
        if iwnConfig.IWN(i).CollisionProbability > 0
            freqDifference = awnFrequency-iwnConfig.IWN(i).Frequency;
            if abs(freqDifference) < iwnConfig.Bandwidth(i)/2
                interferencePower = iwnConfig.IWN(i).TxPower-dBmConverter-iwnPathloss(i);
                linearInterferencePower = linearInterferencePower + 10^(interferencePower/10)*iwnConfig.IWN(i).CollisionProbability;
            elseif abs(freqDifference) == iwnConfig.Bandwidth(i)/2 % Half waveform overlaps in frequency domain
                power3dB = 3;
                interferencePower = iwnConfig.IWN(i).TxPower-dBmConverter-iwnPathloss(i)-power3dB;
                linearInterferencePower = linearInterferencePower + 10^(interferencePower/10)*iwnConfig.IWN(i).CollisionProbability;
            end
        end
    end
    soiPower = awnTxPower-dBmConverter-awnPathloss; % Signal of interest power in dB
    noisePower = soiPower - snr; % Noise power in dB
    linearnoisePower = 10.^(noisePower/10);
    IplusNdB = 10*log10(linearInterferencePower+linearnoisePower); % Interference plus noise power in dB
    sinr = soiPower-IplusNdB;
end