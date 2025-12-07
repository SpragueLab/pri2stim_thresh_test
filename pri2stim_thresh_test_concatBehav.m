% pri2stim_thresh_test_concatBehav.m
%
% Concatenate behavioral data across runs for a single subject.
% Works for BOTH:
%   - pri2stim_testing      (in ./data/testing)
%   - pri2stim_thresholding (in ./data/thresholding)  [name adjustable]
%
% Select which dataset at the top (testing vs thresholding).
%
% AHH 2025

clear;

%% ------------------------------------------------------------------------
%  USER SETTINGS
% -------------------------------------------------------------------------

subject_id   = 'sub001';        % <-- change to subject you want
whichDataset = 'thresholding';       % 'testing' or 'thresholding'
% whichDataset = 'testing';       % 'testing' or 'thresholding'


% These MUST match p.exptName in your respective scripts
exptName_testing    = 'pri2stim_testing';
exptName_threshold  = 'pri2stim_thresholding';  % <--- adjust to your threshold script's p.exptName

%% ------------------------------------------------------------------------
%  CHOOSE DATASET-SPECIFIC SETTINGS
% -------------------------------------------------------------------------

tmpf = mfilename('fullpath');
tmpi = strfind(tmpf, filesep);
root = tmpf(1:tmpi(end));   % folder where THIS script lives

switch lower(whichDataset)
    case 'testing'
        exptName   = exptName_testing;
        dataSubdir = 'testing';
    case 'thresholding'
        exptName   = exptName_threshold;
        dataSubdir = 'thresholding';
    otherwise
        error('whichDataset must be ''testing'' or ''thresholding''.');
end

root_data = fullfile(root, 'data', dataSubdir);

if ~isfolder(root_data)
    error('Data directory not found: %s', root_data);
end

% Files are assumed to look like:
%   subXXX_exptName_sess##_run##_TIMESTAMP.mat
pattern = sprintf('%s_%s_sess*_run*_*.mat', subject_id, exptName);
files   = dir(fullfile(root_data, pattern));

if isempty(files)
    error('No %s files found for %s with pattern: %s', ...
        whichDataset, subject_id, pattern);
end

% Sort by name so sessions/runs are in a stable order
[~, idx] = sort({files.name});
files    = files(idx);

fprintf('Concatenating %s data for %s\n', whichDataset, subject_id);
fprintf('Found %d run file(s):\n', numel(files));
for i = 1:numel(files)
    fprintf('  %2d: %s\n', i, files(i).name);
end

%% ------------------------------------------------------------------------
%  FIELDS TO CONCATENATE
% -------------------------------------------------------------------------
% We define a list of behavioral fields we *try* to grab.
% If a field is missing in a given file (e.g., thresholding might not have
% some attention fields), we fill with NaNs for that run.

fieldsToConcat = { ...
    'attnCond', ...     % 1=neutral,2=valid,3=invalid  (testing)
    'cohLevel', ...
    'stimDir1', ...
    'stimDir2', ...
    'preCueSide', ...
    'postCueSide', ...
    'validity', ...
    'contrast', ...
    'resp', ...
    'correct', ...
    'RT', ...
    'trialStart', ...
    'ITI' ...
};

% Initialize containers
catData = struct();
for k = 1:numel(fieldsToConcat)
    catData.(fieldsToConcat{k}) = [];
end

session_all   = [];
run_all       = [];
trialNum_all  = [];
fileIndex_all = [];

fileList = {files.name}';

%% ------------------------------------------------------------------------
%  LOOP OVER FILES AND CONCATENATE
% -------------------------------------------------------------------------

for f = 1:numel(files)
    fname = fullfile(root_data, files(f).name);
    S = load(fname, 'p');
    
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
    
    % For each field, either grab data or fill with NaNs
    for k = 1:numel(fieldsToConcat)
        fld = fieldsToConcat{k};
        
        if isfield(p, fld)
            thisVec = p.(fld)(:);
            if numel(thisVec) ~= nT
                error('Field %s in file %s has length %d, expected %d', ...
                    fld, files(f).name, numel(thisVec), nT);
            end
        else
            thisVec = nan(nT,1);
        end
        
        catData.(fld) = [catData.(fld); thisVec];
    end
    
    % Session / run / trial indices
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

% Number of concatenated trials (based on resp)
if isfield(catData, 'resp')
    nTotal = numel(catData.resp);
else
    nTotal = numel(trialNum_all);
end

fprintf('Done. Total concatenated trials for %s (%s): %d\n', ...
    subject_id, whichDataset, nTotal);

%% ------------------------------------------------------------------------
%  EXPOSE CONCATENATED VECTORS WITH _all SUFFIX
% -------------------------------------------------------------------------

for k = 1:numel(fieldsToConcat)
    fld     = fieldsToConcat{k};
    varname = [fld '_all'];
    eval([varname ' = catData.(fld);']);
end

%% ------------------------------------------------------------------------
%  SAVE OUTPUT
% -------------------------------------------------------------------------

% Example:
%   subXXX_pri2stim_testing_behav.mat
%   subXXX_pri2stim_thresholding_behav.mat
outFile = fullfile(root_data, ...
    sprintf('%s_%s_behav.mat', subject_id, exptName));

save(outFile, ...
    'subject_id', 'whichDataset', 'exptName', 'fileList', ...
    'session_all', 'run_all', 'trialNum_all', 'fileIndex_all', ...
    'attnCond_all', 'cohLevel_all', 'stimDir1_all', 'stimDir2_all', ...
    'preCueSide_all', 'postCueSide_all', 'validity_all', ...
    'contrast_all', 'resp_all', 'correct_all', 'RT_all', ...
    'trialStart_all', 'ITI_all');

fprintf('Saved concatenated %s data to:\n  %s\n', whichDataset, outFile);
