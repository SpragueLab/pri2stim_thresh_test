function pri2stim_computeThreshold(subName, sessionNum, method)
% pri2stim_computeThreshold(subName, sessionNum, [method])
%
% method:
%   'median'    -> median of last 30 (or fewer) valid trials (default)
%   'palamedes' -> Weibull PF fit using Palamedes toolbox (~82% correct)
%
% Usage examples:
%   pri2stim_computeThreshold('subXXX', 1);
%   pri2stim_computeThreshold('subXXX', 1, 'palamedes');

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

fprintf('Estimated threshold coherence (method = %s): %.4f\n', ...
    threshMethodUsed, cohThresh);

% ------------------------------------------------------------
% Plot staircase using ALL trials (including invalids)
% ------------------------------------------------------------
logCoh_all  = stair.logCoh(:);        % includes NaNs
isCorr_all  = stair.isCorrect(:);     % includes NaNs
nAll        = numel(logCoh_all);
trials_all  = 1:nAll;

cohLin_all  = exp(logCoh_all);        % NaNs propagate, line will break there

figure; hold on;

% coherence trace across all trials (NaNs produce gaps, which is fine)
plot(trials_all, cohLin_all, 'k-', 'LineWidth', 1);

% overlay correctness markers where defined
idxCorr = (isCorr_all == 1) & ~isnan(cohLin_all);
idxErr  = (isCorr_all == 0) & ~isnan(cohLin_all);

plot(trials_all(idxCorr), cohLin_all(idxCorr), 'g.', 'MarkerSize', 14);
plot(trials_all(idxErr),  cohLin_all(idxErr),  'r.', 'MarkerSize', 14);

xlabel('Trial # (all)');
ylabel('Coherence');
title(sprintf('Staircase for %s, session %02d (%s)', ...
    subName, sessionNum, threshMethodUsed));
grid on;
hold off;

% ------------------------------------------------------------
% Save out threshold file for testing script
% ------------------------------------------------------------
threshFile = fullfile(dataDir, ...
    sprintf('%s_%s_sess%02d_thresh.mat', subName, exptName, sessionNum));

save(threshFile, 'cohThresh', 'threshMethodUsed', ...
    'cohThresh_median', 'cohThresh_pal');

end % main function


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
