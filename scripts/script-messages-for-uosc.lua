local ahkPath = "C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64_UIA.exe"
local scriptPath = "C:\\mega\\IDEs\\AutoHotkey v2\\mpv-assistant.ahk"

mp.register_script_message("open-in-imdb", function()
  local filename = mp.get_property("filename")

  if not filename or filename == "" then
    mp.osd_message("No file is loaded")
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
      "--open-in-imdb",
      "--file-name:" ..filename,
    },
  }

  local result = mp.command_native(cmd)
  if result.status ~= 0 then
    mp.msg.error((result.stderr or "AutoHotkey launch failed"):gsub("%s+$", ""))
    mp.osd_message("Failed to launch AutoHotkey")
  end
end)