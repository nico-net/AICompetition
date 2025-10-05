classdef (Abstract) Transmitter
    %TRANSMITTER Summary of this class goes here
    %   Detailed explanation goes here

    properties
        position;
        channel;
        sampleRate;
        txPower;
        centerFreq;
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

    end

    methods (Static)
        function channelSet = validChannels()
            channelSet = ["AWGN", "RICIAN", "REYLEIGH"];
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
    end
end