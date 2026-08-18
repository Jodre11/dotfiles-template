-- Push-to-talk dictation using whisper-cpp
-- Triggered by Karabiner (Print Screen key)

-- Enable IPC for command-line access
require("hs.ipc")

-- Options: ggml-tiny.en.bin (fast), ggml-base.en.bin (balanced), ggml-small.en.bin, ggml-medium.en.bin,
-- ggml-large-v3-turbo-q8_0.bin (large-v3 encoder + 4-layer turbo decoder, quantised to 874MB)
local WHISPER_MODEL = os.getenv("HOME") .. "/.local/share/whisper/ggml-large-v3-turbo-q8_0.bin"
local VAD_MODEL = os.getenv("HOME") .. "/.local/share/whisper/ggml-silero-v6.2.0.bin"
local AUDIO_FILE = os.getenv("HOME") .. "/.local/share/dictation/recording.wav"
-- Customise this prompt with domain-specific vocabulary to improve whisper transcription.
-- See docs/whisper-prompt-technique.md for guidance on generating effective prompts.
local WHISPER_PROMPT = "Software engineering discussion. "
    .. "TypeScript, React, PostgreSQL, Redis, Docker, Kubernetes, Terraform. "
    .. "Claude Code, Anthropic, AWS Bedrock, Ghostty, Hammerspoon, Karabiner, tmux, zsh."

local LOG_FILE = os.getenv("HOME") .. "/.local/share/dictation/dictation.log"

-- -ac bounds the encoder's audio context (1500 frames = 30s), which is a large latency
-- win but silently mangles clips longer than the bound. 1000 covers ~20s, so it is only
-- applied well inside that limit; longer recordings use the full context.
local FAST_AUDIO_CTX = "1000"
local FAST_PATH_MAX_SECONDS = 15
local WAV_BYTES_PER_SECOND = 16000 * 2  -- 16kHz mono 16-bit, per the sox flags below
local WAV_HEADER_BYTES = 44
local CAPTURE_WAIT_TIMEOUT = 1.5

-- Append a timestamped line to the dictation log file
local function log(msg)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. msg .. "\n")
        f:close()
    end
end

local recording = false
local recordingTask = nil
local recordingIndicator = nil
local captureWatcher = nil
local pendingSeq = 0
local lastStateChange = 0
-- Only long enough to swallow a stray F20 arriving with the F19 key-up. Key auto-repeat
-- is already suppressed in karabiner.json ("repeat": false) and startDictation returns
-- early while recording, so a longer window buys nothing and silently discards a
-- deliberate second dictation started moments after the first.
local DEBOUNCE_SECONDS = 0.2

-- Create red dot indicator in top-right corner (near menu bar)
local function createIndicator()
    local screen = hs.screen.mainScreen():fullFrame()
    recordingIndicator = hs.canvas.new({ x = screen.x + screen.w - 50, y = screen.y + 45, w = 12, h = 12 })
    recordingIndicator:level(hs.canvas.windowLevels.overlay)
    recordingIndicator:appendElements({
        type = "circle",
        center = { x = 6, y = 6 },
        radius = 6,
        fillColor = { red = 1, green = 0, blue = 0, alpha = 1 },
        strokeColor = { red = 0.8, green = 0, blue = 0, alpha = 1 },
        strokeWidth = 1
    })
end

local function showIndicator()
    if not recordingIndicator then createIndicator() end
    recordingIndicator:show()
end

local function hideIndicator()
    if recordingIndicator then recordingIndicator:hide() end
end

local function stopCaptureWatcher()
    if captureWatcher then
        captureWatcher:stop()
        captureWatcher = nil
    end
end

-- Toggle dictation (press to start, press again to stop)
function toggleDictation()
    if recording then
        stopDictation()
    else
        startDictation()
    end
end

