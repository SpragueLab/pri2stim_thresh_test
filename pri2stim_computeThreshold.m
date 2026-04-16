function pri2stim_computeThreshold(subName, sessionNum, method)
% pri2stim_computeThreshold(subName, sessionNum, [method])
%
% method:
%   'median'    -> median of last 30 (or fewer) valid trials (default)
%   'palamedes' -> Weibull PF fit using Palamedes toolbox (~82% correct)
%
% Usage examples:
%   pri2stim_computeThreshold('subXXX', 1);
%   pri2stim_computeThreshold('subXXX', 1, 'palamedes'); <-- USE THIS!!
%
% add palamedes to path:
%   workstation: addpath(genpath('C:\Users\aharrison\Documents\MATLAB\Palamedes1_11_13\Palamedes'))
%   EEG: addpath(genpath('C:\Users\tcs-labra\Documents\MATLAB\Palamedes1_11_13\Palamedes')); <-- USE THIS IF IN EEG ROOM!

if nargin < 3 || isempty(method)
    method = 'median';
end

% ------------------------------------------------------------
% Locate data directory and staircase file
% ------------------------------------------------------------
tmpf = mfilename('fullpath');
tmpi = strfind(tmpf, filesep);
root = tmpf(1:tmpi(end));
dataDir = fullfile(root, 'data', 'thresholding');

exptName = 'pri2stimEEG_threshold';

stairStateFile = fullfile(dataDir, ...
    sprintf('%s_%s_sess%02d_stair.mat', subName, exptName, sessionNum));

if ~exist(stairStateFile, 'file')
    error('Staircase file not found: %s', stairStateFile);
end

load(stairStateFile, 'stair');

if ~isfield(stair,'logCoh') || ~isfield(stair,'isCorrect')
    error('Stair struct does not contain logCoh / isCorrect. Run pri2stim_thresholding first.');
end

% ------------------------------------------------------------
% Extract valid trials (for threshold estimation)
% ------------------------------------------------------------
validIdx = ~isnan(stair.logCoh) & ~isnan(stair.isCorrect);

if ~any(validIdx)
    error('No valid thresholding trials found in stair.logCoh / stair.isCorrect.');
end

logCoh  = stair.logCoh(validIdx);
correct = stair.isCorrect(validIdx);   % 1 = correct, 0 = error

% ------------------------------------------------------------
% Option 1: crude median-of-tail (always computed)
% ------------------------------------------------------------
cohThresh_median = local_medianThreshold(logCoh);

% ------------------------------------------------------------
% Option 2: Palamedes Weibull fit
% ------------------------------------------------------------
usePalamedes = strcmpi(method, 'palamedes');

cohThresh_pal = NaN;
palSuccess    = false;
paramsValues  = NaN(1,4);   % [alpha beta gamma lambda], filled if fit succeeds

if usePalamedes
    % Check that core Palamedes functions are on path
    hasPFML    = (exist('PAL_PFML_Fit','file') == 2);
    hasWeibull = (exist('PAL_Weibull','file') == 2);
    hasInvPF   = (exist('PAL_PF_invPF','file') == 2);  % optional

    if ~(hasPFML && hasWeibull)
        warning('Palamedes core functions (PAL_PFML_Fit or PAL_Weibull) not found. Falling back to median-of-tail.');
    else
        try
            % Convert to linear coherence
            coh = exp(logCoh);

            % Bin by unique coherence levels
            [stimLevels, ~, idx] = unique(coh);
            nTrials  = accumarray(idx, 1);
            nCorrect = accumarray(idx, correct);

            % Psychometric function: Weibull
            PF = @PAL_Weibull;

            % Search grid
            searchGrid.alpha  = linspace(min(stimLevels), max(stimLevels), 101);
            searchGrid.beta   = logspace(log10(0.5), log10(10), 51);
            searchGrid.gamma  = 0.5;   % guessing rate (2AFC)
            searchGrid.lambda = 0.02;  % small lapse rate

            % paramsFree: [alpha beta gamma lambda]
            paramsFree = [1 1 0 0];    % free alpha, beta; fix gamma/lambda

            % Fit Weibull
            [paramsValues, ~, exitflag] = PAL_PFML_Fit( ...
                stimLevels, nCorrect, nTrials, ...
                searchGrid, paramsFree, PF);

            if exitflag <= 0
                warning('Palamedes fit did not converge. Falling back to median-of-tail threshold.');
            else
                % Target ~82% correct, appropriate for 3-down-1-up
                targetPerf = 0.82;

                if hasInvPF
                    % Use Palamedes analytic inverse if available
                    cohThresh_pal = PAL_PF_invPF(paramsValues, targetPerf, PF);
                else
                    % Numeric inversion if PAL_PF_invPF is missing
                    invFun = @(x) PF(paramsValues, x) - targetPerf;
                    % Use alpha as a reasonable starting point
                    cohThresh_pal = fzero(invFun, paramsValues(1));
                end

                palSuccess = true;
            end

        catch
            warning('Palamedes threshold fit failed: Falling back to median-of-tail.');
        end
    end
