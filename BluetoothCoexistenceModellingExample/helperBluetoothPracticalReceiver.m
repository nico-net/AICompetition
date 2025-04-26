function [bits,decodedInfo,pktValidStatus] = helperBluetoothPracticalReceiver(rxWaveform,rxCfg)
%helperBluetoothPracticalReceiver detects, synchronizes, and decodes
%received Bluetooth BR/EDR waveform
%
%   [BITS,DECODEDINFO,PKTVALIDSTATUS] =
%   helperBluetoothPracticalReceiver(RXWAVEFORM,RXCFG) detects,
%   synchronizes, and decodes received time domain Bluetooth BR/EDR signal,
%   RXWAVEFORM, for a given system configuration, RXCFG.
%
%   BITS are the decoded payload bits from the detected Bluetooth BR/EDR
%   waveform. It is a binary column vector of type double.
%
%   DECODEDINFO array of structures containing these fields:
%     PacketType               - Type of Bluetooth BR/EDR packet received.
%                                The value of this field is a scalar or a
%                                character vector containing one of these:
%                                {'ID','NULL','POLL','FHS','HV1','HV2',
%                                 'HV3','DV','EV3','EV4','EV5','AUX1',
%                                 'DM3','DM1','DH1','DM5','DH3','DH5',
%                                 '2-DH1','2-DH3','2-DH5','2-DH1','2-DH3',
%                                 '2-DH5','2-EV3','2-EV5','3-EV3','3-EV5'}.
%     LAP                      - Decoded lower address part (LAP) of the
%                                Bluetooth device address, a 24-bit column
%                                vector of type double.
%     PayloadLength            - Number of payload bytes in the received
%                                Bluetooth packet, a scalar of type
%                                double.
%     LogicalTransportAddress  - Active destination peripheral for a packet
%                                in a central-to-peripheral transmission
%                                slot. It is a 3-bit vector of type double.
%     HeaderControlBits        - Link control information, a 3-bit
%                                vector of type double containing FLOW,
%                                ARQN and SEQN bits.
%     LLID                     - Logical link identifier, a 2-bit binary
%                                vector of type double. This field is
%                                applicable only for these packet types:
%                                {'DM1','DH1','DM3','DH3','DM5','DH5',
%                                 'AUX1','DV','2-DH1','2-DH3','2-DH5',
%                                 '3-DH1','3-DH3','3-DH5'}.
%     FlowIndicator            - Control data flow indicator over logical
%                                channels, scalar of type double. This
%                                field is applicable only for these packet
%                                types: {'DM1','DH1','DM3','DH3','DM5',
%                                'DH5','AUX1','DV','2-DH1','2-DH3','2-DH5',
%                                '3-DH1','3-DH3','3-DH5'}.
%
%   PKTVALIDSTATUS is a logical vector indicating whether the received
%   packet is valid or not based on the decoded LAP, packet header error
%   check (HEC), and cyclic redundancy check (CRC).
%
%   helperBluetoothPracticalReceiver performs these operations on the
%   received waveform:
%
%   * Removes DC from the received signal
%   * Detects Bluetooth BR/EDR signal from the received burst 
%   * Performs matched filtering
%   * Estimates and compensates timing offset
%   * Estimates and compensates frequency offset
%   * Demodulates and decodes compensated Bluetooth waveform
%   * Outputs packet valid status based on decoded LAP, HEC and CRC of the
%   waveform

%   Copyright 2019-2022 The MathWorks, Inc.

