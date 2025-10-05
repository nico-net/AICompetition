classdef ZigBeeTx < Transmitter
    %ZIGBEETX Summary of this class goes here
    %   Detailed explanation goes here



    % NOTE ABOUT DSSS-OQPSK For ZigBee
    % The number of chips is fixed, 32 chips map 4 data bits. After that,
    % QPSK handles 2 bits at a time (OQPSK offsets the Q stream to avoid pi
    % jumps in phase).
    % Therefore, every bit od data gets mapped over 8 chips --> 4 OQPSK
    % symbols
    % spc is jsut related to oversampling of each chip 

    properties
        zbCfg = lrwpanOQPSKConfig;
    end

    properties (Constant)
        minTxPower = 0;
        maxTxPower = 10;
        packetTimeDuration = 4.2565e-3; % seconds
        powerRange = [-3 8];
        dstRange = [0.1 20];
    end

    methods
        function obj = ZigBeeTx(position, channel, centerFreq, txPower, spc)
            % Check if valid
            obj@Transmitter(position, channel, centerFreq, txPower);
            if (isempty(spc))
                spc = 4;
            end
            obj.zbCfg.SamplesPerChip = spc;
            obj.sampleRate = obj.zbCfg.SampleRate;
        end

        function wf = getWaveform(obj, vararg)
            assert(isscalar(vararg), "Too many arguments for this kind of transmitter");
            numPackets = vararg(1);

            fs = obj.sampleRate;

            switch obj.channel
                case "RICIAN"
                    pathDelays = [0, 50e-9, 120e-9];
                    avgGains   = [0, -6, -12];
                    Kfactor = [4, 0, 0];
                    maxDoppler = 5;
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
                    pathDelays = [0, 40e-9, 100e-9, 200e-9];
                    avgGains   = [0, -4, -9, -15];
                    maxDoppler = 5;
                    chan = comm.RayleighChannel( ...
                        SampleRate = fs, ...
                        PathDelays = pathDelays, ...
                        AveragePathGains = avgGains, ...
                        MaximumDopplerShift = maxDoppler, ...
                        NormalizePathGains = true, ...
                        PathGainsOutputPort = true);
                otherwise
            end


            switch numPackets
                case 1
                    idleTime = 0;
                case {2, 3}
                    idleTime = 0.0005 + (0.005 - 0.0005) * rand;  % Random delay between 0.5ms and 5ms
                case 4
                    minVal = (timeDuration - obj.packetTimeDuration * 4) / 4;
                    maxVal = (timeDuration - obj.packetTimeDuration * 4) / 3;
                    idleTime = minVal + (maxVal - minVal) * rand;
                otherwise
                    error("numPackets must be 1 to 4.");
            end

            bits = Transmitter.randBits(obj.zbCfg.PSDULength);
            wf = lrwpanWaveformGenerator(bits, obj.zbCfg, ...
                "NumPackets", numPackets, ...
                "IdleTime", idleTime);

            % ---- Apply transmit power and channel effects ----
            W = Transmitter.dBm2W(obj.txPower);
            wf = wf * sqrt(W/Transmitter.sigPwr(wf));

            PL = Transmitter.dB2W(obj.pathLoss);
            wf = wf * sqrt(1/PL);


            if obj.channel == "RICIAN" || obj.channel == "RAYLEIGH"
                wf = chan(wf);
            end


            % --- Trim trailing idle time ---
            wf = wf(1:end - floor(obj.sampleRate * idleTime));

            % --- Time padding: insert at random offset in the 20 ms window ---
            if length(wf) < obj.sampleRate * obj.timeDuration
                zerosToAdd = obj.sampleRate * obj.timeDuration - length(wf);
                zerosBefore = floor(rand * zerosToAdd);
                zerosAfter = zerosToAdd - zerosBefore;
                wf = [zeros(zerosBefore, 1); wf; zeros(zerosAfter,1)];
            else
                wf = wf(1:obj.sampleRate * obj.timeDuration);
                zerosBefore = 0;
                zerosAfter = 0;
            end


            [upP, downQ] = rat(obj.targetSampleRate / obj.sampleRate);
            wf = resample(wf, upP, downQ);

            % --- Ensure waveform is exactly 20 ms long after resampling ---
            targetLen = obj.targetSampleRate * obj.timeDuration;

            if length(wf) > targetLen
                if zerosAfter > zerosBefore
                    wf = wf(1:end - (length(wf) - targetLen));
                else 
                    wf = wf((length(wf) - targetLen + 1):end);
                end
            else
                wf = [wf; zeros(targetLen - length(wf), 1)];
            end

             % --- Apply Frequency Offset ---
            fOff = comm.PhaseFrequencyOffset;
            fOff.SampleRate = obj.targetSampleRate;
            fOff.FrequencyOffset = obj.centerFreq - obj.ISMstart;  % relative offset in Hz
            wf = fOff(wf);
            release(fOff);

        end

        function PL = pathloss(obj)
            % Log Distance model, ignoring walls and shadowing
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

            
    end

    methods (Static)
        
        function dst = randDst()
            dst = ZigBeeTx.dstRange(1) + (ZigBeeTx.dstRange(2) - ZigBeeTx.dstRange(1))*rand();
        end


        function pwr = randPwr()
            pwr = randi(ZigBeeTx.powerRange);
        end

    end
end