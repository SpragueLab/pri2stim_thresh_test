% pri2stim_testing_noPostCue.m
%
% Psychophysics version of pri2stimEEG_static: testing phase, single-target variant.
% Uses coherence threshold estimated by pri2stim_thresholding +
% pri2stim_computeThreshold.
%
% QUESTION: how does focal vs. distributed attention modulate spiral
% direction discrimination at threshold coherence, when only one target
% is present per trial?
%
% STIMULUS: briefly present 2 stimuli (100ms) at left/right of screen.
%   - Target side: coherent spiral at threshold coherence
%   - Distractor side: pure noise (coh = 0)
% Attention cued as neutral (20%), valid (60%), or invalid (20%) across
% trials. No postcue: response window opens at stimulus onset.
%
% TRIAL STRUCTURE (per trial):
%   fixation (300ms) -> precue (250ms) -> stimulus + response (self-paced)
%   -> feedback (200ms) -> ITI (1250-1500ms)
%
% adapted from pri2stim_testing.m
%
% RESPONSE:
% - which direction did the target spiral cohere? (1: CCW, 2: CW)
%   respond any time from stimulus onset onward (self-paced)
%
% AHH 5/2026


function pri2stim_testing_noPostCue
try

    KbName('UnifyKeyNames');

    tmpf = mfilename('fullpath');
    tmpi = strfind(tmpf,filesep);
    % folder where the script lives
    p.root = tmpf(1:tmpi(end));

    % data directories
    p.root_data_test   = fullfile(p.root, 'data', 'testing_noPostCue');
    p.root_data_thresh = fullfile(p.root, 'data', 'thresholding');

    % create directories if needed
    if ~isfolder(p.root_data_test)
        mkdir(p.root_data_test);
    end

    mywhite = [255 255 255];

    warning('off','MATLAB:dispatcher:InexactMatch');

    %-----------------------------
    % INPUT DIALOG
    %-----------------------------
    % Threshold coherence = 0  --> load from threshold file produced by
    % pri2stim_computeThreshold
    prompt = {'Subject Name','Session number','Run Number', ...
        'Threshold coherence (0 = load from file)', ...
        'display (1=EEG, 2=behav, 3=workstation)', ...
        'Eye tracking','Random seed', ...
        'Number of trials (testing)'};

    s = round(sum(100*clock));
    defAns = {'subXXX','1','X','0','3','0',num2str(s),'60'};
    box = inputdlg(prompt,'Enter Subject Information...', 1, defAns);

    if length(box)==length(defAns)
        p.subName        = char(box{1});
        p.sessionNum     = str2double(box{2});
        p.runNum         = eval(box{3});
        targCoh_in       = str2double(box{4});  % may be 0 --> auto-load
        p.display        = str2double(box{5});
        p.eyeTracking    = str2double(box{6});
        p.rndSeed        = str2double(box{7});
        p.nTrials        = str2double(box{8});
        rng(p.rndSeed);
    else
        return
    end

    % Experiment name
    p.exptName = 'pri2stimEEG_testing_noPostCue';

    %-----------------------------
    % LOAD / SET TARGET COHERENCE
    %-----------------------------
    if isnan(targCoh_in) || targCoh_in <= 0
        exptThreshName = 'pri2stimEEG_threshold_noPostCue';
        threshFile = fullfile(p.root_data_thresh, ...
            sprintf('%s_%s_sess%02d_thresh.mat', ...
            p.subName, exptThreshName, p.sessionNum));

        if ~exist(threshFile, 'file')
            error(['Threshold file not found: %s\n' ...
                'Run pri2stim_thresholding and pri2stim_computeThreshold first, ' ...
                'or enter a manual threshold > 0.'], threshFile);
        end

        S = load(threshFile);

        if ~isfield(S,'cohThresh')
            error('Threshold file %s does not contain variable "cohThresh".', threshFile);
        end

        p.targCoh = S.cohThresh;

        if isfield(S,'threshMethodUsed')
            p.threshMethodUsed = S.threshMethodUsed;
        else
            p.threshMethodUsed = 'unknown';
        end

        fprintf('Loaded threshold coherence from %s: %.4f (method: %s)\n', ...
            threshFile, p.targCoh, p.threshMethodUsed);

    else
        % manual override
        p.targCoh          = targCoh_in;
        p.threshMethodUsed = 'manual';
        fprintf('Using MANUAL target coherence: %.4f\n', p.targCoh);
    end

    %-----------------------------
    % ATTENTION CONDITIONS
    %-----------------------------
    % attnCond codes:
    %   1 = neutral / distributed
    %   2 = focal valid
    %   3 = focal invalid
    %
    % Desired proportions across ALL trials:
    %   60% focal valid
    %   20% focal invalid
    %   20% neutral (distributed)

    p.propValid   = 0.60;
    p.propInvalid = 0.20;
    p.propNeutral = 0.20;

    % Compute counts (ensure they sum exactly to p.nTrials)
    nValid   = round(p.propValid   * p.nTrials);
    nInvalid = round(p.propInvalid * p.nTrials);
    nNeutral = p.nTrials - nValid - nInvalid;  % remainder goes to neutral

    % Build condition vector
    condVec = [ ...
        1 * ones(nNeutral,1); ...  % neutral / distributed
        2 * ones(nValid,1);   ...  % focal valid
        3 * ones(nInvalid,1)];     % focal invalid

    % Randomize trial order
    condVec    = condVec(randperm(numel(condVec)));
    p.attnCond = condVec(:);

    % block structure (for breaks)
    p.blockSize = p.nTrials;
    p.nBlocks   = ceil(p.nTrials/p.blockSize);

    %-----------------------------
    % MONITOR / DISPLAY SETUP
    %-----------------------------
    if p.display == 1  % EEG room
        p.vDistCM       = 100;
        p.screenWidthCM = 60;
        p.minITI        = 1.25;
        p.maxITI        = 1.50;
        p.fMRI          = 0;
        p.fullScr       = 1;
        p.resolution    = [1920 1080];
        p.refreshRate   = 240;
        p.LUTfn         = 1:256;
    elseif p.display == 2 % behavioral room (AZ)
        p.vDistCM       = 54.5;
        p.screenWidthCM = 52.5;
        p.minITI        = 1.25;
        p.maxITI        = 1.50;
        p.resolution    = [2560 1440];
        p.refreshRate   = 120;
        p.fMRI          = 0;
        p.fullScr       = 1;
        p.LUTfn         = 1:256;
    else
        % workstation default
        p.vDistCM       = 62;
        p.screenWidthCM = 51;
        p.minITI        = 1.25;
        p.maxITI        = 1.50;
        p.resolution    = [2560 1440];
        p.refreshRate   = 60;
        p.fMRI          = 0;
        p.fullScr       = 1;
        p.eyeTracking   = 0;
        p.LUTfn         = 1:256;
    end

    p.LUT   = 1:256;
    p.sRect = [0 0 p.resolution];

    %-----------------------------
    % FONT / KEY SETTINGS
    %-----------------------------
    p.fontSize  = 24;
    p.fontName  = 'ARIAL';
    p.textColor = [100, 100, 100];

    if ismac
        p.escape = 41;
    else
        p.escape = 27;
    end

    % Explicit key mappings
    p.key1  = KbName('1!');
    p.key2  = KbName('2@');
    p.space = KbName('space');
    p.start = p.space;

    p.keys  = [p.key1, p.key2];

    %-----------------------------
    % COLORS & STIM PROPERTIES
    %-----------------------------
    p.backColorIdeal     = [128, 128, 128];
    p.fixColorIdeal      = [65 65 65];
    p.fixSizeDeg         = 0.33;
    p.fixSizeInnerDeg    = 0.04;

    p.fixLineWidth       = 2;
    p.fixPlusSizeDeg     = 0.15;

    p.lineSizeDeg        = 0.65;
    p.nLines             = 350;
    p.lineWidthDeg       = 0.075;
    p.stimSizeDeg        = 4.0;

    p.fixVerticalOffset  = 5;
    p.fixPosDeg          = [0 p.fixVerticalOffset];
    p.stimPosDeg         = [-8 -8; 8 -8];
    p.eccDeg             = sqrt(sum(p.stimPosDeg.^2,2));

    p.cueSizeDeg         = 0.55;
    p.targOriOffset      = 45;

    % Contrast: fixed at 80%
    p.lineContrast       = 0.8;

    templateRGB = [-1 1];
    thisRGB = (round(127*templateRGB*p.lineContrast)+1)+127;
    p.stimRGB = round(p.LUT(thisRGB));
    clear templateRGB thisRGB;

    p.textColor = round(p.LUT(p.textColor))';
    p.fixColor  = round(p.LUT(p.fixColorIdeal))';
    p.backColor = round(p.LUT(p.backColorIdeal))';

    %-----------------------------
    % TIMING
    %-----------------------------
    p.fixDur        = 0.300;  % s
    p.preCueDur     = 0.250;  % precue
    p.preISIDur     = 0.250;  % ISI between precue and stim
    % NOTE: no postcue or postISI in this version.
    % Response window opens at stimulus onset and remains open until
    % a key is pressed (self-paced). The stimulus is drawn for stimDur,
    % then fixation is held while we continue waiting for a response.
    p.stimDur       = 0.100;  % stimulus epoch
    p.feedbackDur   = 0.200;  % feedback
    p.ITI           = rand(p.nTrials,1)*(p.maxITI-p.minITI)+p.minITI;
    p.startWait     = 0.75;

    %-----------------------------
    % CONVERT DEGREES TO PIXELS
    %-----------------------------
    p = deg2pix(p);

    % fixation location
    fixcenter = [p.resolution(1)/2, (p.resolution(2)/2 - p.ppd*p.fixVerticalOffset)];

    %-----------------------------
    % FILE SETUP
    %-----------------------------
    p.dateTime = datestr(now,30);
    fName = sprintf('%s/%s_%s_sess%02.f_run%02.f_%s.mat', ...
        p.root_data_test, p.subName, p.exptName, p.sessionNum, p.runNum, p.dateTime);

    if exist(fName,'file')
        msgbox('File name already exists, please specify another','modal');
        return
    end

    if p.eyeTracking == 1
        p.eyedatafile = sprintf('s%s_r%01.f',p.subName(4:6),p.runNum);
    end

    p.edfTarget = [fName(1:end-3) 'edf'];

    %-----------------------------
    % OPEN SCREEN
    %-----------------------------
    AssertOpenGL;
    s = max(Screen('Screens'));
    p.black = BlackIndex(s);
    p.white = WhiteIndex(s);

    [w, p.sRect] = Screen('OpenWindow', s, p.black);
    HideCursor;

    % gamma table
    if p.display == 1
        which_gt = load(sprintf('%s/../gammatables/gammatable_EEG1_2020-03-03.mat',p.root));
        new_gt  = which_gt.gammaTable1;
    elseif p.display == 2
        which_gt = load(sprintf('%s/../gammatables/gammatable_AZ_2020-01-21.mat',p.root));
        new_gt  = which_gt.gammaTable1;
    else
        new_gt = linspace(0,1,256);
    end
    p.gamma_table_orig = Screen('LoadNormalizedGammaTable',w,new_gt(:)*[1 1 1]);

    Screen('BlendFunction', w, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    p.fps = Screen('FrameRate',w);
    p.ifi = Screen('GetFlipInterval', w);
    if p.fps == 0
        p.fps = 1/p.ifi;
    end
    if abs(p.fps-p.refreshRate) > 5
        Screen('LoadNormalizedGammaTable', w, p.gamma_table_orig);
        Screen('CloseAll');
        disp('CHANGE YOUR REFRESH RATE');
        ListenChar(0); ShowCursor;
        clear all;
        return
    end

    if p.resolution(1)~=p.sRect(3) || p.resolution(2)~=p.sRect(4)
        Screen('LoadNormalizedGammaTable', w, p.gamma_table_orig);
        Screen('CloseAll');
        fprintf('CHANGE YOUR RESOLUTION (%i x %i)\n',p.resolution(1),p.resolution(2));
        ListenChar(0); ShowCursor;
        clear all;
        return
    end

    Screen('TextSize', w, p.fontSize);
    Screen('TextStyle', w, 1);
    Screen('TextFont', w, p.fontName);
    Screen('TextColor', w, p.textColor);

    ListenChar(2);
    HideCursor;
    Priority(MaxPriority(w));

    %-----------------------------
    % EYETRACKER SETUP (optional)
    %-----------------------------
    el = [];
    if p.eyeTracking == 1
        try
            fprintf('Trying eyetracking\n');

            el = EyelinkInitDefaults(w);

            el.backgroundcolour        = p.backColor(1);
            el.calibrationtargetcolour = p.fixColor(1);
            el.msgfontcolour           = p.fixColor(1);
            EyelinkUpdateDefaults(el);

            statusInit = Eyelink('Initialize', 'PsychEyelinkDispatchCallback');
            if statusInit ~= 0
                error('Eyelink initialization failed (status %d).', statusInit);
            end

            Eyelink('command','calibration_type=HV9');
            Eyelink('command','link_sample_data = LEFT,RIGHT,GAZE,AREA');
            Eyelink('command','sample_rate = 1000');
            Eyelink('command','screen_pixel_coords = %ld %ld %ld %ld', ...
                0, 0, p.sRect(3)-1, p.sRect(4)-1);
            Eyelink('message','DISPLAY_COORDS %ld %ld %ld %ld', ...
                0, 0, p.sRect(3)-1, p.sRect(4)-1);

            if (p.sRect(3)==2560 && p.sRect(4)==1440) || (p.sRect(3)==1920 && p.sRect(4)==1080)
                Eyelink('command', 'calibration_area_proportion 0.59 0.83');
            end

            EyelinkDoTrackerSetup(el);
            Eyelink('openfile', p.eyedatafile);

        catch ME
            warning('Eyelink setup failed: Continuing without eye tracking.');
            p.eyeTracking = 0;
            try
                Eyelink('Shutdown');
            catch
            end
        end
    end

    %-----------------------------
    % START SCREEN + INSTRUCTIONS
    %-----------------------------
    showInstructionScreen(w,p,fixcenter);

    while true
        [resp, ~] = checkForResp([p.space], p.escape);
        if resp == p.space
            break;
        elseif resp == -1
            p.aborted = 1;
            save(fName,'p');
            cleanupAndExit(w,p); return;
        end
    end

    % brief fixation-only period before first trial
    p.startExp = GetSecs;
    while GetSecs < (p.startExp + p.startWait)
        [resp, ~] = checkForResp([],p.escape);
        if resp == -1
            cleanupAndExit(w,p); return;
        end
        drawFixation(w,p,fixcenter);
        Screen('Flip', w);
    end

    %-----------------------------
    % START EYELINK RECORDING
    %-----------------------------
    if p.eyeTracking == 1
        try
            Eyelink('Message','EXPT_START TESTING_NOPOSTCUE');
            Eyelink('Message','xDAT %i',10);
            Eyelink('StartRecording');
            p.eye_used = Eyelink('EyeAvailable');
            if p.eye_used == el.BINOCULAR
                p.eye_used = el.RIGHT_EYE;
            end
            WaitSecs(0.05);
        catch ME
            warning('Eyelink StartRecording failed: Disabling eye tracking.');
            p.eyeTracking = 0;
            try
                Eyelink('Shutdown');
            catch
            end
        end
    end

    %-----------------------------
    % PREALLOCATE TRIAL VECTORS
    %-----------------------------
    p.cohLevel    = nan(p.nTrials,1);
    p.targSide    = nan(p.nTrials,1); % 1=left, 2=right (where coherent target appears)
    p.distSide    = nan(p.nTrials,1); % 1=left, 2=right (noise side; always 3-targSide)
    p.stimDir     = nan(p.nTrials,1); % -1=CCW, +1=CW direction of target
    p.correctResp = nan(p.nTrials,1); % correct key: 1 (CW) or 2 (CCW)
    p.preCueSide  = nan(p.nTrials,1); % 1=left, 2=right, NaN for neutral
    p.validity    = nan(p.nTrials,1); % 1=valid, 0=invalid, NaN for neutral
    p.resp        = nan(p.nTrials,1);
    p.correct     = nan(p.nTrials,1);
    p.RT          = nan(p.nTrials,1); % measured from stimulus onset
    p.tPreCueOn   = nan(p.nTrials,1); % absolute timestamp of precue onset
    p.tStimOn     = nan(p.nTrials,1); % absolute timestamp of stimulus onset
    p.trialStart  = nan(p.nTrials,1);
    p.aborted     = 0;

    save(fName,'p');

    %-----------------------------
    % TRIAL LOOP
    %-----------------------------
    for t = 1:p.nTrials
        p.trialStart(t) = GetSecs;

        if p.eyeTracking == 1
            Eyelink('Message', 'TRIALID %d', t);
            Eyelink('Message', 'TRIAL_START %d', t);
            Eyelink('Message','xDAT %i',1);
        end

        % --- coherence (fixed threshold) ---
        thisCoh       = p.targCoh;
        p.cohLevel(t) = thisCoh;

        % --- target direction (random per trial) ---
        p.stimDir(t) = randsample([-1 1],1);

        % --- target side and precue, depending on attention condition ---
        cond = p.attnCond(t);

        if cond == 1
            % neutral: both sides cued, target side random
            p.targSide(t)   = randi([1 2]);
            p.preCueSide(t) = NaN;
            p.validity(t)   = NaN;
        elseif cond == 2
            % focal valid: precue correctly indicates target side
            p.targSide(t)   = randi([1 2]);
            p.preCueSide(t) = p.targSide(t);
            p.validity(t)   = 1;
        else
            % focal invalid: precue points to the distractor side
            p.targSide(t)   = randi([1 2]);
            p.preCueSide(t) = 3 - p.targSide(t);  % opposite side
            p.validity(t)   = 0;
        end

        % Distractor side is always the non-target side
        p.distSide(t) = 3 - p.targSide(t);

        % Correct response: CW (+1) -> key 1; CCW (-1) -> key 2
        if p.stimDir(t) == 1
            p.correctResp(t) = 1;
        else
            p.correctResp(t) = 2;
        end

        % Assign coherence per side:
        %   target side gets threshold coherence + the chosen direction
        %   distractor side gets coh=0 (pure noise), direction irrelevant
        if p.targSide(t) == 1
            coh1 = thisCoh;  dir1 = p.stimDir(t);
            coh2 = 0;        dir2 = 1;  % direction unused at coh=0
        else
            coh1 = 0;        dir1 = 1;  % direction unused at coh=0
            coh2 = thisCoh;  dir2 = p.stimDir(t);
        end

        %----------------- FIXATION -----------------
        if p.eyeTracking == 1
            Eyelink('Message', 'FIX_ON %d', t);
            Eyelink('Message','xDAT %i',2);
        end

        tFixOn = GetSecs;
        while GetSecs < tFixOn + p.fixDur
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            drawFixation(w,p,fixcenter);
            Screen('Flip',w);
        end

        %----------------- PRE-CUE -----------------
        if p.eyeTracking == 1
            Eyelink('Message', 'PRECUE_ON %d COND=%d PRECUE=%g', t, cond, p.preCueSide(t));
            Eyelink('Message','xDAT %i',20);
        end

        tPreCueOn = GetSecs;
        p.tPreCueOn(t) = tPreCueOn;
        while GetSecs < tPreCueOn + p.preCueDur
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end

            Screen('FillRect',w,p.backColor);
            if cond == 1
                drawPreCueBoth(w,p,fixcenter,mywhite);
            else
                drawPostCueSide(w,p,fixcenter,mywhite,p.preCueSide(t));
            end
            drawFixationNoClear(w,p,fixcenter);
            Screen('Flip',w);
        end

        %----------------- ISI (PRE-CUE --> STIM) -----------------
        tPreISIOn = GetSecs;
        while GetSecs < tPreISIOn + p.preISIDur
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            drawFixation(w,p,fixcenter);
            Screen('Flip',w);
        end

        %----------------- STIMULUS + RESPONSE -----------------
        % Response window opens at stimulus onset (no postcue delay).
        % We draw the stimulus for stimDur, then hold fixation until
        % a response is received.
        if p.eyeTracking == 1
            Eyelink('Message', 'STIM_ON %d TARGSIDE=%d COH=%.4f DIR=%d', ...
                t, p.targSide(t), thisCoh, p.stimDir(t));
            Eyelink('Message','xDAT %i',30);
        end

        % Precompute geometry (target side at threshold coh, distractor at 0)
        stimGeom = makeStaticStimulusGeometry(p, coh1, dir1, coh2, dir2);

        nStimFrames = round(p.stimDur / p.ifi);
        respKey     = NaN;
        respTime    = NaN;
        tStimOn     = GetSecs;
        p.tStimOn(t) = tStimOn;

        % --- Stimulus frames ---
        for f = 1:nStimFrames
            [resp, timeStamp] = checkForResp(p.keys, p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            % Accept response during stimulus if not yet received
            if isnan(respKey) && ~isempty(resp) && resp ~= 0
                if resp == p.key1
                    respKey  = 1;
                    respTime = timeStamp;
                elseif resp == p.key2
                    respKey  = 2;
                    respTime = timeStamp;
                end
            end
            drawStimulusStaticFromGeom(w, p, fixcenter, stimGeom);
            Screen('Flip', w);
        end

        % --- Post-stimulus: hold fixation, keep waiting for response ---
        while isnan(respKey)
            [resp, timeStamp] = checkForResp(p.keys, p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            if ~isempty(resp) && resp ~= 0
                if resp == p.key1
                    respKey  = 1;
                    respTime = timeStamp;
                elseif resp == p.key2
                    respKey  = 2;
                    respTime = timeStamp;
                end
            end
            drawFixation(w,p,fixcenter);
            Screen('Flip', w);
        end

        p.resp(t) = respKey;
        p.RT(t)   = respTime - tStimOn;  % RT from stimulus onset

        if p.eyeTracking == 1
            Eyelink('Message', 'RESP KEY=%d RT=%.3f TRIAL=%d', ...
                respKey, p.RT(t), t);
            Eyelink('Message','xDAT %i',50);
        end

        %----------------- EVALUATE CORRECTNESS -----------------
        % correct: CCW (dir=-1) -> key 2; CW (dir=+1) -> key 1
        if ~isnan(respKey)
            if (p.stimDir(t) == -1 && respKey == 2) || ...
               (p.stimDir(t) ==  1 && respKey == 1)
                p.correct(t) = 1;
            else
                p.correct(t) = 0;
            end
        else
            p.correct(t) = NaN;
        end

        %----------------- FEEDBACK (200 ms) -----------------
        if isnan(p.correct(t))
            fbColor = [255 255 0]; % yellow: miss (shouldn't occur; self-paced)
        elseif p.correct(t) == 1
            fbColor = [0 255 0];   % green: correct
        else
            fbColor = [255 0 0];   % red: error
        end

        if p.eyeTracking == 1
            Eyelink('Message','FEEDBACK_ON TRIAL=%d CORR=%d', t, p.correct(t));
            Eyelink('Message','xDAT %i',60);
        end

        tFbOn = GetSecs;
        while GetSecs < tFbOn + p.feedbackDur
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            Screen('FillRect',w,p.backColor);
            Screen('DrawDots',w,[0;0],p.ppd*p.fixSizeDeg*2,      fbColor',  fixcenter,3);
            Screen('DrawDots',w,[0;0],p.ppd*p.fixSizeDeg*2*0.9,  p.backColor, fixcenter,3);
            Screen('DrawDots',w,[0;0],p.ppd*p.fixSizeInnerDeg*2, fbColor',  fixcenter,3);
            Screen('Flip',w);
        end

        %----------------- ITI -----------------
        if p.eyeTracking == 1
            Eyelink('Message','TRIAL_END %d', t);
            Eyelink('Message','xDAT %i',70);
        end

        tITIOn = GetSecs;
        while GetSecs < tITIOn + p.ITI(t)
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            drawFixation(w,p,fixcenter);
            Screen('Flip',w);
        end

        % save after each trial
        save(fName,'p');

        %----------------- END-OF-BLOCK BREAK -----------------
        if mod(t, p.blockSize) == 0 && t < p.nTrials
            thisBlock = t / p.blockSize;

            blockIdx     = ((thisBlock-1)*p.blockSize + 1) : t;
            blockCorrect = p.correct(blockIdx);
            blockAcc     = 100*nanmean(blockCorrect==1);

            breakStr1 = sprintf('End of block %d / %d', thisBlock, p.nBlocks);
            breakStr2 = sprintf('Block accuracy: %.1f%%', blockAcc);
            breakStr3 = 'Take a short break. Press SPACE to continue, or ESC to quit.';

            showBreakScreen(w,p,fixcenter, breakStr1, breakStr2, breakStr3);

            while true
                [resp, ~] = checkForResp([p.space], p.escape);
                if resp == -1
                    p.aborted = 1;
                    save(fName,'p');
                    cleanupAndExit(w,p); return;
                elseif resp == p.space
                    break;
                end
            end
        end

    end % trial loop

    %-----------------------------
    % END OF RUN: SUMMARY
    %-----------------------------
    p.endExp   = GetSecs;
    p.accuracy = 100*nanmean(p.correct==1);

    save(fName,'p');

    if p.eyeTracking == 1
        try
            Eyelink('Message','EXPT_END');
            Eyelink('Message','xDAT %i',99);
        catch
        end
    end

    Screen('FillRect',w,p.backColor);

    str_acc = sprintf('Overall accuracy: %.2f%%', p.accuracy);
    tCenterAcc = [fixcenter(1)-RectWidth(Screen('TextBounds', w, str_acc))/2, ...
        fixcenter(2)-200];
    Screen('DrawText', w, str_acc, tCenterAcc(1), tCenterAcc(2), p.textColor);

    str_thresh = sprintf('Coherence threshold: %.3f (method: %s)', ...
        p.targCoh, p.threshMethodUsed);
    tCenterTh = [fixcenter(1)-RectWidth(Screen('TextBounds', w, str_thresh))/2, ...
        fixcenter(2)-150];
    Screen('DrawText', w, str_thresh, tCenterTh(1), tCenterTh(2), p.textColor);

    Screen('Flip', w);

    while true
        [resp, ~] = checkForResp(p.space, p.escape);
        if resp == p.space
            break;
        elseif resp == -1
            p.aborted = 1;
            save(fName,'p');
            cleanupAndExit(w,p); return;
        end
    end

    cleanupAndExit(w,p);

catch
    le = lasterror; %#ok<LERR>
    disp('uh oh');
    disp(le.message);
    try
        cleanupAndExit(w,p);
    catch
        sca; ShowCursor;
    end
end

end % main function


%% ========================================================================
%  HELPER FUNCTIONS
%% ========================================================================

function drawFixation(w,p,fixcenter)
Screen('FillRect',w,p.backColor);
drawFixationNoClear(w,p,fixcenter);
end

function drawFixationNoClear(w,p,fixcenter)
Screen('DrawDots',w,[0;0],p.ppd*p.fixSizeDeg*2,      p.fixColor,  fixcenter,3);
Screen('DrawDots',w,[0;0],p.ppd*p.fixSizeDeg*2*0.9,  p.backColor, fixcenter,3);
Screen('DrawDots',w,[0;0],p.ppd*p.fixSizeInnerDeg*2, p.fixColor,  fixcenter,3);
end

function drawPreCueBoth(w,p,fixcenter,mywhite)
cue_angs     = atan2d(p.stimPosDeg(:,2), p.stimPosDeg(:,1));
lineWidthPix = 2;

rFixOuter = p.ppd * p.fixSizeDeg;
rStart    = rFixOuter * 1.05;
rLength   = p.ppd * p.cueSizeDeg;
rEnd      = rStart + rLength;

x1_start = rStart * cosd(cue_angs(1));
y1_start = -rStart * sind(cue_angs(1));
x1_end   = rEnd   * cosd(cue_angs(1));
y1_end   = -rEnd  * sind(cue_angs(1));

x2_start = rStart * cosd(cue_angs(2));
y2_start = -rStart * sind(cue_angs(2));
x2_end   = rEnd   * cosd(cue_angs(2));
y2_end   = -rEnd  * sind(cue_angs(2));

xCoords   = [x1_start, x1_end, x2_start, x2_end];
yCoords   = [y1_start, y1_end, y2_start, y2_end];
allCoords = [xCoords; yCoords];
Screen('DrawLines', w, allCoords, lineWidthPix, mywhite(:), fixcenter, 2);
end

function drawPostCueSide(w,p,fixcenter,mywhite,side)
cue_angs     = atan2d(p.stimPosDeg(:,2), p.stimPosDeg(:,1));
lineWidthPix = 2;

ang    = cue_angs(side);

rFixOuter = p.ppd * p.fixSizeDeg;
rStart    = rFixOuter * 1.05;
rLength   = p.ppd * p.cueSizeDeg;
rEnd      = rStart + rLength;

xCoords   = [rStart * cosd(ang), rEnd * cosd(ang)];
yCoords   = [-rStart * sind(ang), -rEnd * sind(ang)];
allCoords = [xCoords; yCoords];
Screen('DrawLines', w, allCoords, lineWidthPix, mywhite(:), fixcenter, 2);
end

function drawStimulusStaticFromGeom(w,p,fixcenter,stimGeom)
Screen('FillRect',w,p.backColor);
drawFixation(w,p,fixcenter);
for ii = 1:2
    xyShift = p.ppd*[1 -1].*p.stimPosDeg(ii,:);
    Screen('DrawLines', w, stimGeom(ii).dxyb, p.lineWidthPix, ...
        stimGeom(ii).colors, fixcenter + xyShift, 1);
end
end

function stimGeom = makeStaticStimulusGeometry(p, coh1, dir1, coh2, dir2)
% Build line geometry for both sides independently.
%   Side 1 (left):  coherence = coh1, direction = dir1
%   Side 2 (right): coherence = coh2, direction = dir2
% Pass coh=0 for the distractor side; direction is irrelevant at coh=0.

stimGeom = struct;

cohArr = [coh1, coh2];
dirArr = [dir1, dir2];

for ii = 1:2
    thisCoh = cohArr(ii);
    thisDir = dirArr(ii);

    % Random positions within circular aperture
    bxy = rand(2,500)*(p.stimSizePix)*2 - (p.stimSizePix);
    rb  = sqrt((bxy(1,:)).^2 + (bxy(2,:)).^2);
    bxy = bxy(:, rb <= (p.stimSizePix));

    while size(bxy,2) < p.nLines
        bxy2 = rand(2,500)*(p.stimSizePix)*2 - (p.stimSizePix);
        rb2  = sqrt((bxy2(1,:)).^2 + (bxy2(2,:)).^2);
        bxy2 = bxy2(:, rb2 <= (p.stimSizePix));
        bxy  = [bxy bxy2];
    end
    bxy = bxy(:,1:p.nLines);

    dxyb = nan(2, 2*p.nLines);

    % Uniformly distributed baseline orientations (consistent with EEG version)
    ba = linspace(180/p.nLines, 180, p.nLines);
    ba = ba(randperm(p.nLines));

    % Base radial angle for each line position
    ra = rad2deg(atan2(-1*bxy(2,1:p.nLines), bxy(1,1:p.nLines)));

    % Rotate coherent subset toward target orientation
    n_coh = round(thisCoh * p.nLines);
    if n_coh > 0
        ba(1:n_coh) = ra(1:n_coh) + thisDir * p.targOriOffset;
    end
    % If thisCoh == 0, ba is left as the shuffled linspace (pure noise)

    % Line endpoints
    dxyb(1,1:2:end) = -0.5*p.lineSizePix*cosd(ba) + bxy(1,:);
    dxyb(2,1:2:end) =  0.5*p.lineSizePix*sind(ba) + bxy(2,:);
    dxyb(1,2:2:end) =  0.5*p.lineSizePix*cosd(ba) + bxy(1,:);
    dxyb(2,2:2:end) = -0.5*p.lineSizePix*sind(ba) + bxy(2,:);

    % Colors (alternating light/dark lines)
    line_order     = randperm(2);
    line_lightdark = repmat([line_order(1) line_order(1) ...
        line_order(2) line_order(2)], 1, p.nLines/2);
    line_colors    = repmat(p.stimRGB(line_lightdark), 3, 1);

    stimGeom(ii).dxyb   = dxyb;
    stimGeom(ii).colors = [line_colors; ones(1,size(line_colors,2))*255];
end
end

function showInstructionScreen(w,p,fixcenter)

Screen('FillRect',w,p.backColor);

instr1 = 'A cue will appear, then a brief stimulus on both sides.';
instr2 = 'One side has an oriented pattern; the other is random noise.';
instr3 = 'Report the ORIENTATION of the target on the CUED side.';
instr4 = 'Press 1 if lines tilt with the TOP pointing LEFT (like \).';
instr5 = 'Press 2 if lines tilt with the TOP pointing RIGHT (like /).';
instr6 = 'Respond as soon as the stimulus appears. Keep eyes on fixation.';
instr7 = 'Press SPACE to begin.';

ySpacing = 40;
y0 = fixcenter(2) - 3*ySpacing;

drawCenteredTextLine(w, p, instr1, fixcenter(1), y0);
drawCenteredTextLine(w, p, instr2, fixcenter(1), y0 + 1*ySpacing);
drawCenteredTextLine(w, p, instr3, fixcenter(1), y0 + 2*ySpacing);
drawCenteredTextLine(w, p, instr4, fixcenter(1), y0 + 3*ySpacing);
drawCenteredTextLine(w, p, instr5, fixcenter(1), y0 + 4*ySpacing);
drawCenteredTextLine(w, p, instr6, fixcenter(1), y0 + 5*ySpacing);
drawCenteredTextLine(w, p, instr7, fixcenter(1), y0 + 7*ySpacing);

% Example stimuli: left = target (CW, key 1), right = noise
exampleCoh = 1.0;
geom = makeStaticStimulusGeometry(p, exampleCoh, +1, 0, 1);

xyShiftL = p.ppd*[1 -1].*p.stimPosDeg(1,:);
xyShiftR = p.ppd*[1 -1].*p.stimPosDeg(2,:);

stimCenterL = fixcenter + xyShiftL;
stimCenterR = fixcenter + xyShiftR;

Screen('DrawLines', w, geom(1).dxyb, p.lineWidthPix, geom(1).colors, stimCenterL, 1);
Screen('DrawLines', w, geom(2).dxyb, p.lineWidthPix, geom(2).colors, stimCenterR, 1);

labelYOffset = p.stimSizePix + 20;
drawCenteredTextLine(w, p, 'Target: press 1', stimCenterL(1), stimCenterL(2) + labelYOffset);
drawCenteredTextLine(w, p, 'Noise (ignore)', stimCenterR(1), stimCenterR(2) + labelYOffset);

Screen('Flip',w);
end

function drawCenteredTextLine(w, p, str, xCenter, yPos)
bounds = Screen('TextBounds', w, str);
x = xCenter - bounds(3)/2;
Screen('DrawText', w, str, x, yPos, p.textColor);
end

function showBreakScreen(w,p,fixcenter,str1,str2,str3)
Screen('FillRect',w,p.backColor);

bounds1 = Screen('TextBounds', w, str1);
x1 = fixcenter(1) - bounds1(3)/2;
y1 = fixcenter(2) - 60;

bounds2 = Screen('TextBounds', w, str2);
x2 = fixcenter(1) - bounds2(3)/2;
y2 = fixcenter(2);

bounds3 = Screen('TextBounds', w, str3);
x3 = fixcenter(1) - bounds3(3)/2;
y3 = fixcenter(2) + 60;

Screen('DrawText', w, str1, x1, y1, p.textColor);
Screen('DrawText', w, str2, x2, y2, p.textColor);
Screen('DrawText', w, str3, x3, y3, p.textColor);
Screen('Flip', w);
end

function cleanupAndExit(w,p)
ListenChar(0);

if isfield(p,'gamma_table_orig')
    try
        Screen('LoadNormalizedGammaTable', w, p.gamma_table_orig);
    catch
    end
end

if isfield(p,'eyeTracking') && p.eyeTracking == 1
    try
        Eyelink('StopRecording');
    catch
    end
    try
        Eyelink('CloseFile');
    catch
    end
    try
        Eyelink('ReceiveFile', [p.eyedatafile '.edf'], p.root_data_test);
        if isfield(p,'edfTarget')
            srcEDF = fullfile(p.root_data_test, [p.eyedatafile '.edf']);
            if exist(srcEDF,'file')
                movefile(srcEDF, p.edfTarget);
            end
        end
    catch
    end
    try
        Eyelink('Shutdown');
    catch
    end
end

Screen('CloseAll');
ShowCursor;
clear;
end