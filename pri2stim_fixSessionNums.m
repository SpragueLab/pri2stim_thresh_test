% pri2stim_fixSessionNums.m
%
% Corrects p.sessionNum inside .mat files that were saved with the wrong
% session number (e.g. sess00 when it should be sess01).
%
% Handles two scenarios automatically:
%
%   SIMPLE CASE (most subjects):
%     All runs used the wrong session number from the start. The script
%     renames each run file and patches p.sessionNum. The _stair.mat and
%     _thresh.mat files (if present) are renamed to match.
%
%   SPLIT STAIRCASE CASE (e.g. sub009):
%     The RA started correctly (sess01) then switched mid-session (sess00).
%     Both a wrongToken and correctToken _stair.mat exist. Because the
%     median threshold method only uses the last 30 trials, and the
%     wrongToken stair has enough trials to fill that window on its own,
%     merging is unnecessary and potentially counterproductive (the
%     wrongToken stair started fresh from max coherence, so its early
%     trials would add noise). Instead the script:
%       - Backs up the existing correctToken _stair.mat
%       - Renames the wrongToken _stair.mat to correctToken
%         (overwriting the old incomplete correctToken stair)
%       - Renames/patches the wrongToken run files to correctToken
%       - Warns you to discard any existing _thresh.mat and re-run
%         pri2stim_computeThreshold
%
% The script never deletes originals. Always run with dryRun = true first.
% For the split case, a timestamped backup of the old correctToken stair
% is created before anything is overwritten.
%
% USAGE:
%   Edit USER SETTINGS below, set dryRun = true, run and inspect output.
%   Then set dryRun = false and re-run to apply.
%
% AHH / Claude - April 2026

clear;

%% ========================================================================
%  USER SETTINGS  --  edit these before running
% =========================================================================

% Data directory -- run separately for 'thresholding' and 'testing' if needed
dataDir = 'C:\Users\tcs-labra\Documents\stimuli\pri2stim_thresh_test\data\thresholding';
% dataDir = 'C:\Users\tcs-labra\Documents\stimuli\pri2stim_thresh_test\data\testing';

% Subject to fix. Use '' to fix ALL subjects found in the directory.
% Use a specific name (e.g. 'sub009') to fix just one subject.
targetSubject = '';   % '' = all subjects, or e.g. 'sub009'

% Session number as it appears WRONGLY in the filename  (e.g. 0 -> 'sess00')
wrongSessionNum   = 0;

% Session number it SHOULD be  (e.g. 1 -> 'sess01')
correctSessionNum = 1;

% Experiment name -- must match p.exptName in your run files
exptName = 'pri2stimEEG_threshold';
% exptName = 'pri2stimEEG_testing';

% Set true for a dry run (prints what WOULD happen, writes nothing)
dryRun = false;

%% ========================================================================
%  SETUP
% =========================================================================

wrongToken   = sprintf('sess%02d', wrongSessionNum);
correctToken = sprintf('sess%02d', correctSessionNum);

fprintf('\n=== pri2stim_fixSessionNums ===\n');
fprintf('Directory     : %s\n', dataDir);
fprintf('Experiment    : %s\n', exptName);
fprintf('Replacing     : %s  -->  %s\n', wrongToken, correctToken);
fprintf('Target subject: %s\n', iif(isempty(targetSubject), 'ALL', targetSubject));
if dryRun
    fprintf('*** DRY RUN - no files will be written ***\n');
end
fprintf('\n');

if ~isfolder(dataDir)
    error('Data directory not found: %s', dataDir);
end

%% ========================================================================
%  FIND SUBJECTS TO PROCESS
% =========================================================================

if isempty(targetSubject)
    pattern  = sprintf('*_%s_%s_run*_*.mat', exptName, wrongToken);
    allFiles = dir(fullfile(dataDir, pattern));
    subNames = unique( cellfun( ...
        @(n) n(1 : strfind(n, ['_' exptName]) - 1), ...
        {allFiles.name}, 'UniformOutput', false) );
    if isempty(subNames)
        fprintf('No files found matching pattern: %s\nNothing to do.\n', pattern);
        return
    end
else
    subNames = {targetSubject};
end

fprintf('Subjects to process: %s\n\n', strjoin(subNames, ', '));

%% ========================================================================
%  PROCESS EACH SUBJECT
% =========================================================================

