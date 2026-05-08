% pri2stim_thresh_test_plotBehav.m
%
% Analyze and plot behavioral performance for pri2stim thresholding
% and testing datasets, using concatenated *_behav.mat files produced by
% pri2stim_thresh_test_concatBehav.m.
%
% Supports:
%   whichDataset = 'testing'
%   whichDataset = 'threshold'
%   whichDataset = 'threshold_practice'
%
% For 'testing':
%   - Per subject: accuracy by attention condition (with within-subject
%                  binomial error bars).
%   - Group: individual subject data (diamonds) + mean +/- SEM (circles),
%            with significance markers (paired t-tests).
%   - SDT analysis: d-prime and criterion for 2AFC discrimination
%                   (discriminating CW vs CCW at the post-cued location).
%   - RT analysis: mean RT by attention condition.
%
% For 'threshold' / 'threshold_practice':
%   - Per subject: psychometric curve (coherence vs accuracy, Wilson CIs),
%                  Weibull fit (Palamedes), estimated threshold.
%   - Group: individual Weibull overlays, threshold summary bar chart.
%
% Plot aesthetics match pri2stimdist_plotBehav_clean.m:
%   - Individual subjects: filled translucent diamonds, connected by faint
%     grey lines across conditions.
%   - Group mean: filled circles with error bars (LineWidth 2, CapSize 12).
%   - Axes: FontSize 15, LineWidth 1.1, TickDir out, box off, grid off.
%   - Colors: gold     = neutral/dist  [253 187 24]/255
%             mid-blue = valid         [30 90 160]/255
%             dark grey = invalid      [0.45 0.45 0.45]
%
% Dependencies (testing dataset only):
%   Palamedes toolbox (optional) — for Weibull fitting in threshold mode.
%
% AHH 2025, updated 2026:
%   - aesthetic overhaul to match pri2stimdist_plotBehav_clean.m
%   - individual-subject scatter/line plots for group figures
%   - significance brackets on group plots

clear;

%% ------------------------------------------------------------------------
%  USER SETTINGS
% -------------------------------------------------------------------------

% Base project directory
baseDir      = 'Z:\projects\pri2stim_thresh_test';

% Choose which dataset to analyze:
%   'testing'            -> pri2stimEEG_testing
%   'threshold'          -> pri2stimEEG_threshold
%   'threshold_practice' -> pri2stimEEG_threshold_practice
whichDataset = 'threshold';
% whichDataset = 'testing';


% Optional: restrict to a subset of subjects.
%   Leave empty {} to auto-detect from *_behav.mat files.
% subjList = {};
% subjList = {'sub001','sub006','sub007','sub008','sub009'};
subjList = {'sub001','sub004','sub006','sub007','sub008','sub009','sub010'};


% Save summary .mat file?
saveSummary = 0;

% Save figures?
saveFigs = 0;
figDir   = fullfile(baseDir, 'figures');

if saveFigs && ~isfolder(figDir)
    mkdir(figDir);
end

%% ------------------------------------------------------------------------
%  PATHS AND DATASET-SPECIFIC SETTINGS
% -------------------------------------------------------------------------

switch lower(whichDataset)
    case 'testing'
        dataSubdir  = 'testing';
        exptNameOut = 'pri2stimEEG_testing';
    case 'threshold'
        dataSubdir  = 'thresholding';
        exptNameOut = 'pri2stimEEG_threshold';
    case 'threshold_practice'
        dataSubdir  = 'thresholding';
        exptNameOut = 'pri2stimEEG_threshold_practice';
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

% Auto-detect subject IDs if needed
if isempty(subjList)
    subjNames = cell(numel(behavFiles),1);
    for i = 1:numel(behavFiles)
        S = load(fullfile(root_data, behavFiles(i).name), 'subject_id');
        if isfield(S, 'subject_id')
            subjNames{i} = S.subject_id;
        else
            nm = behavFiles(i).name;
            subjNames{i} = erase(nm, ['_' exptNameOut '_behav.mat']);
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

% Helper functions
% sem: for a vector, returns scalar SEM across all elements.
%      for a matrix, returns 1-x-nCols SEM across rows (one per column).
sem = @(x) nanstd(x, 0, 1) ./ sqrt(sum(~isnan(x), 1));
sem_vec = @(x) nanstd(x(:)) ./ sqrt(sum(~isnan(x(:))));
binom_se = @(p,n) sqrt(p .* (1-p) ./ max(n,1));

% Color palette (consistent with pri2stimdist_plotBehav_clean.m style)
% Attention conditions: 1=neutral/dist, 2=valid, 3=invalid
col_dist    = [253 187 24] ./ 255;   % gold      (neutral/distributed)
col_valid   = [30  90  160] ./ 255;  % mid-blue  (focal valid)
col_invalid = [0.45 0.45 0.45];      % dark grey (focal invalid)
col_gray    = [0.55 0.55 0.55];
col_blue    = [0.13 0.45 0.80];      % for threshold/psychometric plots
col_red     = [0.80 0.15 0.15];      % for Weibull fits

attnColors = [col_dist; col_valid; col_invalid];  % row k = attnCond k
attnLabels = {'dist', 'valid', 'invalid'};

%% ------------------------------------------------------------------------
%  PER-SUBJECT ANALYSIS
% -------------------------------------------------------------------------

results            = struct();
results.whichDataset = whichDataset;
results.baseDir      = baseDir;
results.dataSubdir   = dataSubdir;
results.exptNameOut  = exptNameOut;
results.subjects     = subjList;

subjRes = struct([]);

