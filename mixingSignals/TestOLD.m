%% MIXING DIFFERENT SIGNALS
% This example shows you how to model homogeneous and heterogeneous coexistence between Bluetooth® 
% basic rate/enhanced data rate (BR/EDR), low energy (LE) , wireless local area network (WLAN)
% and LR-WPAN (IEEE 802.15.4) waveforms.

%% Simulation parameters
% Specify the AWN parameters such as the signal type, transmitter position, 
% transmitter power, and packet type. Receiver position is assumed to be in
% [0,0]. 
%Possible types of signals:
% "LE1M"
% "LE2M"
% "BR"
% "802.11 ax"
% "IEEE 802.15.4"

insertParameters = "manual"; %manual or random
sampleRate = 20e6; %in Hz
numPackets = 1;

iwn(1).SignalType = "802.11ax with 20 MHz Bandwidth";
iwn(1).TxPosition = [20,0,0];                       % In meters
iwn(1).Frequency = 2437e6;                          % In Hz
iwn(1).NumTransmitAntennas = 1;                     % Number of transmit antennas
iwn(1).TxPower = 15;                                % In dBm (typically 12-20dBm)
iwn(1).CollisionProbability = 0;                    % Probability of collision in time, must be between [0,1]
iwn(1).OverSamplingFactor = 1;                      % over sampling factor
wlanFsym = str2double(extractBetween(iwn(1).SignalType,"with "," MHz"))*1e6; % WLAN signal symbol rate
ospf = iwn(1).OverSamplingFactor;
wlanFsamp = wlanFsym*ospf;                          % WLAN signal sampling rate in Hz

iwn(2).SignalType = "BR";
iwn(2).TxPosition = [25,0,0];                       % In meters
iwn(2).Frequency = 2420e6;                          % In Hz
iwn(2).TxPower = 2;                                % In dBm
iwn(2).CollisionProbability = 1;                  % Probability of collision in time, must be between [0,1]

iwn(3).SignalType = "IEEE 802.15.4";
iwn(3).TxPosition = [30,0,0];    %in meters (typically distances from 10 to 100m, It could be up to 500m too)
iwn(3).Frequency = 2460e6;        %in Hz 
iwn(3).TxPower = 0;              %in dBm (typically 0dBm)
iwn(3).CollisionProbability = 0;


if strcmp(insertParameters, "manual")
    nSignals = 3; % number of coexisting signals
    for i = 1:nSignals
        % Mappatura dei campi base da iwn a rfSignals
        switch iwn(i).SignalType
            case "802.11ax with 20 MHz Bandwidth"
                rfSignals(i).SignalType = "802.11ax";
            case "IEEE 802.15.4"
                rfSignals(i).SignalType = "802.15.4";
            otherwise
                rfSignals(i).SignalType = iwn(i).SignalType;
        end
        rfSignals(i).TxPosition = iwn(i).TxPosition;
        rfSignals(i).Frequency = iwn(i).Frequency;
        rfSignals(i).TxPower = iwn(i).TxPower;
        
        % Configurazioni specifiche per tipo di segnale
        switch rfSignals(i).SignalType
            case {"LE1M", "LE2M"}
                rfSignals(i).EnableHopping = 1;
                rfSignals(i).FrequencyHop = bleChannelSelection;
                rfSignals(i).numBTChannels = 79;
                rfSignals(i).minChannels = 20;
                rfSignals(i).ChannelMap = true(1,37);  % Mappa canali abilitati
                rfSignals(i).HopIncrement = 5;         % Incremento dello hopping
                
            case "BR"
                rfSignals(i).PacketType = "FHS";
                rfSignals(i).EnableHopping = 1;
                phyFactor = 1;
                %sampleRate = iwn(i).Frequency; % Esempio, potrebbe richiedere correzioni
                spsB = sampleRate/(1e6*phyFactor);
                rfSignals(i).WaveformConfig = bluetoothWaveformConfig(...
                    Mode=rfSignals(i).SignalType, ...
                    PacketType=rfSignals(i).PacketType, ...
                    SamplesPerSymbol=spsB);
                rfSignals(i).InputClock = 0;
                rfSignals(i).numBTChannels = 79;
                rfSignals(i).minChannels = 20;
                rfSignals(i).DeviceAddress = hex2dec('012345'); % Indirizzo univoco dispositivo
                rfSignals(i).InputClock = randi([0 2^28-1]);    % Clock iniziale
                
            case "802.11ax"
                rfSignals(i).NumTransmitAntennas = iwn(i).NumTransmitAntennas;
                rfSignals(i).OverSamplingFactor = iwn(i).OverSamplingFactor;
                rfSignals(i).WlanConfig = wlanHESUConfig(...
                    ChannelBandwidth='CBW20',...
                    NumTransmitAntennas=rfSignals(i).NumTransmitAntennas,...
                    NumSpaceTimeStreams=rfSignals(i).NumTransmitAntennas);
                
            case "802.15.4"
                rfSignals(i).probTx = 0.2;
                spc = 4;
                msgLen = 120*8; % in bits
                rfSignals(i).LRWPanConfig = lrwpanOQPSKConfig(...
                    Band=2450, ...
                    PSDULength=msgLen/8, ...
                    SamplesPerChip=spc);
        end
        switch rfSignals(i).SignalType
            case "LE1M"
                symRate = 1e6;      % 1 Msym/s :contentReference[oaicite:5]{index=5}
            case "LE2M"
                symRate = 2e6;      % 2 Msym/s :contentReference[oaicite:6]{index=6}
            case "BR"
                symRate = 1e6;      % 1 Msym/s :contentReference[oaicite:7]{index=7}
            case "802.11ax"
                symRate = 20e6;     % 20 MHz BW :contentReference[oaicite:8]{index=8}
            case "802.15.4"
                symRate = 1e6;      % 1 Msym/s :contentReference[oaicite:9]{index=9}
            otherwise
                error("Unknown SignalType %s", rfSignals(i).SignalType);
        end
        % Sample-rate unificato
        Fs = sampleRate;           
        % Assegna SamplesPerSymbol
        rfSignals(i).SamplesPerSymbol = Fs/symRate; 
    end
end

%% Channel parameters
environment = "Office"; %"Outdoor" "Industrial" "Home" "Office"
EbNo = 3; %in dB
channelModel = "Rayleigh"; %Rayleigh Rician AWGN


%% Generate waveforms
rfConfig = helperRFConfigOLD(RfSignals =rfSignals ,SampleRate=sampleRate,...
    Environment=environment);
signalsWaveform = generateWaveforms(rfConfig);

% dopo aver creato rfConfig e specAn come prima

for pkt = 1:numPackets
    wf = rfConfig.generateWaveforms(pkt);    % ritorna {wf1; wf2; …}
    rx = rfConfig.applyPathloss(wf, [0 0 0]);             % attenuate
    rx = rfConfig.applyChannel(rx, channelModel);   
end