for si = 1:numel(subNames)
    subName = subNames{si};
    fprintf('------------------------------------------------------------\n');
    fprintf('Subject: %s\n', subName);
    fprintf('------------------------------------------------------------\n');

    % Locate stair files
    stairFile_wrong   = fullfile(dataDir, ...
        sprintf('%s_%s_%s_stair.mat', subName, exptName, wrongToken));
    stairFile_correct = fullfile(dataDir, ...
        sprintf('%s_%s_%s_stair.mat', subName, exptName, correctToken));

    hasWrongStair   = exist(stairFile_wrong,   'file') == 2;
    hasCorrectStair = exist(stairFile_correct, 'file') == 2;

    % Find wrong-session run files
    runPattern_wrong = sprintf('%s_%s_%s_run*_*.mat', subName, exptName, wrongToken);
    wrongRunFiles    = dir(fullfile(dataDir, runPattern_wrong));

    if isempty(wrongRunFiles)
        fprintf('  No wrong-session run files found. Skipping.\n\n');
        continue
    end

    fprintf('  Wrong-session run files found: %d\n', numel(wrongRunFiles));
    for k = 1:numel(wrongRunFiles)
        fprintf('    %s\n', wrongRunFiles(k).name);
    end

    % Detect and dispatch to the appropriate scenario
    if hasWrongStair && hasCorrectStair
        fprintf('\n  SCENARIO: SPLIT STAIRCASE (rename wrongToken stair, backup correctToken stair)\n');
        fprintf('  Both %s_stair.mat and %s_stair.mat exist.\n', correctToken, wrongToken);
        fprintf('  The RA switched session numbers mid-session.\n');
        fprintf('  The %s stair is sufficient for threshold estimation on its own.\n', wrongToken);
        fprintf('  The old %s stair will be backed up and replaced.\n\n', correctToken);
        fixSplitStaircase(dataDir, subName, exptName, ...
            wrongToken, correctToken, correctSessionNum, ...
            wrongRunFiles, stairFile_wrong, stairFile_correct, dryRun);

    elseif hasWrongStair && ~hasCorrectStair
        fprintf('\n  SCENARIO: SIMPLE RENAME (stair under wrong token only)\n\n');
        fixSimple(dataDir, subName, exptName, ...
            wrongToken, correctToken, correctSessionNum, ...
            wrongRunFiles, stairFile_wrong, dryRun);

    elseif ~hasWrongStair && ~hasCorrectStair
        fprintf('\n  SCENARIO: SIMPLE RENAME (no stair file found)\n\n');
        fixSimple(dataDir, subName, exptName, ...
            wrongToken, correctToken, correctSessionNum, ...
            wrongRunFiles, [], dryRun);

    else
        % wrongToken run files exist but no wrongToken stair, and a
        % correctToken stair already exists -- unusual edge case
        fprintf('\n  SCENARIO: SIMPLE RENAME\n');
        fprintf('  NOTE: %s_stair.mat already exists but no %s_stair.mat found.\n', ...
            correctToken, wrongToken);
        fprintf('  Verify manually that the correct stair already contains\n');
        fprintf('  all trials from the wrong-session run files.\n\n');
        fixSimple(dataDir, subName, exptName, ...
            wrongToken, correctToken, correctSessionNum, ...
            wrongRunFiles, [], dryRun);
    end

end % subject loop

fprintf('============================================================\n');
if dryRun
    fprintf('Dry run complete. Set dryRun = false and re-run to apply.\n');
else
    fprintf('All done.\n');
end
fprintf('\n');


%% ========================================================================
%% LOCAL FUNCTIONS
%% ========================================================================

% -------------------------------------------------------------------------
function fixSimple(dataDir, subName, exptName, ...
        wrongToken, correctToken, correctSessionNum, ...
        wrongRunFiles, stairFile_wrong, dryRun)
% Handles simple case: all wrong-session files get renamed/patched.

    % Run files
    renameAndPatch(dataDir, wrongRunFiles, wrongToken, correctToken, ...
        correctSessionNum, dryRun);

    % Stair file
    if ~isempty(stairFile_wrong)
        newStairPath = strrep(stairFile_wrong, wrongToken, correctToken);
        fprintf('  Stair file:\n    %s\n    --> %s\n', stairFile_wrong, newStairPath);
        if ~dryRun
            if exist(newStairPath, 'file')
                fprintf('    WARNING: target stair already exists, skipping.\n');
            else
                S = load(stairFile_wrong);
                save(newStairPath, '-struct', 'S');
                fprintf('    Saved OK.\n');
            end
        else
            fprintf('    (dry run - skipped)\n');
        end
    end

    % Thresh file
    threshFile_wrong = fullfile(dataDir, ...
        sprintf('%s_%s_%s_thresh.mat', subName, exptName, wrongToken));
    if exist(threshFile_wrong, 'file')
        newThreshPath = strrep(threshFile_wrong, wrongToken, correctToken);
        fprintf('\n  Thresh file:\n    %s\n    --> %s\n', threshFile_wrong, newThreshPath);
        if ~dryRun
            if exist(newThreshPath, 'file')
                fprintf('    WARNING: target thresh already exists, skipping.\n');
            else
                S = load(threshFile_wrong);
                save(newThreshPath, '-struct', 'S');
                fprintf('    Saved OK.\n');
            end
        else
            fprintf('    (dry run - skipped)\n');
        end
    end

    fprintf('\n');