end

% ------------------------------------------------------------
% Decide which threshold to report
% ------------------------------------------------------------
if palSuccess
    cohThresh         = cohThresh_pal;
    threshMethodUsed  = 'palamedes';
else
    cohThresh         = cohThresh_median;
    threshMethodUsed  = 'median';
end

% ------------------------------------------------------------
% QUALITY DIAGNOSTICS
% (criteria grounded in Levitt 1971 staircase conventions and
%  Carrasco lab threshold estimation practice)
% ------------------------------------------------------------
diag = local_computeDiagnostics(logCoh, correct, cohThresh, palSuccess);

% Print the diagnostics report to the console
local_printDiagnosticsReport(subName, sessionNum, cohThresh, threshMethodUsed, diag);

% ------------------------------------------------------------
% FIGURE: two-panel layout
%   Left  - staircase trace (existing)
%   Right - binned psychometric function + Weibull fit (new)
% ------------------------------------------------------------
local_plotFigure(subName, sessionNum, stair, logCoh, correct, ...
    cohThresh, threshMethodUsed, palSuccess, paramsValues, diag);

% ------------------------------------------------------------
% Save out threshold file for testing script
% ------------------------------------------------------------
threshFile = fullfile(dataDir, ...
    sprintf('%s_%s_sess%02d_thresh.mat', subName, exptName, sessionNum));

save(threshFile, 'cohThresh', 'threshMethodUsed', ...
    'cohThresh_median', 'cohThresh_pal', 'diag');

end % main function



% ============================================================
% DIAGNOSTICS
% ============================================================
function diag = local_computeDiagnostics(logCoh, correct, cohThresh, palSuccess)
% Compute staircase quality metrics and an overall readiness verdict.
%
% Convergence is assessed by two complementary measures:
%
%   1. SD of raw coherence in the second half of valid trials.
%      This directly captures what you see in the staircase plot: a
%      converged staircase has trials clustered tightly around the threshold;
%      an unconverged one (e.g., large step size causing floor-ceiling
%      bouncing) has trials spread across the full range. Late-reversal SD
%      is fooled by this pathology because reversal points by definition
%      sit at turning points in the middle of each swing.
%
%   2. Mean step size (mean |delta coh| between successive trials).
%      This directly diagnoses the root cause of floor-ceiling bouncing:
%      a step size that is too large relative to the PF slope. Reported
%      as informational context to help interpret the raw-SD flag.
%
% Note: the absolute value of the threshold is NOT a criterion. A high
% threshold just means the participant needs higher coherence to reach target
% performance, which is fine for individualizing difficulty across subjects.

coh = exp(logCoh);
n   = numel(logCoh);

% --- Overall accuracy ---
diag.overallAcc = mean(correct);

% --- Locate reversal points (for plotting only) ---
isReversal = false(n, 1);
for i = 2:n-1
    if (logCoh(i) - logCoh(i-1)) * (logCoh(i+1) - logCoh(i)) < 0
        isReversal(i) = true;
    end
end
revIdx          = find(isReversal);
revCoh          = coh(revIdx);
diag.nReversals = numel(revIdx);
diag.revIdx     = revIdx;
diag.revCoh     = revCoh;
diag.nLateRev   = floor(diag.nReversals / 2);  % kept for plot compatibility

