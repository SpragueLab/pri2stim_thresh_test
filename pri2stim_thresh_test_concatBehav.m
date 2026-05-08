% pri2stim_thresh_test_concatBehav.m
%
% Concatenate behavioral data across runs for one or more subjects.
%
% Works with:
%   - pri2stim_testing.m       -> p.exptName = 'pri2stimEEG_testing'
%                                saved in Z:\projects\pri2stim_thresh_test\testing
%
%   - pri2stim_thresholding.m  -> p.exptName = 'pri2stimEEG_threshold'
%                                or 'pri2stimEEG_threshold_practice'
%                                saved in Z:\projects\pri2stim_thresh_test\thresholding
%
% You choose which dataset via "whichDataset" below:
%   'testing'
%   'threshold'
%   'threshold_practice'
%
% You can:
%   - Set subject_id = 'sub003'  -> single subject
%   - Set subject_id = 'ALL'     -> auto-detect all subjects in that dataset folder
%
% Output: one *_behav.mat per dataset type per subject.
%
% AHH 2025 (concat script adapted, batch-capable)

clear;

%% ------------------------------------------------------------------------
%  USER SETTINGS
% -------------------------------------------------------------------------

% Either a specific subject (e.g., 'sub003') OR 'ALL' to process every subject
% for this dataset found in the data directory.
subject_id   = 'ALL';          % <-- change this if you want just one subject

% Options:
%   'testing'
%   'threshold'
%   'threshold_practice'
whichDataset = 'testing';
% whichDataset = 'threshold';


%% ------------------------------------------------------------------------
%  PATHS AND EXPT NAMES (MUST MATCH YOUR SCRIPTS)
% -------------------------------------------------------------------------

% Base project directory on Z:
baseDir = 'Z:\projects\pri2stim_thresh_test';

switch lower(whichDataset)
    case 'testing'
        dataSubdir   = 'testing';
        exptNameList = {'pri2stimEEG_testing'};
    case 'threshold'
        dataSubdir   = 'thresholding';
        exptNameList = {'pri2stimEEG_threshold'};  % real thresholding only
    case 'threshold_practice'
        dataSubdir   = 'thresholding';
        exptNameList = {'pri2stimEEG_threshold_practice'}; % practice only
    otherwise
        error('whichDataset must be ''testing'', ''threshold'', or ''threshold_practice''.');
end

root_data = fullfile(baseDir, dataSubdir);
if ~isfolder(root_data)
    error('Data directory not found: %s', root_data);
end

%% ------------------------------------------------------------------------
%  DETERMINE SUBJECT LIST
% -------------------------------------------------------------------------

if strcmpi(subject_id, 'ALL')
    % Auto-detect all subjects with files matching subXXX_*.mat
    allFiles = dir(fullfile(root_data, 'sub*_*.mat'));
    if isempty(allFiles)
        error('No sub*_*.mat files found in %s', root_data);
    end

    allNames = {allFiles.name};
    % Extract "subXXX" from the prefix of each file name
    subjTokens = regexp(allNames, '^(sub\d+)_', 'tokens', 'once');
    subjTokens = subjTokens(~cellfun(@isempty, subjTokens));

    if isempty(subjTokens)
        error('Could not parse subject IDs from file names in %s', root_data);
    end

    subjList = unique(cellfun(@(c)c{1}, subjTokens, 'UniformOutput', false));
    fprintf('Auto-detected %d subject(s) for dataset "%s":\n', numel(subjList), whichDataset);
    disp(subjList(:));
else
    % Single subject mode: wrap in a cell array for unified loop
    subjList = {subject_id};
end

%% ------------------------------------------------------------------------
%  FIELDS TO CONCATENATE (TRIAL-LEVEL)
% -------------------------------------------------------------------------

fieldsToConcat = { ...
    'attnCond', ...     % testing: vector; thresholding: scalar (=2)
    'cohLevel', ...
    'stimDir1', ...
    'stimDir2', ...
    'preCueSide', ...   % testing only
    'postCueSide', ...
    'validity', ...     % testing only
    'contrast', ...     % testing only; thresholding is fixed 0.8
    'resp', ...
    'correct', ...
    'RT', ...
    'trialStart', ...
    'ITI' ...
};

%% ------------------------------------------------------------------------
%  LOOP OVER SUBJECTS
% -------------------------------------------------------------------------

