classdef SmartBanTx < Transmitter
    %SMARTBANTX Summary of this class goes here
    %   Detailed explanation goes here

    properties

        % Sensors have been tested with -10 / 0 dBm
        
        slotDuration = 1.25e-3;
        dataPacketLength = 64;          % Payload: 64 bytes
        ackPacketLength = 64/8 + 104/8;     % ACK: MAC + PHY bits
        packetTxPower;                  % Note: Transmitter.txPower refers 
                                        % to the beacon power, not the power
                                        % of the intermediate packets of a
                                        % smartban communication
    end

    properties (Constant)
        beaconLength = 248;
        ifs = 150e-6;
        bitRate = 1e6;
        missProb = 0.1;
        powerRange = [0 12];
        sensorPwrRange = [-6 4];         %dBm
        dstRange = [1 20]
    end

    methods
        function obj = SmartBanTx(position, channel, centerFreq, txPower)
            %SMARTBANTX Construct an instance of this class
            %   Detailed explanation goes here
            obj@Transmitter(position, channel, centerFreq, txPower);
            obj.label = "SmartBAN";
            obj.centerFreqs = (0:39)*2e6 + 2.402e9;
            obj.availableFreqs = obj.centerFreqs;
        end

        function wf = getWaveform(obj,~)

            fOff = comm.PhaseFrequencyOffset;
            fOff.SampleRate = obj.targetSampleRate;
            fOff.FrequencyOffset = obj.centerFreq - Transmitter.ISMstart;


            modulator = comm.GMSKModulator( ...
                "BandwidthTimeProduct", 0.5, ...
                "BitInput", true, ...
                "SamplesPerSymbol", obj.targetSampleRate / obj.bitRate);
            
            beaconBits = Transmitter.randBits(obj.beaconLength/8);
            beaconSignal = modulator(beaconBits);

            W = Transmitter.dBm2W(obj.txPower);
            PL = Transmitter.dB2W(obj.pathLoss);

            % We are using the same channel for both SC and nodes. This is
            % because it's not currently in the scope of the project to
            % accurately model a whole BAN, therefore we assume that
            % everything is coming from the same point (the SC location)
            % and that everything goes through the same channel. We are,
            % however, accounting for different Tx Powers. The argument
            % passed to the constructor is the SC beacon power, while the
            % range of power of nodes is saved as a constant in the class

            beaconSignal = beaconSignal * sqrt(W/Transmitter.sigPwr(beaconSignal));
            beaconSignal = beaconSignal * sqrt(1/PL);
            

            fs = obj.targetSampleRate;

            switch obj.channel
                case "RICIAN"
                    pathDelays = [0 50e-9 150e-9];
                    avgGains = [0 -6 -12];
                    Kfactor = [3 0 0];
                    maxDoppler = 5;
                    directDoppler = [1 0 0];
                    directPhase = [0 0 0];

                    chan = comm.RicianChannel( ...
                        SampleRate = fs, ...
                        PathDelays = pathDelays, ...
                        AveragePathGains = avgGains, ...
                        KFactor = Kfactor, ...
                        MaximumDopplerShift = maxDoppler, ...
                        DirectPathDopplerShift = directDoppler, ...
                        DirectPathInitialPhase = directPhase, ...
                        NormalizePathGains = true, ...
                        PathGainsOutputPort = true);

                    beaconSignal = chan(beaconSignal);

                case "RAYLEIGH"
                    pathDelays = [0 40e-9 100e-9 200e-9];
                    avgGains = [0 -4 -9 -15];
                    maxDoppler = 5;
                    chan = comm.RayleighChannel( ...
                        SampleRate = fs, ...
                        PathDelays = pathDelays, ...
                        AveragePathGains = avgGains, ...
                        MaximumDopplerShift = maxDoppler, ...
                        NormalizePathGains = true, ...
                        PathGainsOutputPort = true);

                    beaconSignal = chan(beaconSignal);

                otherwise

            end
            
           
            startPoint = floor(rand()*0.8*obj.timeDuration * obj.targetSampleRate);

            if (startPoint > obj.timeDuration * obj.targetSampleRate - length(beaconSignal) + 1)
                wf = [zeros(startPoint - 1, 1); beaconSignal];
                wf = wf(1:obj.timeDuration * obj.targetSampleRate);
            elseif (startPoint > obj.timeDuration * obj.targetSampleRate - obj.slotDuration * ...
                    obj.targetSampleRate + 1)
                wf = [zeros(startPoint -1, 1); beaconSignal; zeros(obj.slotDuration * ...
                    obj.targetSampleRate - length(beaconSignal), 1)];
                wf = wf(1:obj.timeDuration * obj.targetSampleRate);
            else
                wf = [zeros(startPoint - 1, 1); beaconSignal; ...
                    zeros(obj.targetSampleRate * obj.slotDuration - length(beaconSignal), 1)];
                currMissProb = obj.missProb;

                while length(wf) < obj.timeDuration * obj.targetSampleRate
                    dataPacket = Transmitter.randBits(obj.dataPacketLength);

                    if rand() > currMissProb
                        packetSignal = modulator(dataPacket);
                        
                        W = Transmitter.dBm2W(randi(obj.sensorPwrRange));
                        
                        packetSignal = packetSignal * sqrt(W/PL);

                        if obj.channel == "RICIAN" || obj.channel == "RAYLEIGH"
                            packetSignal = chan(packetSignal);
                        end

                        padding = zeros(floor((obj.slotDuration - 2*obj.ifs - ...
                            obj.ackPacketLength / obj.bitRate - ...
                            obj.dataPacketLength / obj.bitRate)) * obj.targetSampleRate, 1);

                        wf = [wf; packetSignal; padding];

                        wf = [wf; zeros(floor(obj.ifs * obj.targetSampleRate), 1)];

                        dataAck = Transmitter.randBits(obj.ackPacketLength);
                        ackSignal = modulator(dataAck);

                        ackSignal = ackSignal * sqrt(W/PL);
                        if obj.channel == "RICIAN" || obj.channel == "RAYLEIGH"
                            ackSignal = chan(ackSignal);
                        end

                        wf = [wf; ackSignal; zeros(floor(obj.ifs * obj.targetSampleRate), 1)];

                        currMissProb = currMissProb * 0.05;
                    else
                        % Drop
                        missedPacket = zeros(obj.targetSampleRate * obj.slotDuration, 1);
                        wf = [wf; missedPacket];
                        currMissProb = currMissProb - 0.1;
                        if (currMissProb < 0)
                            currMissProb = 0;
                        end
                    end

                    if length(wf) > obj.timeDuration * obj.targetSampleRate
                        wf = wf(1:obj.timeDuration * obj.targetSampleRate);
                    end
                end            
            end

            
            wf = fOff(wf);
        end
    

        function PL = pathloss(obj)
            % We are still using Log Normal, might make sense to look into
            % CM 3-6
            if obj.channel == "RICIAN"
                n = 2.5;
            elseif obj.channel == "RAYLEIGH"
                n = 3.5;
            else
                PL = Transmitter.pathloss(obj);
                return;
            end
            PL = 40 + 10*n*log10(norm(obj.position));
        end

        function obj = randParams(obj, vararg)
            obj = randParams@Transmitter(obj, vararg);
            i = randi([1 numel(obj.availableFreqs)]);
            obj.centerFreq = obj.availableFreqs(i);
            obj.availableFreqs(i) = [];
        end

    end

    methods (Static)

        function dst = randDst()
            dst = SmartBanTx.dstRange(1) + (SmartBanTx.dstRange(2) - SmartBanTx.dstRange(1))*rand();
        end

        function pwr = randPwr()
            pwr = randi(SmartBanTx.powerRange);
        end
    end

end