% --- SD of raw coherence in the second half of trials ---
% This is what the staircase plot actually shows. A converged staircase
% oscillates tightly; floor-ceiling bouncing produces high SD even when
% reversal points happen to cluster in the middle of the range.
halfN = floor(n / 2);
if halfN >= 10
    lateTrialCoh      = coh(end-halfN+1:end);
    diag.lateTrialSD  = std(lateTrialCoh);
else
    diag.lateTrialSD  = NaN;
end

% Criterion: SD > 0.20 in linear coherence units flags instability.
% A well-behaved staircase oscillating +/- one step around threshold
% will produce SD << 0.20; floor-ceiling bouncing will be >> 0.20.
diag.lateTrialSDThresh = 0.20;
diag.unstable = isnan(diag.lateTrialSD) || ...
                (diag.lateTrialSD > diag.lateTrialSDThresh);

% --- Mean step size (informational: root cause of bouncing) ---
% Large mean |delta coh| means step size is too coarse for the PF slope.
if n >= 2
    diag.meanStepLinear = mean(abs(diff(coh)));
else
    diag.meanStepLinear = NaN;
end

% --- Staircase range (informational only) ---
diag.minCohVisited = min(coh);
diag.maxCohVisited = max(coh);

% --- Weibull fit ---
diag.palSuccess = palSuccess;

% --- Accuracy check ---
% 3-down/1-up theoretical asymptote ~79.4% (Levitt 1971).
% Below 65%: too noisy / task not understood.
% Above 92%: never challenged; estimate unreliable.
diag.accTooLow  = diag.overallAcc < 0.65;
diag.accTooHigh = diag.overallAcc > 0.92;

% --- Trial count ---
diag.nValid       = n;
diag.tooFewTrials = n < 60;

% ------------------------------------------------------------
% OVERALL VERDICT
%   GO      - stable convergence, accuracy in range, Weibull fit OK
%   CAUTION - marginal; RA should inspect plot and use judgment
%   NO-GO   - hard failure; run more thresholding blocks
% ------------------------------------------------------------
hardFail = diag.tooFewTrials || diag.accTooLow || diag.unstable;

softFail = (diag.nReversals < 8) || (~palSuccess) || diag.accTooHigh;

if hardFail
    diag.verdict = 'NO-GO';
elseif softFail
    diag.verdict = 'CAUTION';
else
    diag.verdict = 'GO';
end

end



% ============================================================
% CONSOLE REPORT
% ============================================================
function local_printDiagnosticsReport(subName, sessionNum, cohThresh, threshMethodUsed, diag)

fprintf('\n');
fprintf('================================================================\n');
fprintf('  THRESHOLD QUALITY REPORT\n');
fprintf('  Subject: %s   Session: %02d\n', subName, sessionNum);
fprintf('================================================================\n');
fprintf('  Estimated threshold (%-9s): %.4f\n', threshMethodUsed, cohThresh);
fprintf('  Valid trials             : %d', diag.nValid);
if diag.tooFewTrials
    fprintf('  << BELOW MINIMUM (60)');
end
fprintf('\n');
  fprintf('  Reversals (total)        : %d', diag.nReversals);
if diag.nReversals < 8
    fprintf('  << LOW (need >= 8)');
end
fprintf('\n');
if isnan(diag.lateTrialSD)
    fprintf('  Late-trial coh SD        : n/a (too few trials)\n');
else
    fprintf('  Late-trial coh SD        : %.3f  (last %d trials, threshold = %.2f)', ...
        diag.lateTrialSD, floor(diag.nValid/2), diag.lateTrialSDThresh);
    if diag.unstable
        fprintf('  << UNSTABLE -- staircase has not converged');
    end
    fprintf('\n');
end
if ~isnan(diag.meanStepLinear)
    fprintf('  Mean step size (coh)     : %.3f  (informational)\n', diag.meanStepLinear);
end
fprintf('  Overall accuracy         : %.1f%%', diag.overallAcc*100);
if diag.accTooLow
    fprintf('  << TOO LOW (<65%%) -- participant may not understand task');
elseif diag.accTooHigh
    fprintf('  << HIGH (>92%%) -- staircase may not have challenged participant');
end
fprintf('\n');
fprintf('  Coherence range visited  : %.3f -- %.3f  (informational)\n', ...
    diag.minCohVisited, diag.maxCohVisited);
