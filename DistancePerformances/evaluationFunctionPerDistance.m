function [metricsPerDistance, confMat] = evaluationFunctionPerDistance(...
            YTrue, YPred, distanceVec, classNames, scoresCell, ignoreUnknown, folderName, netName)
% Comprehensive segmentation evaluation across different distances

assert(numel(YTrue)==numel(YPred) && numel(YTrue)==numel(distanceVec), ...
    'Input arrays YTrue, YPred, and distanceVec must have identical lengths');

C = numel(classNames);
allDistances = unique(distanceVec);
allDistances = sort(allDistances(:), 'ascend');
numDist = numel(allDistances);

acc     = nan(numDist,1);
mpa     = nan(numDist,1);
miou    = nan(numDist,1);
mdice   = nan(numDist,1);
wiou    = nan(numDist,1);
prec    = nan(numDist,1);
rec     = nan(numDist,1);
pd_val  = nan(numDist,1);
pfa_val = nan(numDist,1);
auc_val = nan(numDist,1);

perClassAccMat  = nan(numDist, C);
perClassIoUMat  = nan(numDist, C);
perClassDiceMat = nan(numDist, C);

confMat = zeros(C,C);

for k = 1:numDist
    thisDist = allDistances(k);
    idx = (distanceVec == thisDist);
    
    if ~any(idx)
        continue;
    end
    
    confMatDist = zeros(C,C);
    allBinaryLabels = [];
    allScores = [];
    
    for ii = find(idx)
        gt = YTrue{ii};
        pred = YPred{ii};
        
        gt = categorical(gt, [0,16,32,64,128], classNames);
        oldValues = categorical(["C1","C2","C3","C4","C5"]);
        pred = categorical(pred, oldValues, classNames);
        
        gtVec = gt(:);
        predVec = pred(:);
        cmThis = confusionmat(gtVec, predVec);
        confMatDist = confMatDist + cmThis;
        
        if ~isempty(scoresCell)
            scoreImg = scoresCell{ii};
            fgScore = max(scoreImg(:,:,2:end), [], 3);
            binGT = (gtVec ~= classNames(1));
            allBinaryLabels = [allBinaryLabels; binGT(:)];
            allScores = [allScores; fgScore(:)];
        end
    end
    
    confMat = confMat + confMatDist;
    
    totalPixels = sum(confMatDist(:));
    acc(k) = trace(confMatDist) / totalPixels;
    
    diagVals = diag(confMatDist);
    rowSums = sum(confMatDist,2);
    colSums = sum(confMatDist,1)';
    
    if ignoreUnknown
        incIdx = 2:C;
    else
        incIdx = 1:C;
    end
    
    perClassAcc = diagVals ./ (rowSums + eps);
    mpa(k) = mean(perClassAcc(incIdx));
    
    iouVals = zeros(C,1);
    diceVals = zeros(C,1);
    
    for c = 1:C
        tp = confMatDist(c,c);
        fp = colSums(c) - tp;
        fn = rowSums(c) - tp;
        iouVals(c) = tp / (tp + fp + fn + eps);
        diceVals(c) = (2*tp) / (2*tp + fp + fn + eps);
    end
    
    miou(k) = mean(iouVals(incIdx));
    mdice(k) = mean(diceVals(incIdx));
    
    perClassAccMat(k,:) = perClassAcc;
    perClassIoUMat(k,:) = iouVals;
    perClassDiceMat(k,:) = diceVals;
    
    TP = sum(sum(confMatDist(2:end,2:end)));
    FP = sum(confMatDist(1,2:end));
    FN = sum(confMatDist(2:end,1));
    TN = confMatDist(1,1);
    
    prec(k) = TP / (TP + FP + eps);
    rec(k) = TP / (TP + FN + eps);
    pd_val(k) = rec(k);
    pfa_val(k) = FP / (FP + TN + eps);
    
    classWeights = rowSums;
    if ignoreUnknown
        classWeights(1) = 0;
    end
    if sum(classWeights)==0
        wiou(k) = NaN;
    else
        wiou(k) = sum(iouVals .* classWeights) / sum(classWeights);
    end
    
    %if ~isempty(scoresCell) && ~isempty(allBinaryLabels)
     %   [~,~,~,auc_val(k)] = perfcurve(allBinaryLabels, allScores, 1);
    %end
end

metricsPerDistance = table(allDistances, acc, mpa, miou, wiou, mdice, prec, rec, pd_val, pfa_val, auc_val, ...
    'VariableNames', {'Distance','Accuracy','MeanPixelAcc','MeanIoU','WeightedIoU','MeanDice',...
    'Precision','Recall','Pd','Pfa','AUC'});

fprintf('\nSummary metrics (ignoreUnknown = %d):\n', ignoreUnknown);
disp(metricsPerDistance);

%% Visualization
figure;
metrics = {'Accuracy','IoU','Dice'};
dataMat = {perClassAccMat, perClassIoUMat, perClassDiceMat};

for m = 1:numel(metrics)
    subplot(3,1,m); hold on; grid on;
    for c = 1:C
        if ignoreUnknown && c==1
            continue;
        end
        plot(allDistances, dataMat{m}(:,c), '-o', 'DisplayName', classNames(c));
    end
    xlabel('Distance [m]');
    ylabel(metrics{m});
    title([metrics{m} ' per class vs Distance']);
    legend('Location','bestoutside');
end

figure;
confusionchart(confMat, classNames,'RowSummary','row-normalized','ColumnSummary','column-normalized');

%% Save outputs
csvFile = fullfile(folderName, sprintf('%s_metricsPerDistance.csv', netName));
writetable(metricsPerDistance, csvFile);
matFile = fullfile(folderName, sprintf('%s_metricsPerDistance.mat', netName));
save(matFile, 'metricsPerDistance');
txtFile = fullfile(folderName, sprintf('%s_metricsPerDistance.txt', netName));
fid = fopen(txtFile, 'w');
fprintf(fid, 'Summary metrics (ignoreUnknown = %d):\n', ignoreUnknown);
fprintf(fid, '%s\n', evalc('disp(metricsPerDistance)'));
fclose(fid);

csvConf = fullfile(folderName, sprintf('%s_confusionMatrix.csv', netName));
writematrix(confMat, csvConf);
matConf = fullfile(folderName, sprintf('%s_confusionMatrix.mat', netName));
save(matConf, 'confMat');

figHandles = findall(0, 'Type', 'figure');
for kFig = 1:numel(figHandles)
    fName = get(figHandles(kFig), 'Name');
    if isempty(fName)
        fName = sprintf('Figure_%02d', kFig);
    end
    fName = regexprep(fName, '[^\w\d_\- ]', '');
    pngPath = fullfile(folderName, [fName '.png']);
    figPath = fullfile(folderName, [fName '.fig']);
    saveas(figHandles(kFig), pngPath);
    savefig(figHandles(kFig), figPath);
end

fprintf('Results and visualizations saved to:\n%s\n', folderName);

end
