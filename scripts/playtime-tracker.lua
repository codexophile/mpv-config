-- playtime-tracker.lua
--
-- Tracks the actual real-world (wall-clock) time spent in "playing" state
-- per file, excluding paused time. Speed setting is irrelevant: whether you
-- play at 0.5x, 1x, or 4x, what's recorded is the real seconds that elapsed
-- while unpaused -- not the amount of media consumed. Seeking around and
-- re-watching sections simply keeps adding real time; there is no
-- deduplication by media position.
--
-- For local files, data is stored as a numeric sidecar next to the media:
--   media-file-name.mp4.playtime
--
-- Install: save this file to your mpv "scripts" folder, e.g.
--   %APPDATA%\mpv\scripts\playtime-tracker.lua

local utils = require 'mp.utils'
local msg = require 'mp.msg'

local SAVE_INTERVAL = 10 -- seconds; periodic safety-save while playing

local current_key = nil
local current_playtime_path = nil
local total_seconds = 0  -- accumulated seconds for the current file (committed)
local segment_start = nil -- mp.get_time() timestamp of current unpaused run, or nil
local save_timer = nil
-- Other scripts can read this with:
-- mp.get_property_number("user-data/playtime-tracker-seconds", 0)
local PLAYTIME_PROPERTY = "user-data/playtime-tracker/seconds"
local PLAYTIME_FILE_PROPERTY = "user-data/playtime-tracker/file"

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
        msg.warn("failed to open " .. path .. " for writing: " .. tostring(err))
        return false
    end
    local ok, write_err = file:write(content)
    file:close()
    if not ok then
        msg.warn("failed to write " .. path .. ": " .. tostring(write_err))
        return false
    end
    return true
end

local function load_playtime(path)
    local content = read_file(path)
    if not content then
        msg.debug("load_playtime: file not found at " .. path)
        return 0
    end

    local trimmed = content:gsub("^%s+|%s+$", "")
    local value = tonumber(trimmed)
    if not value or value < 0 then
        msg.warn("could not parse " .. path .. ", content='" .. tostring(trimmed) .. "', starting at zero")
        return 0
    end
    msg.debug("load_playtime: " .. path .. " -> " .. tostring(value))
    return value
end

local function save_playtime(path, seconds)
    write_file(path, string.format("%.3f\n", seconds))
end

-- Live total for the current file, without mutating total_seconds.
local function live_total()
    local t = total_seconds
    if segment_start then
        t = t + (mp.get_time() - segment_start)
    end
    return t
end

local function publish_playtime()
    mp.set_property(PLAYTIME_PROPERTY, string.format("%.3f", live_total()))
    mp.set_property(PLAYTIME_FILE_PROPERTY, current_key or "")
end

-- Build a stable identity string for the currently loaded file.
local function file_key()
    local path = mp.get_property("path")
    if not path then
        msg.debug("file_key: no path property")
        return nil
    end

    msg.debug("file_key: raw path = " .. path)

    -- Leave URLs / protocol paths (http://, dvd://, etc.) alone.
    if path:find("^%a[%a%d+.-]*://") then
        msg.debug("file_key: URL, returning as-is")
        return path
    end

    -- Normalize local/relative paths to absolute so the same file always
    -- maps to the same key regardless of the working directory it was
    -- opened from.
    if not path:find("^%a:[\\/]") and not path:find("^[\\/]") then
        local wd = mp.get_property("working-directory")
        msg.debug("file_key: relative path, wd = " .. tostring(wd))
        if wd then
            path = utils.join_path(wd, path)
            msg.debug("file_key: normalized to " .. path)
        end
    else
        msg.debug("file_key: already absolute")
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

local function commit_and_save()
    if current_playtime_path then
        save_playtime(current_playtime_path, total_seconds)
    end
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
        if current_playtime_path then
            save_playtime(current_playtime_path, live_total())
        end
        publish_playtime()
    end)
end

local function on_pause_change(_, paused)
    if paused then
        close_segment()
        commit_and_save()
    else
        open_segment()
    end
    publish_playtime()
end

local function finalize_current_file()
    close_segment()
    commit_and_save()
    current_key = nil
    current_playtime_path = nil
    total_seconds = 0
    publish_playtime()
end

local function on_start_file()
    -- Safety: make sure any previous file's segment is closed/saved
    -- before switching keys (normally end-file already did this).
    finalize_current_file()
end

local function on_file_loaded()
    current_key = file_key()
    if not current_key then
        msg.debug("on_file_loaded: no current_key")
        return
    end

    msg.debug("on_file_loaded: key = " .. current_key)

    -- URLs have no local parent folder, so they are tracked for this session
    -- only. Local media uses the requested sibling sidecar file.
    if current_key:find("^%a[%a%d+.-]*://") then
        current_playtime_path = nil
        total_seconds = 0
        msg.debug("on_file_loaded: URL detected, no persistence")
    else
        current_playtime_path = current_key .. ".playtime"
        msg.debug("on_file_loaded: sidecar path = " .. current_playtime_path)
        total_seconds = load_playtime(current_playtime_path)
    end

    if mp.get_property_native("pause") then
        segment_start = nil
    else
        segment_start = mp.get_time()
    end

    msg.debug("File loaded: key=" .. tostring(current_key) .. " playtime=" .. tostring(total_seconds))
    publish_playtime()
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

mp.register_event("file-loaded", function()
  
  --! wrapping this in file-loaded event to ensure that the script-opts are 
  --! fully loaded before checking the option
  local enabled = mp.get_opt("playtime-tracker-enabled")
  if enabled ~= "yes" then
    return  -- bail out immediately, rest of the file never runs
  end

  mp.register_event("start-file", on_start_file)
  mp.register_event("file-loaded", on_file_loaded)
  mp.register_event("end-file", on_end_file)
  mp.register_event("shutdown", on_shutdown)
  mp.observe_property("pause", "bool", on_pause_change)

  -- Initialize properties at script startup
  mp.set_property(PLAYTIME_PROPERTY, "0")
  mp.set_property(PLAYTIME_FILE_PROPERTY, "")
  msg.debug("playtime-tracker initialized")

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
  mp.register_script_message("playtime-tracker-get", function()
      publish_playtime()
  end)

  mp.register_script_message("playtime-tracker-debug", function()
      local file_prop = mp.get_property(PLAYTIME_FILE_PROPERTY, "")
      local seconds_prop = mp.get_property(PLAYTIME_PROPERTY, "0")
      local loaded_path = mp.get_property("path", "?")
      local loaded_wd = mp.get_property("working-directory", "?")
      
      mp.osd_message(string.format(
          "FILE: %s | TRACKED_KEY: %s | TRACKED_SECS: %s | LIVE_KEY: %s | LIVE_SECS: %s | WD: %s",
          loaded_path, file_prop, seconds_prop, tostring(current_key), tostring(total_seconds), loaded_wd
      ))
  end)

end)
