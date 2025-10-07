classdef (Abstract) Transmitter
    %TRANSMITTER Summary of this class goes here
    %   Detailed explanation goes here

    properties
        position;
        channel;
        sampleRate;
        txPower;
        centerFreq;
        centerFreqs;
        availableFreqs;
        label;
    end

    properties (Constant)
        ISMstart = 2.402e9; % Hz
        timeDuration = 20e-3; % seconds
        targetSampleRate = 80e6; % Hz
        octetLength = 8;
        c = 3e8;
    end

    methods
        function obj = Transmitter(position, channel, centerFreq, txPower)
            % Check validity of position (vector of 3 coordinates)
            assert(isvector(position) && length(position) == 3, 'Position must be a vector of 3 coordinates.');
            obj.position = position;
            obj.channel = channel;
            obj.centerFreq = centerFreq;
            obj.txPower = txPower;
        end
        
        function dispProperties(obj)
            disp('Transmitter Properties:');
            disp(['Position: ', mat2str(obj.position)]);
            disp(['Channel: ', obj.channel]);
            disp(['Center Frequency: ', num2str(obj.centerFreq), ' Hz']);
            disp(['Transmit Power: ', num2str(obj.txPower), ' dBm']);
        end

        function label = returnLabel(obj)
            label = obj.label;
        end

        function obj = setPos(obj,position)
            assert(isvector(position) && length(position) == 3, 'Position must be a vector of 3 coordinates.');
            obj.position = position;
        end

        function obj = setChan(obj, channel)
            validChannels = Transmitter.validChannels();
            assert(ismember(channel.type, validChannels));
            obj.channel = channel;
        end



        function PL = pathLoss(obj)
            % Path Loss in Db, atm is freespace only
            % Calculate path loss using the free space path loss formula
            d = norm(obj.position); % Distance from the transmitter
            frequency = obj.centerFreq; % Frequency in Hz
            %c = Transmitter.c; % Speed of light in m/s
            PL = 20*log10(d) + 20*log10(frequency) - 147.55; % Path loss in dB

        end

        function obj = randParams(obj, vararg)
            obj.channel = obj.randChan(); % Assign a random channel to the transmitter
            if ~isempty(vararg(1)) && vararg(1)
                obj.txPower = obj.randPwr();
            end
            obj = obj.setPos(Transmitter.findPos(obj.randDst));
        end

        function obj = resetFreqs(obj)
            obj.availableFreqs = obj.centerFreqs;
        end


    end

    methods (Static)
        function channelSet = validChannels()
            channelSet = ["AWGN", "RICIAN", "REYLEIGH"];
        end

        function chan = randChan()
            chans = ["AWGN", "RICIAN", "RAYLEIGH"];
            index = randi([1 numel(chans)]);
            chan = chans(index);
        end

        function bits = randBits(numByte)
            bits = randi([0 1], numByte * Transmitter.octetLength, 1);
        end

        function W = dBm2W(txPower)
            W = 10^((txPower - 30) / 10); % Convert dBm to Watts
        end

        function W = dB2W(pwr)
            W = 10^(pwr/10);
        end

        function pwr = sigPwr(wf)
            pwr = mean(abs(wf).^2); % Calculate the average power of the waveform
        end

        function pos = findmePos(dst)
            u = randn(3,1);        % random 3D Gaussian
            u = u / norm(u);       % normalize to unit vector
            r = dst * rand^(1/3);    % random radius with uniform distribution in sphere
            pos = r * u;             % 3x1 vector
        end

        function pos = findPos(dst)
            v = randn(3,1);
            v_unit = v / norm(v);
            pos = dst * v_unit;
        end

    end

    methods (Abstract)
        getWaveform(obj, vararg);
        randPwr();
    end

    methods (Abstract, Static)
        randDst();
    end
end