% Generate known LAP and access code from the system parameters
btDeviceAddr = int2bit(hex2dec(rxCfg.DeviceAddress)',48, false);
btLAP = btDeviceAddr(1:24);
sps = rxCfg.SamplesPerSymbol;
modIndex = rxCfg.ModulationIndex;
accessCodeWaveform = bluetoothGenerateACWaveform(btLAP,sps,modIndex);

% Remove DC from the received signal 
dcCompensatedWaveform = bluetoothDCBlocker(rxWaveform);

% Get Bluetooth BR/EDR signal indices from the burst
[numOfSignals,startIndices,endIndices] = bluetoothSignalIndices(dcCompensatedWaveform,rxCfg);

% Initialize output arguments
validPacketsTemp = zeros(1,numOfSignals);
decodedInfoTemp(1:numOfSignals) = struct('LAP',zeros(24,1),'PacketType','ID',...
                                    'LogicalTransportAddress',zeros(3,1),...
                                    'HeaderControlBits',zeros(3,1),...
                                    'PayloadLength',0,'LLID',zeros(2,1),'FlowIndicator',0);
bits = [];
count = 0;
for ii = 1:numOfSignals
    % Trim the waveform
    rxWaveformTrim = rxWaveform(startIndices(ii):endIndices(ii));

    % Time and frequency estimation and compensation
    rxComp = bluetoothTimeFreqSync(rxWaveformTrim,accessCodeWaveform,sps);
    
    % Decode Bluetooth signal
    [outBits,decodedInformation,PktStatus] = bluetoothIdealReceiver(rxComp,rxCfg);
    
    % Check if the decoded LAP is correct
    lapFlag = isequal(decodedInformation.LAP,btLAP);
    if (lapFlag)        
        count = count + 1;
        decodedInfoTemp(count) = decodedInformation;
        validPacketsTemp(count) = PktStatus;
        bits = [bits;outBits];
    end
end
if ~(count == 0)
    decodedInfo = decodedInfoTemp(1:count);
    pktValidStatus = validPacketsTemp(1:count);
else
    decodedInfo = struct('LAP',zeros(24,1),'PacketType','ID',...
                                    'LogicalTransportAddress',zeros(3,1),...
                                    'HeaderControlBits',zeros(3,1),...
                                    'PayloadLength',0,'LLID',zeros(2,1),'FlowIndicator',0);
    pktValidStatus = [];
end
end

function accessCodeWaveform = bluetoothGenerateACWaveform(btLAP,sps,modInd)
%bluetoothGenerateACWaveform generates access code waveform,
%ACCESSCODEWAVEFORM, based on the system parameters, RXCFG

accessCode = bluetooth.internal.accessCodeGenerate(btLAP,'ID');
persistent cpmMod
if isempty(cpmMod)
    cpmMod = comm.CPMModulator('ModulationOrder',2,'FrequencyPulse','Gaussian',...
                   'BandwidthTimeProduct',0.5,'ModulationIndex',modInd,...
                   'BitInput',true,'SamplesPerSymbol',sps);
elseif((cpmMod.SamplesPerSymbol ~= sps) || (cpmMod.ModulationIndex ~= modInd))
    release(cpmMod);
    cpmMod.SamplesPerSymbol = sps;
    cpmMod.ModulationIndex = modInd;
end
accessCodeWaveform = cpmMod(accessCode);
end

function dcCompensatedWaveform = bluetoothDCBlocker(waveform)
%bluetoothDCBlocker removes DC offset from the signal, WAVEFORM
dcComponent = mean(waveform);
dcCompensatedWaveform = waveform-dcComponent;
end

 
function [numOfSignals,startIndices,endIndices] = bluetoothSignalIndices(waveform,rxCfg)
%bluetoothSignalIndices performs energy detection on the received
%signal, WAVEFORM and outputs these things:
%   NUMOFSIGNALS - Number of signals detected from the received burst
%   STARTINDICES - Array containing start indices of each detected burst
%   ENDINDICES - Array containing end indices of each detected burst

% Normalize received signal
meanTxWaveform = zeros(numel(waveform),1);
windowLen = 100;
nofWindows = floor(numel(waveform)/windowLen);
winMag = abs(sum(reshape(abs(waveform(1:nofWindows*windowLen)),windowLen,nofWindows)));
for ii = 1:nofWindows
    meanTxWaveform(((ii-1)*windowLen)+1:ii*windowLen) = winMag(ii);
end
diffMag = diff([min(meanTxWaveform);meanTxWaveform]);
% Get start signal indices
startIndices = find((diffMag>(0.5*max(diffMag(1:end)))));
if any(strcmp(rxCfg.Mode,{'EDR2M','EDR3M'}))
    accessCodeHeader = 126*rxCfg.SamplesPerSymbol;
    if numel(startIndices)>=2 && startIndices(2)<=accessCodeHeader+16*rxCfg.SamplesPerSymbol
        startIndices(2) = [];
    end
end
numOfSignals = numel(startIndices);
endIndices = zeros(size(startIndices));
% Get end indices
for iend = 1:numOfSignals
    if iend<numOfSignals
        eIndices = diffMag(startIndices(iend):startIndices(iend+1));
    else
        eIndices = diffMag(startIndices(iend):end);
    end
    [~,endIndices(iend)] = max(-eIndices); 
    packetGap = endIndices(iend)-startIndices(iend);
    if packetGap<625*rxCfg.SamplesPerSymbol
       endIndices(iend) = startIndices(iend)+625*rxCfg.SamplesPerSymbol-1;
   elseif packetGap<3*625*rxCfg.SamplesPerSymbol
       endIndices(iend) = startIndices(iend)+3*625*rxCfg.SamplesPerSymbol-1;
   else
       endIndices(iend) = startIndices(iend)+5*625*rxCfg.SamplesPerSymbol-1;
   end
   if endIndices(iend)>numel(waveform)
       numOfSignals = iend-1;
       startIndices = startIndices(1:iend-1);
       endIndices = endIndices(1:iend-1);
       break;
   end
end
end

function rxComp = bluetoothTimeFreqSync(rcv,accessCodeWaveform,sps)
%bluetoothTimeFreqSync estimates time and frequency offsets from the
%received signal, RCV, based on the known access code, ACCESSCODEWAVEFORM
%and samples per symbol, SPS
sampleRate = 1e6*sps;
L = numel(accessCodeWaveform(1:68*sps));
h = accessCodeWaveform(1:sps);
filteredACKnown = conv(accessCodeWaveform(1:L),h,'same');
persistent phaseExtractor
if isempty(phaseExtractor)
    phaseExtractor = dsp.PhaseExtractor;
end
% Timing offset estimation and compensation
filteredRCV = conv(rcv(1:(200)*sps),h,'same');
[acorTime,lagTime] = xcorr(diff(unwrap(phaseExtractor(filteredACKnown))),...
                            diff(unwrap(phaseExtractor(filteredRCV))));
[~,ITime] = max(abs(acorTime));
lagTimeDiff = lagTime(ITime);
IndexTime = lagTimeDiff;
idxTime = -IndexTime+1;
if(idxTime <=0)
    idxTime = 1;
end
timeSyncRcv = rcv(idxTime:end);

% Frequency offset estimation and compensation
filteredTimeSyncRcv =  conv(timeSyncRcv(1:L),h,'same');
a = (diff(unwrap(phaseExtractor(filteredACKnown))))./(2*pi);
b = (diff(unwrap(phaseExtractor(filteredTimeSyncRcv))))./(2*pi);
estimatedFreqOff = mean(b-a)*sampleRate;

pfOffset = comm.PhaseFrequencyOffset('SampleRate',1e6*sps,'FrequencyOffset',-estimatedFreqOff);
freqTimeSyncRcv = pfOffset(timeSyncRcv);

rxComp = freqTimeSyncRcv;
if numel(rxComp)<5*625*sps
    rxComp = [rxComp;zeros(5*625*sps-numel(rxComp),1)];
end

end