fprintf('  Weibull fit converged?   : %s', yesno(diag.palSuccess));
if ~diag.palSuccess
    fprintf('  (run more blocks and retry with ''palamedes'')');
end
fprintf('\n');
fprintf('----------------------------------------------------------------\n');

switch diag.verdict
    case 'GO'
        fprintf('  VERDICT:  *** GO ***   Proceed to testing phase.\n');
    case 'CAUTION'
        fprintf('  VERDICT:  *** CAUTION ***\n');
        fprintf('  Check the staircase plot carefully.\n');
        fprintf('  Consider running one more thresholding block if unsure.\n');
    case 'NO-GO'
        fprintf('  VERDICT:  *** NO-GO ***\n');
        fprintf('  Do NOT proceed to testing. Run at least one more\n');
        fprintf('  thresholding block, then re-run computeThreshold.\n');
        if diag.unstable
            fprintf('  Reason: staircase did not converge (late-trial SD = %.3f > %.2f).\n', ...
                diag.lateTrialSD, diag.lateTrialSDThresh);
            fprintf('  The step size may be too large -- check staircase plot.\n');
        end
end

fprintf('================================================================\n\n');

end


function s = yesno(val)
if val
    s = 'YES';
else
    s = 'no';
end
end



% ============================================================
% FIGURE
% ============================================================
function local_plotFigure(subName, sessionNum, stair, logCoh, correct, ...
    cohThresh, threshMethodUsed, palSuccess, paramsValues, diag)

% Colors
col_green  = [0.18 0.63 0.18];
col_red    = [0.80 0.15 0.15];
col_blue   = [0.13 0.45 0.80];
col_orange = [0.90 0.50 0.05];
col_gray   = [0.45 0.45 0.45];

figure('Name', sprintf('Threshold: %s sess %02d', subName, sessionNum), ...
    'Color', 'w', 'Position', [100 100 1100 460]);

% ---- Panel 1: Staircase trace --------------------------------
subplot(1,2,1); hold on;

logCoh_all = stair.logCoh(:);
isCorr_all = stair.isCorrect(:);
nAll       = numel(logCoh_all);
cohLin_all = exp(logCoh_all);

plot(1:nAll, cohLin_all, 'k-', 'LineWidth', 1);

idxCorr = (isCorr_all == 1) & ~isnan(cohLin_all);
idxErr  = (isCorr_all == 0) & ~isnan(cohLin_all);

plot(find(idxCorr), cohLin_all(idxCorr), '.', ...
    'Color', col_green, 'MarkerSize', 14);
plot(find(idxErr),  cohLin_all(idxErr),  '.', ...
    'Color', col_red,   'MarkerSize', 14);

% Mark late reversals (the ones that drive the SD criterion)
% Early reversals = open circles; late reversals = filled diamonds
if ~isempty(diag.revIdx)
    nLate       = diag.nLateRev;
    nEarly      = diag.nReversals - nLate;
    earlyRevIdx = diag.revIdx(1:nEarly);
    lateRevIdx  = diag.revIdx(nEarly+1:end);

    % Early reversals: small open circles
    plot(earlyRevIdx, cohLin_all(earlyRevIdx), 'o', ...
        'Color', col_gray, 'MarkerSize', 7, 'LineWidth', 1, ...
        'MarkerFaceColor', 'none');

    % Late reversals: filled diamonds -- these drive the SD criterion
    plot(lateRevIdx, cohLin_all(lateRevIdx), 'd', ...
        'Color', col_orange, 'MarkerSize', 8, 'LineWidth', 1.2, ...
        'MarkerFaceColor', col_orange);
end

% Threshold line
yline(cohThresh, '--', 'Color', col_blue, 'LineWidth', 1.5, ...
    'Label', sprintf('thresh = %.3f', cohThresh), ...
    'LabelVerticalAlignment', 'bottom', 'FontSize', 9);

xlabel('Trial #');
ylabel('Coherence');
if isnan(diag.lateTrialSD)
    sdStr = 'trial SD: n/a';
else
    sdStr = sprintf('trial SD = %.3f', diag.lateTrialSD);
end
title(sprintf('Staircase  |  %d reversals  |  acc = %.0f%%  |  %s', ...
    diag.nReversals, diag.overallAcc*100, sdStr), 'FontSize', 10);
