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
 local var = mp.get_opt("playtime-tracker-enabled")
 mp.osd_message("playtime-tracker-enabled: " .. tostring(var))
end

mp.register_script_message("uosc-test", show_playtime)

mp.register_script_message("open-in-imdb", function()
  launch_assistant("--open-in-imdb")
end)

mp.register_script_message("open-in-trakt", function()
  launch_assistant("--open-in-trakt")
end)
