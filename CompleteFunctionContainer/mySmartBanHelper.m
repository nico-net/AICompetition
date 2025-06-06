function [noisyWf, finWf] = mySmartBanHelper(Channel, centerFreq)



dataBeacon = randi([0 1], 248, 1);

ISMSstart = 2.402e9;

fOff = comm.PhaseFrequencyOffset;


timeDuration = 0.02; %s
slotDuration = 0.001250; %s
bitRate = 1e6;  %Nominal Transmission rate for smartban
sampleRate = 80e6;

fOff.SampleRate = sampleRate;
fOff.FrequencyOffset = centerFreq - ISMSstart;

dataPacketLength = 64 * 8;
ackPacketLength = 64 + 104; % Bodyless MAC frame + PHY
ifs = 0.000150; % interframe spacing, 150 us

missProb = 0.1;
currentMissProb = missProb;


modulator = comm.GMSKModulator( ...
    "BandwidthTimeProduct", 0.5, ...
    "BitInput", true, ...
    "SamplesPerSymbol", sampleRate/bitRate);


switch Channel
    case 'Rician'
        chan = comm.RicianChannel;
        chan.SampleRate = sampleRate;
        chan.PathDelays = [0 50e-9 150e-9 300e-9];
        chan.AveragePathGains = [0 -3 -8 -15]; %Typical model for indoor BT --> We also use it for SmartBAN because of similiar use cases
        chan.KFactor = 8;   % LoS indoor
        chan.MaximumDopplerShift = 12;  % walking speed doppler
        chan.DopplerSpectrum = doppler('Jakes');
        chan.NormalizePathGains = true;
    case 'Rayleigh'
        chan = comm.RayleighChannel;
        chan.SampleRate = sampleRate;
        chan.PathDelays        = [0 50e-9 150e-9 300e-9];    % seconds
        chan.AveragePathGains  = [0 -3  -8   -15   ];       % dB
        % Maximum Doppler shift for ~1 m/s
        fD = (1/3e8)*2.4e9;        % ≈8 Hz
        chan.MaximumDopplerShift = 12;         % e.g. moderate walking speed
        chan.DopplerSpectrum     = doppler('Jakes');


    otherwise
end

beaconSignal = modulator(dataBeacon);

beaconchan = comm.RicianChannel;
        beaconchan.SampleRate = sampleRate;
        beaconchan.PathDelays = [0 50e-9 150e-9 300e-9];
        beaconchan.AveragePathGains = [0 -3 -8 -15]; %Typical model for indoor BT --> We also use it for SmartBAN because of similiar use cases
        beaconchan.KFactor = 8;   % LoS indoor
        beaconchan.MaximumDopplerShift = 12;  % walking speed doppler
        beaconchan.DopplerSpectrum = doppler('Jakes');
        beaconchan.NormalizePathGains = true;

beaconSignal = beaconchan(beaconSignal);


startPoint = floor(rand() * timeDuration * sampleRate);


if (startPoint > timeDuration * sampleRate - length(beaconSignal) + 1)
  finWf = [zeros(startPoint -1, 1); beaconSignal];
  finWf = finWf(1:timeDuration * sampleRate);
elseif (startPoint > timeDuration * sampleRate - slotDuration*sampleRate + 1)
    finWf = [zeros(startPoint -1, 1); beaconSignal; zeros(slotDuration * sampleRate - length(beaconSignal), 1)];
    finWf = finWf(1:timeDuration * sampleRate);
else 
    finWf = [zeros(startPoint - 1, 1); beaconSignal; zeros(sampleRate * slotDuration - length(beaconSignal), 1)];
    while (length(finWf) < timeDuration * sampleRate)
        dataPacket = randi([0 1], dataPacketLength, 1);
        if (rand() > currentMissProb)
            packetSignal = modulator(dataPacket) * 0.1;
            packetSignal = chan(packetSignal);
            finWf = [finWf; packetSignal; zeros((slotDuration - ifs * 2 - ackPacketLength/bitRate - dataPacketLength) * sampleRate/bitRate, 1)];
            finWf = [finWf; zeros(floor(ifs*sampleRate), 1)];
            dataAck = randi([0 1], ackPacketLength, 1);
            ackSignal = modulator(dataAck) * 0.1;
            ackSignal = chan(ackSignal);
            finWf = [finWf; ackSignal; zeros(floor(ifs * sampleRate), 1)];
            currentMissProb = currentMissProb + 0.05;
        else 
            missedPacket = zeros(sampleRate*slotDuration, 1);
            finWf = [finWf; missedPacket];
            currentMissProb = currentMissProb - 0.1;
        end
        if (length(finWf) > timeDuration * sampleRate)
            finWf = finWf(1:timeDuration * sampleRate);
        end
    end
end
finWf = fOff(finWf);
noisyWf = awgn(finWf, 20);
end



%Generate beacon 



% GFSK   BT = 0.5   h = 0.5 
% Lslot = 625 * 2 = 1250 microsec
% 64 byte = 512 bits 
% Ack is pretty much required and is 168 bit

% The beacon is 248 bits MAC + PHY

% Beacon randomly placed, then followed by lower energy packets

% We use comm.GMSKModulator