ylim([0 1.05]);
grid on; box off;

% Verdict badge in corner
verdictColor = local_verdictColor(diag.verdict, col_green, col_orange, col_red);
text(0.97, 0.97, diag.verdict, 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'FontSize', 12, 'FontWeight', 'bold', 'Color', verdictColor);

hold off;


% % ---- Panel 2: Binned psychometric function -------------------
% subplot(1,2,2); hold on;
% 
% coh = exp(logCoh);
% [stimLevels, ~, idx] = unique(coh);
% nTrialsPerBin  = accumarray(idx, 1);
% nCorrectPerBin = accumarray(idx, correct);
% pCorrect       = nCorrectPerBin ./ nTrialsPerBin;
% 
% % Error bars: Wilson score interval (better than normal approx at extremes)
% % Agresti & Coull 1998; widely used in psychophysics (e.g., Carrasco lab)
% z   = 1.96;
% n_  = nTrialsPerBin;
% p_  = pCorrect;
% pCI_lo = (p_ + z^2./(2*n_) - z.*sqrt(p_.*(1-p_)./n_ + z^2./(4*n_.^2))) ./ (1 + z^2./n_);
% pCI_hi = (p_ + z^2./(2*n_) + z.*sqrt(p_.*(1-p_)./n_ + z^2./(4*n_.^2))) ./ (1 + z^2./n_);
% 
% errorbar(stimLevels, pCorrect, pCorrect - pCI_lo, pCI_hi - pCorrect, ...
%     'o', 'Color', col_blue, 'MarkerFaceColor', col_blue, ...
%     'MarkerSize', 6, 'LineWidth', 1.2, 'CapSize', 5);
% 
% % Weibull fit curve (if available)
% if palSuccess && ~any(isnan(paramsValues))
%     PF      = @PAL_Weibull;
%     xFit    = linspace(min(stimLevels)*0.8, max(stimLevels)*1.1, 300);
%     yFit    = PF(paramsValues, xFit);
%     plot(xFit, yFit, '-', 'Color', col_blue, 'LineWidth', 2);
% end
% 
% % Reference lines
% yline(0.5,  ':', 'Color', col_gray, 'LineWidth', 1);   % chance
% yline(0.75, ':', 'Color', col_gray, 'LineWidth', 1);   % ~75% reference
% yline(0.82, '--','Color', col_gray, 'LineWidth', 1, ...
%     'Label', '82%', 'LabelHorizontalAlignment', 'left', ...
%     'FontSize', 8);                                     % 3-down/1-up target
% 
% % Threshold vertical line
% xline(cohThresh, '--', 'Color', col_blue, 'LineWidth', 1.5, ...
%     'Label', sprintf('%.3f', cohThresh), ...
%     'LabelVerticalAlignment', 'bottom', 'FontSize', 9);
% 
% xlabel('Coherence');
% ylabel('Proportion correct');
% title(sprintf('Psychometric function  |  method: %s', threshMethodUsed), ...
%     'FontSize', 10);
% ylim([0.3 1.05]);
% xlim([0 max(stimLevels)*1.15]);
% grid on; box off;
% 
% % Trial counts as text under each data point
% for b = 1:numel(stimLevels)
%     text(stimLevels(b), 0.33, sprintf('n=%d', nTrialsPerBin(b)), ...
%         'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', col_gray);
% end
% 
% hold off;

sgtitle(sprintf('%s  |  Session %02d', subName, sessionNum), ...
    'FontSize', 12, 'FontWeight', 'bold');

end

function c = local_verdictColor(verdict, go, caution, nogo)
switch verdict
    case 'GO',      c = go;
    case 'CAUTION', c = caution;
    case 'NO-GO',   c = nogo;
    otherwise,      c = [0 0 0];
end
end


% ============================================================
% Local helper: crude median-of-tail threshold
% ============================================================
function cohThresh = local_medianThreshold(logCoh)
% logCoh: vector of valid log-coherence values (one per trial)

nValid = numel(logCoh);
nTail  = min(30, nValid);  % last 30 trials, or all if < 30

logCohTail = logCoh(end-nTail+1:end);
cohThresh  = exp(median(logCohTail));
end