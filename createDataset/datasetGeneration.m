
startPos = [0 0 0];
startFreq = 2.402e9;

numFrame = 10;

btTx = BluetoothTx(startPos, "AWGN", startFreq, 4, "RANDOM");
sbTx = SmartBanTx(startPos, "AWGN", startFreq, 4);
wlanTx = WlanTx(startPos, "AWGN", startFreq, 20);
zbTx = ZigBeeTx(startPos, "AWGN", startFreq, 6, 4);

txBatch = {wlanTx, zbTx, btTx, sbTx};




for i = 1:numFrame
    
    sigTypes = currTxSigs;
    wfTotal = [];

    for i = 1:numel(sigTypes)
        index = sigTypes(i);
        txBatch{index} = txBatch{index}.randParams(0);
        disp(txBatch{index});
        wf = txBatch{sigTypes(i)}.getWaveform();
        wfTotal = [wfTotal, wf];
    end

    wfFin = mySignalMixerInterf(wfTotal, 20e-3, 1e-8);
    spectrogram(wfFin, hann(256), 100, 4096, 80e6, 'psd'); 
    pause();


    for i = 1:numel(txBatch)
        txBatch{i}.resetFreqs;
    end

end












function sigTypes = currTxSigs()

    weights = [0.2 0.25 0.3 0.25];  
    possibleCombinations = [1 2 3 4];
       
    numSignals = randsample(possibleCombinations, 1, true, weights);
    sigTypes = zeros(numSignals, 1);
    for iter = 1:numSignals
        if numSignals ~= 1
            prob = rand(); % 1=WLAN, 2=ZigBee, 3=Bluetooth 4 = SmartBAN
            if prob < 0.20 
                type_signal = 1;
            end
            if prob < 0.45 && prob >= 0.20
                type_signal = 2;
            end
            if prob >= 0.45 && prob < 0.7
                type_signal = 3;
            end
            if prob >= 0.7
                type_signal = 4;
            end
        else
            type_signal = 4;  %only smartban
  
        end
        sigTypes(iter) = type_signal;
    end
end








