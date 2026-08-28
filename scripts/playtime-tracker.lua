-- playtime-tracker.lua
--
-- Tracks the actual real-world (wall-clock) time spent in "playing" state
-- per file, excluding paused time. Speed setting is irrelevant: whether you
-- play at 0.5x, 1x, or 4x, what's recorded is the real seconds that elapsed
-- while unpaused -- not the amount of media consumed. Seeking around and
-- re-watching sections simply keeps adding real time; there is no
-- deduplication by media position.
--
-- Data is stored as JSON at: <mpv config dir>/playtime.json
-- (on Windows, typically: %APPDATA%\mpv\playtime.json)
--
-- Install: save this file to your mpv "scripts" folder, e.g.
--   %APPDATA%\mpv\scripts\playtime-tracker.lua

local utils = require 'mp.utils'
local msg = require 'mp.msg'

local SAVE_INTERVAL = 10 -- seconds; periodic safety-save while playing

local db = {}            -- key(path) -> accumulated seconds (persisted)
local db_path = nil
local current_key = nil
local total_seconds = 0  -- accumulated seconds for the current file (committed)
local segment_start = nil -- mp.get_time() timestamp of current unpaused run, or nil
local save_timer = nil

local function expand_path(p)
    return mp.command_native({"expand-path", p})
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path, content)
    local file, err = io.open(path, "wb")
    if not file then
        msg.warn("failed to open playtime.json for writing: " .. tostring(err))
        return false
    end
    local ok, write_err = file:write(content)
    file:close()
    if not ok then
        msg.warn("failed to write playtime.json: " .. tostring(write_err))
        return false
    end
    return true
end

local function load_db()
    local content = read_file(db_path)
    if content then
        local ok, parsed = pcall(utils.parse_json, content)
        if ok and type(parsed) == "table" then
            db = parsed
        else
            msg.warn("could not parse playtime.json, starting fresh")
        end
    end
end

local function save_db()
    local ok, encoded = pcall(utils.format_json, db)
    if ok and encoded then
        write_file(db_path, encoded)
    else
        msg.warn("failed to encode playtime db")
    end
end

-- Live total for the current file, without mutating total_seconds.
local function live_total()
    local t = total_seconds
    if segment_start then
        t = t + (mp.get_time() - segment_start)
    end
    return t
end

-- Build a stable identity string for the currently loaded file.
local function file_key()
    local path = mp.get_property("path")
    if not path then return nil end

    -- Leave URLs / protocol paths (http://, dvd://, etc.) alone.
    if path:find("^%a[%a%d+.-]*://") then
        return path
    end

    -- Normalize local/relative paths to absolute so the same file always
    -- maps to the same key regardless of the working directory it was
    -- opened from.
    if not path:find("^%a:[\\/]") and not path:find("^[\\/]") then
        local wd = mp.get_property("working-directory")
        if wd then
            path = utils.join_path(wd, path)
        end
    end
    return path
end

-- Commit the currently-open segment (if any) into total_seconds and
-- close it. Call this whenever we transition out of "playing".
local function close_segment()
    if segment_start then
        total_seconds = total_seconds + (mp.get_time() - segment_start)
        segment_start = nil
    end
end

local function open_segment()
    if not segment_start then
        segment_start = mp.get_time()
    end
end

-- Write current file's total into the db table (in-memory) and persist.
local function commit_and_save()
    if current_key then
        db[current_key] = total_seconds
    end
    save_db()
end

local function stop_save_timer()
    if save_timer then
        save_timer:kill()
        save_timer = nil
    end
end

local function start_save_timer()
    stop_save_timer()
    save_timer = mp.add_periodic_timer(SAVE_INTERVAL, function()
        if current_key then
            db[current_key] = live_total()
            save_db()
        end
    end)
end

local function on_pause_change(_, paused)
    if paused then
        close_segment()
        if current_key then
            db[current_key] = total_seconds
            save_db()
        end
    else
        open_segment()
    end
end

local function finalize_current_file()
    close_segment()
    if current_key then
        db[current_key] = total_seconds
        save_db()
    end
    current_key = nil
    total_seconds = 0
end

local function on_start_file()
    -- Safety: make sure any previous file's segment is closed/saved
    -- before switching keys (normally end-file already did this).
    finalize_current_file()
end

local function on_file_loaded()
    current_key = file_key()
    if not current_key then return end

    total_seconds = tonumber(db[current_key]) or 0

    if mp.get_property_native("pause") then
        segment_start = nil
    else
        segment_start = mp.get_time()
    end

    start_save_timer()
end

local function on_end_file()
    stop_save_timer()
    finalize_current_file()
end

local function on_shutdown()
    stop_save_timer()
    finalize_current_file()
end

-- Init
local config_dir = expand_path("~~/")
db_path = utils.join_path(config_dir, "playtime.json")
load_db()

mp.register_event("start-file", on_start_file)
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", on_end_file)
mp.register_event("shutdown", on_shutdown)
mp.observe_property("pause", "bool", on_pause_change)

-- Optional: bind a key to show the current file's tracked playtime as OSD.
-- Remove this if you don't want it, or rebind via input.conf instead:
--   script-message playtime-tracker-show
mp.register_script_message("playtime-tracker-show", function()
    local t = live_total()
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t % 60)
    mp.osd_message(string.format("Playtime this file: %02d:%02d:%02d", h, m, s))
end)
