function wfFin = mySignalMixer(varargin)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

sampleRate = 80e6;
timeDuration = 0.02; % seconds

n = nargin;
if n<1 || n>3
    error("Wrong number of parameters")
end

wfFin = zeros(1600000,1);
for i=1:nargin
    wfFin = wfFin + varargin{i};
end

wfFin = awgn(wfFin, 20);

end