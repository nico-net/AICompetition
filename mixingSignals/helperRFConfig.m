classdef helperRFConfig < comm.internal.ConfigBase
    %HELPERRFCONFIG Config for multi-signal RF coexistence (BLE, BR, 802.11ax, 802.15.4)
    
    properties
        RfSignals               % Array of structs describing each RF signal
        SampleRate = 20e6       % Common output sample rate for all waveforms
        Environment = "Outdoor" % Channel environment
        DelayProfile = "Model-B"% WLAN delay profile
        ChannelModel = "Rician"          % e.g. "Rayleigh", "Rician", "AWGN"
    end

    properties(Hidden)
        NumRFSignals            % Number of RF signals
        Bandwidth               % Bandwidth vector per signal
    end
    
    methods
        function obj = helperRFConfig(varargin)
            % Constructor: set properties via name-value
            obj = obj@comm.internal.ConfigBase(varargin{:});
            obj.NumRFSignals = numel(obj.RfSignals);
            obj.Bandwidth = computeBandwidth(obj);
        end
        
        function wfCell = generateWaveforms(obj, pkt)
            % generateWaveforms  Generate waveforms for all signals
            if nargin<2 || isempty(pkt)
                pkt = 1;
            end
            wfCell = cell(obj.NumRFSignals,1);
            for i = 1:obj.NumRFSignals
                sig = obj.RfSignals(i);
                switch sig.SignalType
                    case {'LE1M','LE2M'}
                        ch = helperRFConfig.bleFrequencyHop(sig.CurrentChannel, sig.ChannelMap, sig.HopIncrement);
                        obj.RfSignals(i).CurrentChannel = ch;
                        data = randi([0 1],255*8,1,'int8');
                        sps = obj.SampleRate/(1e6*(1 + strcmp(sig.SignalType,'LE2M')));
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
                        msg = randi([0 1], sig.LRWPanConfig.PSDULength*8,1);
                        wf = lrwpanWaveformGenerator(msg, sig.LRWPanConfig);
                    case '802.11ax'
                        data = randi([0 1], getPSDULength(sig.WlanConfig)*8,1);
                        wf = wlanWaveformGenerator(data, sig.WlanConfig,...
                            OversamplingFactor=sig.OverSamplingFactor);
                    otherwise
                        error('Unsupported SignalType %s', sig.SignalType);
                end
                origFs = sig.SamplesPerSymbol * 1e6;
                if origFs ~= obj.SampleRate
                    [p_up,q_dn] = rat(obj.SampleRate/origFs);
                    wf = resample(wf, p_up, q_dn);
                end
                wfCell{i} = wf;
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
                        chan = comm.RayleighChannel(SampleRate=obj.SampleRate,...
                            PathDelays=[0 30e-9 70e-9], AveragePathGains=[0 -3 -6]);
                        rxWaveforms{k} = chan(wf);
                    case 'Rician'
                        chan = comm.RicianChannel(SampleRate=obj.SampleRate,...
                            PathDelays=[0 30e-9 70e-9], AveragePathGains=[0 -3 -6], KFactor=6);
                        rxWaveforms{k} = chan(wf);
                    case 'AWGN'
                        rxWaveforms{k} = awgn(wf, 10, 'measured');
                    otherwise
                        error('Unknown ChannelModel %s', obj.ChannelModel);
                end
            end
        end
        
        function bandwidth = computeBandwidth(obj)
            bandwidth = zeros(1,obj.NumRFSignals);
            for i = 1:obj.NumRFSignals
                switch obj.RfSignals(i).SignalType
                    case {'LE1M','LE2M'}, bandwidth(i)=2e6;
                    case 'BR',           bandwidth(i)=1e6;
                    case '802.15.4',     bandwidth(i)=8e6;
                    case '802.11ax',     bandwidth(i)=20e6;
                    otherwise,          bandwidth(i)=obj.SampleRate;
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
    end
end
