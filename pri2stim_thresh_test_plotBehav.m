% pri2stim_thresh_test_plotBehav.m
%
% Analyze and plot behavioral performance for pri2stim thresholding
% and testing datasets, using concatenated *_behav.mat files produced by
% pri2stim_concatBehav.m.
%
% Supports:
%   whichDataset = 'testing'
%   whichDataset = 'threshold'
%   whichDataset = 'threshold_practice'
%
% For 'testing':
%   - Per subject: overall accuracy, accuracy by attention condition
%                  (with within-subject binomial error bars)
%   - Group: mean +/- SEM across subjects for attention conditions,
%            with significance markers (paired t-tests).
%   - SDT analysis: d-prime and criterion for 2AFC discrimination
%                   (discriminating CW vs CCW orientation at cued location)
%
% For 'threshold' / 'threshold_practice':
%   - Per subject: overall accuracy, psychometric curve
%                  (coherence vs accuracy, with binomial error bars),
%                  estimated threshold via "median tail".
%   - Group: distribution of estimated thresholds.
%
% AHH 2025, updated to:
%   - add subject-level error bars
%   - add group-level significance markers
%   - focus on attention-condition performance for testing dataset

clear;

%% ------------------------------------------------------------------------
%  USER SETTINGS
% -------------------------------------------------------------------------

% Base project directory
baseDir      = 'Z:\projects\pri2stim_thresh_test';

% Choose which dataset to analyze:
%   'testing'              -> pri2stimEEG_testing
%   'threshold'            -> pri2stimEEG_threshold
%   'threshold_practice'   -> pri2stimEEG_threshold_practice
whichDataset = 'testing';

% Optional: restrict to a subset of subjects
%   Leave empty {} to auto-detect from *_behav.mat files.
% subjList     = {};   % e.g., {'sub001','sub002'} or {}
% subjList     = {'sub001','sub003','sub005','sub006','sub007','sub008','sub009'};   % sub003, 005: no good Palamedes fit
subjList     = {'sub001','sub006','sub007','sub008','sub009'};   % sub003, 005: no good Palamedes fit

% Save summary .mat file?
saveSummary  = 0;

% Save figures?
saveFigs     = 0;
figDir       = fullfile(baseDir, 'figures');

if saveFigs && ~isfolder(figDir)
    mkdir(figDir);
end

%% ------------------------------------------------------------------------
%  PATHS AND DATASET-SPECIFIC SETTINGS
% -------------------------------------------------------------------------

switch lower(whichDataset)
    case 'testing'
        dataSubdir   = 'testing';
        exptNameOut  = 'pri2stimEEG_testing';
    case 'threshold'
        dataSubdir   = 'thresholding';
        exptNameOut  = 'pri2stimEEG_threshold';
    case 'threshold_practice'
        dataSubdir   = 'thresholding';
        exptNameOut  = 'pri2stimEEG_threshold_practice';
    otherwise
        error('whichDataset must be ''testing'', ''threshold'', or ''threshold_practice''.');
end

root_data = fullfile(baseDir, dataSubdir);
if ~isfolder(root_data)
    error('Data directory not found: %s', root_data);
end

behavFiles = dir(fullfile(root_data, sprintf('*_%s_behav.mat', exptNameOut)));
if isempty(behavFiles)
    error('No *_behav.mat files found in %s for exptNameOut=%s', root_data, exptNameOut);
end

% auto-detect subject IDs if needed
if isempty(subjList)
    subjNames = cell(numel(behavFiles),1);
    for i = 1:numel(behavFiles)
        S = load(fullfile(root_data, behavFiles(i).name), 'subject_id');
        if isfield(S, 'subject_id')
            subjNames{i} = S.subject_id;
        else
            % Fallback: parse prefix before exptNameOut
            nm = behavFiles(i).name;
            token = erase(nm, ['_' exptNameOut '_behav.mat']);
            subjNames{i} = token;
        end
    end
    subjList = unique(subjNames);
end

nSubj = numel(subjList);
fprintf('Found %d subject(s) for dataset %s:\n', nSubj, whichDataset);
for i = 1:nSubj
    fprintf('  %2d: %s\n', i, subjList{i});
end

if nSubj == 0
    error('No subjects to analyze.');
end

% Simple SEM function (across subjects)
sem = @(x) nanstd(x) ./ sqrt(sum(~isnan(x)));

% Binomial SE (within subject, per condition), returns SE in proportion units
binom_se = @(p,n) sqrt(p .* (1-p) ./ max(n,1));  % guard n=0


%% ------------------------------------------------------------------------
%  PER-SUBJECT ANALYSIS
% -------------------------------------------------------------------------

results = struct();
results.whichDataset = whichDataset;
results.baseDir      = baseDir;
results.dataSubdir   = dataSubdir;
results.exptNameOut  = exptNameOut;
results.subjects     = subjList;

subjRes = struct([]);