for iSub = 1:numel(subjList)

    subject_id = subjList{iSub};
    fprintf('\n============================================================\n');
    fprintf('Processing subject: %s  (%d of %d)  | dataset: %s\n', ...
        subject_id, iSub, numel(subjList), whichDataset);
    fprintf('------------------------------------------------------------\n');

    %% --------------------------------------------------------------------
    %  FIND FILES FOR THIS SUBJECT / DATASET
    % ---------------------------------------------------------------------

    allFiles = dir(fullfile(root_data, sprintf('%s_*.mat', subject_id)));
    % Exclude staircase state and threshold estimate files
    keepIdx = ~contains({allFiles.name}, '_stair.mat') & ...
        ~contains({allFiles.name}, '_thresh.mat') & ...
        ~contains({allFiles.name}, '_behav.mat');  % also skip existing behav files
    files = allFiles(keepIdx);
    if isempty(files)
        warning('No files found for %s in %s. Skipping subject.', subject_id, root_data);
        continue;
    end

    % Filter by exptName inside p.exptName
    keepIdx = false(numel(files),1);
    for i = 1:numel(files)
        fname = fullfile(root_data, files(i).name);
        try
            S = load(fname, 'p');
        catch
            warning('Could not load %s. Skipping this file.', fname);
            continue;
        end

        if ~isfield(S, 'p'), continue; end
        if isfield(S.p, 'exptName') && ismember(S.p.exptName, exptNameList)
            keepIdx(i) = true;
        end
    end

    files = files(keepIdx);
    if isempty(files)
        warning('No %s files with exptName in %s for %s. Skipping subject.', ...
            whichDataset, strjoin(exptNameList, ', '), subject_id);
        continue;
    end

    [~, idx] = sort({files.name});
    files    = files(idx);

    fprintf('Concatenating %s data for %s\n', whichDataset, subject_id);
    fprintf('Found %d run file(s):\n', numel(files));
    for i = 1:numel(files)
        fprintf('  %2d: %s\n', i, files(i).name);
    end

    %% --------------------------------------------------------------------
    %  INIT CONCATENATION STRUCTS FOR THIS SUBJECT
    % ---------------------------------------------------------------------

    catData = struct();
    for k = 1:numel(fieldsToConcat)
        catData.(fieldsToConcat{k}) = [];
    end

    session_all   = [];
    run_all       = [];
    trialNum_all  = [];
    fileIndex_all = [];

    fileList = {files.name}';

    %% --------------------------------------------------------------------
    %  LOOP OVER FILES AND CONCATENATE
    % ---------------------------------------------------------------------

    for f = 1:numel(files)
        fname = fullfile(root_data, files(f).name);

        try
            S = load(fname, 'p');
        catch
            warning('File %s could not be loaded. Skipping.', files(f).name);
            continue;
        end

        if ~isfield(S, 'p')
            warning('File %s does not contain variable p. Skipping.', files(f).name);
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
                thisVec = p.(fld)(:);  % column

                % Scalar fields (e.g., attnCond = 2) -> replicate per trial
                if numel(thisVec) == 1 && nT > 1
                    thisVec = repmat(thisVec, nT, 1);
                end

                if numel(thisVec) ~= nT
                    error('Field %s in file %s has length %d, expected %d', ...
                        fld, files(f).name, numel(thisVec), nT);
                end
            else
                thisVec = nan(nT,1);
            end

            catData.(fld) = [catData.(fld); thisVec];
        end

        if isfield(p, 'sessionNum')
            session_all = [session_all; repmat(p.sessionNum, nT, 1)];
        else
            session_all = [session_all; nan(nT,1)];
        end

        if isfield(p, 'runNum')
            run_all = [run_all; repmat(p.runNum, nT, 1)];
        else
            run_all = [run_all; nan(nT,1)];
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

    %% --------------------------------------------------------------------
    %  EXPOSE CONCATENATED VECTORS WITH _all SUFFIX
    % ---------------------------------------------------------------------

    for k = 1:numel(fieldsToConcat)
        fld     = fieldsToConcat{k};
        varname = [fld '_all'];
        eval([varname ' = catData.(fld);']);
    end

    %% --------------------------------------------------------------------
    %  SAVE OUTPUT FOR THIS SUBJECT
    % ---------------------------------------------------------------------

    switch lower(whichDataset)
        case 'testing'
            exptNameOut = 'pri2stimEEG_testing';
        case 'threshold'
            exptNameOut = 'pri2stimEEG_threshold';
        case 'threshold_practice'
            exptNameOut = 'pri2stimEEG_threshold_practice';
    end

    outFile = fullfile(root_data, ...
        sprintf('%s_%s_behav.mat', subject_id, exptNameOut));

    save(outFile, ...
        'subject_id', 'whichDataset', 'exptNameOut', 'fileList', ...
        'session_all', 'run_all', 'trialNum_all', 'fileIndex_all', ...
        'attnCond_all', 'cohLevel_all', 'stimDir1_all', 'stimDir2_all', ...
        'preCueSide_all', 'postCueSide_all', 'validity_all', ...
        'contrast_all', 'resp_all', 'correct_all', 'RT_all', ...
        'trialStart_all', 'ITI_all');

    fprintf('Saved concatenated %s data for %s to:\n  %s\n', ...
        whichDataset, subject_id, outFile);

end % loop over subjects

fprintf('\nAll done for dataset "%s".\n', whichDataset);
