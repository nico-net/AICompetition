classdef BluetoothTx < Transmitter
    %BLUETOOTHTX Summary of this class goes here
    %   Detailed explanation goes here

    properties
        btCfg = bluetoothWaveformConfig;
        currentSlotUse;
        randomProfile;
    end

    properties (Constant)
        slotDuration = 625e-6;
        packetTypes = ["FHS", "DM1", "DH1", "DM3", "DH3", "DM5", "DH5", "2-DH1", ...    
        "2-DH3", "2-DH5", "3-DH1", "3-DH3", "3-DH5", "HV1", "HV2", "HV3", "DV", ...
        "EV3", "EV4", "EV5", "2-EV3", "2-EV5", "3-EV3", "3-EV5"];
        symbolRate = 1e6;
        powerRange = [0 8];
        dstRange = [1 20];
    end

    methods
        function obj = BluetoothTx(position, channel, centerFreq, txPower, packetType)
            obj@Transmitter(position, channel, centerFreq, txPower)
            obj.btCfg.SamplesPerSymbol = 20;
            obj.label = "Bluetooth";
            obj.sampleRate = obj.symbolRate * obj.btCfg.SamplesPerSymbol;
            if (exist("packetType", 'var'))
                if (packetType == "RANDOM")
                    packetType = obj.packetTypes(randi(numel(obj.packetTypes)));
                elseif (ismember(packetType, obj.packetTypes))
                    obj.btCfg.PacketType = packetType;
                else
                    obj.btCfg.PacketType = "FHS";
                end
            else 
                packetType = "FHS";
            end
            [obj.btCfg.PayloadLength, obj.currentSlotUse, obj.btCfg.Mode, ~, obj.randomProfile] = ...
            BluetoothTx.myBtPacketFinder(packetType);
            obj.centerFreqs = 2402e6:1e6:2480e6;
            obj.availableFreqs = obj.centerFreqs;
        end

        function wf = getWaveform(obj, ~)

            btHop = bluetoothFrequencyHop;
            btHop.DeviceAddress = obj.btCfg.DeviceAddress;
            inputClock = randi([1, 2^28-1]);


            currentRandomProfile = obj.randomProfile;

            fs = obj.sampleRate;

            switch obj.channel
                case "RICIAN"
                    pathDelays = [0, 30e-9, 80e-9];
                    avgGains   = [0, -6, -12];
                    Kfactor = [6, 0, 0];
                    maxDoppler = 10;
                    directDoppler = [1, 0, 0];
                    directPhase = [0, 0, 0];

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
                case "RAYLEIGH"
                    pathDelays = [0, 30e-9, 80e-9];
                    avgGains   = [0, -5, -10]; 
                    maxDoppler = 10;

                    chan = comm.RayleighChannel( ...
                        SampleRate = fs, ...
                        PathDelays = pathDelays, ...
                        AveragePathGains = avgGains, ...
                        MaximumDopplerShift = maxDoppler, ...
                        NormalizePathGains = true, ...
                        PathGainsOutputPort = true);
                otherwise
            end

            numSlots = obj.timeDuration/obj.slotDuration;

            i = 0;
            W = Transmitter.dBm2W(obj.txPower);
            PL = Transmitter.dB2W(obj.pathLoss);

            finWf = [];

            while (i<numSlots)
                if (rand > currentRandomProfile)
                    bits = Transmitter.randBits(obj.btCfg.PayloadLength);
                    wf = bluetoothWaveformGenerator(bits, obj.btCfg);
                    wf = wf * sqrt(W/Transmitter.sigPwr(wf));
                    wf = wf * sqrt(1/PL);

                    if obj.channel == "RAYLEIGH" || obj.channel == "RICIAN"
                        wf = chan(wf);
                    end

                    [p, q] = rat(obj.targetSampleRate/(obj.symbolRate * obj.btCfg.SamplesPerSymbol));
                    wf = resample(wf, p, q);

                    ch = btHop.nextHop(inputClock);
                    fOff = comm.PhaseFrequencyOffset;
                    fOff.FrequencyOffset = ch*1e6;
                    fOff.SampleRate = obj.targetSampleRate;
                    wf = fOff(wf);
                    i = i + obj.currentSlotUse;
                    inputClock = inputClock + 2*obj.currentSlotUse;
                    wf = [wf; zeros(obj.slotDuration * obj.targetSampleRate, 1)];
                    inputClock = inputClock + 2;
                    i = i + 1;
                    release(fOff);
                    currentRandomProfile = currentRandomProfile + 0.1;
                else
                    wf = zeros(obj.targetSampleRate * obj.currentSlotUse * obj.slotDuration, 1);
                    currentRandomProfile = obj.randomProfile;
                    inputClock = inputClock + 2*obj.currentSlotUse;
                    i = i + obj.currentSlotUse;
                end
                finWf = [finWf; wf];
                if (i >= numSlots)
                    finWf = finWf(1:obj.timeDuration*obj.targetSampleRate);
                    wf = finWf;
                end
            end
        end

        function PL = pathloss(obj)
            % Log distance model, n = 2.5/3.5, reference distance = 1m,
            % ignoring shadowing
            if obj.channel == "RAYLEIGH"
                n = 3.5;
            elseif obj.channel == "RICIAN"
                n = 2.5;
            else 
                PL = Transmitter.pathloss(obj);
                return;
            end
            PL = 40 + 10*n*log10(norm(obj.distance));
        end


        function obj = randParams(obj, vararg)
            obj = randParams@Transmitter(obj, vararg);
            packet = randi([1 numel(obj.packetTypes)]);
            packet = obj.packetTypes(packet);
            obj.btCfg.PacketType = packet;
            [obj.btCfg.PayloadLength, obj.currentSlotUse, obj.btCfg.Mode, ~, obj.randomProfile] = ...
            BluetoothTx.myBtPacketFinder(packet);
            i = randi([1 numel(obj.availableFreqs)]);
            obj.centerFreq = obj.availableFreqs(i);
            obj.availableFreqs(i) = [];
        end

    end

    methods (Static)

        function pwr = randPwr()
            pwr = randi(BluetoothTx.powerRange);
        end

        function dst = randDst()
            dst = BluetoothTx.dstRange(1) + (BluetoothTx.dstRange(2) - BluetoothTx.dstRange(1))*rand();
        end

        function [payLoadLen, slotNum, phyMode, syncProfile, randomProfile] = myBtPacketFinder(packetType)
            switch packetType
                case 'FHS' 
                    payLoadLen = 18;
                    slotNum = 1;  
                    phyMode = 'BR';
                    syncProfile = 'SCO';
                    randomProfile = 0.8;
                case 'DM1'
                    payLoadLen = 17;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'SCO';
                    randomProfile = 0.5;
                case 'DH1'
                    payLoadLen = 27;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'ACL';
                    randomProfile = 0.3; 
                case 'DM3' 
                    payLoadLen = 121;
                    slotNum = 3;
                    phyMode = 'BR';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case 'DH3'
                    payLoadLen = 183;
                    slotNum = 3;
                    phyMode = 'BR';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case 'DM5'
                    payLoadLen = 224;
                    slotNum = 5;
                    phyMode = 'BR';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case 'DH5'
                    payLoadLen = 339;
                    slotNum = 5;
                    phyMode = 'BR';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case '2-DH1' 
                    payLoadLen = 54;
                    slotNum = 1; 
                    phyMode = 'EDR2M';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case '2-DH3'
                    payLoadLen = 367;
                    slotNum = 3;
                    phyMode = 'EDR2M';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case '2-DH5'
                    payLoadLen = 679;
                    slotNum = 5;
                    phyMode = 'EDR2M';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case '3-DH1'
                    payLoadLen = 83;
                    slotNum = 1; 
                    phyMode = 'EDR3M';
                    syncProfile = 'ACL';
                    randomProfile = 0.5;
                case '3-DH3'
                    payLoadLen = 552;
                    slotNum = 3;
                    phyMode = 'EDR3M';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case '3-DH5'
                    payLoadLen = 1021;
                    slotNum = 5;
                    phyMode = 'EDR3M';
                    syncProfile = 'ACL';
                    randomProfile = 0.3;
                case 'HV1'
                    payLoadLen = 10;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'SCO';
                    randomProfile = 0.1;
                case 'HV2'
                    payLoadLen = 20;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'SCO';
                    randomProfile = 0.1;
                case 'HV3'
                    payLoadLen = 30;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'SCO';
                    randomProfile = 0.1;
                case 'DV'
                    payLoadLen = 19;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'SCO';
                    randomProfile = 0.5;
                case 'EV3'
                    payLoadLen = 30;
                    slotNum = 1; 
                    phyMode = 'BR';
                    syncProfile = 'eSCO';
                    randomProfile = 0.1;
                case 'EV4'
                    payLoadLen = 120;
                    slotNum = 3;
                    phyMode = 'BR';
                    syncProfile = 'eSCO';
                    randomProfile = 0.2;
                case 'EV5'
                    payLoadLen = 180;
                    slotNum = 3;
                    phyMode = 'BR';
                    syncProfile = 'eSCO';
                    randomProfile = 0.2;
                case '2-EV3'
                    payLoadLen = 60;
                    slotNum = 1; 
                    phyMode = 'EDR2M';
                    syncProfile = 'eSCO';
                    randomProfile = 0.1;
                case '2-EV5'
                    payLoadLen = 360;
                    slotNum = 3;
                    phyMode = 'EDR2M';
                    syncProfile = 'eSCO';
                    randomProfile = 0.2;
                case '3-EV3'
                    payLoadLen = 90;
                    slotNum = 1; 
                    phyMode = 'EDR3M';
                    syncProfile = 'eSCO';
                    randomProfile = 0.1;
                case '3-EV5'
                    payLoadLen = 540;
                    slotNum = 3;
                    phyMode = 'EDR3M';
                    syncProfile = 'eSCO';
                    randomProfile = 0.2;
                otherwise
                    payLoadLen = 18;
                    slotNum = 1;
                    phyMode = 'BR';
                    syncProfile = 'eSCO';
                    randomProfile = 0.8;
            end
        end
    end
end
