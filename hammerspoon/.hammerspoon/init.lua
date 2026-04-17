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
local lastStateChange = 0
local DEBOUNCE_SECONDS = 1

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
    showIndicator()

    -- Remove stale audio file before recording
    os.remove(AUDIO_FILE)

    -- Record using sox (16kHz mono WAV for whisper, high-pass filter to cut low-frequency rumble)
    recordingTask = hs.task.new("/opt/homebrew/bin/sox", nil, {
        "-d",           -- default input device
        "-r", "16000",  -- 16kHz sample rate
        "-c", "1",      -- mono
        "-b", "16",     -- 16-bit
        AUDIO_FILE,
        "highpass", "200"
    })
    recordingTask:start()
end

-- Stop recording and transcribe
function stopDictation()
    if not recording then return end
    lastStateChange = hs.timer.secondsSinceEpoch()
    recording = false
    log("STOP recording")
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

        -- Transcribe with whisper
        local transcribeTask = hs.task.new("/opt/homebrew/bin/whisper-cli", function(exitCode, stdOut, stdErr)
            if exitCode == 0 and stdOut then
                -- Clean up the output (remove timestamps and extra whitespace, add trailing space)
                local text = stdOut:gsub("%[.*%]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n+", " ") .. " "
                if text and #text > 0 then
                    log("TRANSCRIBED (" .. #text .. " chars)")
                    -- Deferred paste to avoid nested event tap calls
                    local saved = hs.pasteboard.readAllData()
                    hs.pasteboard.setContents(text)
                    hs.timer.doAfter(0, function()
                        hs.eventtap.keyStroke({"cmd"}, "v")
                        hs.timer.doAfter(0.1, function()
                            if saved then
                                hs.pasteboard.clearContents()
                                hs.pasteboard.writeAllData(saved)
                            end
                        end)
                    end)
                else
                    log("TRANSCRIBED (empty result)")
                end
            else
                log("TRANSCRIBE FAILED exit=" .. tostring(exitCode) .. " stderr=" .. tostring(stdErr))
            end
        end, {
            "-m", WHISPER_MODEL,
            "-f", AUDIO_FILE,
            "-l", "en",             -- skip language detection
            "-t", "6",              -- threads (M4: 4P + 6E cores)
            "--prompt", WHISPER_PROMPT,
            "--no-fallback",        -- disable temperature fallback (reduces hallucination)
            "--suppress-nst",       -- suppress non-speech token hallucinations
            "--vad",
            "--vad-model", VAD_MODEL,
            "-np",                  -- no prints (cleaner output)
            "-nt"                   -- no timestamps
        })
        transcribeTask:start()
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