-- Start recording audio
function startDictation()
    if recording then return end
    local now = hs.timer.secondsSinceEpoch()
    if (now - lastStateChange) < DEBOUNCE_SECONDS then
        log("DEBOUNCE: ignoring rapid start")
        return
    end
    lastStateChange = now
    recording = true
    log("START recording")

    -- Remove stale audio file before recording
    os.remove(AUDIO_FILE)

    -- Record using sox (16kHz mono WAV for whisper, high-pass filter to cut low-frequency rumble)
    recordingTask = hs.task.new("/opt/homebrew/bin/sox", nil, {
        "-d",           -- default input device
        "-r", "16000",  -- 16kHz sample rate
        "-c", "1",      -- mono
        "-b", "16",     -- 16-bit
        -- Default buffering delays the first flush to disk by ~560ms; 1024 bytes halves
        -- that to ~275ms, so the "capture live" indicator can appear sooner. Smaller
        -- values buy little and risk dropouts under load.
        "--buffer", "1024",
        AUDIO_FILE,
        "highpass", "200"
    })
    recordingTask:start()

    -- Opening the CoreAudio device costs ~200ms, during which nothing is captured.
    -- Showing the indicator before that window closes invites the speaker to start
    -- talking into audio that does not exist, clipping the first word. Poll for the
    -- first audio bytes past the WAV header and only then signal "speak now".
    local waited = 0
    captureWatcher = hs.timer.doEvery(0.02, function()
        waited = waited + 0.02
        if not recording then
            stopCaptureWatcher()
            return
        end
        local f = io.open(AUDIO_FILE, "r")
        local size = 0
        if f then
            size = f:seek("end")
            f:close()
        end
        if size > WAV_HEADER_BYTES then
            stopCaptureWatcher()
            log(string.format("CAPTURE live after %.0fms", waited * 1000))
            showIndicator()
        elseif waited >= CAPTURE_WAIT_TIMEOUT then
            -- Never leave the user without feedback if the poll never sees growth.
            stopCaptureWatcher()
            log("CAPTURE detect timed out, showing indicator anyway")
            showIndicator()
        end
    end)
end

-- Normalise whisper output: strip timestamp brackets, trim, collapse newlines, and
-- leave one trailing space so consecutive dictations do not run together.
local function cleanText(raw)
    return (raw:gsub("%[.*%]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n+", " ")) .. " "
end

-- Paste via the clipboard, restoring whatever was there afterwards.
local function pasteText(text)
    log("TRANSCRIBED (" .. #text .. " chars)")
    local saved = hs.pasteboard.readAllData()
    hs.pasteboard.setContents(text)
    -- Deferred paste to avoid nested event tap calls
    hs.timer.doAfter(0, function()
        hs.eventtap.keyStroke({"cmd"}, "v")
        hs.timer.doAfter(0.1, function()
            if saved then
                hs.pasteboard.clearContents()
                hs.pasteboard.writeAllData(saved)
            end
        end)
    end)
end

-- audioPath is a per-recording file, not AUDIO_FILE: the next recording deletes and
-- recreates AUDIO_FILE, which with a short debounce can happen before whisper-cli has
-- opened it, transcribing the new recording's opening fragment instead.
local function transcribe(audioPath, durationSeconds)
    local args = {
        "-m", WHISPER_MODEL,
        "-f", audioPath,
        "-l", "en",             -- skip language detection
        "-t", "6",              -- threads (M4: 4P + 6E cores)
        "--prompt", WHISPER_PROMPT,
        "--no-fallback",        -- disable temperature fallback (reduces hallucination)
        "--suppress-nst",       -- suppress non-speech token hallucinations
        "--vad",
        "--vad-model", VAD_MODEL,
        "-np",                  -- no prints (cleaner output)
        "-nt"                   -- no timestamps
    }
    if durationSeconds < FAST_PATH_MAX_SECONDS then
        table.insert(args, "-ac")
        table.insert(args, FAST_AUDIO_CTX)
    end

    local task = hs.task.new("/opt/homebrew/bin/whisper-cli", function(exitCode, stdOut, stdErr)
        os.remove(audioPath)
        if exitCode == 0 and stdOut then
            local text = cleanText(stdOut)
            if #text > 1 then
                pasteText(text)
            else
                log("TRANSCRIBED (empty result)")
            end
        else
            log("TRANSCRIBE FAILED exit=" .. tostring(exitCode) .. " stderr=" .. tostring(stdErr))
        end
    end, args)
    task:start()
end

-- Stop recording and transcribe
function stopDictation()
    if not recording then return end
    lastStateChange = hs.timer.secondsSinceEpoch()
    recording = false
    log("STOP recording")
    stopCaptureWatcher()
    hideIndicator()

    -- Stop sox
    if recordingTask and recordingTask:isRunning() then
        recordingTask:terminate()
    end

    -- Small delay to ensure file is written
    hs.timer.doAfter(0.2, function()
        -- Verify audio file exists and is non-empty before transcribing
        local audioFile = io.open(AUDIO_FILE, "r")
        if not audioFile then
            log("SKIP transcription: audio file not found")
            return
        end
        local size = audioFile:seek("end")
        audioFile:close()
        if size == 0 then
            log("SKIP transcription: audio file is empty")
            return
        end

        -- Claim the audio under a unique name so the next recording cannot delete it
        -- from under the transcription still reading it.
        pendingSeq = pendingSeq + 1
        local audioPath = string.format("%s.%d.wav", AUDIO_FILE, pendingSeq)
        if not os.rename(AUDIO_FILE, audioPath) then
            log("SKIP transcription: could not claim audio file")
            return
        end

        local durationSeconds = size / WAV_BYTES_PER_SECOND
        log(string.format("TRANSCRIBE start (%.1fs audio)", durationSeconds))
        transcribe(audioPath, durationSeconds)
    end)
end

-- F20 = start recording, F19 = stop recording (from Karabiner)
local f20Hotkey = hs.hotkey.bind({}, "f20", function()
    startDictation()
end)

local f19Hotkey = hs.hotkey.bind({}, "f19", function()
    stopDictation()
end)

-- Reset dictation state after sleep/lock (cleans up orphaned recordings)
function recover(reason)
    log("RECOVER (" .. reason .. ")")
    if recording then
        log("RECOVER: recording was stuck, resetting")
        recording = false
        hideIndicator()
    end
    if recordingTask and recordingTask:isRunning() then
        log("RECOVER: killing orphaned sox process")
        recordingTask:terminate()
        recordingTask = nil
    end
    f20Hotkey:enable()
    f19Hotkey:enable()
end

local wakeWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        recover("systemDidWake")
    elseif event == hs.caffeinate.watcher.screensDidWake then
        recover("screensDidWake")
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        recover("screensDidUnlock")
    end
end)
wakeWatcher:start()

