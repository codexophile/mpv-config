-- drive_specific_settings.lua

-- Define the target drives and their settings
local TARGET_DRIVES = {
    -- Drive letter (uppercase) : {saturation, volume}
    W = {saturation = 0.01, volume = 20},
    X = {saturation = 0.01, volume = 20},
    -- Add more drives here if needed, e.g.:
    -- Y = {saturation = 10, volume = 50},
}

-- Default settings to apply when the drive is NOT in TARGET_DRIVES
-- You might want to remove these if you prefer mpv's global defaults
local DEFAULT_SETTINGS = {
    saturation = 30, -- Default saturation
    volume = 100       -- Default volume (or whatever your mpv.conf default is)
}

-- Function to apply settings based on the current file path
local function apply_drive_settings()
    local path = mp.get_property("path")
    if not path then
        -- No file loaded yet, or path is somehow unavailable
        mp.msg.warn("drive_specific_settings: No path available yet.")
        return
    end

    -- Extract the drive letter (works for Windows paths like C:\, D:\, etc.)
    local drive_letter = string.match(path, "^([A-Za-z]):") -- Capture A-Z or a-z followed by :
    if drive_letter then
        drive_letter = string.upper(drive_letter) -- Convert to uppercase for lookup
    end

    local settings_to_apply = nil

    if drive_letter and TARGET_DRIVES[drive_letter] then
        settings_to_apply = TARGET_DRIVES[drive_letter]
        mp.msg.info(string.format("drive_specific_settings: Applying settings for drive %s.", drive_letter))
    else
        settings_to_apply = DEFAULT_SETTINGS
        if drive_letter then
            mp.msg.info(string.format("drive_specific_settings: Applying default settings (drive %s not in list).", drive_letter))
        else
            mp.msg.info("drive_specific_settings: Applying default settings (no drive letter found).")
        end
    end

    if settings_to_apply then
        mp.set_property("saturation", settings_to_apply.saturation)
        mp.set_property("volume", settings_to_apply.volume)
    end
end

-- Register the function to run when a file is loaded
-- "file-loaded" event is perfect as it fires after a new file starts playing
mp.register_event("file-loaded", apply_drive_settings)

-- Also run it once on script load/initialization, in case mpv starts with a file
-- or for seeking within the same file.
apply_drive_settings()

-- Optional: If you want settings to revert when *no* file is loaded (e.g., in playlist mode,
-- or when mpv is idle), you could listen for "idle" and set defaults.
-- mp.register_event("idle", function()
--    -- Apply default settings when idle, if desired
--    mp.set_property("saturation", DEFAULT_SETTINGS.saturation)
--    mp.set_property("volume", DEFAULT_SETTINGS.volume)
-- end)

mp.msg.info("drive_specific_settings.lua: Script loaded.")