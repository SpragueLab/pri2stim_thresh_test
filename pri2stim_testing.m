function pri2stim_testing
try

    KbName('UnifyKeyNames');

    tmpf = mfilename('fullpath');
    tmpi = strfind(tmpf,filesep);
    % folder where the script lives
    p.root = tmpf(1:tmpi(end));

    % data directories
    % new data directory for TESTING runs
    p.root_data_test   = fullfile(p.root, 'data', 'testing');
    % directory where thresholding/staircase files live
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
        'Number of trials (testing)', ...
        'Contrast mode (1=80% only, 2=mixed 20/40/80)'};

    s = round(sum(100*clock));
    defAns = {'subXXX','1','X','0','3','0',num2str(s),'60','1'};
    box = inputdlg(prompt,'Enter Subject Information...', 1, defAns);

    if length(box)==length(defAns)
        p.subName        = char(box{1});
        p.sessionNum     = str2double(box{2});
        p.runNum         = eval(box{3});
        targCoh_in       = str2double(box{4});  % may be 0 --> auto-load
        p.display        = str2double(box{5});
        p.eyeTracking    = str2double(box{6});
        p.rndSeed        = str2double(box{7});
        p.nTrials        = str2double(box{8}); % shortened to account for self-pacing
        p.contrastMode   = str2double(box{9});  % 1 or 2
        rng(p.rndSeed);
    else
        return
    end

    % Experiment name
    p.exptName = 'pri2stimEEG_testing';

    %-----------------------------
    % LOAD / SET TARGET COHERENCE
    %-----------------------------
    if isnan(targCoh_in) || targCoh_in <= 0
        exptThreshName = 'pri2stimEEG_threshold';
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
        p.minITI        = 1.25; % 1250 ms
        p.maxITI        = 1.50; % 1500 ms
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
    p.fontSize = 24;
    p.fontName = 'ARIAL';
    p.textColor = [100, 100, 100];

    if ismac
        p.escape = 41;
    else
        p.escape = 27;
    end

    % Explicit key mappings
    p.key1  = KbName('1!');    % main '1' key (handles shift as well)
    p.key2  = KbName('2@');    % main '2' key
    p.space = KbName('space');
    p.start = p.space;

    % For the response checker, we only care about 1 and 2
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

    % Contrast: initial value for instructions (per-trial later)
    p.lineContrast       = 0.8;  % default 80%

    templateRGB = [-1 1];
    thisRGB = (round(127*templateRGB*p.lineContrast)+1)+127;
    p.stimRGB = round(p.LUT(thisRGB));
    clear templateRGB thisRGB;

    p.textColor = round(p.LUT(p.textColor))';
    p.fixColor  = round(p.LUT(p.fixColorIdeal))';
    p.backColor = round(p.LUT(p.backColorIdeal))';

    %-----------------------------
    % TIMING (all fixed)
    %-----------------------------
    p.fixDur        = 0.300;  % s
    p.preCueDur     = 0.250;  % precue
    p.preISIDur     = 0.250;  % ISI between precue and stim
    p.stimDur       = 0.100;  % stimulus epoch
    p.postISIDur    = 0.250;  % ISI between stim and postcue
    p.postCueDur    = 0.200;  % postcue
    p.respWindow    = 1.5;    % legacy; unused for self-pacing
    p.feedbackDur   = 0.200;  % feedback
    p.ITI           = rand(p.nTrials,1)*(p.maxITI-p.minITI)+p.minITI;
    p.startWait     = 0.75;
    p.passiveDur    = 0.5;

    %-----------------------------
    % CONTRAST MODE SETUP
    %-----------------------------
    if p.contrastMode == 1
        p.contrastLevels = 0.8;
    else
        p.contrastLevels = [0.2 0.4 0.8];
    end

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

    % final EDF pathname we want (same basename as .mat file)
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

            % Setup defaults
            el = EyelinkInitDefaults(w);

            % match colors to your display
            el.backgroundcolour        = p.backColor(1);
            el.calibrationtargetcolour = p.fixColor(1);
            el.msgfontcolour           = p.fixColor(1);
            EyelinkUpdateDefaults(el);

            % Initialize Eyelink with PTB dispatch callback
            statusInit = Eyelink('Initialize', 'PsychEyelinkDispatchCallback');
            if statusInit ~= 0
                error('Eyelink initialization failed (status %d).', statusInit);
            end

            % Basic configuration
            Eyelink('command','calibration_type=HV9');
            Eyelink('command','link_sample_data = LEFT,RIGHT,GAZE,AREA');
            Eyelink('command','sample_rate = 1000');
            Eyelink('command','screen_pixel_coords = %ld %ld %ld %ld', ...
                0, 0, p.sRect(3)-1, p.sRect(4)-1);
            Eyelink('message','DISPLAY_COORDS %ld %ld %ld %ld', ...
                0, 0, p.sRect(3)-1, p.sRect(4)-1);

            % Widescreen calibration area tweak
            if (p.sRect(3)==2560 && p.sRect(4)==1440) || (p.sRect(3)==1920 && p.sRect(4)==1080)
                Eyelink('command', 'calibration_area_proportion 0.59 0.83');
            end

            % Run standard 9-point calibration
            EyelinkDoTrackerSetup(el);

            % Open EDF file (no extension here; Eyelink adds .edf)
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

    % wait for SPACE (or ESC) to start
    while true
        [resp, ~] = checkForResp([p.space], p.escape);
        if resp == p.space
            break;
        elseif resp == -1   % ESC pressed
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
            Eyelink('Message','EXPT_START TESTING');
            Eyelink('Message','xDAT %i',10);  % experiment start marker
            Eyelink('StartRecording');
            p.eye_used = Eyelink('EyeAvailable');
            if p.eye_used == el.BINOCULAR
                p.eye_used = el.RIGHT_EYE;
            end
            WaitSecs(0.05); % brief settle
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
    p.stimDir1    = nan(p.nTrials,1); % -1=CCW +1=CW
    p.stimDir2    = nan(p.nTrials,1);
    p.postCueSide = nan(p.nTrials,1); % 1=left, 2=right
    p.preCueSide  = nan(p.nTrials,1); % 1=left, 2=right, NaN for distributed
    p.validity    = nan(p.nTrials,1); % 1=valid, 0=invalid, NaN for distributed
    p.contrast    = nan(p.nTrials,1); % per-trial contrast (0-1)
    p.resp        = nan(p.nTrials,1);
    p.correct     = nan(p.nTrials,1);
    p.RT          = nan(p.nTrials,1);
    p.trialStart  = nan(p.nTrials,1);
    p.targFrame   = nan(p.nTrials,1);
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
            Eyelink('Message','xDAT %i',1); % trial start
        end

        % --- coherence (fixed threshold) ---
        thisCoh         = p.targCoh;
        p.cohLevel(t)   = thisCoh;

        % --- contrast (per trial) ---
        if p.contrastMode == 1
            thisContrast = p.contrastLevels;           % 0.8
        else
            thisContrast = p.contrastLevels(randi(length(p.contrastLevels)));
        end
        p.contrast(t) = thisContrast;

        % update p.stimRGB for this contrast
        templateRGB = [-1 1];
        thisRGB = (round(127*templateRGB*thisContrast)+1)+127;
        p.stimRGB = round(p.LUT(thisRGB));

        % --- stimulus directions (independent per side) ---
        p.stimDir1(t) = randsample([-1 1],1);
        p.stimDir2(t) = randsample([-1 1],1);

        % --- postcue side (what subject will report) ---
        p.postCueSide(t) = randi([1 2]); % 1=left, 2=right

        % --- precue depending on condition ---
        cond = p.attnCond(t);
        if cond == 1
            p.preCueSide(t) = NaN;
            p.validity(t)   = NaN;
        elseif cond == 2
            p.preCueSide(t) = p.postCueSide(t);
            p.validity(t)   = 1;
        else
            p.preCueSide(t) = 3 - p.postCueSide(t);
            p.validity(t)   = 0;
        end

        %----------------- FIXATION -----------------
        if p.eyeTracking == 1
            Eyelink('Message', 'FIX_ON %d', t);
            Eyelink('Message','xDAT %i',2); % fixation
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
            Eyelink('Message','xDAT %i',20); % precue marker
        end

        tPreCueOn = GetSecs;
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

        %----------------- ISI (PRE --> STIM) -----------------
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

        %----------------- STIMULUS -----------------
        if p.eyeTracking == 1
            Eyelink('Message', 'STIM_ON %d COH=%.4f CONTRAST=%.2f', t, thisCoh, thisContrast);
            Eyelink('Message','xDAT %i',30); % stim onset
        end

        nStimFrames     = round(p.stimDur / p.ifi);
        p.targFrame(t)  = NaN;

        stimGeom = makeStaticStimulusGeometry(p, thisCoh, p.stimDir1(t), p.stimDir2(t));

        for f = 1:nStimFrames
            [resp, ~] = checkForResp([], p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end

            drawStimulusStaticFromGeom(w, p, fixcenter, stimGeom);
            Screen('Flip', w);
        end

        %----------------- ISI (STIM --> POSTCUE) -----------------
        tPostISIOn = GetSecs;
        while GetSecs < tPostISIOn + p.postISIDur
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end
            drawFixation(w,p,fixcenter);
            Screen('Flip',w);
        end

        %----------------- POSTCUE (ONE SIDE) -----------------
        if p.eyeTracking == 1
            Eyelink('Message', 'POSTCUE_ON %d SIDE=%d', t, p.postCueSide(t));
            Eyelink('Message','xDAT %i',40); % postcue onset
        end

        tPostCueOn = GetSecs;
        while GetSecs < tPostCueOn + p.postCueDur
            [resp, ~] = checkForResp([],p.escape);
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end

            Screen('FillRect',w,p.backColor);
            drawPostCueSide(w,p,fixcenter,mywhite,p.postCueSide(t));
            drawFixationNoClear(w,p,fixcenter);
            Screen('Flip',w);
        end

        %----------------- RESPONSE (SELF-PACED) -----------------
        respKey    = NaN;
        respTime   = NaN;
        tRespStart = GetSecs;

        while isnan(respKey)
            [resp, timeStamp] = checkForResp(p.keys, p.escape);

            % allow abort with ESC at any time
            if resp == -1
                p.aborted = 1;
                save(fName,'p');
                cleanupAndExit(w,p); return;
            end

            % first valid response ends the trial
            if ~isempty(resp)
                if resp == p.key1
                    respKey  = 1;
                    respTime = timeStamp;
                elseif resp == p.key2
                    respKey  = 2;
                    respTime = timeStamp;
                end
            end

            % keep showing fixation while waiting
            drawFixation(w,p,fixcenter);
            Screen('Flip', w);
        end

        p.resp(t) = respKey;
        p.RT(t)   = respTime - tRespStart;

        %----------------- EVALUATE CORRECTNESS -----------------
        if ~isnan(respKey)
            if p.postCueSide(t) == 1
                trueDir = p.stimDir1(t);
            else
                trueDir = p.stimDir2(t);
            end

            if     (trueDir == -1 && respKey == 2) || ...
                    (trueDir ==  1 && respKey == 1)
                p.correct(t) = 1;
            else
                p.correct(t) = 0;
            end
        else
            p.correct(t) = NaN; % miss
        end

        if p.eyeTracking == 1
            if isnan(respKey)
                Eyelink('Message', 'RESP MISS TRIAL=%d', t);
            else
                Eyelink('Message', 'RESP KEY=%d CORR=%d RT=%.3f TRIAL=%d', ...
                    respKey, p.correct(t), p.RT(t), t);
            end
            Eyelink('Message','xDAT %i',50); % response marker
        end

        %----------------- FEEDBACK (200 ms) -----------------
        if isnan(p.correct(t))
            fbColor = [255 255 0]; % yellow for miss
        elseif p.correct(t) == 1
            fbColor = [0 255 0];   % green for correct
        else
            fbColor = [255 0 0];   % red for error
        end

        if p.eyeTracking == 1
            Eyelink('Message','FEEDBACK_ON TRIAL=%d', t);
            Eyelink('Message','xDAT %i',60); % feedback onset
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
            Eyelink('Message','xDAT %i',70); % ITI / trial end
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
            Eyelink('Message','xDAT %i',99); % experiment end marker
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

    % wait for space bar to exit
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

end % function

%% HELPER FUNCTIONS

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
cue_angs = atan2d(p.stimPosDeg(:,2), p.stimPosDeg(:,1));
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

xCoords = [x1_start, x1_end, x2_start, x2_end];
yCoords = [y1_start, y1_end, y2_start, y2_end];

allCoords = [xCoords; yCoords];
Screen('DrawLines', w, allCoords, lineWidthPix, mywhite(:), fixcenter, 2);
end

function drawPostCueSide(w,p,fixcenter,mywhite,side)
cue_angs = atan2d(p.stimPosDeg(:,2), p.stimPosDeg(:,1));
lineWidthPix = 2;

ang = cue_angs(side);

rFixOuter = p.ppd * p.fixSizeDeg;
rStart    = rFixOuter * 1.05;
rLength   = p.ppd * p.cueSizeDeg;
rEnd      = rStart + rLength;

xCoords = [rStart * cosd(ang), rEnd * cosd(ang)];
yCoords = [-rStart * sind(ang), -rEnd * sind(ang)];

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

function stimGeom = makeStaticStimulusGeometry(p, coh, dir1, dir2)
stimGeom = struct;

for ii = 1:2
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

    ba = rand(1,p.nLines)*360;
    ra = rad2deg(atan2(-1*bxy(2,1:p.nLines), bxy(1,1:p.nLines)));

    n_coh  = round(coh * p.nLines);
    if ii == 1
        thisDir = dir1;
    else
        thisDir = dir2;
    end
    if n_coh > 0
        ba(1:n_coh) = ra(1:n_coh) + thisDir * p.targOriOffset;
    end

    dxyb(1,1:2:end) = -0.5*p.lineSizePix*cosd(ba) + bxy(1,:);
    dxyb(2,1:2:end) =  0.5*p.lineSizePix*sind(ba) + bxy(2,:);
    dxyb(1,2:2:end) =  0.5*p.lineSizePix*cosd(ba) + bxy(1,:);
    dxyb(2,2:2:end) = -0.5*p.lineSizePix*sind(ba) + bxy(2,:);

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

instr1 = 'Report the ORIENTATION of the lines on the cued side.';
instr2 = 'Press 1 if the lines tilt with the TOP pointing to the LEFT (like \).';
instr3 = 'Press 2 if the lines tilt with the TOP pointing to the RIGHT (like /).';
instr4 = 'Keep your eyes on the fixation at all times.';
instr5 = 'Press SPACE to begin.';

ySpacing = 40;
y0 = fixcenter(2) - 2*ySpacing;

drawCenteredTextLine(w, p, instr1, fixcenter(1), y0);
drawCenteredTextLine(w, p, instr2, fixcenter(1), y0 + 1*ySpacing);
drawCenteredTextLine(w, p, instr3, fixcenter(1), y0 + 2*ySpacing);
drawCenteredTextLine(w, p, instr4, fixcenter(1), y0 + 3*ySpacing);
drawCenteredTextLine(w, p, instr5, fixcenter(1), y0 + 5*ySpacing);

exampleCoh = 1.0;
geom1 = makeStaticStimulusGeometry(p, exampleCoh, +1, +1);
geom2 = makeStaticStimulusGeometry(p, exampleCoh, -1, -1);

xyShiftL = p.ppd*[1 -1].*p.stimPosDeg(1,:);
xyShiftR = p.ppd*[1 -1].*p.stimPosDeg(2,:);

stimCenterL = fixcenter + xyShiftL;
stimCenterR = fixcenter + xyShiftR;

Screen('DrawLines', w, geom1(1).dxyb, p.lineWidthPix, ...
    geom1(1).colors, stimCenterL, 1);
Screen('DrawLines', w, geom2(2).dxyb, p.lineWidthPix, ...
    geom2(2).colors, stimCenterR, 1);

labelYOffset = p.stimSizePix + 20;
label1 = 'Example: press 1';
label2 = 'Example: press 2';

drawCenteredTextLine(w, p, label1, stimCenterL(1), stimCenterL(2) + labelYOffset);
drawCenteredTextLine(w, p, label2, stimCenterR(1), stimCenterR(2) + labelYOffset);

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

% Restore gamma if possible
if isfield(p,'gamma_table_orig')
    try
        Screen('LoadNormalizedGammaTable', w, p.gamma_table_orig);
    catch
    end
end

% Eyelink shutdown if active
if isfield(p,'eyeTracking') && p.eyeTracking == 1
    try
        Eyelink('StopRecording');
    catch
    end

    try
        Eyelink('CloseFile');
    catch
    end

    % Receive EDF into the data directory, then rename to match .mat
    try
        Eyelink('ReceiveFile', [p.eyedatafile '.edf'], p.root_data_test);

        if isfield(p,'edfTarget')
            srcEDF = fullfile(p.root_data_test, [p.eyedatafile '.edf']);
            % p.edfTarget is already a full path (same base as fName, .edf)
            if exist(srcEDF,'file')
                movefile(srcEDF, p.edfTarget);
            end
        end
    catch
        % swallow errors but don't crash cleanup
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