-- Karabiner BLE grab watchdog
-- Detects when Pro Type Ultra reconnects without being grabbed and restarts Karabiner
local KARABINER_LOG = "/var/log/karabiner/core_service.log"
local GRAB_DEVICE = "Pro Type Ultra"
local karabinerNeedsGrab = false
local karabinerGrabTimer = nil

local function checkKarabinerGrab()
    -- Read last 50 lines of the Karabiner log
    local task = hs.task.new("/usr/bin/tail", function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 or not stdOut then return end

        -- Only consider lines after the last Karabiner restart
        local lines = {}
        local lastLoadIdx = 0
        local idx = 0
        for line in stdOut:gmatch("[^\n]+") do
            idx = idx + 1
            lines[idx] = line
            if line:find("core_configuration is updated", 1, true) then
                lastLoadIdx = idx
            end
        end

        -- Check entries since last restart for the device
        local seen = false
        local grabbed = false
        for i = lastLoadIdx, idx do
            local line = lines[i]
            if line and line:find(GRAB_DEVICE, 1, true) then
                if line:find("caps lock is found", 1, true) then
                    seen = true
                end
                if line:find("grabbed", 1, true) then
                    grabbed = true
                end
            end
        end

        if seen and not grabbed then
            if not karabinerNeedsGrab then
                karabinerNeedsGrab = true
                log("KARABINER WATCHDOG: " .. GRAB_DEVICE .. " not grabbed, restarting Karabiner")
                hs.task.new("/usr/bin/killall", function()
                    karabinerNeedsGrab = false
                end, { "karabiner_console_user_server" }):start()
            end
        else
            karabinerNeedsGrab = false
        end
    end, { "-50", KARABINER_LOG })
    task:start()
end

karabinerGrabTimer = hs.timer.doEvery(10, checkKarabinerGrab)

-- Middle-click paste in Ghostty
-- Ghostty's native middle-click reads from a private selection pasteboard, not the system
-- clipboard. Intercept middle-click when the cursor is over a Ghostty window and synthesise
-- Cmd+V instead. We check the window under the cursor rather than the frontmost app because
-- the middle-click itself may be what brings Ghostty to the front.
local GHOSTTY_BUNDLE = "com.mitchellh.ghostty"

-- Resolve the window under the mouse cursor. Try the event property first (cheap); fall back
-- to a geometry scan of visible windows when it returns 0 (known Hammerspoon issue #2848).
local function windowUnderMouse(event)
    local props = hs.eventtap.event.properties
    local wid = event:getProperty(props.mouseEventWindowUnderMousePointer)
    if wid and wid ~= 0 then
        local win = hs.window.find(wid)
        if win then return win end
    end
    local mousePoint = hs.geometry.point(hs.mouse.absolutePosition())
    for _, win in ipairs(hs.window.orderedWindows()) do
        if mousePoint:inside(win:frame()) then
            return win
        end
    end
    return nil
end

middleClickPaste = hs.eventtap.new({ hs.eventtap.event.types.otherMouseDown }, function(event)
    if event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) == 2 then
        local win = windowUnderMouse(event)
        if win and win:application() and win:application():bundleID() == GHOSTTY_BUNDLE then
            win:focus()
            hs.timer.doAfter(0.05, function()
                hs.eventtap.keyStroke({"cmd"}, "v")
            end)
            return true  -- consume the middle-click
        end
    end
    return false
end)
middleClickPaste:start()

log("Push-to-talk dictation loaded")
print("Push-to-talk dictation loaded.")
