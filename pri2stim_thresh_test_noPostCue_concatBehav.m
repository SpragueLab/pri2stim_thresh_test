% pri2stim_thresh_test_noPostCue_concatBehav.m
%
% Concatenate behavioral data across runs for one or more subjects,
% for the noPostCue variants of the pri2stim_thresh_test experiment.
%
% Works with:
%   - pri2stim_testing_noPostCue.m
%       p.exptName = 'pri2stimEEG_testing_noPostCue'
%       data dir:  Z:\projects\pri2stim_thresh_test\testing_noPostCue
%
%   - pri2stim_thresholding_noPostCue.m
%       p.exptName = 'pri2stimEEG_threshold_noPostCue'
%                 or 'pri2stimEEG_threshold_noPostCue_practice'
%       data dir:  Z:\projects\pri2stim_thresh_test\thresholding_noPostCue
%
% Choose which dataset via whichDataset:
%   'testing_noPostCue'
%   'threshold_noPostCue'
%   'threshold_noPostCue_practice'
%
% Fields concatenated differ between datasets (see fieldsToConcat below):
%
%   testing_noPostCue fields (from p struct):
%     cohLevel, stimDir, targSide, distSide, preCueSide, validity,
%     attnCond, resp, correct, RT, trialStart, ITI
%
%   threshold_noPostCue fields (from p struct):
%     cohLevel, stimDir1, stimDir2, attnCond, resp, correct, RT,
%     trialStart, ITI
%
%   Fields absent in a given script are saved as NaN columns so that
%   the output _behav.mat has a consistent set of _all variables.
%
% Output: one *_behav.mat per subject in the relevant data directory.
%
% AHH 2026
%   Adapted from pri2stim_thresh_test_concatBehav.m

clear;

%% ------------------------------------------------------------------------
%  USER SETTINGS
% -------------------------------------------------------------------------

% Either a specific subject (e.g., 'sub003') OR 'ALL'
subject_id   = 'ALL';

% Options:
%   'testing_noPostCue'
%   'threshold_noPostCue'
%   'threshold_noPostCue_practice'

% whichDataset = 'testing_noPostCue';
whichDataset = 'threshold_noPostCue';


%% ------------------------------------------------------------------------
%  PATHS AND EXPT NAMES
% -------------------------------------------------------------------------

baseDir = 'Z:\projects\pri2stim_thresh_test';

