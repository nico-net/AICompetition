classdef helperIWNConfig < comm.internal.ConfigBase
%helperIWNConfig Interference wireless node (IWN) configuration parameters
%
%   IWNCONFIG = helperIWNConfig creates a default IWN configuration object,
%   IWNCONFIG.
%
%   IWNCONFIG = helperIWNConfig(Name=Value) creates an IWN configuration
%   object, IWNCONFIG, with the specified property Name set to the
%   specified Value. You can specify additional name-value arguments in any
%   order as (Name1=Value1,...,NameN=ValueN).
%
%   helperIWNConfig methods:
%   generateIWNWaveform - Generate IWN waveform(s)
%   computeBandwidth    - Compute IWN bandwidth(s)
%   applyPathloss       - Apply path loss to the IWN waveform(s)
%   addInterference     - Add interference to the AWN waveform
%
%   helperIWNConfig properties:
%
%   IWN                 - IWN properties of multiple nodes
%   SampleRate          - Sample rate
%   Environment         - Environment in which the signal propagates

%   Copyright 2021-2023 The MathWorks, Inc.

properties
    %IWN IWN properties of multiple nodes
    %   Specify the IWN as 1-by-N structure with these five fields
    %   {SignalType, TxPosition, Frequency, TxPower, CollisionProbability}.
    %   N represents the number of interference nodes.
    IWN

    %InputSampleRate Sample rate of the baseband signal in Hz
    %   Specify the sample rate as a positive double value in Hz. The
    %   default value is 20e6.
    InputSampleRate = 20e6

    %OutputSampleRate Sample rate of the wanted signal after interference
    %addition. The default value is 80e6.
    OutputSampleRate = 80e6;

    %Environment Environment in which the signal propagates
    %   Specify the environment as one of 'Outdoor'|'Industrial'|'Home'|
    %   'Office'. The default value is 'Outdoor'.
    Environment = "Outdoor"

    %DelayProfile Channel propagation condition
    %   Specify the Delay profile model of WLAN multipath fading channel as
    %   one of 'Model-A' | 'Model-B' | 'Model-C' | 'Model-D' | 'Model-E' |
    %   'Model-F'. The default is 'Model-B'.
    DelayProfile = "Model-B"

% Environment type, specified as 'Residential', 'Indoor office', 'Outdoor',
% 'Open outdoor', or 'Industrial'.
% This property determines lower level configuration settings and the mode
% of operation for the UWB Channel. The default is 'Outdoor'
    EnvironmentWpan = "Outdoor"
    
end

properties (Hidden)
    %NumIWNNodes Number of IWN nodes
    NumIWNNodes

    %Bandwidth Bandwidth of the signal in Hz
    Bandwidth

end

