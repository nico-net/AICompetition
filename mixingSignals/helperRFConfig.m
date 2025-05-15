classdef helperRFConfig < comm.internal.ConfigBase
    %HELPERRFCONFIG Config for multi-signal RF coexistence (BLE, BR, 802.11ax, 802.15.4)
    
    properties
        maxSignals = 10;        % To be num of Signals in the future and be calculated from inputs
        RfSignals;               % Array of structs describing each RF signal
        InputSampleRate = 20e6;  % Common input sample rate for all waveforms
        OutputSampleRate = 80e6;
        Environment = "Outdoor" % Channel environment
        DelayProfile = "Model-B"% WLAN delay profile
        ChannelModel = "Rician"          % e.g. "Rayleigh", "Rician", "AWGN"
        BTSlotsPerSnapshot = 5;
        BTslotDebit = [];
        ZigBeeProb = 0.1;
        slotsLength = 250000;
        ceneterFreq = 2441e6;
        

    end

    properties(Hidden)
        NumRFSignals            % Number of RF signals
        Bandwidth               % Bandwidth vector per signal
        upscaler
        decimator
        packetDebit = [];
    end
    
    methods
        function obj = helperRFConfig(varargin)
            % Constructor: set properties via name-value
            obj = obj@comm.internal.ConfigBase(varargin{:});
            obj.NumRFSignals = numel(obj.RfSignals);
            obj.Bandwidth = computeBandwidth(obj);
            [obj.upscaler, obj.decimator] = rat(obj.OutputSampleRate/obj.InputSampleRate);
            obj.packetDebit = cell(1, obj.maxSignals);
            obj.BTslotDebit = zeros(1, obj.NumRFSignals);
        end
        


        function finalWf = createSnapshot(obj)
            wfCell = cell(1, obj.NumRFSignals);
            for i = 1:obj.NumRFSignals
                slotCount = 0;
                sig=obj.RfSignals(i);
                switch sig.SignalType
                    case {'LE1M','LE2M'}
                    case 'BR'
                        %The function should
                        %1) Check if there are any leftovers from previous
                        %   snapshots
                        %2) Loop BTSlotsPerSnapshot times over
                        %2.1) Generate Packet in BB 
                        %2.2) Apply channel
                        %2.3) Upscale
                        %2.4) Shift frequency
                        %2.5) Append
                        if (obj.BTslotDebit(i) ~= 0)
                            wf = obj.packetDebit{i};
                            disp('size of wf')
                            size(wf)
                            obj.packetDebit{i} = {};
                            slotCount = obj.BTslotDebit(i);
                            obj.BTslotDebit(i) = 0; 
                        end
                        wf = [];
                        while (slotCount < obj.BTSlotsPerSnapshot)
                            nSlots = obj.packetSlotOccupancy(sig.WaveformConfig.PacketType);
                            data = randi([0 1], getPayloadLength(sig.WaveformConfig)*8,1);
                            bbWf = bluetoothWaveformGenerator(data, sig.WaveformConfig);
                            % Multiply for Tx Power
                            chanBBWf = bbWf; % APPLY CHANNEL --> We are at 20 Mhz atm (InputSampleRate
                            %Upscaling --> Ask prof Tubaro about using FIR
                            %instead
                            wfResampled = resample(chanBBWf, obj.upscaler, obj.decimator);
                            %Shifting Frequency
                            ch = helperRFConfig.brFrequencyHop(sig.InputClock, sig.DeviceAddress);
                            fOff = comm.PhaseFrequencyOffset;
                            fOff.FrequencyOffset = (ch-39)*1e6;
                            hoppedWf = fOff(wfResampled);
                            release(fOff);
                            sig.InputClock = sig.InputClock + nSlots*2;
                            slotCount = slotCount + nSlots;
                            %Fixing for longer packets
                            if (slotCount > obj.BTSlotsPerSnapshot)
                                slotSize = size(hoppedWf, 1)/nSlots;
                                obj.BTslotDebit(i)
                                obj.BTslotDebit(i) = slotCount - obj.BTSlotsPerSnapshot;
                                obj.packetDebit{i} = hoppedWf(end-slotSize*obj.BTslotDebit(i) +1 :end);
                                hoppedWf = hoppedWf(1 : end-slotSize*obj.BTslotDebit(i));
                            end
                            %Appending
                            wf = [wf; hoppedWf];
                        end
                    case '802.15.4'
                        wf = [];
                        if (rand() < obj.ZigBeeProb)
                            sig.LRWPanConfig.PSDULength; %DB
                            msg = randi([0 1], sig.LRWPanConfig.PSDULength*8,1);
                            ZigWf = lrwpanWaveformGenerator(msg, sig.LRWPanConfig);
                            %Apply channel and stuff
                            ResWf = resample(ZigWf, obj.upscaler * obj.RfSignals(i).SamplesPerSymbol, obj.decimator);
                            zerosToAdd = size(ResWf,1) - obj.slotsLength;
                            if (zerosToAdd > 0)
                                zerosBef = zeros(floor(zerosToAdd * rand()), 1);
                                zerosAft = zeros(zerosToAdd - size(zerosBef, 1), 1);
                                wf = [zerosBef; ResWf; zerosAft];
                            else 
                                wf = ResWf(1:obj.slotsLength);
                                disp('Longer than expected');
                            end
                            fOff = comm.PhaseFrequencyOffset;
                            fOff.FrequencyOffset(obj.RfSignals(i).Frequency-obj.ceneterFreq);
                            wf = fOff(wf);
                        else
                            wf = zeros(obj.slotsLength, 1);
                        end
                    case '802.11ax'
                        wf = [];
                        data = randi([0 1], getPSDULength(sig.WlanConfig)*8,1);
                        Wlanwf = wlanWaveformGenerator(data, sig.WlanConfig,...
                            OversamplingFactor=sig.OverSamplingFactor);
                        %Apply channel
                        ResWf = resample(Wlanwf, obj.upscaler, obj.decimator);
                        zerosToAdd = obj.slotsLength - size(ResWf, 1);
                        if (zerosToAdd > 0)
                            disp('We have to add zeros')
                            wf = [ResWf; zeros(zerosToAdd, 1)];
                        else
                            %Fill DebitPacket
                            wf = ResWf;
                        end
                end
                wfCell{i} = wf;
            end
            finalWf = zeros(obj.slotsLength, 1);
            for i = 1:obj.NumRFSignals
                size(wfCell{i});
                finalWf = finalWf + wfCell{i};
            end
        end
        









        function wfCellold = generateWaveforms(obj)
            % generateWaveforms  Generate waveforms for all signals
            wfCellold = cell(obj.NumRFSignals,1);
            for i = 1:obj.NumRFSignals
                sig = obj.RfSignals(i);
                switch sig.SignalType
                    case {'LE1M','LE2M'}
                        ch = helperRFConfig.bleFrequencyHop(sig.CurrentChannel, sig.ChannelMap, sig.HopIncrement);
                        obj.RfSignals(i).CurrentChannel = ch;
                        data = randi([0 1],255*8,1,'int8');
                        sps = obj.InputSampleRate/(1e6*(1 + strcmp(sig.SignalType,'LE2M')));
                        wf = bleWaveformGenerator(data,...
                            'Mode',sig.SignalType,...
                            'ChannelIndex',ch,...
                            'SamplesPerSymbol',sps);

                    case 'BR'
                        sig.InputClock = sig.InputClock + 1;
                        ch = helperRFConfig.brFrequencyHop(sig.InputClock, sig.DeviceAddress);
                        data = randi([0 1], getPayloadLength(sig.WaveformConfig)*8,1);
                        wf = bluetoothWaveformGenerator(data, sig.WaveformConfig);
                    case '802.15.4'
                        sig.LRWPanConfig.PSDULength; %DB
                        msg = randi([0 1], sig.LRWPanConfig.PSDULength*8,1);
                        wf = lrwpanWaveformGenerator(msg, sig.LRWPanConfig);
                    case '802.11ax'
                        getPSDULength(sig.WlanConfig); %DB
                        data = randi([0 1], getPSDULength(sig.WlanConfig)*8,1);
                        wf = wlanWaveformGenerator(data, sig.WlanConfig,...
                            OversamplingFactor=sig.OverSamplingFactor);
                    otherwise
                        error('Unsupported SignalType %s', sig.SignalType);
                end
                origFs = sig.SamplesPerSymbol * sig.symRate;
                if origFs ~= obj.OutputSampleRate
                    disp(['had to undergo resamplig'])
                    [p_up,q_dn] = rat(obj.OutputSampleRate/origFs);
                    wf = resample(wf, p_up, q_dn);
                end
                wfCellold{i} = wf;
            end
        end
        
        function [rxWaveforms, pathLossdB] = applyPathloss(obj, txWaveforms, rxPosition)
            %applyPathloss  Apply path loss scaling to each transmitted waveform
            % txWaveforms: cell array {wf1, wf2, ...}
            % rxWaveforms: cell array of attenuated waveforms
            N = obj.NumRFSignals;
            rxWaveforms = cell(1,N);
            pathLossdB = zeros(1,N);
            cfg = bluetoothPathLossConfig(Environment=obj.Environment);
            for k=1:N
                txPos = obj.RfSignals(k).TxPosition;
                d = norm(txPos - rxPosition);
                Ld = bluetoothPathLoss(d, cfg);
                pathLossdB(k) = Ld;
                rxWaveforms{k} = txWaveforms{k} / (10^(Ld/20));
            end
        end
        
        function rxWaveforms = applyChannel(obj, txWaveforms,channelModel, EbNo)
            %applyChannel  Pass waveforms through fading channel models
            % txWaveforms: cell array of waveforms
            % rxWaveforms: cell array of faded waveforms
            N = obj.NumRFSignals;
            rxWaveforms = cell(1,N);
            for k=1:N
                sig = obj.RfSignals(k);
                wf = txWaveforms{k};
                switch channelModel
                    case 'Rayleigh'
                        chan = comm.RayleighChannel(SampleRate=obj.InputSampleRate,...
                            PathDelays=[0 30e-9 70e-9], AveragePathGains=[0 -3 -6]);
                        rxWaveforms{k} = chan(wf);
                    case 'Rician'
                        chan = comm.RicianChannel(SampleRate=obj.InputSampleRate,...
                            PathDelays=[0 30e-9 70e-9], AveragePathGains=[0 -3 -6], KFactor=6);
                        rxWaveforms{k} = chan(wf);
                    case 'AWGN'
                        rxWaveforms{k} = awgn(wf, 10, 'measured');
                    otherwise
                        error('Unknown ChannelModel %s', obj.ChannelModel);
                end
            end
        end
        


        %Why is it both inside and outside ffs
        function bandwidth = computeBandwidth(obj)
            bandwidth = zeros(1,obj.NumRFSignals);
            for i = 1:obj.NumRFSignals
                switch obj.RfSignals(i).SignalType
                    case {'LE1M','LE2M'}, bandwidth(i)=2e6;
                    case 'BR',           bandwidth(i)=1e6;
                    case '802.15.4',     bandwidth(i)=4e6;
                    case '802.11ax',     bandwidth(i)=20e6;
                    otherwise,          bandwidth(i)=obj.InputSampleRate;
                end
            end
        end
    end
    
    methods (Static)
        function nextChannel = bleFrequencyHop(currChannel, channelMap, hopIncrement)
            used = find(channelMap);
            idx  = mod(find(used==currChannel)+hopIncrement-1, numel(used))+1;
            nextChannel = used(idx);
        end
        function nextChannel = brFrequencyHop(clk, address)
            f = @(k) mod(bitxor(address, bitand(bitshift(address,-16),clk+k)),79);
            nextChannel = f(mod(clk,625))+1;
        end

        function slotDuration = packetSlotOccupancy(packetType)
            switch packetType
                case {'ID', 'NULL', 'POLL', 'FHS', 'DM1', 'DH1','2-DH1','3-DH1', ...
                    'HV1', 'HV2', 'HV3', 'DV', 'EV3', '2-EV3', '3-EV3'} 
                    slotDuration = 1;
                case {'DM3', 'DH3', '2-DH3', '3-DH3', 'EV4', 'EV5', '2-EV5', '3-EV5'}
                    slotDuration = 3;
                case {'DM5', 'DH5', '2-DH5', '3-DH5'}
                    slotDuration = 5;
            end
        end
    end
end