for s = 1:nSubj
    thisSub  = subjList{s};
    pattern  = sprintf('%s_%s_behav.mat', thisSub, exptNameOut);
    thisFile = fullfile(root_data, pattern);
    if ~exist(thisFile, 'file')
        warning('No behav file found for %s (%s). Skipping.', thisSub, pattern);
        continue;
    end

    fprintf('\n--- Subject %s ---\n', thisSub);
    D = load(thisFile);

    cohLevel_all = D.cohLevel_all(:);
    correct_all  = D.correct_all(:);
    resp_all     = D.resp_all(:);
    RT_all       = D.RT_all(:);
    attnCond_all = D.attnCond_all(:);
    contrast_all = D.contrast_all(:); %#ok<NASGU>

    nTrials    = numel(correct_all);
    overallAcc = 100 * nanmean(correct_all == 1);

    fprintf('  Total trials: %d\n', nTrials);
    fprintf('  Overall accuracy: %.2f %%\n', overallAcc);

    subjRes(s).subject_id = thisSub;
    subjRes(s).nTrials    = nTrials;
    subjRes(s).overallAcc = overallAcc;
    subjRes(s).meanRT     = nanmean(RT_all(correct_all == 1));
    subjRes(s).medianRT   = nanmedian(RT_all(correct_all == 1));

    %% -----------------------------------------------------------------
    %  Dataset-specific analysis
    % ------------------------------------------------------------------

    switch lower(whichDataset)

        %% =============================================================
        %  TESTING
        % =============================================================
        case 'testing'

            validIdx = ~isnan(correct_all);
            uAttn    = sort(unique(attnCond_all(validIdx & ~isnan(attnCond_all))));

            % --- Accuracy by attention condition ---
            accByAttn    = nan(size(uAttn));
            nByAttn      = nan(size(uAttn));
            seByAttn_pct = nan(size(uAttn));

            for k = 1:numel(uAttn)
                idx   = attnCond_all == uAttn(k) & validIdx;
                nThis = sum(idx);
                nByAttn(k) = nThis;
                if nThis > 0
                    pThis           = nanmean(correct_all(idx) == 1);
                    accByAttn(k)    = 100 * pThis;
                    seByAttn_pct(k) = 100 * binom_se(pThis, nThis);
                end
            end

            subjRes(s).attnLevels   = uAttn;
            subjRes(s).accByAttn    = accByAttn;
            subjRes(s).nByAttn      = nByAttn;
            subjRes(s).seByAttn_pct = seByAttn_pct;

            % --- SDT analysis (d' and criterion by attention) ---
            % 2AFC: Category A = CW (stimDir=+1), Category B = CCW (stimDir=-1)
            % "Hit"  = P(resp=CW | stim=CW)
            % "FA"   = P(resp=CW | stim=CCW)
            % Macmillan & Creelman (2005) log-linear correction for extremes.

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

            dPrimeByAttn    = nan(size(uAttn));
            criterionByAttn = nan(size(uAttn));

            for k = 1:numel(uAttn)
                idx = attnCond_all == uAttn(k) & validIdx & ~isnan(trueDir_all);
                if sum(idx) > 0
                    cwTrials     = idx & (trueDir_all == 1);
                    ccwTrials    = idx & (trueDir_all == -1);
                    nCW          = sum(cwTrials);
                    nCCW         = sum(ccwTrials);
                    nCorrectCW   = sum(cwTrials  & resp_all == 1);
                    nIncorrectCW = sum(ccwTrials & resp_all == 1);

                    if nCW > 0 && nCCW > 0
                        pH = nCorrectCW   / nCW;
                        pF = nIncorrectCW / nCCW;
                        % Log-linear correction
                        pH = max(0.5/nCW,   min(1 - 0.5/nCW,   pH));
                        pF = max(0.5/nCCW,  min(1 - 0.5/nCCW,  pF));
                        dPrimeByAttn(k)    = norminv(pH) - norminv(pF);
                        criterionByAttn(k) = -0.5 * (norminv(pH) + norminv(pF));
                    end
                end
            end

            subjRes(s).dPrimeByAttn    = dPrimeByAttn;
            subjRes(s).criterionByAttn = criterionByAttn;

            fprintf('  SDT by attention:\n');
            for k = 1:numel(uAttn)
                if ~isnan(dPrimeByAttn(k))
                    fprintf('    %s: d'' = %.2f, c = %.2f\n', ...
                        getAttnLabel(uAttn(k)), dPrimeByAttn(k), criterionByAttn(k));
                end
            end

            % --- RT by attention condition ---
            meanRTByAttn        = nan(size(uAttn));
            medianRTByAttn      = nan(size(uAttn));
            meanRTCorrectByAttn = nan(size(uAttn));
            meanRTErrorByAttn   = nan(size(uAttn));

            for k = 1:numel(uAttn)
                idx = attnCond_all == uAttn(k) & validIdx;
                if sum(idx) > 0
                    meanRTByAttn(k)   = nanmean(RT_all(idx));
                    medianRTByAttn(k) = nanmedian(RT_all(idx));
                    idxCorr = idx & correct_all == 1;
                    idxErr  = idx & correct_all == 0;
                    if sum(idxCorr) > 0, meanRTCorrectByAttn(k) = nanmean(RT_all(idxCorr)); end
                    if sum(idxErr)  > 0, meanRTErrorByAttn(k)   = nanmean(RT_all(idxErr));  end
                end
            end

            subjRes(s).meanRTByAttn        = meanRTByAttn;
            subjRes(s).medianRTByAttn      = medianRTByAttn;
            subjRes(s).meanRTCorrectByAttn = meanRTCorrectByAttn;
            subjRes(s).meanRTErrorByAttn   = meanRTErrorByAttn;

            fprintf('  RT by attention (mean | median):\n');
            for k = 1:numel(uAttn)
                if ~isnan(meanRTByAttn(k))
                    fprintf('    %s: M = %.3f s, Mdn = %.3f s\n', ...
                        getAttnLabel(uAttn(k)), meanRTByAttn(k), medianRTByAttn(k));
                end
            end

        %% =============================================================
        %  THRESHOLD / THRESHOLD_PRACTICE
        % =============================================================
        otherwise

            validIdx     = ~isnan(correct_all) & ~isnan(cohLevel_all);
            cohUse       = round(cohLevel_all(validIdx), 4);
            corrUse      = correct_all(validIdx);
            nValidTrials = sum(validIdx);

            uCoh  = sort(unique(cohUse(~isnan(cohUse))));
            nBins = numel(uCoh);

            nPerCoh     = nan(nBins,1);
            nCorrPerCoh = nan(nBins,1);
            pCorrPerCoh = nan(nBins,1);
            accByCoh    = nan(nBins,1);

            for k = 1:nBins
                idx           = cohUse == uCoh(k);
                nThis         = sum(idx);
                nCorrThis     = sum(corrUse(idx) == 1);
                nPerCoh(k)    = nThis;
                nCorrPerCoh(k)= nCorrThis;
                if nThis > 0
                    pThis          = nCorrThis / nThis;
                    pCorrPerCoh(k) = pThis;
                    accByCoh(k)    = 100 * pThis;
                end
            end

            subjRes(s).cohLevels    = uCoh;
            subjRes(s).nPerCoh      = nPerCoh;
            subjRes(s).nCorrPerCoh  = nCorrPerCoh;
            subjRes(s).pCorrPerCoh  = pCorrPerCoh;
            subjRes(s).accByCoh     = accByCoh;

            fprintf('  Psychometric bins (%d trials, %d coherence levels):\n', ...
                nValidTrials, nBins);
            fprintf('    %8s  %6s  %8s  %6s\n', 'coh', 'n', 'nCorr', 'acc%');
            for k = 1:nBins
                fprintf('    %8.4f  %6d  %8d  %5.1f%%\n', ...
                    uCoh(k), nPerCoh(k), nCorrPerCoh(k), accByCoh(k));
            end

            % --- Palamedes Weibull fit ---
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
                warning('%s: Palamedes not on path. Using median-tail fallback.', thisSub);
            elseif nBins < 3
                warning('%s: Only %d coherence bins (need >= 3 for Weibull fit).', thisSub, nBins);
            else
                try
                    PF = @PAL_Weibull;
                    searchGrid.alpha  = linspace(min(uCoh), max(uCoh), 101);
                    searchGrid.beta   = logspace(log10(0.5), log10(10), 51);
                    searchGrid.gamma  = 0.5;
                    searchGrid.lambda = 0.02;
                    paramsFree = [1 1 0 0];

                    [paramsValues, ~, exitflag] = PAL_PFML_Fit( ...
                        uCoh(:)', nCorrPerCoh(:)', nPerCoh(:)', ...
                        searchGrid, paramsFree, PF);

                    if exitflag > 0
                        targetPerf = 0.82;
                        if hasInvPF
                            cohThresh_pal = PAL_PF_invPF(paramsValues, targetPerf, PF);
                        else
                            invFun        = @(x) PF(paramsValues, x) - targetPerf;
                            cohThresh_pal = fzero(invFun, paramsValues(1));
                        end
                        palSuccess   = true;
                        threshMethod = 'palamedes';
                        fprintf('  Weibull fit converged: alpha=%.4f, beta=%.2f\n', ...
                            paramsValues(1), paramsValues(2));
                    else
                        warning('%s: Palamedes fit did not converge. Using median-tail.', thisSub);
                    end
                catch ME
                    warning('%s: Palamedes fit error: %s. Using median-tail.', thisSub, ME.message);
                end
            end

            % Median-tail fallback
            if nValidTrials > 0
                logCohAll        = log(cohUse);
                nTail            = min(30, nValidTrials);
                cohThresh_median = exp(median(logCohAll(end-nTail+1:end)));
            end

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

            % --- Per-subject psychometric plot ---
            figure('Name', sprintf('%s thresholding', thisSub), ...
                   'Color', 'w', 'Position', [100 100 900 420]);

            % Left panel: psychometric function
            subplot(1,2,1); hold on;

            z_ci  = 1.96;
            n_    = nPerCoh;
            p_    = pCorrPerCoh;
            pCI_lo = (p_ + z_ci^2./(2*n_) - z_ci.*sqrt(p_.*(1-p_)./n_ + z_ci^2./(4*n_.^2))) ...
                     ./ (1 + z_ci^2./n_);
            pCI_hi = (p_ + z_ci^2./(2*n_) + z_ci.*sqrt(p_.*(1-p_)./n_ + z_ci^2./(4*n_.^2))) ...
                     ./ (1 + z_ci^2./n_);

            errorbar(uCoh, accByCoh, ...
                     (pCorrPerCoh - pCI_lo)*100, (pCI_hi - pCorrPerCoh)*100, ...
                     'o', 'Color', col_blue, 'MarkerFaceColor', col_blue, ...
                     'MarkerSize', 6, 'LineWidth', 1.2, 'CapSize', 5);

            if palSuccess
                PF      = @PAL_Weibull;
                cohFine = linspace(max(min(uCoh)*0.5, 0.01), min(max(uCoh)*1.3, 1.0), 300);
                pFine   = PF(paramsValues, cohFine);
                plot(cohFine, pFine*100, '-', 'Color', col_red, 'LineWidth', 2);
            end

            yline(50,  ':', 'Color', col_gray, 'LineWidth', 1, ...
                  'Label', 'chance', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
            yline(75,  ':', 'Color', col_gray, 'LineWidth', 0.8, ...
                  'Label', '75%', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
            yline(82, '--', 'Color', col_gray, 'LineWidth', 1.0, ...
                  'Label', '82% (target)', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);

            if ~isnan(cohThresh_est)
                xline(cohThresh_est, '--', 'Color', col_red, 'LineWidth', 1.5, ...
                      'Label', sprintf('thresh=%.3f', cohThresh_est), ...
                      'LabelVerticalAlignment', 'bottom', 'FontSize', 8);
            end

            for k = 1:nBins
                text(uCoh(k), 42, sprintf('n=%d', nPerCoh(k)), ...
                     'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', col_gray);
            end

            xlabel('Coherence', 'FontSize', 13);
            ylabel('Accuracy (%)', 'FontSize', 13);
            ylim([40 105]);
            set(gca, 'FontSize', 12, 'LineWidth', 1.1, 'TickDir', 'out');
            box off;

            if palSuccess
                title(sprintf('%s  |  Weibull \\alpha=%.3f, \\beta=%.2f', ...
                    thisSub, paramsValues(1), paramsValues(2)), ...
                    'Interpreter','tex', 'FontSize', 11, 'FontWeight', 'bold');
                legend({'Data (Wilson CI)', 'Weibull fit'}, 'Location', 'southeast', 'FontSize', 9);
            else
                title(sprintf('%s  |  No fit (median-tail only)', thisSub), ...
                    'Interpreter','none', 'FontSize', 11, 'FontWeight', 'bold');
            end

            % Right panel: staircase trace
            subplot(1,2,2); hold on;

            allCoh  = cohLevel_all;
            allCorr = correct_all;

            plot(1:numel(allCoh), allCoh, 'k-', 'LineWidth', 0.8);

            idxCorr = ~isnan(allCoh) & allCorr == 1;
            idxErr  = ~isnan(allCoh) & allCorr == 0;
            idxMiss = ~isnan(allCoh) & isnan(allCorr);

            plot(find(idxCorr), allCoh(idxCorr), '.', ...
                 'Color', [0.18 0.63 0.18], 'MarkerSize', 10);
            plot(find(idxErr),  allCoh(idxErr),  '.', ...
                 'Color', col_red,              'MarkerSize', 10);
            if any(idxMiss)
                plot(find(idxMiss), allCoh(idxMiss), '.', ...
                     'Color', col_gray, 'MarkerSize', 8);
            end

            if ~isnan(cohThresh_est)
                yline(cohThresh_est, '--', 'Color', col_red, 'LineWidth', 1.5, ...
                      'Label', sprintf('%.3f', cohThresh_est), ...
                      'LabelVerticalAlignment', 'bottom', 'FontSize', 8);
            end

            xlabel('Trial #', 'FontSize', 13);
            ylabel('Coherence', 'FontSize', 13);
            title(sprintf('acc=%.0f%%  |  thresh=%s', ...
                nanmean(correct_all == 1)*100, threshMethod), ...
                'FontSize', 11, 'FontWeight', 'bold');
            ylim([0 1.05]);
            set(gca, 'FontSize', 12, 'LineWidth', 1.1, 'TickDir', 'out');
            box off;

            lgEntries = {'Trace', 'Correct', 'Error'};
            if any(idxMiss), lgEntries{end+1} = 'Miss'; end
            legend(lgEntries, 'Location', 'northeast', 'FontSize', 8);

            sgtitle(sprintf('%s  |  %s', thisSub, whichDataset), ...
                    'FontSize', 13, 'FontWeight', 'bold', 'Interpreter', 'none');

            if saveFigs
                fn = fullfile(figDir, sprintf('%s_%s_%s.png', ...
                     thisSub, exptNameOut, whichDataset));
                saveas(gcf, fn);
            end
    end
end

% Remove skipped subjects
emptySubj = arrayfun(@(x) ~isfield(x,'subject_id') || isempty(x.subject_id), subjRes);
subjRes(emptySubj) = [];
results.subj = subjRes;
nSubjEff     = numel(subjRes);

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
fprintf('  Mean overall accuracy: %.2f %%  (SEM = %.2f)\n', mean(allAcc), sem_vec(allAcc));

results.group.overallAcc_mean = mean(allAcc);
results.group.overallAcc_sem  = sem_vec(allAcc);
results.group.overallAcc_all  = allAcc;

switch lower(whichDataset)

    %% =================================================================
    %  GROUP: TESTING
    % =================================================================
    case 'testing'

        allAttnLevels = sort(unique(cat(1, subjRes.attnLevels)));
        allAttnLevels = allAttnLevels(~isnan(allAttnLevels));
        nAttn         = numel(allAttnLevels);

        fprintf('  Attention condition codes found: %s\n', num2str(allAttnLevels(:)'));

        % Build per-condition labels and colors from the actual attnCond codes.
        % attnCond coding: 1=neutral/dist, 2=focal valid, 3=focal invalid
        allAttnNames  = {'dist','valid','invalid'};
        allAttnColorsMat = [col_dist; col_valid; col_invalid];
        condLabels = cell(nAttn,1);
        condColors = nan(nAttn,3);
        for k = 1:nAttn
            code = allAttnLevels(k);
            if code >= 1 && code <= 3
                condLabels{k} = allAttnNames{code};
                condColors(k,:) = allAttnColorsMat(code,:);
            else
                condLabels{k} = sprintf('cond%d', code);
                condColors(k,:) = [0.5 0.5 0.5];
            end
        end

        % Collect accuracy across subjects
        groupAccAttn = nan(nSubjEff, nAttn);
        for s = 1:nSubjEff
            for k = 1:nAttn
                idx = subjRes(s).attnLevels == allAttnLevels(k);
                if any(idx), groupAccAttn(s,k) = subjRes(s).accByAttn(idx); end
            end
        end

        groupAccAttn_mean = nanmean(groupAccAttn, 1);
        groupAccAttn_sem  = sem(groupAccAttn);

        results.group.attnLevels       = allAttnLevels;
        results.group.accAttn_mean     = groupAccAttn_mean;
        results.group.accAttn_sem      = groupAccAttn_sem;
        results.group.accAttn_all      = groupAccAttn;

        % Collect d' and criterion
        groupDPrimeAttn    = nan(nSubjEff, nAttn);
        groupCriterionAttn = nan(nSubjEff, nAttn);
        for s = 1:nSubjEff
            for k = 1:nAttn
                idx = subjRes(s).attnLevels == allAttnLevels(k);
                if any(idx)
                    groupDPrimeAttn(s,k)    = subjRes(s).dPrimeByAttn(idx);
                    groupCriterionAttn(s,k) = subjRes(s).criterionByAttn(idx);
                end
            end
        end

        groupDPrimeAttn_mean    = nanmean(groupDPrimeAttn, 1);
        groupDPrimeAttn_sem     = sem(groupDPrimeAttn);
        groupCriterionAttn_mean = nanmean(groupCriterionAttn, 1);
        groupCriterionAttn_sem  = sem(groupCriterionAttn);

        results.group.dPrimeAttn_mean    = groupDPrimeAttn_mean;
        results.group.dPrimeAttn_sem     = groupDPrimeAttn_sem;
        results.group.dPrimeAttn_all     = groupDPrimeAttn;
        results.group.criterionAttn_mean = groupCriterionAttn_mean;
        results.group.criterionAttn_sem  = groupCriterionAttn_sem;
        results.group.criterionAttn_all  = groupCriterionAttn;

        % Collect RT
        groupMeanRTAttn        = nan(nSubjEff, nAttn);
        groupMeanRTCorrectAttn = nan(nSubjEff, nAttn);
        groupMeanRTErrorAttn   = nan(nSubjEff, nAttn);
        for s = 1:nSubjEff
            for k = 1:nAttn
                idx = subjRes(s).attnLevels == allAttnLevels(k);
                if any(idx)
                    groupMeanRTAttn(s,k)        = subjRes(s).meanRTByAttn(idx);
                    groupMeanRTCorrectAttn(s,k) = subjRes(s).meanRTCorrectByAttn(idx);
                    groupMeanRTErrorAttn(s,k)   = subjRes(s).meanRTErrorByAttn(idx);
                end
            end
        end

        groupMeanRTAttn_mean = nanmean(groupMeanRTAttn, 1);
        groupMeanRTAttn_sem  = sem(groupMeanRTAttn);

        results.group.meanRTAttn_mean       = groupMeanRTAttn_mean;
        results.group.meanRTAttn_sem        = groupMeanRTAttn_sem;
        results.group.meanRTAttn_all        = groupMeanRTAttn;
        results.group.meanRTCorrectAttn_all = groupMeanRTCorrectAttn;
        results.group.meanRTErrorAttn_all   = groupMeanRTErrorAttn;

        % --- Pairwise paired t-tests (accuracy) ---
        pAttn = nan(nAttn, nAttn);
        for i = 1:nAttn-1
            for j = i+1:nAttn
                a     = groupAccAttn(:,i);
                b     = groupAccAttn(:,j);
                valid = ~isnan(a) & ~isnan(b);
                if sum(valid) > 1
                    [~, pv] = ttest(a(valid), b(valid));
                    pAttn(i,j) = pv;
                    pAttn(j,i) = pv;
                end
            end
        end
        results.group.attn_pvals = pAttn;

        % --- Pairwise t-tests (d') ---
        pDPrime = nan(nAttn, nAttn);
        for i = 1:nAttn-1
            for j = i+1:nAttn
                a     = groupDPrimeAttn(:,i);
                b     = groupDPrimeAttn(:,j);
                valid = ~isnan(a) & ~isnan(b);
                if sum(valid) > 1
                    [~, pv] = ttest(a(valid), b(valid));
                    pDPrime(i,j) = pv;
                    pDPrime(j,i) = pv;
                end
            end
        end
        results.group.dPrime_pvals = pDPrime;

        % --- Pairwise t-tests (RT) ---
        pRT = nan(nAttn, nAttn);
        for i = 1:nAttn-1
            for j = i+1:nAttn
                a     = groupMeanRTAttn(:,i);
                b     = groupMeanRTAttn(:,j);
                valid = ~isnan(a) & ~isnan(b);
                if sum(valid) > 1
                    [~, pv] = ttest(a(valid), b(valid));
                    pRT(i,j) = pv;
                    pRT(j,i) = pv;
                end
            end
        end
        results.group.RT_pvals = pRT;

        % --- Print statistics ---
        fprintf('\n--- ACCURACY BY ATTENTION ---\n');
        for k = 1:nAttn
            fprintf('  %s: M = %.2f%%, SEM = %.2f%%\n', ...
                condLabels{k}, groupAccAttn_mean(k), groupAccAttn_sem(k));
        end
        fprintf('\nPairwise comparisons (paired t-tests):\n');
        for i = 1:nAttn-1
            for j = i+1:nAttn
                pv = pAttn(i,j);
                if ~isnan(pv)
                    a = groupAccAttn(:,i); b = groupAccAttn(:,j);
                    valid = ~isnan(a) & ~isnan(b);
                    diff  = a(valid) - b(valid);
                    fprintf('  %s vs %s: Delta=%.2f%%, p=%.4f, d=%.2f%s\n', ...
                        condLabels{i}, condLabels{j}, ...
                        groupAccAttn_mean(i)-groupAccAttn_mean(j), pv, ...
                        mean(diff)/std(diff), sigLabel(pv));
                end
            end
        end

        fprintf('\n--- SDT (d'' and criterion) ---\n');
        for k = 1:nAttn
            fprintf('  %s: d''=%.2f (SEM=%.2f), c=%.2f (SEM=%.2f)\n', ...
                condLabels{k}, ...
                groupDPrimeAttn_mean(k), groupDPrimeAttn_sem(k), ...
                groupCriterionAttn_mean(k), groupCriterionAttn_sem(k));
        end

        fprintf('\n--- RT BY ATTENTION ---\n');
        for k = 1:nAttn
            fprintf('  %s: M=%.3f s (SEM=%.3f s)\n', ...
                condLabels{k}, groupMeanRTAttn_mean(k), groupMeanRTAttn_sem(k));
        end

        %% --- GROUP FIGURES (testing) ---
        xPositions = (1:nAttn);

        % ---- Figure 1: Accuracy by attention ----
        figure('Name', 'Group testing: Accuracy by attention', ...
               'Color', 'w', 'Position', [100 100 420 500]);
        hold on;

        for s = 1:nSubjEff
            % connect individual data across conditions with faint grey lines
            plot(xPositions, groupAccAttn(s,:), '-', ...
                 'Color', [0.6 0.6 0.6 0.18], 'LineWidth', 1);
        end
        for k = 1:nAttn
            for s = 1:nSubjEff
                scatter(xPositions(k), groupAccAttn(s,k), 55, condColors(k,:), 'd', 'filled', ...
                    'MarkerFaceAlpha', 0.4, 'MarkerEdgeAlpha', 0.5);
            end
            errorbar(xPositions(k), groupAccAttn_mean(k), groupAccAttn_sem(k), ...
                'o', 'MarkerFaceColor', condColors(k,:), ...
                'MarkerEdgeColor', condColors(k,:), 'Color', condColors(k,:), ...
                'LineWidth', 2, 'CapSize', 12, 'MarkerSize', 9);
        end

        set(gca, 'XTick', xPositions, 'XTickLabel', condLabels, ...
            'FontSize', 15, 'LineWidth', 1.1, 'TickDir', 'out');
        ylabel('Accuracy (%)', 'FontSize', 16);
        ylim([0 100]);
        xlim([xPositions(1)-0.5, xPositions(end)+0.5]);
        box off; grid off;
        addSigBrackets(xPositions, groupAccAttn_mean, groupAccAttn_sem, pAttn);
        title(['\bf' sprintf('Accuracy  (N=%d)', nSubjEff)], 'FontSize', 17);

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_testing_accuracy.png', exptNameOut)));
        end

        % ---- Figure 2: d-prime by attention ----
        figure('Name', 'Group testing: d'' by attention', ...
               'Color', 'w', 'Position', [100 100 420 500]);
        hold on;

        for s = 1:nSubjEff
            plot(xPositions, groupDPrimeAttn(s,:), '-', ...
                 'Color', [0.6 0.6 0.6 0.18], 'LineWidth', 1);
        end
        for k = 1:nAttn
            for s = 1:nSubjEff
                scatter(xPositions(k), groupDPrimeAttn(s,k), 55, condColors(k,:), 'd', 'filled', ...
                    'MarkerFaceAlpha', 0.4, 'MarkerEdgeAlpha', 0.5);
            end
            errorbar(xPositions(k), groupDPrimeAttn_mean(k), groupDPrimeAttn_sem(k), ...
                'o', 'MarkerFaceColor', condColors(k,:), ...
                'MarkerEdgeColor', condColors(k,:), 'Color', condColors(k,:), ...
                'LineWidth', 2, 'CapSize', 12, 'MarkerSize', 9);
        end

        yline(0, '--k', 'LineWidth', 0.8, 'Alpha', 0.5);
        set(gca, 'XTick', xPositions, 'XTickLabel', condLabels, ...
            'FontSize', 15, 'LineWidth', 1.1, 'TickDir', 'out');
        ylabel('d''', 'FontSize', 16);
        xlim([xPositions(1)-0.5, xPositions(end)+0.5]);
        box off; grid off;
        addSigBrackets(xPositions, groupDPrimeAttn_mean, groupDPrimeAttn_sem, pDPrime);
        title(['\bf' sprintf('Perceptual Sensitivity  (N=%d)', nSubjEff)], 'FontSize', 17);

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_testing_dprime.png', exptNameOut)));
        end

        % ---- Figure 3: Criterion by attention ----
        figure('Name', 'Group testing: criterion by attention', ...
               'Color', 'w', 'Position', [100 100 420 500]);
        hold on;

        for s = 1:nSubjEff
            plot(xPositions, groupCriterionAttn(s,:), '-', ...
                 'Color', [0.6 0.6 0.6 0.18], 'LineWidth', 1);
        end
        for k = 1:nAttn
            for s = 1:nSubjEff
                scatter(xPositions(k), groupCriterionAttn(s,k), 55, condColors(k,:), 'd', 'filled', ...
                    'MarkerFaceAlpha', 0.4, 'MarkerEdgeAlpha', 0.5);
            end
            errorbar(xPositions(k), groupCriterionAttn_mean(k), groupCriterionAttn_sem(k), ...
                'o', 'MarkerFaceColor', condColors(k,:), ...
                'MarkerEdgeColor', condColors(k,:), 'Color', condColors(k,:), ...
                'LineWidth', 2, 'CapSize', 12, 'MarkerSize', 9);
        end

        yline(0, '--k', 'LineWidth', 1, 'Label', 'No bias', ...
              'LabelHorizontalAlignment', 'right', 'FontSize', 9);
        set(gca, 'XTick', xPositions, 'XTickLabel', condLabels, ...
            'FontSize', 15, 'LineWidth', 1.1, 'TickDir', 'out');
        ylabel('Criterion c', 'FontSize', 16);
        xlim([xPositions(1)-0.5, xPositions(end)+0.5]);
        yl = ylim; ylim([-max(abs(yl))*1.3, max(abs(yl))*1.3]);
        box off; grid off;
        title(['\bf' sprintf('Response Bias  (N=%d)', nSubjEff)], 'FontSize', 17);

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_testing_criterion.png', exptNameOut)));
        end

        % ---- Figure 4: RT by attention ----
        figure('Name', 'Group testing: RT by attention', ...
               'Color', 'w', 'Position', [100 100 420 500]);
        hold on;

        for s = 1:nSubjEff
            plot(xPositions, groupMeanRTAttn(s,:), '-', ...
                 'Color', [0.6 0.6 0.6 0.18], 'LineWidth', 1);
        end
        for k = 1:nAttn
            for s = 1:nSubjEff
                scatter(xPositions(k), groupMeanRTAttn(s,k), 55, condColors(k,:), 'd', 'filled', ...
                    'MarkerFaceAlpha', 0.4, 'MarkerEdgeAlpha', 0.5);
            end
            errorbar(xPositions(k), groupMeanRTAttn_mean(k), groupMeanRTAttn_sem(k), ...
                'o', 'MarkerFaceColor', condColors(k,:), ...
                'MarkerEdgeColor', condColors(k,:), 'Color', condColors(k,:), ...
                'LineWidth', 2, 'CapSize', 12, 'MarkerSize', 9);
        end

        set(gca, 'XTick', xPositions, 'XTickLabel', condLabels, ...
            'FontSize', 15, 'LineWidth', 1.1, 'TickDir', 'out');
        ylabel('Mean RT (s)', 'FontSize', 16);
        xlim([xPositions(1)-0.5, xPositions(end)+0.5]);
        ylim([0, max(groupMeanRTAttn_mean + groupMeanRTAttn_sem) * 1.3]);
        box off; grid off;
        addSigBrackets(xPositions, groupMeanRTAttn_mean, groupMeanRTAttn_sem, pRT);
        title(['\bf' sprintf('Reaction Time  (N=%d)', nSubjEff)], 'FontSize', 17);

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_testing_RT.png', exptNameOut)));
        end

    %% =================================================================
    %  GROUP: THRESHOLD
    % =================================================================
    otherwise

        thresh_all = [subjRes.cohThresh_est];
        fprintf('  Threshold range: %.4f – %.4f\n', min(thresh_all), max(thresh_all));
        fprintf('  Mean: %.4f  SEM: %.4f\n', mean(thresh_all), sem_vec(thresh_all));

        results.group.cohThresh_mean = mean(thresh_all);
        results.group.cohThresh_sem  = sem_vec(thresh_all);
        results.group.cohThresh_all  = thresh_all;

        palSuccess_all = [subjRes.palSuccess];
        fprintf('  Palamedes fit succeeded for %d/%d subjects\n', ...
            sum(palSuccess_all), nSubjEff);

        % ---- Figure 1: Individual psychometric panels ----
        nRows = ceil(sqrt(nSubjEff));
        nCols = ceil(nSubjEff / nRows);

        figure('Name', sprintf('Psychometric summary (%s)', whichDataset), ...
               'Color', 'w', 'Position', [50 50 320*nCols 280*nRows]);

        for s = 1:nSubjEff
            subplot(nRows, nCols, s); hold on;

            uCoh_s  = subjRes(s).cohLevels;
            pCorr_s = subjRes(s).pCorrPerCoh;
            acc_s   = subjRes(s).accByCoh;
            n_s     = subjRes(s).nPerCoh;

            z_ci  = 1.96;
            pCI_lo = (pCorr_s + z_ci^2./(2*n_s) - z_ci.*sqrt(pCorr_s.*(1-pCorr_s)./n_s + z_ci^2./(4*n_s.^2))) ...
                     ./ (1 + z_ci^2./n_s);
            pCI_hi = (pCorr_s + z_ci^2./(2*n_s) + z_ci.*sqrt(pCorr_s.*(1-pCorr_s)./n_s + z_ci^2./(4*n_s.^2))) ...
                     ./ (1 + z_ci^2./n_s);

            errorbar(uCoh_s, acc_s, ...
                     (pCorr_s - pCI_lo)*100, (pCI_hi - pCorr_s)*100, ...
                     'o', 'Color', col_blue, 'MarkerFaceColor', col_blue, ...
                     'MarkerSize', 5, 'LineWidth', 1.0, 'CapSize', 4);

            if subjRes(s).palSuccess
                PF      = @PAL_Weibull;
                cohFine = linspace(max(min(uCoh_s)*0.5, 0.01), min(max(uCoh_s)*1.3, 1.0), 300);
                pFine   = PF(subjRes(s).paramsValues, cohFine);
                plot(cohFine, pFine*100, '-', 'Color', col_red, 'LineWidth', 1.5);
            end

            yline(82, '--', 'Color', col_gray, 'LineWidth', 0.8, 'Alpha', 0.6);
            yline(50, ':',  'Color', col_gray, 'LineWidth', 0.6, 'Alpha', 0.4);

            if ~isnan(subjRes(s).cohThresh_est)
                xline(subjRes(s).cohThresh_est, '--', 'Color', col_red, 'LineWidth', 1.2);
            end

            for k = 1:numel(uCoh_s)
                text(uCoh_s(k), 42, sprintf('%d', n_s(k)), ...
                     'HorizontalAlignment', 'center', 'FontSize', 6, 'Color', col_gray);
            end

            xlabel('Coherence', 'FontSize', 9);
            ylabel('Accuracy (%)', 'FontSize', 9);
            ylim([40 105]);
            set(gca, 'FontSize', 9, 'LineWidth', 1, 'TickDir', 'out');
            box off;

            methChar = 'M';
            if subjRes(s).palSuccess, methChar = 'W'; end
            title(sprintf('%s  [%s=%.3f]', ...
                subjRes(s).subject_id, methChar, subjRes(s).cohThresh_est), ...
                'Interpreter', 'none', 'FontSize', 9, 'FontWeight', 'bold');
        end

        sgtitle(sprintf('Psychometric Functions (%s)  |  W=Weibull  M=Median-tail', whichDataset), ...
            'FontSize', 12, 'FontWeight', 'bold');

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_%s_psychometrics_panel.png', exptNameOut, whichDataset)));
        end

        % ---- Figure 2: Group Weibull overlay ----
        figure('Name', sprintf('Group psychometric overlay (%s)', whichDataset), ...
               'Color', 'w', 'Position', [100 100 620 480]);
        hold on;

        colors = lines(nSubjEff);

        for s = 1:nSubjEff
            uCoh_s = subjRes(s).cohLevels;
            acc_s  = subjRes(s).accByCoh;

            if subjRes(s).palSuccess
                PF      = @PAL_Weibull;
                cohFine = linspace(max(min(uCoh_s)*0.5, 0.01), min(max(uCoh_s)*1.3, 1.0), 300);
                pFine   = PF(subjRes(s).paramsValues, cohFine);
                plot(cohFine, pFine*100, '-', 'Color', colors(s,:), 'LineWidth', 1.5, ...
                     'DisplayName', sprintf('%s (W, thresh=%.3f)', ...
                     subjRes(s).subject_id, subjRes(s).cohThresh_est));
            end

            plot(uCoh_s, acc_s, 'o', 'Color', colors(s,:), 'MarkerSize', 5, ...
                 'MarkerFaceColor', colors(s,:), 'HandleVisibility', 'off');
        end

        yline(82, '--k', 'LineWidth', 1.2, 'Alpha', 0.5, ...
              'Label', '82% (3dn/1up target)', ...
              'LabelHorizontalAlignment', 'left', 'FontSize', 9, ...
              'DisplayName', '82% target');
        yline(50, ':k', 'LineWidth', 0.8, 'Alpha', 0.3, ...
              'Label', 'chance', 'LabelHorizontalAlignment', 'left', ...
              'FontSize', 9, 'HandleVisibility', 'off');

        xlabel('Coherence', 'FontSize', 14);
        ylabel('Accuracy (%)', 'FontSize', 14);
        title(sprintf('Group Psychometric Functions (%s, N=%d)', whichDataset, nSubjEff), ...
              'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold');
        ylim([40 105]);
        maxCoh = max(cellfun(@max, {subjRes.cohLevels}));
        xlim([0 maxCoh * 1.1]);
        set(gca, 'FontSize', 13, 'LineWidth', 1.1, 'TickDir', 'out');
        box off;
        legend('Location', 'southeast', 'FontSize', 9);

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_%s_psychometrics_overlay.png', exptNameOut, whichDataset)));
        end

        % ---- Figure 3: Threshold summary ----
        figure('Name', sprintf('Threshold summary (%s)', whichDataset), ...
               'Color', 'w', 'Position', [100 100 500 400]);
        hold on;

        subjLabels = {subjRes.subject_id};
        xPos       = 1:nSubjEff;

        for s = 1:nSubjEff
            barCol = col_red;
            if ~subjRes(s).palSuccess, barCol = col_gray; end
            bar(xPos(s), subjRes(s).cohThresh_est, 'FaceColor', barCol, ...
                'EdgeColor', 'none', 'BarWidth', 0.7);
        end

        yMean = results.group.cohThresh_mean;
        ySEM  = results.group.cohThresh_sem;
        plot([0.5 nSubjEff+0.5], [yMean yMean], 'k--', 'LineWidth', 1.5);
        patch([0.5 nSubjEff+0.5 nSubjEff+0.5 0.5], ...
              [yMean-ySEM yMean-ySEM yMean+ySEM yMean+ySEM], ...
              'k', 'FaceAlpha', 0.1, 'EdgeColor', 'none');

        set(gca, 'XTick', xPos, 'XTickLabel', subjLabels, 'XTickLabelRotation', 30, ...
            'FontSize', 13, 'LineWidth', 1.1, 'TickDir', 'out');
        ylabel('Coherence threshold', 'FontSize', 14);
        title(sprintf('\\bfThresholds  |  Mean=%.3f \\pm %.3f SEM', yMean, ySEM), 'FontSize', 14);
        patch(nan, nan, col_red,  'EdgeColor', 'none', 'DisplayName', 'Weibull fit');
        patch(nan, nan, col_gray, 'EdgeColor', 'none', 'DisplayName', 'Median-tail');
        legend('Location', 'northeast', 'FontSize', 10);
        box off;

        if saveFigs
            saveas(gcf, fullfile(figDir, sprintf('group_%s_%s_thresh_summary.png', exptNameOut, whichDataset)));
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

%% ========================================================================
%  LOCAL HELPER FUNCTIONS
% ========================================================================

function lbl = getAttnLabel(code)
% Return a string label for an attnCond code (1=dist, 2=valid, 3=invalid).
names = {'dist','valid','invalid'};
if code >= 1 && code <= 3
    lbl = names{code};
else
    lbl = sprintf('cond%d', code);
end
end % getAttnLabel


function addSigBrackets(xPos, means, sems, pMat)
% Draw significance brackets above a plot.
%   xPos : x-coordinates of conditions (row vector)
%   means: group means (same size as xPos)
%   sems : group SEMs  (same size as xPos)
%   pMat : n x n symmetric p-value matrix

n      = numel(xPos);
yl     = ylim;
yBase  = yl(2);
yStep  = (yl(2) - yl(1)) * 0.07;
nUsed  = 0;

for i = 1:n-1
    for j = i+1:n
        pv = pMat(i,j);
        if isnan(pv) || pv >= 0.10, continue; end

        if pv < 0.05
            lStyle = '-';
            star   = getStar(pv);
        else
            lStyle = '--';
            star   = '†';
        end
        if isempty(star), continue; end

        nUsed = nUsed + 1;
        x1 = xPos(i);
        x2 = xPos(j);
        y  = yBase + yStep * nUsed;
        plot([x1 x1 x2 x2], [y y+yStep/2 y+yStep/2 y], ...
             'k', 'LineStyle', lStyle, 'LineWidth', 1.0);
        text(mean([x1 x2]), y + yStep/2, star, ...
             'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'bottom', 'FontSize', 12);
    end
end

if nUsed > 0
    ylim([yl(1), yBase + yStep*(nUsed+1)]);
end
end % addSigBrackets


function star = getStar(p)
% Convert p-value to significance star string.
if isnan(p) || p >= 0.05
    star = '';
elseif p < 0.001
    star = '***';
elseif p < 0.01
    star = '**';
else
    star = '*';
end
end % getStar


function s = sigLabel(p)
% One-line significance label for console output.
if p < 0.001,      s = ' ***';
elseif p < 0.01,   s = ' **';
elseif p < 0.05,   s = ' *';
elseif p < 0.10,   s = ' (trend)';
else,               s = '';
end
end % sigLabel