methods
    % Constructor
    function obj = helperIWNConfig(varargin)
        obj = obj@comm.internal.ConfigBase(varargin{:});
        obj.NumIWNNodes = numel(obj.IWN); % Number of IWN nodes
        obj.Bandwidth = computeBandwidth(obj); % Compute IWN signal bandwidth
    end

    function iwnWaveform = generateIWNWaveform(obj)
    %generateIWNWaveform Generate IWN waveform(s)
    %   IWNWAVEFORM = generateIWNWaveform(OBJ) returns the generated IWN
    %   waveform(s).
    %
    %   IWNWAVEFORM is a cell array of size 1-by-N, where N represents the
    %   number of interference nodes. Each cell represents a column vector
    %   of size Ns-by-1, where Ns represents the number of time-domain
    %   samples.
    %
    %   OBJ is an object of type helperIWNConfig.

        iwnWaveform = cell(1,obj.NumIWNNodes);
        % Generate multiple IWN waveforms
        for  i = 1:obj.NumIWNNodes
            switch obj.IWN(i).SignalType
                case {'LE1M','LE2M','LE500K','LE125K'}
                    % Bluetooth LE
                    channelIndexArray = [37 0:10 38 11:36 39];
                    channelIndex = channelIndexArray((obj.IWN(i).Frequency-2402e6)/2e6+1);
                    payloadLength = 255;
                    data = randi([0 1],payloadLength*8,1,'int8');
                    phyFactor = 1+strcmp(obj.IWN(i).SignalType,'LE2M');
                    sps = obj.InputSampleRate/(phyFactor*1e6);
                    accessAddBits = int2bit(hex2dec('01234567'),32,false);
                    waveform = bleWaveformGenerator(data, ...
                        Mode=obj.IWN(i).SignalType, ...
                        ChannelIndex=channelIndex, ...
                        SamplesPerSymbol=sps, ...
                        AccessAddress=accessAddBits);

                case {'BR','EDR2M','EDR3M'}
                    % Bluetooth BR/EDR
                    % Change packet type eventually
                    bluetoothPacket = 'FHS';
                    sps = obj.InputSampleRate/1e6;
                    cfg = bluetoothWaveformConfig(Mode=obj.IWN(i).SignalType, ...
                                  PacketType=bluetoothPacket, ...
                                  SamplesPerSymbol=sps);
                    dataLen = getPayloadLength(cfg);
                    data = randi([0 1],dataLen*8,1);
                    waveform = bluetoothWaveformGenerator(data,cfg);
                case 'IEEE 802.15.4'
                    spc = 4;
                    msgLen = 120*8; %in bits
                    cfglrWpan = lrwpanOQPSKConfig(Band=2450, ...
                                    PSDULength=msgLen/8, SamplesPerChip=spc);
                    message = randi([0 1],msgLen,1);   
                    waveform = lrwpanWaveformGenerator( ...
                                message, cfglrWpan);


                otherwise % WLAN waveform
                    switch obj.IWN(i).SignalType
                        case '802.11b/g with 22 MHz Bandwidth'
                            psduLength = 2304;
                            cfgWLAN = wlanNonHTConfig(Modulation='DSSS',...
                                DataRate='11Mbps',PSDULength=psduLength);
                        case '802.11g with 20 MHz Bandwidth'
                            psduLength = 2304;
                            cfgWLAN = wlanNonHTConfig(Modulation='OFDM', ...
                                ChannelBandwidth='CBW20',PSDULength=psduLength,...
                                NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas);
                        case '802.11n with 20 MHz Bandwidth'
                            psduLength = 2304;
                            cfgWLAN = wlanHTConfig(ChannelBandwidth='CBW20',PSDULength=psduLength,...
                                NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas,...
                                NumSpaceTimeStreams=obj.IWN(i).NumTransmitAntennas);
                            if obj.IWN(i).NumTransmitAntennas > 1
                                cfgWLAN.MCS = 8;
                            end
                        case '802.11n with 40 MHz Bandwidth'
                            psduLength = 2304;
                            cfgWLAN = wlanHTConfig(ChannelBandwidth='CBW40',PSDULength=psduLength,...
                                NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas,...
                                NumSpaceTimeStreams=obj.IWN(i).NumTransmitAntennas);
                            if obj.IWN(i).NumTransmitAntennas > 1
                                cfgWLAN.MCS = 8;
                            end
                        case '802.11ax with 20 MHz Bandwidth'
                            cfgWLAN = wlanHESUConfig(ChannelBandwidth='CBW20',...
                                NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas,...
                                NumSpaceTimeStreams=obj.IWN(i).NumTransmitAntennas);
                            psduLength = getPSDULength(cfgWLAN);
                        case '802.11ax with 40 MHz Bandwidth'
                            cfgWLAN = wlanHESUConfig(ChannelBandwidth='CBW40',...
                                NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas,...
                                 NumSpaceTimeStreams=obj.IWN(i).NumTransmitAntennas);
                            psduLength = getPSDULength(cfgWLAN);
                    end
                    data = randi([0 1], psduLength*8, 1); % Create a random PSDU
                    waveform = wlanWaveformGenerator(data,cfgWLAN,...
                        OversamplingFactor=obj.IWN(i).OverSamplingFactor);
            end

            % Apply transmit power
            dBmConverter = 30;
            iwnWaveform{i}  = 10^((obj.IWN(i).TxPower-dBmConverter)/20)*waveform;
        end
    end

    function bandwidth = computeBandwidth(obj)
    %computeBandwidth Compute bandwidth
    %   BANDWIDTH = computeBandwidth(OBJ) returns the bandwidth(s) of the
    %   interfering nodes.
    %
    %   BANDWIDTH is a vector of size 1-by-N, where N represents the number
    %   of interference nodes.
    %
    %   OBJ is an object of type helperIWNConfig.

        bandwidth = zeros(1,obj.NumIWNNodes);
        for  i = 1:obj.NumIWNNodes
            switch obj.IWN(i).SignalType
                case {'LE1M','LE2M','LE500K','LE125K'}
                    bandwidth(i) = 2e6;
                case {'BR','EDR2M','EDR3M'}
                    bandwidth(i) = 1e6;
                case 'IEEE 802.15.4'
                    bandwidth(i) = 8e6;
                otherwise
                    switch obj.IWN(i).SignalType
                        case {'802.11b/g with 22 MHz Bandwidth','WLANBasebandFile'}
                            bandwidth(i) = 22e6;
                        case {'802.11g with 20 MHz Bandwidth',...
                              '802.11n with 20 MHz Bandwidth','802.11ax with 20 MHz Bandwidth'}
                            bandwidth(i) = 20e6;
                        case {'802.11n with 40 MHz Bandwidth','802.11ax with 40 MHz Bandwidth'}
                            bandwidth(i) = 40e6;
                    end
            end
        end
    end

    function [attenuatedWaveform,pldB] = applyPathloss(obj,iwnWaveform,awnRxPosition)
    %applyPathloss Apply path loss to the IWN waveform(s)
    %   [ATTENUATEDWAVEFORM,PLDB] = applyPathloss(OBJ,IWNWAVEFORM,...
    %   AWNRXPOSITION) returns the attenuated waveform by scaling the IWN
    %   waveform with the computed path loss.
    %
    %   ATTENUATEDWAVEFORM is a cell array of size 1-by-N, where N
    %   represents the number of interference nodes. Each cell represents a
    %   column vector of size Ns-by-1, where Ns represents the number of
    %   time-domain samples.
    %
    %   PLDB specifies the path loss in dB. It is a row vector of size
    %   1-by-N, where N represents the number of interference nodes.
    %
    %   OBJ is an object of type helperIWNConfig.
    %
    %   IWNWAVEFORM is a cell array of size 1-by-N, where N represents the
    %   number of interference nodes. Each cell represents a column vector
    %   of size Ns-by-1, where Ns represents the number of time-domain
    %   samples.
    %
    %   AWNRXPOSITION is a scalar which specifies the AWN receiver
    %   position.

        attenuatedWaveform = cell(1,obj.NumIWNNodes);
        pldB = zeros(1,obj.NumIWNNodes);
        pathlossCfg = bluetoothPathLossConfig(Environment=obj.Environment,RandomStream="mt19937ar with seed");
        for i = 1:obj.NumIWNNodes
            distAWNRxIWNTx = sqrt(sum((obj.IWN(i).TxPosition-awnRxPosition).^2,2));
            pathlossdB = bluetoothPathLoss(distAWNRxIWNTx,pathlossCfg);
            attenuatedWaveform{i} = iwnWaveform{i}/(10^(pathlossdB/20));
            pldB(i) = pathlossdB;
        end
    end
    function rxIWN = applyChannel(obj,iwnWaveform,awnRxPosition,channelModel)
    %applyChannel Pass IWN waveform(s) through fading channel model
    %   RXIWN = applyChannel(OBJ,IWNWAVEFORM,AWNRXPOSITION,...
    %   CHANNELMODEL) passes the IWN waveform(s) through the fading
    %   channel model.
    %
    %   RXIWN is a cell array of size 1-by-N, where N
    %   represents the number of interference nodes. Each cell represents a
    %   column vector of size Ns-by-1, where Ns represents the number of
    %   time-domain samples.
    %
    %   OBJ is an object of type helperIWNConfig.
    %
    %   IWNWAVEFORM is a cell array of size 1-by-N, where N represents the
    %   number of interference nodes. Each cell represents a column vector
    %   of size Ns-by-1, where Ns represents the number of time-domain
    %   samples.
    %
    %   AWNRXPOSITION is a scalar which specifies the AWN receiver
    %   position.
    %
    %   CHANNELMODEL is one of the string scalars: Rayleigh Channel or
    %   Rician Channel

        rxIWN = cell(1,obj.NumIWNNodes);
        for i = 1:obj.NumIWNNodes
            switch obj.IWN(i).SignalType
                case {'LE1M','LE2M','LE500K','LE125K','BR','EDR2M','EDR3M'}
                    channelIWN = helperBluetoothChannelInit(obj.InputSampleRate,channelModel);
                    chanDelay = info(channelIWN.fadingChan).ChannelFilterDelay;
                    % Pass through the fading channel model
                    chImpWaveTmp = channelIWN.fadingChan([iwnWaveform{i}; zeros(chanDelay,1)]);
                    rxIWN{i} = chImpWaveTmp(chanDelay+1:end,1);
                case {'802.11b/g with 22 MHz Bandwidth','802.11g with 20 MHz Bandwidth',...
                      '802.11n with 20 MHz Bandwidth','802.11n with 40 MHz Bandwidth'}
                    distAWNRxIWNTx = sqrt(sum((obj.IWN(i).TxPosition-awnRxPosition).^2,2));
                    channelIWN = wlanTGnChannel(SampleRate=obj.InputSampleRate*obj.IWN(i).OverSamplingFactor,...
                        CarrierFrequency=obj.IWN(i).Frequency,...
                        TransmitReceiveDistance=distAWNRxIWNTx,...
                        NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas,...
                        DelayProfile=obj.DelayProfile);
                    rxIWN{i} = channelIWN(iwnWaveform{i});

                case 'IEEE 802.15.4'
                    % % Fading channel for IEEE 802.15.4 using Rayleigh or Rician
                    sig = iwnWaveform{i};
                    fs = obj.InputSampleRate;
                    % Select path delays and gains based on environment
                    switch obj.EnvironmentWpan
                        case 'Indoor office'
                            pathDelays   = [0 30e-9 70e-9 90e-9];    % seconds
                            avgPathGains = [ 0   -1    -2    -3];      % dB
                        case 'Home'
                            pathDelays   = [0 20e-9 50e-9 80e-9];
                            avgPathGains = [ 0   -2    -4    -6];
                        case 'Industrial'
                            pathDelays   = [0 40e-9 100e-9 150e-9];
                            avgPathGains = [ 0   -3    -6    -9];
                        case 'Outdoor'
                            pathDelays   = [0 100e-9 200e-9 300e-9];
                            avgPathGains = [ 0   -5   -10   -15];
                        otherwise
                            % default to indoor office
                            pathDelays   = [0 30e-9 70e-9 90e-9];
                            avgPathGains = [ 0   -1    -2    -3];
                    end
                    % Create fading channel
                    switch channelModel
                        case 'Rician Channel'
                            fadeChan = comm.RicianChannel( ...
                                SampleRate=fs, PathDelays=pathDelays, ...
                                AveragePathGains=avgPathGains, KFactor=6, ...
                                MaximumDopplerShift=0);
                        case 'Rayleigh Channel'
                            fadeChan = comm.RayleighChannel( ...
                                SampleRate=fs, PathDelays=pathDelays, ...
                                AveragePathGains=avgPathGains, MaximumDopplerShift=0);
                        otherwise
                            error('Unsupported channelModel %s for IEEE 802.15.4', channelModel);
                    end
                    rxIWN{i} = fadeChan(sig);

                otherwise
                    distAWNRxIWNTx = sqrt(sum((obj.IWN(i).TxPosition-awnRxPosition).^2,2));
                    bw = ['CBW' num2str(obj.InputSampleRate/1e6)];
                    channelIWN = wlanTGaxChannel(SampleRate=obj.InputSampleRate*obj.IWN(i).OverSamplingFactor,...
                        CarrierFrequency=obj.IWN(i).Frequency,...
                        ChannelBandwidth=bw,...
                        TransmitReceiveDistance=distAWNRxIWNTx,...
                        NumTransmitAntennas=obj.IWN(i).NumTransmitAntennas,...
                        DelayProfile=obj.DelayProfile);
                    rxIWN{i} = channelIWN(iwnWaveform{i});
            end
        end
    end
    function awnIWNWaveform = addInterference(obj,awnWaveform,iwnWaveform,awnFrequency)
    %addInterference Add interference to the AWN waveform
    %   AWNIWNWAVEFORM = addInterference(OBJ,AWNWAVEFORM,IWNWAVEFORM,...
    %   TIMINGDELAY) adds IWN waveforms to the AWN waveform.
    %
    %   AWNIWNWAVEFORM is a complex column vector, representing the
    %   AWN waveform along with interference.
    %
    %   OBJ is an object of type helperIWNConfig.
    %
    %   AWNWAVEFORM is a complex column vector, representing the AWN
    %   waveform.
    %
    %   IWNWAVEFORM is a cell array of size 1-by-N, where N represents the
    %   number of interference nodes. Each cell represents a column vector
    %   of size Ns-by-1, where Ns represents the number of time-domain
    %   samples.
    %
    %   AWNFREQUENCY is a scalar, representing the carrier frequency of the
    %   AWN waveform.
       nIWN = numel(iwnWaveform);   %Num of different waveforms
       nIWNC = cellfun('size',iwnWaveform,2);  %Should be a vector with the sizes of every cell in the row 
       numSig = sum(nIWNC)+1;                  %Num of signals + 1 apparently, the +1 is for the AWN signal, not sure how it works (maybe because double)
       TWInterpolation = 0.01;  %Transition Band width of filter
       AstopInterpolation = 40;  %Attenuation of Stop band filter
       % Sample rate match: Bring all waveforms to the sampling rate of the
       % highest sample rate signal
       newFs = obj.InputSampleRate;    %Takes Input Sample Rate, which is WLAN's, again, because it's the biggest i assume?
       if obj.IWN(1).OverSamplingFactor ~= 1    %Why IWN(1)? I assume because it was designed by a retard
           newFs = obj.IWN(1).OverSamplingFactor*obj.InputSampleRate;   %Calculating REAL SampleRate
           [P,Q] = rat(obj.IWN(1).OverSamplingFactor);   %Still calculated on IWN(1), still assume it's for the same reason as before
           awnWaveform = resample(awnWaveform,P,Q);         %Resamples everything to fit 80Mhz --> 
           iwnWaveform{2} = resample(iwnWaveform{2},P,Q);   
           iwnWaveform{3} = resample(iwnWaveform{3},P,Q);
       end
        

       %At this point, we have n waveforms, all sampled at 80Mhz, but of
       %different lengths based on the signals we had in input



       % Interpolating all waveforms to a higher sampling rate based on
       % collision probability
       % [n,d] = rat(obj.OutputSampleRate/newFs);
       % firinterp = dsp.FIRRateConverter(n,d,...
       %      designMultirateFIR(n,d,TWInterpolation,AstopInterpolation));
       spc = 4;                      % samples per chip ZigBee
       zigbeeType = "IEEE 802.15.4";
    
        % 1) Se c'è un IWN ZigBee, risampla quell’unico waveform  --> Imo
        % dovrebbe essere fatto prima
        for k = 1:obj.NumIWNNodes
            if obj.IWN(k).SignalType == zigbeeType
                % calcola fattore di upsampling F = InputSampleRate/(spc*2e6)
                F = obj.InputSampleRate/(spc*2e6);
                if F ~= 1
                    [Pz, Qz] = rat(F);
                    % risampia solo il cell corrispondente
                    iwnWaveform{k} = resample(iwnWaveform{k}, Pz, Qz);
                end
            end
        end
    
        % 2) Prepara newFs in base all’oversampling (resta invariato)
        newFs = obj.InputSampleRate * obj.IWN(1).OverSamplingFactor;
    
        reqLen = numel(awnWaveform);    %AWN waveform lenght (it should be size(awnWaveform, 1))
        allSig = zeros(reqLen,numSig);  % Generates a matrix that has numSig (IWN size) column vectors filled with zeros of the size of awnWf
        allSig(:,end) = awnWaveform;    % The last column is set to be the awn signal
        sInd = 1;               
        for n = 1:nIWN
            if obj.IWN(n).CollisionProbability > 0 && obj.IWN(n).CollisionProbability <= 1
                numZerosAppended = ...
                    ceil(numel(awnWaveform)*(1-obj.IWN(n).CollisionProbability));  
                iwnWaveformTemp = [iwnWaveform{n}];
                nS = size(iwnWaveformTemp,2);
                iwnWaveformTemp = [zeros(numZerosAppended,nS);iwnWaveformTemp]; %#ok<*AGROW>
                
                %Ok here's how the collision probability works and why it's
                %shit imo:
                %Basically this code "shifts forward" the signals by
                %putting a bunch of zeros at the start. This should only
                %result in a spectrum that starts after a while right?
                %WRONG, because the Interference gets added every Bluetooth
                %packet, so everything gets delayed and results in a fucked
                %up signal on the spectrum



                %Fixes length of the signals to match the waveform
                for nC = 1:nS
                    if numel(iwnWaveformTemp(:,nC)) < reqLen
                        allSig(:,sInd) = [iwnWaveformTemp(:,nC);zeros(numel(awnWaveform)-numel(iwnWaveformTemp(:,nC)),1)];
                    else
                        allSig(:,sInd) = iwnWaveformTemp(1:reqLen,nC);
                    end
                     sInd = sInd+1;
                end
            else
                sInd = sInd+1;
            end
        end

        %Why in the actual fuck do i care if Rows * Columns is divisible
        %for that? I should care that Rows is 
        allSigRem = rem(numel(allSig), ceil(newFs/1e6));
        if allSigRem
            allSigTemp = [allSig;zeros(ceil(newFs/1e6)-allSigRem,numSig)];
        else
            allSigTemp = allSig;
        end

        %Fixes again the sample rate, but this time in relation to what it
        %wants it to be when it goes out
        [n,d] = rat(obj.OutputSampleRate/newFs);
        firinterp = dsp.FIRRateConverter(n, d, ...
            designMultirateFIR(n,d,TWInterpolation,AstopInterpolation));
        allSigFilt = firinterp(allSigTemp);
        iwnFreqs = [obj.IWN.Frequency];
        freqOffset = [iwnFreqs awnFrequency]-2440e6;
        nDiff = size(allSigFilt,2) - numel(freqOffset);
        if nDiff
            freqOffset = [freqOffset(1)*ones(1,nDiff+1) freqOffset(2:end)];
        end
        % Combine the AWN and IWN waveforms 
        sigcom = comm.MultibandCombiner(InputSampleRate=obj.OutputSampleRate,...
            FrequencyOffsets=freqOffset,...
            OutputSampleRateSource="Property",OutputSampleRate=obj.OutputSampleRate); 
        awnIWNWaveform = sigcom(allSigFilt);
    end
end
end