switch lower(whichDataset)
    case 'testing_nopostcue'
        dataSubdir   = 'testing_noPostCue';
        exptNameList = {'pri2stimEEG_testing_noPostCue'};
        exptNameOut  = 'pri2stimEEG_testing_noPostCue';
    case 'threshold_nopostcue'
        dataSubdir   = 'thresholding_noPostCue';
        exptNameList = {'pri2stimEEG_threshold_noPostCue'};
        exptNameOut  = 'pri2stimEEG_threshold_noPostCue';
    case 'threshold_nopostcue_practice'
        dataSubdir   = 'thresholding_noPostCue';
        exptNameList = {'pri2stimEEG_threshold_noPostCue_practice'};
        exptNameOut  = 'pri2stimEEG_threshold_noPostCue_practice';
    otherwise
        error(['whichDataset must be ''testing_noPostCue'', ' ...
               '''threshold_noPostCue'', or ''threshold_noPostCue_practice''.']);
end

root_data = fullfile(baseDir, dataSubdir);
if ~isfolder(root_data)
    error('Data directory not found: %s', root_data);
end

%% ------------------------------------------------------------------------
%  FIELDS TO CONCATENATE
% -------------------------------------------------------------------------
% All fields listed here are attempted for every file. If a field is
% absent from a given script's p struct (e.g., stimDir is only in the
% testing script; stimDir1/2 are only in the thresholding script), the
% missing field is filled with NaNs so the output _behav.mat is consistent.
%
% Field presence by script:
%                           testing_nPC  thresh_nPC
%   cohLevel                    Y           Y
%   stimDir      (single dir)   Y           -
%   stimDir1     (left stim)    -           Y
%   stimDir2     (right stim)   -           Y
%   targSide                    Y           -
%   distSide                    Y           -
%   preCueSide                  Y           -
%   validity                    Y           -
%   attnCond                    Y           Y  (scalar=2 in threshold)
%   resp                        Y           Y
%   correct                     Y           Y
%   RT                          Y           Y
%   trialStart                  Y           Y
%   ITI                         Y           Y

fieldsToConcat = { ...
    'cohLevel', ...
    'stimDir', ...       % testing_noPostCue only; NaN in thresholding
    'stimDir1', ...      % thresholding_noPostCue only; NaN in testing
    'stimDir2', ...      % thresholding_noPostCue only; NaN in testing
    'targSide', ...      % testing_noPostCue only
    'distSide', ...      % testing_noPostCue only
    'preCueSide', ...    % testing_noPostCue only
    'validity', ...      % testing_noPostCue only
    'attnCond', ...
    'resp', ...
    'correct', ...
    'RT', ...
    'trialStart', ...
    'ITI' ...
};

%% ------------------------------------------------------------------------
%  DETERMINE SUBJECT LIST
% -------------------------------------------------------------------------

if strcmpi(subject_id, 'ALL')
    allFiles = dir(fullfile(root_data, 'sub*_*.mat'));
    if isempty(allFiles)
        error('No sub*_*.mat files found in %s', root_data);
    end
    allNames   = {allFiles.name};
    subjTokens = regexp(allNames, '^(sub\d+)_', 'tokens', 'once');
    subjTokens = subjTokens(~cellfun(@isempty, subjTokens));
    if isempty(subjTokens)
        error('Could not parse subject IDs from file names in %s', root_data);
    end
    subjList = unique(cellfun(@(c)c{1}, subjTokens, 'UniformOutput', false));
    fprintf('Auto-detected %d subject(s) for dataset "%s":\n', numel(subjList), whichDataset);
    disp(subjList(:));
else
    subjList = {subject_id};
end

%% ------------------------------------------------------------------------
%  LOOP OVER SUBJECTS
% -------------------------------------------------------------------------

for iSub = 1:numel(subjList)

    subject_id = subjList{iSub};
    fprintf('\n============================================================\n');
    fprintf('Processing subject: %s  (%d of %d)  | dataset: %s\n', ...
        subject_id, iSub, numel(subjList), whichDataset);
    fprintf('------------------------------------------------------------\n');

    %% Find files for this subject
    allFiles = dir(fullfile(root_data, sprintf('%s_*.mat', subject_id)));
    keepIdx  = ~contains({allFiles.name}, '_stair.mat') & ...
               ~contains({allFiles.name}, '_thresh.mat') & ...
               ~contains({allFiles.name}, '_behav.mat');
    files = allFiles(keepIdx);
    if isempty(files)
        warning('No files found for %s in %s. Skipping subject.', subject_id, root_data);
        continue;
    end

    % Filter by p.exptName
    keepIdx = false(numel(files),1);
    for i = 1:numel(files)
        fname = fullfile(root_data, files(i).name);
        try
            S = load(fname, 'p');
        catch
            warning('Could not load %s. Skipping.', files(i).name);
            continue;
        end
        if ~isfield(S, 'p'), continue; end
        if isfield(S.p, 'exptName') && ismember(S.p.exptName, exptNameList)
            keepIdx(i) = true;
        end
    end

    files = files(keepIdx);
    if isempty(files)
        warning('No %s files for %s in %s. Skipping subject.', ...
            whichDataset, subject_id, root_data);
        continue;
    end

    [~, idx] = sort({files.name});
    files    = files(idx);

    fprintf('Concatenating %s data for %s\n', whichDataset, subject_id);
    fprintf('Found %d run file(s):\n', numel(files));
    for i = 1:numel(files)
        fprintf('  %2d: %s\n', i, files(i).name);
    end

    %% Init concatenation structs
    catData = struct();
    for k = 1:numel(fieldsToConcat)
        catData.(fieldsToConcat{k}) = [];
    end

    session_all   = [];
    run_all       = [];
    trialNum_all  = [];
    fileIndex_all = [];
    fileList      = {files.name}';

    %% Loop over files
    for f = 1:numel(files)
        fname = fullfile(root_data, files(f).name);
        try
            S = load(fname, 'p');
        catch
            warning('File %s could not be loaded. Skipping.', files(f).name);
            continue;
        end

        if ~isfield(S, 'p')
            warning('File %s has no variable p. Skipping.', files(f).name);
            continue;
        end

        p = S.p;

        if ~isfield(p, 'resp')
            warning('File %s missing p.resp; cannot determine trial count. Skipping.', files(f).name);
            continue;
        end

        nT = numel(p.resp);
        fprintf('  Concatenating file %s (%d trials)\n', files(f).name, nT);

        for k = 1:numel(fieldsToConcat)
            fld = fieldsToConcat{k};

            if isfield(p, fld)
                thisVec = p.(fld)(:);

                % Scalar fields (e.g., attnCond = 2 in thresholding) ->
                % replicate to full trial length
                if numel(thisVec) == 1 && nT > 1
                    thisVec = repmat(thisVec, nT, 1);
                end

                if numel(thisVec) ~= nT
                    error('Field %s in %s has length %d, expected %d.', ...
                        fld, files(f).name, numel(thisVec), nT);
                end
            else
                % Field absent in this script -> fill with NaN
                thisVec = nan(nT, 1);
            end

            catData.(fld) = [catData.(fld); thisVec];
        end

        if isfield(p, 'sessionNum')
            session_all = [session_all; repmat(p.sessionNum, nT, 1)];
        else
            session_all = [session_all; nan(nT, 1)];
        end

        if isfield(p, 'runNum')
            run_all = [run_all; repmat(p.runNum, nT, 1)];
        else
            run_all = [run_all; nan(nT, 1)];
        end

        trialNum_all  = [trialNum_all;  (1:nT)'];
        fileIndex_all = [fileIndex_all; repmat(f, nT, 1)];
    end

    if isempty(catData.resp)
        warning('No valid trials concatenated for %s (%s). Skipping save.', ...
            subject_id, whichDataset);
        continue;
    end

    nTotal = numel(catData.resp);
    fprintf('Done. Total concatenated trials for %s (%s): %d\n', ...
        subject_id, whichDataset, nTotal);

    %% Expose concatenated vectors with _all suffix
    for k = 1:numel(fieldsToConcat)
        fld     = fieldsToConcat{k};
        varname = [fld '_all'];
        eval([varname ' = catData.(fld);']);
    end

    %% Save
    outFile = fullfile(root_data, ...
        sprintf('%s_%s_behav.mat', subject_id, exptNameOut));

    save(outFile, ...
        'subject_id', 'whichDataset', 'exptNameOut', 'fileList', ...
        'session_all', 'run_all', 'trialNum_all', 'fileIndex_all', ...
        'cohLevel_all', ...
        'stimDir_all', ...
        'stimDir1_all', 'stimDir2_all', ...
        'targSide_all', 'distSide_all', ...
        'preCueSide_all', 'validity_all', ...
        'attnCond_all', ...
        'resp_all', 'correct_all', 'RT_all', ...
        'trialStart_all', 'ITI_all');

    fprintf('Saved concatenated %s data for %s to:\n  %s\n', ...
        whichDataset, subject_id, outFile);

end % loop over subjects

fprintf('\nAll done for dataset "%s".\n', whichDataset);