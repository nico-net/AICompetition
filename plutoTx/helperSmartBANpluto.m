function [cleanWf] = helperSmartBANpluto(sampleRate, frameDuration)

dataBeacon = randi([0 1], 248, 1);  % Beacon MAC+PHY

timeDuration = frameDuration; %s
slotDuration = 0.001250; %s
bitRate = 1e6;  


dataPacketLength = 64 * 8;
ackPacketLength = 64 + 104; 
ifs = 0.000150;

missProb = 0.1;
currentMissProb = missProb;

modulator = comm.GMSKModulator( ...
    "BandwidthTimeProduct", 0.5, ...
    "BitInput", true, ...
    "SamplesPerSymbol", sampleRate/bitRate);

% Modula il beacon
beaconSignal = modulator(dataBeacon);

% Genera il punto di partenza casuale
startPoint = floor(rand() * timeDuration * sampleRate);

% Costruisce la waveform completa
if (startPoint > timeDuration * sampleRate - length(beaconSignal) + 1)
  cleanWf = [zeros(startPoint -1, 1); beaconSignal];
  cleanWf = cleanWf(1:timeDuration * sampleRate);
elseif (startPoint > timeDuration * sampleRate - slotDuration*sampleRate + 1)
    cleanWf = [zeros(startPoint -1, 1); beaconSignal; zeros(slotDuration * sampleRate - length(beaconSignal), 1)];
    cleanWf = cleanWf(1:timeDuration * sampleRate);
else 
    cleanWf = [zeros(startPoint - 1, 1); beaconSignal; zeros(sampleRate * slotDuration - length(beaconSignal), 1)];
    while (length(cleanWf) < timeDuration * sampleRate)
        dataPacket = randi([0 1], dataPacketLength, 1);
        if (rand() > currentMissProb)
            packetSignal = modulator(dataPacket) * 0.1;
            cleanWf = [cleanWf; packetSignal; zeros((slotDuration - ifs * 2 - ackPacketLength/bitRate - dataPacketLength) * sampleRate/bitRate, 1)];
            cleanWf = [cleanWf; zeros(floor(ifs*sampleRate), 1)];
            dataAck = randi([0 1], ackPacketLength, 1);
            ackSignal = modulator(dataAck) * 0.1;
            cleanWf = [cleanWf; ackSignal; zeros(floor(ifs * sampleRate), 1)];
            currentMissProb = currentMissProb + 0.05;
        else 
            missedPacket = zeros(sampleRate*slotDuration, 1);
            cleanWf = [cleanWf; missedPacket];
            currentMissProb = currentMissProb - 0.1;
        end
        if (length(cleanWf) > timeDuration * sampleRate)
            cleanWf = cleanWf(1:timeDuration * sampleRate);
        end
    end
end

end
