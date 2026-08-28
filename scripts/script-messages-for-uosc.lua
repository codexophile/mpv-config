local ahkPath = "C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64_UIA.exe"
local scriptPath = "C:\\mega\\IDEs\\AutoHotkey v2\\mpv-assistant.ahk"

local function get_loaded_filename()
  local filename = mp.get_property("filename")

  if not filename or filename == "" then
    mp.osd_message("No file is loaded")
    return nil
  end

  return filename
end

local function launch_assistant(action)
  local filename = get_loaded_filename()

  if not filename then
    return
  end

  local cmd = {
    name = "subprocess",
    playback_only = false,
    capture_stdout = true,
    capture_stderr = true,
    args = {
      "cmd.exe",
      "/c",
      "start",
      "",
      ahkPath,
      scriptPath,
      action,
      "--file-name:" .. filename,
    },
  }

  local result = mp.command_native(cmd)

  if not result or result.status ~= 0 then
    mp.msg.error(((result and result.stderr) or "AutoHotkey launch failed"):gsub("%s+$", ""))
    mp.osd_message("Failed to launch AutoHotkey")
  end
end

local function show_playtime()
  -- Request tracker to publish current values
  mp.commandv("script-message", "playtime-tracker-get")
  
  -- Add delay to ensure property is updated
  mp.add_timeout(0.05, function()
    local seconds = mp.get_property(
      "user-data/playtime-tracker/seconds",
      -1
    )
    local current_file = mp.get_property("path", "")

    mp.osd_message("Playtime for current file: " .. tostring(seconds) .. " seconds")
    -- return
    
    -- if not current_file or current_file == "" then
    --   mp.osd_message("No file loaded")
    --   return
    -- end
    
    -- if seconds < 0 then
    --   mp.osd_message("Playtime property not found")
    --   return
    -- end
    
    -- if seconds > 0 then
    --   local hours = math.floor(seconds / 3600)
    --   local mins = math.floor((seconds % 3600) / 60)
    --   local secs = math.floor(seconds % 60)
    --   if hours > 0 then
    --     mp.osd_message(string.format("Playtime: %02d:%02d:%02d", hours, mins, secs))
    --   else
    --     mp.osd_message(string.format("Playtime: %02d:%02d", mins, secs))
    --   end
    -- else
    --   mp.osd_message("New file - no playtime yet")
    -- end
  end)
end

mp.register_script_message("uosc-test", show_playtime)

mp.register_script_message("open-in-imdb", function()
  launch_assistant("--open-in-imdb")
end)

mp.register_script_message("open-in-trakt", function()
  launch_assistant("--open-in-trakt")
end)