end


% -------------------------------------------------------------------------
function fixSplitStaircase(dataDir, subName, exptName, ...
        wrongToken, correctToken, correctSessionNum, ...
        wrongRunFiles, stairFile_wrong, stairFile_correct, dryRun)
% Handles split staircase: back up the old correctToken stair, rename the
% wrongToken stair to correctToken, then rename/patch the run files.
% No merging -- the wrongToken stair is used as-is. It has enough trials
% (>=30) for the median-of-tail estimate and its own converged state.
% The old correctToken stair is preserved as a timestamped backup.

    % Report trial counts for transparency
    S_wrong   = load(stairFile_wrong,   'stair');
    S_correct = load(stairFile_correct, 'stair');
    nWrong    = numel(S_wrong.stair.logCoh);
    nCorrect  = numel(S_correct.stair.logCoh);

    fprintf('  Trials in %s stair (will become new %s stair): %d\n', ...
        wrongToken, correctToken, nWrong);
    fprintf('  Trials in %s stair (will be backed up, not used) : %d\n', ...
        correctToken, nCorrect);

    if nWrong < 30
        fprintf('  WARNING: %s stair has only %d trials (< 30).\n', wrongToken, nWrong);
        fprintf('  Threshold estimate will use all available trials rather than the last 30.\n');
    end

    % Back up existing correctToken stair, then replace it with wrongToken stair
    backupPath = strrep(stairFile_correct, '_stair.mat', ...
        sprintf('_stair_BACKUP_%s.mat', datestr(now, 'yyyymmddTHHMMSS')));

    fprintf('\n  Stair file plan:\n');
    fprintf('    Backup : %s\n         --> %s\n', stairFile_correct, backupPath);
    fprintf('    Rename : %s\n         --> %s\n', stairFile_wrong, stairFile_correct);

    if ~dryRun
        copyfile(stairFile_correct, backupPath);
        fprintf('    Backup saved OK.\n');

        S = load(stairFile_wrong);
        save(stairFile_correct, '-struct', 'S');
        fprintf('    Stair saved to correct path OK.\n');
    else
        fprintf('    (dry run - skipped)\n');
    end

    % Rename/patch wrong-session run files
    fprintf('\n  Renaming wrong-session run files:\n');
    renameAndPatch(dataDir, wrongRunFiles, wrongToken, correctToken, ...
        correctSessionNum, dryRun);

    % Warn about stale thresh files
    threshFile_wrong        = fullfile(dataDir, ...
        sprintf('%s_%s_%s_thresh.mat', subName, exptName, wrongToken));
    threshFile_correct_th   = fullfile(dataDir, ...
        sprintf('%s_%s_%s_thresh.mat', subName, exptName, correctToken));

    fprintf('\n  THRESHOLD FILE WARNING:\n');
    if exist(threshFile_wrong, 'file')
        fprintf('    %s\n    --> stale. Move to "bad".\n', threshFile_wrong);
    end
    if exist(threshFile_correct_th, 'file')
        fprintf('    %s\n    --> stale (based on old incomplete stair). Move to "bad".\n', ...
            threshFile_correct_th);
    end
    fprintf('    ACTION: after this script, re-run:\n');
    fprintf('      pri2stim_computeThreshold(''%s'', %d)\n\n', subName, correctSessionNum);
end



% -------------------------------------------------------------------------
function renameAndPatch(dataDir, runFiles, wrongToken, correctToken, ...
        correctSessionNum, dryRun)
% Rename each run file from wrongToken to correctToken and patch p.sessionNum.

    for k = 1:numel(runFiles)
        oldName = runFiles(k).name;
        oldPath = fullfile(dataDir, oldName);
        newName = strrep(oldName, wrongToken, correctToken);
        newPath = fullfile(dataDir, newName);

        fprintf('  %s\n  --> %s\n', oldName, newName);

        if exist(newPath, 'file')
            fprintf('  WARNING: target already exists, skipping.\n\n');
            continue
        end

        if ~dryRun
            S = load(oldPath);
            if isfield(S, 'p') && isfield(S.p, 'sessionNum')
                S.p.sessionNum = correctSessionNum;
            end
            save(newPath, '-struct', 'S');
            fprintf('  Saved OK.\n\n');
        else
            fprintf('  (dry run - skipped)\n\n');
        end
    end
end


% -------------------------------------------------------------------------
function out = iif(cond, a, b)
% Inline ternary helper.
    if cond; out = a; else; out = b; end
end