for s = 1:nSubj
    thisSub = subjList{s};
    
    % Find this subject's behav file
    pattern = sprintf('%s_%s_behav.mat', thisSub, exptNameOut);
    thisFile = fullfile(root_data, pattern);
    if ~exist(thisFile, 'file')
        warning('No behav file found for %s (%s). Skipping.', thisSub, pattern);
        continue;
    end
    
    fprintf('\n--- Subject %s ---\n', thisSub);
    D = load(thisFile);
    
    % Required fields from concatenation
    cohLevel_all   = D.cohLevel_all(:);
    correct_all    = D.correct_all(:);
    resp_all       = D.resp_all(:);
    RT_all         = D.RT_all(:);
    attnCond_all   = D.attnCond_all(:);
    contrast_all   = D.contrast_all(:); %#ok<NASGU> % currently unused
    
    nTrials        = numel(correct_all);
    overallAcc     = 100 * nanmean(correct_all == 1);
    
    fprintf('  Total trials: %d\n', nTrials);
    fprintf('  Overall accuracy: %.2f %%\n', overallAcc);
    
    subjRes(s).subject_id   = thisSub;
    subjRes(s).nTrials      = nTrials;
    subjRes(s).overallAcc   = overallAcc;
    
    % Basic RT stats (only for correct trials)
    subjRes(s).meanRT       = nanmean(RT_all(correct_all == 1));
    subjRes(s).medianRT     = nanmedian(RT_all(correct_all == 1));
    
    %% -------------------------------------------------------------
    %  Dataset-specific analyses
    % --------------------------------------------------------------
    
    switch lower(whichDataset)
        
        %% =========================================================
        %  TESTING DATASET  (focus on attention condition)
        % =========================================================
        case 'testing'
            % attnCond coding:
            %   1 = neutral/distributed
            %   2 = focal valid
            %   3 = focal invalid
            
            validIdx = ~isnan(correct_all);
            
            % Accuracy by attention condition (with within-subject binomial SE)
            uAttn = unique(attnCond_all(validIdx));
            uAttn = uAttn(~isnan(uAttn));
            uAttn = sort(uAttn(:));
            
            accByAttn    = nan(size(uAttn));
            nByAttn      = nan(size(uAttn));
            seByAttn_pct = nan(size(uAttn));  % SE in percent units
            
            for k = 1:numel(uAttn)
                idx = attnCond_all == uAttn(k) & validIdx;
                nThis = sum(idx);
                nByAttn(k) = nThis;
                if nThis > 0
                    pThis = nanmean(correct_all(idx) == 1);
                    accByAttn(k)    = 100 * pThis;
                    seByAttn_pct(k) = 100 * binom_se(pThis, nThis);
                end
            end
            
            subjRes(s).attnLevels      = uAttn;
            subjRes(s).accByAttn       = accByAttn;
            subjRes(s).nByAttn         = nByAttn;
            subjRes(s).seByAttn_pct    = seByAttn_pct;
            
            % --- SDT ANALYSIS (d-prime and criterion by attention) ---
            % 2-alternative forced choice (2AFC) discrimination task:
            %   Category A = CW orientation at cued location (stimDir = +1)
            %   Category B = CCW orientation at cued location (stimDir = -1)
            %   Response A = "CW" (key 1)
            %   Response B = "CCW" (key 2)
            % 
            % Computed probabilities:
            %   P(resp=CW | stim=CW)  = proportion correct for CW stimuli
            %   P(resp=CW | stim=CCW) = proportion incorrect CW responses for CCW stimuli
            %
            % These map to traditional SDT terminology as:
            %   "hit rate" and "false alarm rate" respectively
            
            % Get the true stimulus direction for each trial
            trueDir_all = nan(size(resp_all));
            for tt = 1:numel(resp_all)
                if ~isnan(D.postCueSide_all(tt))
                    if D.postCueSide_all(tt) == 1
                        trueDir_all(tt) = D.stimDir1_all(tt);
                    else
                        trueDir_all(tt) = D.stimDir2_all(tt);
                    end
                end
            end
            
            dPrimeByAttn = nan(size(uAttn));
            criterionByAttn = nan(size(uAttn));
            
            for k = 1:numel(uAttn)
                idx = attnCond_all == uAttn(k) & validIdx & ~isnan(trueDir_all);
                
                if sum(idx) > 0
                    % CW stimulus trials (Category A)
                    cwTrials = idx & (trueDir_all == 1);
                    nCW = sum(cwTrials);
                    nCorrectCW = sum(cwTrials & resp_all == 1);  % correct CW identification
                    
                    % CCW stimulus trials (Category B)
                    ccwTrials = idx & (trueDir_all == -1);
                    nCCW = sum(ccwTrials);
                    nIncorrectCW = sum(ccwTrials & resp_all == 1);  % incorrect CW response when stim was CCW
                    
                    if nCW > 0 && nCCW > 0
                        % Compute response probabilities (with correction for extreme values)
                        pRespCW_givenCW = nCorrectCW / nCW;      % P(resp=CW | stim=CW)
                        pRespCW_givenCCW = nIncorrectCW / nCCW;  % P(resp=CW | stim=CCW)
                        
                        % Correction for extreme values (Macmillan & Creelman, 2005)
                        pRespCW_givenCW = max(0.5/nCW, min(1 - 0.5/nCW, pRespCW_givenCW));
                        pRespCW_givenCCW = max(0.5/nCCW, min(1 - 0.5/nCCW, pRespCW_givenCCW));
                        
                        % Compute d' and criterion using standard SDT formulas
                        dPrimeByAttn(k)    = norminv(pRespCW_givenCW) - norminv(pRespCW_givenCCW);
                        criterionByAttn(k) = -0.5 * (norminv(pRespCW_givenCW) + norminv(pRespCW_givenCCW));
                    end
                end
            end
            
            subjRes(s).dPrimeByAttn    = dPrimeByAttn;
            subjRes(s).criterionByAttn = criterionByAttn;
            
            fprintf('  SDT by attention:\n');
            for k = 1:numel(uAttn)
                condNames = {'dist', 'valid', 'invalid'};
                if ~isnan(dPrimeByAttn(k))
                    fprintf('    %s: d'' = %.2f, c = %.2f\n', ...
                        condNames{uAttn(k)}, dPrimeByAttn(k), criterionByAttn(k));
                end
            end
            
            % --- RT ANALYSIS (by attention condition) ---
            meanRTByAttn = nan(size(uAttn));
            medianRTByAttn = nan(size(uAttn));
            meanRTCorrectByAttn = nan(size(uAttn));
            meanRTErrorByAttn = nan(size(uAttn));
            
            for k = 1:numel(uAttn)
                idx = attnCond_all == uAttn(k) & validIdx;
                
                if sum(idx) > 0
                    % Overall RT for this condition
                    meanRTByAttn(k) = nanmean(RT_all(idx));
                    medianRTByAttn(k) = nanmedian(RT_all(idx));
                    
                    % RT split by correct/error
                    idxCorr = idx & correct_all == 1;
                    idxErr  = idx & correct_all == 0;
                    
                    if sum(idxCorr) > 0
                        meanRTCorrectByAttn(k) = nanmean(RT_all(idxCorr));
                    end
                    if sum(idxErr) > 0
                        meanRTErrorByAttn(k) = nanmean(RT_all(idxErr));
                    end
                end
            end
            
            subjRes(s).meanRTByAttn = meanRTByAttn;
            subjRes(s).medianRTByAttn = medianRTByAttn;
            subjRes(s).meanRTCorrectByAttn = meanRTCorrectByAttn;
            subjRes(s).meanRTErrorByAttn = meanRTErrorByAttn;
            
            fprintf('  RT by attention (mean ± median):\n');
            for k = 1:numel(uAttn)
                condNames = {'dist', 'valid', 'invalid'};
                if ~isnan(meanRTByAttn(k))
                    fprintf('    %s: M = %.3f s, Mdn = %.3f s\n', ...
                        condNames{uAttn(k)}, meanRTByAttn(k), medianRTByAttn(k));
                end
            end
            
            % --- subject-level plotting: attention only ---
            figure('Name', sprintf('%s testing', thisSub), ...
                   'Color', 'w');
            
            bar(uAttn, accByAttn); hold on;
            errorbar(uAttn, accByAttn, seByAttn_pct, ...
                     'k', 'LineStyle','none', 'LineWidth',1.2);
            xlabel('Attention condition');
            ylabel('Accuracy (%)');
            title(sprintf('%s: accuracy by attention', thisSub), 'Interpreter','none');
            set(gca,'XTick',uAttn, ...
                    'XTickLabel',{'dist','valid','invalid'});
            ylim([0 100]);
            
            if saveFigs
                fn = fullfile(figDir, sprintf('%s_%s_testing_attnOnly.png', thisSub, exptNameOut));
                saveas(gcf, fn);
            end
            
        %% =========================================================
        %  THRESHOLD / THRESHOLD_PRACTICE
        % =========================================================
        otherwise   % 'threshold' or 'threshold_practice'
            
            % Valid trials only
            validIdx = ~isnan(correct_all) & ~isnan(cohLevel_all);
            cohUse   = cohLevel_all(validIdx);
            corrUse  = correct_all(validIdx);
            nValidTrials = sum(validIdx);
            
            % Round coherence to 4 decimal places before binning.
            % This merges bins that represent the same staircase level but
            % differ in floating-point representation across runs (e.g., two
            % entries for 0.1585 from different blocks hitting the same level).
            cohUse = round(cohUse, 4);
            
            % Bin by unique (rounded) coherence level, computing counts directly
            uCoh = unique(cohUse);
            uCoh = uCoh(~isnan(uCoh));
            uCoh = sort(uCoh(:));
            nBins = numel(uCoh);
            
            nPerCoh     = nan(nBins, 1);
            nCorrPerCoh = nan(nBins, 1);
            pCorrPerCoh = nan(nBins, 1);   % proportion correct (0-1)
            accByCoh    = nan(nBins, 1);   % accuracy in %
            seByCoh_pct = nan(nBins, 1);   % binomial SE in %
            
            for k = 1:nBins
                idx = cohUse == uCoh(k);
                nThis     = sum(idx);
                nCorrThis = sum(corrUse(idx) == 1);
                nPerCoh(k)     = nThis;
                nCorrPerCoh(k) = nCorrThis;
                if nThis > 0
                    pThis           = nCorrThis / nThis;
                    pCorrPerCoh(k)  = pThis;
                    accByCoh(k)     = 100 * pThis;
                    seByCoh_pct(k)  = 100 * binom_se(pThis, nThis);
                end
            end
            
            subjRes(s).cohLevels    = uCoh;
            subjRes(s).nPerCoh      = nPerCoh;
            subjRes(s).nCorrPerCoh  = nCorrPerCoh;
            subjRes(s).pCorrPerCoh  = pCorrPerCoh;
            subjRes(s).accByCoh     = accByCoh;
            subjRes(s).seByCoh_pct  = seByCoh_pct;
            
            % Print per-bin summary
            fprintf('  Psychometric bins (%d total valid trials, %d unique coh levels):\n', ...
                nValidTrials, nBins);
            fprintf('    %8s  %6s  %8s  %6s\n', 'coh', 'n', 'nCorr', 'acc%');
            for k = 1:nBins
                fprintf('    %8.4f  %6d  %8d  %5.1f%%\n', ...
                    uCoh(k), nPerCoh(k), nCorrPerCoh(k), accByCoh(k));
            end
            
            % --- PALAMEDES WEIBULL FIT ---
            % Mirrors the approach in pri2stim_computeThreshold.m exactly:
            %   PF = Weibull, free params = [alpha beta], fixed gamma=0.5, lambda=0.02
            %   Threshold = coherence at 82% correct (3-down/1-up target)
            %
            % gamma = 0.5: 2AFC guessing rate (chance = 50%)
            % lambda = 0.02: small fixed lapse rate
            % alpha: threshold (location parameter)
            % beta:  slope parameter
            
            hasPFML    = (exist('PAL_PFML_Fit', 'file') == 2);
            hasWeibull = (exist('PAL_Weibull',  'file') == 2);
            hasInvPF   = (exist('PAL_PF_invPF', 'file') == 2);
            usePalamedes = hasPFML && hasWeibull;
            
            cohThresh_pal    = NaN;
            cohThresh_median = NaN;
            cohThresh_est    = NaN;
            paramsValues     = NaN(1,4);
            palSuccess       = false;
            threshMethod     = 'median';
            
            if ~usePalamedes
                warning('%s: Palamedes not found on path. Using median-tail fallback.', thisSub);
            elseif nBins < 3
                warning('%s: Only %d coherence bins — need >= 3 for Weibull fit.', thisSub, nBins);
            else
                try
                    PF = @PAL_Weibull;
                    
                    searchGrid.alpha  = linspace(min(uCoh), max(uCoh), 101);
                    searchGrid.beta   = logspace(log10(0.5), log10(10), 51);
                    searchGrid.gamma  = 0.5;    % 2AFC guessing rate
                    searchGrid.lambda = 0.02;   % fixed lapse rate
                    paramsFree = [1 1 0 0];     % free: alpha, beta; fixed: gamma, lambda
                    
                    [paramsValues, ~, exitflag] = PAL_PFML_Fit( ...
                        uCoh(:)', nCorrPerCoh(:)', nPerCoh(:)', ...
                        searchGrid, paramsFree, PF);
                    
                    if exitflag > 0
                        targetPerf = 0.82;  % 3-down/1-up convergence point
                        
                        if hasInvPF
                            cohThresh_pal = PAL_PF_invPF(paramsValues, targetPerf, PF);
                        else
                            % Numeric inversion fallback
                            invFun = @(x) PF(paramsValues, x) - targetPerf;
                            cohThresh_pal = fzero(invFun, paramsValues(1));
                        end
                        
                        palSuccess  = true;
                        threshMethod = 'palamedes';
                        fprintf('  Weibull fit converged: alpha=%.4f, beta=%.2f\n', ...
                            paramsValues(1), paramsValues(2));
                    else
                        warning('%s: Palamedes fit did not converge (exitflag=%d). Using median-tail.', ...
                            thisSub, exitflag);
                    end
                catch ME
                    warning('%s: Palamedes fit threw an error: %s. Using median-tail.', ...
                        thisSub, ME.message);
                end
            end
            
            % Always compute median-tail as fallback / comparison
            if nValidTrials > 0
                logCohAll     = log(cohUse);
                nTail         = min(30, nValidTrials);
                logCohTail    = logCohAll(end-nTail+1:end);
                cohThresh_median = exp(median(logCohTail));
            end
            
            % Use Palamedes threshold if successful, otherwise median-tail
            cohThresh_est = cohThresh_pal;
            if ~palSuccess
                cohThresh_est = cohThresh_median;
            end
            
            subjRes(s).cohThresh_est    = cohThresh_est;
            subjRes(s).cohThresh_pal    = cohThresh_pal;
            subjRes(s).cohThresh_median = cohThresh_median;
            subjRes(s).palSuccess       = palSuccess;
            subjRes(s).threshMethod     = threshMethod;
            subjRes(s).paramsValues     = paramsValues;
            
            fprintf('  Median-tail threshold:  %.4f\n', cohThresh_median);
            if palSuccess
                fprintf('  Palamedes threshold:    %.4f  [USED]\n', cohThresh_pal);
            else
                fprintf('  Palamedes threshold:    (fit failed) -- using median-tail\n');
            end
            
            % --- SUBJECT-LEVEL PSYCHOMETRIC PLOT ---
            % Two-panel figure matching computeThreshold.m layout:
            %   Left:  raw data + Weibull fit
            %   Right: staircase-style coherence sequence (from binned data, since
            %          we only have _behav.mat here, not _stair.mat)
            
            col_blue   = [0.13 0.45 0.80];
            col_red    = [0.80 0.15 0.15];
            col_gray   = [0.55 0.55 0.55];
            
            figure('Name', sprintf('%s thresholding', thisSub), ...
                   'Color', 'w', 'Position', [100 100 900 420]);
            
            % ---- Left panel: psychometric function ----
            subplot(1,2,1); hold on;
            
            % Wilson score confidence intervals (better than normal approx at extremes)
            % Agresti & Coull 1998
            z_ci  = 1.96;
            n_    = nPerCoh;
            p_    = pCorrPerCoh;
            pCI_lo = (p_ + z_ci^2./(2*n_) - z_ci.*sqrt(p_.*(1-p_)./n_ + z_ci^2./(4*n_.^2))) ...
                     ./ (1 + z_ci^2./n_);
            pCI_hi = (p_ + z_ci^2./(2*n_) + z_ci.*sqrt(p_.*(1-p_)./n_ + z_ci^2./(4*n_.^2))) ...
                     ./ (1 + z_ci^2./n_);
            
            % Data points with Wilson CI error bars
            errorbar(uCoh, accByCoh, ...
                     (pCorrPerCoh - pCI_lo)*100, (pCI_hi - pCorrPerCoh)*100, ...
                     'o', 'Color', col_blue, 'MarkerFaceColor', col_blue, ...
                     'MarkerSize', 6, 'LineWidth', 1.2, 'CapSize', 5);
            
            % Weibull fit curve (extended slightly beyond data range for full sigmoid)
            if palSuccess
                PF = @PAL_Weibull;
                cohFine = linspace(max(min(uCoh)*0.5, 0.01), min(max(uCoh)*1.3, 1.0), 300);
                pFine = PF(paramsValues, cohFine);
                plot(cohFine, pFine*100, '-', 'Color', col_red, 'LineWidth', 2);
            end
            
            % Reference lines
            yline(50,  ':', 'Color', col_gray, 'LineWidth', 1, ...
                  'Label', 'chance', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
            yline(75,  ':', 'Color', col_gray, 'LineWidth', 0.8, ...
                  'Label', '75%', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
            yline(82, '--', 'Color', col_gray, 'LineWidth', 1.0, ...
                  'Label', '82% (target)', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
            
            % Threshold vertical line
            if ~isnan(cohThresh_est)
                xline(cohThresh_est, '--', 'Color', col_red, 'LineWidth', 1.5, ...
                      'Label', sprintf('thresh=%.3f', cohThresh_est), ...
                      'LabelVerticalAlignment', 'bottom', 'FontSize', 8);
            end
            
            % Trial counts under each data point
            yl = ylim;
            for k = 1:nBins
                text(uCoh(k), max(yl(1)+2, 42), sprintf('n=%d', nPerCoh(k)), ...
                     'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', col_gray);
            end
            
            xlabel('Coherence');
            ylabel('Accuracy (%)');
            ylim([40 105]);
            
            if palSuccess
                title(sprintf('%s  |  Weibull fit  |  \\alpha=%.3f, \\beta=%.2f', ...
                    thisSub, paramsValues(1), paramsValues(2)), ...
                    'Interpreter','tex', 'FontSize', 9);
                legend({'Data (Wilson CI)', 'Weibull fit'}, 'Location', 'southeast', 'FontSize', 8);
            else
                title(sprintf('%s  |  No fit (median-tail only)', thisSub), ...
                    'Interpreter','none', 'FontSize', 9);
            end
            grid on; box off;
            
            % ---- Right panel: trial-by-trial coherence sequence ----
            % (from _behav.mat, shows the staircase trace in the data we have)
            subplot(1,2,2); hold on;
            
            allCoh  = cohLevel_all;   % all trials including NaN
            allCorr = correct_all;
            nAll    = numel(allCoh);
            
            plot(1:nAll, allCoh, 'k-', 'LineWidth', 0.8);
            
            idxCorr = ~isnan(allCoh) & allCorr == 1;
            idxErr  = ~isnan(allCoh) & allCorr == 0;
            idxMiss = ~isnan(allCoh) & isnan(allCorr);
            
            plot(find(idxCorr), allCoh(idxCorr), '.', ...
                 'Color', [0.18 0.63 0.18], 'MarkerSize', 10);   % green = correct
            plot(find(idxErr),  allCoh(idxErr),  '.', ...
                 'Color', col_red,              'MarkerSize', 10); % red = error
            if any(idxMiss)
                plot(find(idxMiss), allCoh(idxMiss), '.', ...
                     'Color', col_gray, 'MarkerSize', 8);          % gray = miss
            end
            
            % Threshold line
            if ~isnan(cohThresh_est)
                yline(cohThresh_est, '--', 'Color', col_red, 'LineWidth', 1.5, ...
                      'Label', sprintf('%.3f', cohThresh_est), ...
                      'LabelVerticalAlignment', 'bottom', 'FontSize', 8);
            end
            
            xlabel('Trial #');
            ylabel('Coherence');
            title(sprintf('acc=%.0f%%  |  thresh=%s', ...
                nanmean(correct_all == 1)*100, threshMethod), 'FontSize', 9);
            ylim([0 1.05]);
            
            lgEntries = {'Trace', 'Correct', 'Error'};
            if any(idxMiss), lgEntries{end+1} = 'Miss'; end
            legend(lgEntries, 'Location', 'northeast', 'FontSize', 7);
            grid on; box off;
            
            sgtitle(sprintf('%s  |  %s', thisSub, whichDataset), ...
                    'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
            
            if saveFigs
                fn = fullfile(figDir, sprintf('%s_%s_%s.png', ...
                     thisSub, exptNameOut, whichDataset));
                saveas(gcf, fn);
            end
    end
end

% Remove any empty entries if some subjects were skipped
emptySubj = arrayfun(@(x) ~isfield(x,'subject_id') || isempty(x.subject_id), subjRes);
subjRes(emptySubj) = [];
results.subj = subjRes;
nSubjEff = numel(subjRes);

if nSubjEff == 0
    error('No valid subjects analyzed (all skipped).');
end

%% ------------------------------------------------------------------------
%  GROUP-LEVEL SUMMARY
% -------------------------------------------------------------------------

fprintf('\n============================================================\n');
fprintf('GROUP-LEVEL SUMMARY (%s, N=%d)\n', whichDataset, nSubjEff);
fprintf('============================================================\n');

allAcc = [subjRes.overallAcc];
fprintf('  Mean overall accuracy: %.2f %%  (SEM = %.2f)\n', ...
    mean(allAcc), sem(allAcc));

results.group.overallAcc_mean = mean(allAcc);
results.group.overallAcc_sem  = sem(allAcc);
results.group.overallAcc_all  = allAcc;

switch lower(whichDataset)
    
    %% =============================================================
    %  GROUP-LEVEL: TESTING (attention only)
    % =============================================================
    case 'testing'
        % Align attention levels across subjects.
        % We'll assume:
        %   attnCond: 1=dist, 2=valid, 3=invalid
        
        % --- Attention conditions ---
        allAttnLevels = unique(cat(1, subjRes.attnLevels));
        allAttnLevels = allAttnLevels(~isnan(allAttnLevels));
        allAttnLevels = sort(allAttnLevels(:));
        
        % For each attn level, collect subject accuracies
        groupAccAttn = nan(nSubjEff, numel(allAttnLevels));
        for s = 1:nSubjEff
            for k = 1:numel(allAttnLevels)
                lvl = allAttnLevels(k);
                idx = subjRes(s).attnLevels == lvl;
                if any(idx)
                    groupAccAttn(s,k) = subjRes(s).accByAttn(idx);
                end
            end
        end
        
        groupAccAttn_mean = nanmean(groupAccAttn,1);
        groupAccAttn_sem  = sem(groupAccAttn);
        
        results.group.attnLevels       = allAttnLevels;
        results.group.accAttn_mean     = groupAccAttn_mean;
        results.group.accAttn_sem      = groupAccAttn_sem;
        results.group.accAttn_all      = groupAccAttn;
        
        % --- SDT: collect d' and criterion across subjects ---
        groupDPrimeAttn = nan(nSubjEff, numel(allAttnLevels));
        groupCriterionAttn = nan(nSubjEff, numel(allAttnLevels));
        for s = 1:nSubjEff
            for k = 1:numel(allAttnLevels)
                lvl = allAttnLevels(k);
                idx = subjRes(s).attnLevels == lvl;
                if any(idx)
                    groupDPrimeAttn(s,k) = subjRes(s).dPrimeByAttn(idx);
                    groupCriterionAttn(s,k) = subjRes(s).criterionByAttn(idx);
                end
            end
        end
        
        groupDPrimeAttn_mean = nanmean(groupDPrimeAttn,1);
        groupDPrimeAttn_sem  = sem(groupDPrimeAttn);
        groupCriterionAttn_mean = nanmean(groupCriterionAttn,1);
        groupCriterionAttn_sem  = sem(groupCriterionAttn);
        
        results.group.dPrimeAttn_mean = groupDPrimeAttn_mean;
        results.group.dPrimeAttn_sem  = groupDPrimeAttn_sem;
        results.group.dPrimeAttn_all  = groupDPrimeAttn;
        results.group.criterionAttn_mean = groupCriterionAttn_mean;
        results.group.criterionAttn_sem  = groupCriterionAttn_sem;
        results.group.criterionAttn_all  = groupCriterionAttn;
        
        % --- RT: collect across subjects ---
        groupMeanRTAttn = nan(nSubjEff, numel(allAttnLevels));
        groupMeanRTCorrectAttn = nan(nSubjEff, numel(allAttnLevels));
        groupMeanRTErrorAttn = nan(nSubjEff, numel(allAttnLevels));
        
        for s = 1:nSubjEff
            for k = 1:numel(allAttnLevels)
                lvl = allAttnLevels(k);
                idx = subjRes(s).attnLevels == lvl;
                if any(idx)
                    groupMeanRTAttn(s,k) = subjRes(s).meanRTByAttn(idx);
                    groupMeanRTCorrectAttn(s,k) = subjRes(s).meanRTCorrectByAttn(idx);
                    groupMeanRTErrorAttn(s,k) = subjRes(s).meanRTErrorByAttn(idx);
                end
            end
        end
        
        groupMeanRTAttn_mean = nanmean(groupMeanRTAttn,1);
        groupMeanRTAttn_sem  = sem(groupMeanRTAttn);
        
        results.group.meanRTAttn_mean = groupMeanRTAttn_mean;
        results.group.meanRTAttn_sem  = groupMeanRTAttn_sem;
        results.group.meanRTAttn_all  = groupMeanRTAttn;
        results.group.meanRTCorrectAttn_all = groupMeanRTCorrectAttn;
        results.group.meanRTErrorAttn_all = groupMeanRTErrorAttn;
        
        %% --- SIGNIFICANCE TESTS & MARKERS (ATTENTION ONLY) ---
        % Paired t-tests across subjects; store p-values in matrix
        nAttn = numel(allAttnLevels);
        pAttn = nan(nAttn, nAttn);
        for i = 1:nAttn-1
            for j = i+1:nAttn
                a = groupAccAttn(:, i);
                b = groupAccAttn(:, j);
                valid = ~isnan(a) & ~isnan(b);
                if sum(valid) > 1
                    [~, pval] = ttest(a(valid), b(valid));
                    pAttn(i,j) = pval;
                    pAttn(j,i) = pval;
                end
            end
        end
        results.group.attn_pvals = pAttn;
        
        % --- Print detailed statistics ---
        fprintf('\n--- ATTENTION CONDITION STATISTICS ---\n');
        condNames = {'dist', 'valid', 'invalid'};
        for i = 1:nAttn
            fprintf('  %s: M = %.2f%%, SEM = %.2f%%\n', ...
                condNames{i}, groupAccAttn_mean(i), groupAccAttn_sem(i));
        end
        fprintf('\nPairwise comparisons (paired t-tests):\n');
        for i = 1:nAttn-1
            for j = i+1:nAttn
                pval = pAttn(i,j);
                if ~isnan(pval)
                    % Compute effect size (Cohen's d for paired samples)
                    a = groupAccAttn(:, i);
                    b = groupAccAttn(:, j);
                    valid = ~isnan(a) & ~isnan(b);
                    diff = a(valid) - b(valid);
                    cohensD = mean(diff) / std(diff);
                    
                    sigStr = '';
                    if pval < 0.001
                        sigStr = ' ***';
                    elseif pval < 0.01
                        sigStr = ' **';
                    elseif pval < 0.05
                        sigStr = ' *';
                    elseif pval < 0.10
                        sigStr = ' (trend)';
                    end
                    
                    fprintf('  %s vs %s: Δ = %.2f%%, p = %.4f, d = %.2f%s\n', ...
                        condNames{i}, condNames{j}, ...
                        groupAccAttn_mean(i) - groupAccAttn_mean(j), ...
                        pval, cohensD, sigStr);
                end
            end
        end
        fprintf('\n');
        
        % --- SDT STATISTICS ---
        fprintf('--- SDT (2AFC Discrimination) STATISTICS ---\n');
        condNames = {'dist', 'valid', 'invalid'};
        for i = 1:nAttn
            fprintf('  %s: d'' = %.2f (SEM = %.2f), c = %.2f (SEM = %.2f)\n', ...
                condNames{i}, groupDPrimeAttn_mean(i), groupDPrimeAttn_sem(i), ...
                groupCriterionAttn_mean(i), groupCriterionAttn_sem(i));
        end
        
        % Criterion bias check
        fprintf('\nResponse bias check (criterion c):\n');
        fprintf('  c < 0: bias toward ''CW'' response (Response A)\n');
        fprintf('  c > 0: bias toward ''CCW'' response (Response B)\n');
        fprintf('  c = 0: no response bias\n\n');
        for i = 1:nAttn
            cVal = groupCriterionAttn_mean(i);
            if abs(cVal) < 0.1
                biasStr = 'No bias (neutral)';
            elseif cVal > 0.1
                biasStr = sprintf('Slight bias toward CCW (c = %.2f)', cVal);
            else
                biasStr = sprintf('Slight bias toward CW (c = %.2f)', cVal);
            end
            fprintf('  %s: %s\n', condNames{i}, biasStr);
        end
        
        % Test if any criterion differs from zero
        fprintf('\nTesting if criterion differs from zero (one-sample t-tests):\n');
        for i = 1:nAttn
            cVals = groupCriterionAttn(:, i);
            validC = ~isnan(cVals);
            if sum(validC) > 1
                [~, pval] = ttest(cVals(validC), 0);
                fprintf('  %s: c = %.2f, p vs 0 = %.4f', ...
                    condNames{i}, groupCriterionAttn_mean(i), pval);
                if pval < 0.05
                    fprintf(' * (significant bias)\n');
                else
                    fprintf(' (no significant bias)\n');
                end
            end
        end
        fprintf('\n');
        
        % Paired t-tests for d'
        fprintf('\nPairwise comparisons for d'' (paired t-tests):\n');
        pDPrime = nan(nAttn, nAttn);
        for i = 1:nAttn-1
            for j = i+1:nAttn
                a = groupDPrimeAttn(:, i);
                b = groupDPrimeAttn(:, j);
                valid = ~isnan(a) & ~isnan(b);
                if sum(valid) > 1
                    [~, pval] = ttest(a(valid), b(valid));
                    pDPrime(i,j) = pval;
                    pDPrime(j,i) = pval;
                    
                    % Cohen's d
                    diff = a(valid) - b(valid);
                    cohensD = mean(diff) / std(diff);
                    
                    sigStr = '';
                    if pval < 0.001
                        sigStr = ' ***';
                    elseif pval < 0.01
                        sigStr = ' **';
                    elseif pval < 0.05
                        sigStr = ' *';
                    elseif pval < 0.10
                        sigStr = ' (trend)';
                    end
                    
                    fprintf('  %s vs %s: Δd'' = %.2f, p = %.4f, d = %.2f%s\n', ...
                        condNames{i}, condNames{j}, ...
                        groupDPrimeAttn_mean(i) - groupDPrimeAttn_mean(j), ...
                        pval, cohensD, sigStr);
                end
            end
        end
        results.group.dPrime_pvals = pDPrime;
        fprintf('\n');
        
        % --- RT STATISTICS ---
        fprintf('--- RT STATISTICS ---\n');
        condNames = {'dist', 'valid', 'invalid'};
        for i = 1:nAttn
            fprintf('  %s: M = %.3f s (SEM = %.3f s)\n', ...
                condNames{i}, groupMeanRTAttn_mean(i), groupMeanRTAttn_sem(i));
        end
        
        % Paired t-tests for RT
        fprintf('\nPairwise comparisons for RT (paired t-tests):\n');
        pRT = nan(nAttn, nAttn);
        for i = 1:nAttn-1
            for j = i+1:nAttn
                a = groupMeanRTAttn(:, i);
                b = groupMeanRTAttn(:, j);
                valid = ~isnan(a) & ~isnan(b);
                if sum(valid) > 1
                    [~, pval] = ttest(a(valid), b(valid));
                    pRT(i,j) = pval;
                    pRT(j,i) = pval;
                    
                    % Cohen's d
                    diff = a(valid) - b(valid);
                    cohensD = mean(diff) / std(diff);
                    
                    sigStr = '';
                    if pval < 0.001
                        sigStr = ' ***';
                    elseif pval < 0.01
                        sigStr = ' **';
                    elseif pval < 0.05
                        sigStr = ' *';
                    elseif pval < 0.10
                        sigStr = ' (trend)';
                    end
                    
                    fprintf('  %s vs %s: ΔRT = %.3f s, p = %.4f, d = %.2f%s\n', ...
                        condNames{i}, condNames{j}, ...
                        groupMeanRTAttn_mean(i) - groupMeanRTAttn_mean(j), ...
                        pval, cohensD, sigStr);
                end
            end
        end
        results.group.RT_pvals = pRT;
        
        % RT correct vs error
        fprintf('\nRT: Correct vs Error trials\n');
        meanRTCorrect_all = nanmean(groupMeanRTCorrectAttn, 2);
        meanRTError_all = nanmean(groupMeanRTErrorAttn, 2);
        validSubj = ~isnan(meanRTCorrect_all) & ~isnan(meanRTError_all);
        if sum(validSubj) > 1
            [~, pCorrErr] = ttest(meanRTCorrect_all(validSubj), meanRTError_all(validSubj));
            fprintf('  Correct: M = %.3f s, Error: M = %.3f s, p = %.4f\n', ...
                nanmean(meanRTCorrect_all), nanmean(meanRTError_all), pCorrErr);
        end
        fprintf('\n');
        
        % --- Group-level plot with sig markers ---
        figure('Name', sprintf('Group testing (%s)', whichDataset), ...
               'Color','w');
        
        bar(allAttnLevels, groupAccAttn_mean); hold on;
        errorbar(allAttnLevels, groupAccAttn_mean, groupAccAttn_sem, ...
                 'k', 'LineStyle','none', 'LineWidth',1.2);
        xlabel('Attention condition');
        ylabel('Accuracy (%)');
        title(sprintf('Group: accuracy by attention (N=%d)', nSubjEff));
        set(gca, 'XTick', allAttnLevels, ...
                 'XTickLabel', {'dist','valid','invalid'});
        ylim([0 100]);
        
        % add significance brackets for p < .05 (solid) and trends p < .10 (dashed)
        yl = ylim;
        yBase = yl(2);
        yStep = (yl(2) - yl(1)) * 0.06;   % spacing between brackets
        nLevelsUsed = 0;
        for i = 1:nAttn-1
            for j = i+1:nAttn
                pval = pAttn(i,j);
                if isnan(pval) || pval >= 0.10  % show up to p < 0.10
                    continue;
                end
                
                % Determine line style and star
                if pval < 0.05
                    lineStyle = '-';   % solid for significant
                    star = getStar(pval);
                else  % 0.05 <= p < 0.10
                    lineStyle = '--';  % dashed for trend
                    star = '†';  % dagger for trend
                end
                
                if isempty(star), continue; end
                nLevelsUsed = nLevelsUsed + 1;
                x1 = allAttnLevels(i);
                x2 = allAttnLevels(j);
                y  = yBase + yStep * nLevelsUsed;
                plot([x1 x1 x2 x2], [y y+yStep/2 y+yStep/2 y], ...
                     'k', 'LineStyle', lineStyle, 'LineWidth',1.0);
                text(mean([x1 x2]), y + yStep/2, star, ...
                     'HorizontalAlignment','center', ...
                     'VerticalAlignment','bottom', ...
                     'FontSize',10);
            end
        end
        if nLevelsUsed > 0
            ylim([yl(1) yBase + yStep*(nLevelsUsed+1)]);
        end
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_testing_attnOnly.png', exptNameOut));
            saveas(gcf, fn);
        end
        
        % --- D-PRIME PLOT ---
        figure('Name', sprintf('Group testing d-prime (%s)', whichDataset), ...
               'Color','w');
        
        bar(allAttnLevels, groupDPrimeAttn_mean); hold on;
        errorbar(allAttnLevels, groupDPrimeAttn_mean, groupDPrimeAttn_sem, ...
                 'k', 'LineStyle','none', 'LineWidth',1.2);
        xlabel('Attention condition');
        ylabel('d'' (discrimination sensitivity)');
        title(sprintf('Group: d'' by attention (N=%d)', nSubjEff));
        set(gca, 'XTick', allAttnLevels, ...
                 'XTickLabel', {'dist','valid','invalid'});
        yline(0, '--k', 'LineWidth', 0.5);  % chance line
        
        % add significance brackets for d'
        yl = ylim;
        yBase = yl(2);
        yStep = (yl(2) - yl(1)) * 0.06;
        nLevelsUsed = 0;
        for i = 1:nAttn-1
            for j = i+1:nAttn
                pval = pDPrime(i,j);
                if isnan(pval) || pval >= 0.10
                    continue;
                end
                
                if pval < 0.05
                    lineStyle = '-';
                    star = getStar(pval);
                else
                    lineStyle = '--';
                    star = '†';
                end
                
                if isempty(star), continue; end
                nLevelsUsed = nLevelsUsed + 1;
                x1 = allAttnLevels(i);
                x2 = allAttnLevels(j);
                y  = yBase + yStep * nLevelsUsed;
                plot([x1 x1 x2 x2], [y y+yStep/2 y+yStep/2 y], ...
                     'k', 'LineStyle', lineStyle, 'LineWidth',1.0);
                text(mean([x1 x2]), y + yStep/2, star, ...
                     'HorizontalAlignment','center', ...
                     'VerticalAlignment','bottom', ...
                     'FontSize',10);
            end
        end
        if nLevelsUsed > 0
            ylim([yl(1) yBase + yStep*(nLevelsUsed+1)]);
        end
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_testing_dprime.png', exptNameOut));
            saveas(gcf, fn);
        end
        
        % --- CRITERION PLOT ---
        figure('Name', sprintf('Group testing criterion (%s)', whichDataset), ...
               'Color','w');
        
        bar(allAttnLevels, groupCriterionAttn_mean); hold on;
        errorbar(allAttnLevels, groupCriterionAttn_mean, groupCriterionAttn_sem, ...
                 'k', 'LineStyle','none', 'LineWidth',1.2);
        xlabel('Attention condition');
        ylabel('Criterion c (response bias)');
        title(sprintf('Group: criterion by attention (N=%d)', nSubjEff));
        set(gca, 'XTick', allAttnLevels, ...
                 'XTickLabel', {'dist','valid','invalid'});
        yline(0, '--k', 'LineWidth', 1, 'Label', 'No bias', ...
              'LabelHorizontalAlignment', 'left', 'FontSize', 9);
        
        % Add text annotations for interpretation
        yl = ylim;
        yRange = yl(2) - yl(1);
        if yl(2) > 0.05
            text(mean(allAttnLevels), yl(2) - 0.08*yRange, ...
                 'Conservative (bias toward CCW, key 2)', ...
                 'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', [0.5 0.5 0.5]);
        end
        if yl(1) < -0.05
            text(mean(allAttnLevels), yl(1) + 0.08*yRange, ...
                 'Liberal (bias toward CW, key 1)', ...
                 'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', [0.5 0.5 0.5]);
        end
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_testing_criterion.png', exptNameOut));
            saveas(gcf, fn);
        end
        
        % --- COMBINED SDT PLOT (d' and criterion side-by-side) ---
        figure('Name', sprintf('Group testing SDT combined (%s)', whichDataset), ...
               'Color','w', 'Position', [100 100 900 400]);
        
        % Left panel: d-prime
        subplot(1,2,1); hold on;
        bar(allAttnLevels, groupDPrimeAttn_mean);
        errorbar(allAttnLevels, groupDPrimeAttn_mean, groupDPrimeAttn_sem, ...
                 'k', 'LineStyle','none', 'LineWidth',1.2);
        xlabel('Attention condition');
        ylabel('d'' (discrimination sensitivity)');
        title('Perceptual Sensitivity');
        set(gca, 'XTick', allAttnLevels, ...
                 'XTickLabel', {'dist','valid','invalid'});
        yline(0, '--k', 'LineWidth', 0.5);
        ylim([0 max(groupDPrimeAttn_mean + groupDPrimeAttn_sem)*1.2]);
        
        % Add significance brackets for d'
        yl = ylim;
        yBase = yl(2);
        yStep = (yl(2) - yl(1)) * 0.06;
        nLevelsUsed = 0;
        for i = 1:nAttn-1
            for j = i+1:nAttn
                pval = pDPrime(i,j);
                if isnan(pval) || pval >= 0.10
                    continue;
                end
                
                if pval < 0.05
                    lineStyle = '-';
                    star = getStar(pval);
                else
                    lineStyle = '--';
                    star = '†';
                end
                
                if isempty(star), continue; end
                nLevelsUsed = nLevelsUsed + 1;
                x1 = allAttnLevels(i);
                x2 = allAttnLevels(j);
                y  = yBase + yStep * nLevelsUsed;
                plot([x1 x1 x2 x2], [y y+yStep/2 y+yStep/2 y], ...
                     'k', 'LineStyle', lineStyle, 'LineWidth',1.0);
                text(mean([x1 x2]), y + yStep/2, star, ...
                     'HorizontalAlignment','center', ...
                     'VerticalAlignment','bottom', ...
                     'FontSize',10);
            end
        end
        if nLevelsUsed > 0
            ylim([yl(1) yBase + yStep*(nLevelsUsed+1)]);
        end
        
        % Right panel: criterion
        subplot(1,2,2); hold on;
        bar(allAttnLevels, groupCriterionAttn_mean);
        errorbar(allAttnLevels, groupCriterionAttn_mean, groupCriterionAttn_sem, ...
                 'k', 'LineStyle','none', 'LineWidth',1.2);
        xlabel('Attention condition');
        ylabel('Criterion c (response bias)');
        title('Response Bias');
        set(gca, 'XTick', allAttnLevels, ...
                 'XTickLabel', {'dist','valid','invalid'});
        yline(0, '--k', 'LineWidth', 1, 'Label', 'No bias', ...
              'LabelHorizontalAlignment', 'right', 'FontSize', 8);
        
        % Symmetric y-axis for criterion
        maxAbsC = max(abs([groupCriterionAttn_mean - groupCriterionAttn_sem, ...
                           groupCriterionAttn_mean + groupCriterionAttn_sem]));
        ylim([-maxAbsC*1.3, maxAbsC*1.3]);
        
        sgtitle(sprintf('SDT Analysis by Attention (N=%d)', nSubjEff), ...
                'FontSize', 12, 'FontWeight', 'bold');
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_testing_SDT_combined.png', exptNameOut));
            saveas(gcf, fn);
        end
        
        % --- RT PLOT ---
        figure('Name', sprintf('Group testing RT (%s)', whichDataset), ...
               'Color','w');
        
        bar(allAttnLevels, groupMeanRTAttn_mean); hold on;
        errorbar(allAttnLevels, groupMeanRTAttn_mean, groupMeanRTAttn_sem, ...
                 'k', 'LineStyle','none', 'LineWidth',1.2);
        xlabel('Attention condition');
        ylabel('Reaction Time (s)');
        title(sprintf('Group: RT by attention (N=%d)', nSubjEff));
        set(gca, 'XTick', allAttnLevels, ...
                 'XTickLabel', {'dist','valid','invalid'});
        
        % add significance brackets for RT
        yl = ylim;
        yBase = yl(2);
        yStep = (yl(2) - yl(1)) * 0.06;
        nLevelsUsed = 0;
        for i = 1:nAttn-1
            for j = i+1:nAttn
                pval = pRT(i,j);
                if isnan(pval) || pval >= 0.10
                    continue;
                end
                
                if pval < 0.05
                    lineStyle = '-';
                    star = getStar(pval);
                else
                    lineStyle = '--';
                    star = '†';
                end
                
                if isempty(star), continue; end
                nLevelsUsed = nLevelsUsed + 1;
                x1 = allAttnLevels(i);
                x2 = allAttnLevels(j);
                y  = yBase + yStep * nLevelsUsed;
                plot([x1 x1 x2 x2], [y y+yStep/2 y+yStep/2 y], ...
                     'k', 'LineStyle', lineStyle, 'LineWidth',1.0);
                text(mean([x1 x2]), y + yStep/2, star, ...
                     'HorizontalAlignment','center', ...
                     'VerticalAlignment','bottom', ...
                     'FontSize',10);
            end
        end
        if nLevelsUsed > 0
            ylim([yl(1) yBase + yStep*(nLevelsUsed+1)]);
        end
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_testing_RT.png', exptNameOut));
            saveas(gcf, fn);
        end
        
        % --- D-PRIME vs RT SCATTER ---
        figure('Name', sprintf('Group testing d'' vs RT (%s)', whichDataset), ...
               'Color','w');
        
        condColors = [0.2 0.4 0.8; 0.2 0.7 0.3; 0.8 0.2 0.2];  % dist, valid, invalid
        condNames = {'dist', 'valid', 'invalid'};
        condMarkers = {'o', 's', '^'};
        
        hold on;
        for i = 1:nAttn
            dPrimeVals = groupDPrimeAttn(:, i);
            rtVals = groupMeanRTAttn(:, i);
            validPts = ~isnan(dPrimeVals) & ~isnan(rtVals);
            
            if sum(validPts) > 0
                scatter(rtVals(validPts), dPrimeVals(validPts), 80, ...
                        condColors(i,:), condMarkers{i}, 'filled', ...
                        'MarkerFaceAlpha', 0.6, 'LineWidth', 1.5);
            end
        end
        
        xlabel('Reaction Time (s)');
        ylabel('d'' (discrimination sensitivity)');
        title(sprintf('Sensitivity vs Speed (N=%d)', nSubjEff));
        legend(condNames, 'Location', 'best');
        grid on;
        
        % Add diagonal reference line (faster RT and higher d' is better)
        xl = xlim;
        yl = ylim;
        text(xl(2)*0.95, yl(2)*0.95, 'Better →', ...
             'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
             'FontSize', 10, 'Color', [0.5 0.5 0.5], 'FontWeight', 'bold');
        text(xl(1)*1.05, yl(1)*1.05, '← Worse', ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
             'FontSize', 10, 'Color', [0.5 0.5 0.5], 'FontWeight', 'bold');
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_testing_dprime_vs_RT.png', exptNameOut));
            saveas(gcf, fn);
        end
        
    %% =============================================================
    %  GROUP-LEVEL: THRESHOLD / PRACTICE
    % =============================================================
    otherwise
        % Collect thresholds across subjects
        thresh_all        = [subjRes.cohThresh_est];
        thresh_pal_all    = [subjRes.cohThresh_pal];
        thresh_median_all = [subjRes.cohThresh_median];
        palSuccess_all    = [subjRes.palSuccess];
        
        results.group.cohThresh_all        = thresh_all;
        results.group.cohThresh_pal_all    = thresh_pal_all;
        results.group.cohThresh_median_all = thresh_median_all;
        results.group.palSuccess_all       = palSuccess_all;
        results.group.cohThresh_mean       = nanmean(thresh_all);
        results.group.cohThresh_sem        = sem(thresh_all);
        
        % --- Console summary ---
        fprintf('\n--- THRESHOLD SUMMARY ---\n');
        fprintf('  %-10s  %-8s  %-12s  %-12s  %s\n', ...
            'Subject', 'Method', 'Pal thresh', 'Median thresh', 'Used');
        for s = 1:nSubjEff
            methStr = subjRes(s).threshMethod;
            fprintf('  %-10s  %-8s  %-12s  %-12.4f  %.4f\n', ...
                subjRes(s).subject_id, methStr, ...
                sprintf('%.4f', subjRes(s).cohThresh_pal), ...
                subjRes(s).cohThresh_median, ...
                subjRes(s).cohThresh_est);
        end
        fprintf('\n  Group mean threshold: %.4f (SEM = %.4f)\n', ...
            results.group.cohThresh_mean, results.group.cohThresh_sem);
        fprintf('  Palamedes fit succeeded for %d/%d subjects\n', ...
            sum(palSuccess_all), nSubjEff);
        
        % --- Figure 1: Individual panels (psychometric + trace, one per subject) ---
        % Already produced per-subject above. Here produce a compact summary panel.
        nRows = ceil(sqrt(nSubjEff));
        nCols = ceil(nSubjEff / nRows);
        
        col_blue = [0.13 0.45 0.80];
        col_red  = [0.80 0.15 0.15];
        col_gray = [0.55 0.55 0.55];
        
        figure('Name', sprintf('Psychometric summary (%s)', whichDataset), ...
               'Color', 'w', 'Position', [50 50 320*nCols 280*nRows]);
        
        for s = 1:nSubjEff
            subplot(nRows, nCols, s); hold on;
            
            uCoh_s    = subjRes(s).cohLevels;
            pCorr_s   = subjRes(s).pCorrPerCoh;
            acc_s     = subjRes(s).accByCoh;
            n_s       = subjRes(s).nPerCoh;
            
            % Wilson CI
            z_ci  = 1.96;
            pCI_lo = (pCorr_s + z_ci^2./(2*n_s) - z_ci.*sqrt(pCorr_s.*(1-pCorr_s)./n_s + z_ci^2./(4*n_s.^2))) ...
                     ./ (1 + z_ci^2./n_s);
            pCI_hi = (pCorr_s + z_ci^2./(2*n_s) + z_ci.*sqrt(pCorr_s.*(1-pCorr_s)./n_s + z_ci^2./(4*n_s.^2))) ...
                     ./ (1 + z_ci^2./n_s);
            
            errorbar(uCoh_s, acc_s, ...
                     (pCorr_s - pCI_lo)*100, (pCI_hi - pCorr_s)*100, ...
                     'o', 'Color', col_blue, 'MarkerFaceColor', col_blue, ...
                     'MarkerSize', 5, 'LineWidth', 1.0, 'CapSize', 4);
            
            % Weibull fit
            if subjRes(s).palSuccess
                PF = @PAL_Weibull;
                cohFine = linspace(max(min(uCoh_s)*0.5, 0.01), min(max(uCoh_s)*1.3, 1.0), 300);
                pFine = PF(subjRes(s).paramsValues, cohFine);
                plot(cohFine, pFine*100, '-', 'Color', col_red, 'LineWidth', 1.5);
            end
            
            % Reference lines
            yline(82, '--', 'Color', col_gray, 'LineWidth', 0.8, 'Alpha', 0.6);
            yline(50, ':',  'Color', col_gray, 'LineWidth', 0.6, 'Alpha', 0.4);
            
            % Threshold line
            if ~isnan(subjRes(s).cohThresh_est)
                xline(subjRes(s).cohThresh_est, '--', 'Color', col_red, 'LineWidth', 1.2);
            end
            
            % Trial counts
            yl = ylim;
            for k = 1:numel(uCoh_s)
                text(uCoh_s(k), 42, sprintf('%d', n_s(k)), ...
                     'HorizontalAlignment', 'center', 'FontSize', 6, 'Color', col_gray);
            end
            
            xlabel('Coherence', 'FontSize', 8);
            ylabel('Accuracy (%)', 'FontSize', 8);
            ylim([40 105]);
            
            methChar = 'M';  % median
            if subjRes(s).palSuccess, methChar = 'W'; end  % Weibull
            title(sprintf('%s  [%s=%.3f]', ...
                subjRes(s).subject_id, methChar, subjRes(s).cohThresh_est), ...
                'Interpreter', 'none', 'FontSize', 8);
            grid on; box off;
        end
        
        sgtitle(sprintf('Individual Psychometric Functions (%s)  |  W=Weibull  M=Median', ...
            whichDataset), 'FontSize', 11, 'FontWeight', 'bold');
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_%s_psychometrics_panel.png', exptNameOut, whichDataset));
            saveas(gcf, fn);
        end
        
        % --- Figure 2: Group overlay of Weibull fits only (clean comparison) ---
        figure('Name', sprintf('Group psychometric overlay (%s)', whichDataset), ...
               'Color', 'w', 'Position', [100 100 620 480]);
        hold on;
        
        colors = lines(nSubjEff);
        
        for s = 1:nSubjEff
            uCoh_s  = subjRes(s).cohLevels;
            pCorr_s = subjRes(s).pCorrPerCoh;
            acc_s   = subjRes(s).accByCoh;
            
            if subjRes(s).palSuccess
                % Plot Weibull fit curve
                PF = @PAL_Weibull;
                cohFine = linspace(max(min(uCoh_s)*0.5, 0.01), min(max(uCoh_s)*1.3, 1.0), 300);
                pFine   = PF(subjRes(s).paramsValues, cohFine);
                plot(cohFine, pFine*100, '-', 'Color', colors(s,:), 'LineWidth', 1.5, ...
                     'DisplayName', sprintf('%s (W, thresh=%.3f)', ...
                     subjRes(s).subject_id, subjRes(s).cohThresh_est));
            end
            
            % Always plot raw data (smaller markers for overlay)
            plot(uCoh_s, acc_s, 'o', 'Color', colors(s,:), 'MarkerSize', 5, ...
                 'MarkerFaceColor', colors(s,:), 'HandleVisibility', 'off');
        end
        
        yline(82, '--k', 'LineWidth', 1.2, 'Alpha', 0.5, ...
              'Label', '82% (3dn/1up target)', ...
              'LabelHorizontalAlignment', 'left', 'FontSize', 8, ...
              'DisplayName', '82% target');
        yline(50, ':k',  'LineWidth', 0.8, 'Alpha', 0.3, ...
              'Label', 'chance', 'LabelHorizontalAlignment', 'left', ...
              'FontSize', 8, 'HandleVisibility', 'off');
        
        xlabel('Coherence', 'FontSize', 12);
        ylabel('Accuracy (%)', 'FontSize', 12);
        title(sprintf('Group Psychometric Functions (%s, N=%d)', whichDataset, nSubjEff), ...
              'Interpreter', 'none', 'FontSize', 12);
        ylim([40 105]);
        
        % Compute max coherence safely (cohLevels differs in length per subject)
        maxCoh = max(cellfun(@max, {subjRes.cohLevels}));
        xlim([0 maxCoh * 1.1]);
        legend('Location', 'southeast', 'FontSize', 8);
        grid on; box off;
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_%s_psychometrics_overlay.png', exptNameOut, whichDataset));
            saveas(gcf, fn);
        end
        
        % --- Figure 3: Threshold summary (bar chart across subjects) ---
        figure('Name', sprintf('Threshold summary (%s)', whichDataset), ...
               'Color', 'w', 'Position', [100 100 500 380]);
        hold on;
        
        subjLabels = {subjRes.subject_id};
        xPos = 1:nSubjEff;
        
        % Bar for each subject, colored by method
        for s = 1:nSubjEff
            if subjRes(s).palSuccess
                barColor = col_red;   % Weibull fit
            else
                barColor = col_gray;  % median fallback
            end
            bar(xPos(s), subjRes(s).cohThresh_est, 'FaceColor', barColor, ...
                'EdgeColor', 'none', 'BarWidth', 0.7);
        end
        
        % Group mean ± SEM
        yMean = results.group.cohThresh_mean;
        ySEM  = results.group.cohThresh_sem;
        plot(xlim, [yMean yMean], 'k--', 'LineWidth', 1.5);
        patch([0.5 nSubjEff+0.5 nSubjEff+0.5 0.5], ...
              [yMean-ySEM yMean-ySEM yMean+ySEM yMean+ySEM], ...
              'k', 'FaceAlpha', 0.1, 'EdgeColor', 'none');
        
        set(gca, 'XTick', xPos, 'XTickLabel', subjLabels, 'XTickLabelRotation', 30);
        ylabel('Coherence threshold');
        title(sprintf('Thresholds by subject  |  Mean=%.3f \\pm %.3f SEM', yMean, ySEM));
        
        % Legend for method
        patch(nan, nan, col_red,  'EdgeColor','none', 'DisplayName', 'Weibull fit');
        patch(nan, nan, col_gray, 'EdgeColor','none', 'DisplayName', 'Median-tail');
        legend('Location', 'northeast', 'FontSize', 8);
        grid on; box off;
        
        if saveFigs
            fn = fullfile(figDir, sprintf('group_%s_%s_thresh_summary.png', exptNameOut, whichDataset));
            saveas(gcf, fn);
        end
end

%% ------------------------------------------------------------------------
%  SAVE SUMMARY
% -------------------------------------------------------------------------

if saveSummary
    summaryFile = fullfile(root_data, ...
        sprintf('pri2stim_%s_summary.mat', whichDataset));
    save(summaryFile, 'results');
    fprintf('\nSaved summary to:\n  %s\n', summaryFile);
end

fprintf('\nDone.\n');

%% ------------------------------------------------------------------------
%  HELPER: convert p-value to significance stars
% -------------------------------------------------------------------------
function star = getStar(p)
% Returns '', '*', '**', or '***' based on the p-value.
    if isnan(p) || p >= 0.05
        star = '';
    elseif p < 0.001
        star = '***';
    elseif p < 0.01
        star = '**';
    else % 0.01 <= p < 0.05
        star = '*';
    end
end