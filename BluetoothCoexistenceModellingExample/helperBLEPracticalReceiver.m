function [bits,accessAddress] = helperBLEPracticalReceiver(rxWaveform,rxCfg)
%helperBLEPracticalReceiver Demodulate and decodes the received Bluetooth
%LE waveform
%
%   [BITS,ACCESSADDRESS] = helperBLEPracticalReceiver(RXWAVEFORM,RXCFG)
%   decodes the received Bluetooth LE waveform, RXWAVEFORM.
%
%   BITS is an int8 column vector containing the recovered information
%   bits with maximum length of 2080 bits.
%
%   ACCESSADDRESS is an int8 column vector of length 32 bits containing the
%   access address information.
%
%   RXWAVEFORM is a complex valued time-domain waveform with size Ns-by-1,
%   where Ns represents the number of received samples.
%
%   RXCFG is a structure containing these fields:
%   'Mode'                  Specify the physical layer reception mode as
%                           one of 'LE1M', 'LE2M', 'LE500K', and 'LE125K'.
%
%   'ChannelIndex'          Specify the channel index as an integer in
%                           the range [0,39]. For data channels,
%                           specify this value in the range [0,36]. For
%                           advertising channels, specify this value in
%                           the range [37,39].
%
%   'SamplesPerSymbol'      Specify the samples per symbol as a positive
%                           integer.
%
%   'DFPacketType'          Specify the direction finding packet type as
%                           'ConnectionlessCTE', 'ConnectionCTE', or
%                           'Disabled'.
%
%   'CoarseFreqCompensator' Specify the coarse frequency compensator system
%                           object as comm.CoarseFrequencyCompensator.
%
%   'PreambleDetector'      Specify the preamble detector system object as
%                           comm.PreambleDetector.
%
%  'EqualizerFlag'          Specify the flag to enable or disable equalizer

%   Copyright 2018-2023 The MathWorks, Inc.

[bits,accessAddress] = ble.internal.practicalReceiver(rxWaveform,rxCfg);
end