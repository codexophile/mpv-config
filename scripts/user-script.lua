local utils = require 'mp.utils'

--* copy current frame to clipboard
function copy_frame_to_clipboard()
    local tmp_file = mp.command_native({"expand-path", "~~/tmp_screenshot.png"})
    local platform = mp.get_property("platform") or "unknown"

    local ok, err = pcall(function()
        mp.commandv("screenshot-to-file", tmp_file)
    end)

    if not ok then
        mp.osd_message("screenshot failed: " .. tostring(err))
        return
    end

    if platform == "windows" then
        local ps_path = tmp_file:gsub('"', '`"')
        local ps_script = string.format([[Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $p="%s"; $img=[System.Drawing.Image]::FromFile($p); [System.Windows.Forms.Clipboard]::SetImage($img); Remove-Item $p]], ps_path)
        local res = utils.subprocess({ args = {"powershell", "-NoProfile", "-Command", ps_script} })
        if res.status ~= 0 then
            mp.osd_message("clipboard copy failed")
            mp.msg.warn("clipboard copy failed: " .. (res.stderr or ""))
            return
        end
        mp.osd_message("frame copied to clipboard")
    else
        mp.osd_message("clipboard copy not implemented for this OS")
    end
end

-- The most common approach uses a dedicated script that first saves a screenshot and then calls the OS utility.
-- The core logic for the OS specific command has to be correct.

--*

-- ab_text.lua
function custom_ab_loop()
        mp.osd_message("xxxxxxxxxxx")

    -- Get the current state of the loop points
    local a_point = mp.get_property("ab-loop-a")
    local b_point = mp.get_property("ab-loop-b")

    -- Execute the native ab-loop command silently (no-osd)
    mp.command("no-osd ab-loop")
    -- Determine which message to show based on the Previous state
    if a_point == "no" then
        mp.osd_message("point a set")
    elseif b_point == "no" then
        mp.osd_message("point b set")
    else
        mp.osd_message("ab loop cleared")
    end
end



local function set_ab_point(which)
    local time_pos = mp.get_property_number("time-pos")
    if not time_pos then
        mp.osd_message("No playback position available")
        return
    end

    mp.set_property_number(which, time_pos)

    local label = which == "ab-loop-a" and "A" or "B"
    mp.osd_message(string.format("point %s set at %.3fs", label, time_pos))
end


local high_contrast = false
function toggle_contrast_gamma()

    if high_contrast then
        mp.set_property("contrast", 1)
        mp.set_property("gamma", 1)
        high_contrast = false
    else
        mp.set_property("contrast", 100)
        mp.set_property("gamma", 20)
        high_contrast = true
    end

    display_current_display_settings()
    
end

function display_current_display_settings()
    local brightness = mp.get_property("brightness")
    local contrast   = mp.get_property("contrast")
    local gamma      = mp.get_property("gamma")
    local saturation = mp.get_property("saturation")
    local hue        = mp.get_property("hue")

    brightness = round_and_pad(brightness, 3)
    contrast   = round_and_pad(contrast,   3)
    gamma      = round_and_pad(gamma,      3)
    saturation = round_and_pad(saturation, 3)
    hue        = round_and_pad(hue,        3)

    mp.osd_message( "Brightness: " .. brightness .. "\n" ..
                    "Contrast  : " .. contrast .. "\n" ..
                    "Gamma     : " .. gamma .. "\n" ..
                    "Saturation: " .. saturation .. "\n" ..
                    "Hue       : " .. hue)
end

local function create_toggler(property)
    local original_value = nil
    return function()
        if original_value == nil then
            original_value = mp.get_property_number(property)
            mp.set_property_number(property, 0)
        else
            mp.set_property_number(property, original_value)
            original_value = nil
        end
        mp.osd_message(string.format("%s: %s", property, mp.get_property(property)))
    end
end

function round_and_pad(number, width)
    local rounded_number = math.floor(number + 0.5)
    local padded_number = string.format("%0" .. width .. "d", rounded_number)
    return padded_number
end

function delete_current_file()
    local current_file = mp.get_property("path")
    if not current_file then
        mp.osd_message("No file is currently playing")
        return
    end

    -- Convert to absolute path if necessary
    current_file = mp.command_native({"expand-path", current_file})

    -- Use PowerShell to move the file to the Recycle Bin
    local ps_command = string.format([[
        Add-Type -AssemblyName Microsoft.VisualBasic;
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("%s", 'OnlyErrorDialogs', 'SendToRecycleBin')
    ]], current_file:gsub("\\", "\\\\"):gsub('"', '\\"'))

    local delete_result = utils.subprocess({ args = {'powershell', '-NoProfile', '-Command', ps_command} })

    if delete_result.status == 0 then
        mp.osd_message("File sent to Recycle Bin")
        
        -- Get current playlist position and count
        local playlist_pos = mp.get_property_number("playlist-pos")
        local playlist_count = mp.get_property_number("playlist-count")
        
        mp.osd_message(string.format("Playlist position: %s, Count: %s", playlist_pos, playlist_count))
        
        if playlist_count > 1 then
            if playlist_pos < (playlist_count - 1) then
                mp.commandv("playlist-next")
            else
                mp.commandv("playlist-prev")
            end
        else
            mp.osd_message("No more files in playlist")
        end
        
        -- Check if playback started
        mp.add_timeout(0.5, function()
            local new_path = mp.get_property("path")
            if new_path then
                mp.osd_message("Now playing: " .. new_path)
            else
                mp.osd_message("Failed to start next file")
            end
        end)
    else
        mp.osd_message("Failed to delete file: " .. (delete_result.stderr or "Unknown error"))
    end
end

function on_file_loaded()
    local path = mp.get_property("path")
    if path then
        local filename = mp.get_property("filename")
        local title = filename
        
        -- Convert path to lowercase for case-insensitive matching
        local path_lower = path:lower()
        
        -- Check if path contains 'tv' or 'movies' folder
        if path_lower:match("[/\\]tv[/\\]") then
            title = filename .. " [tv]"
        elseif path_lower:match("[/\\]movies?[/\\]") then
            title = filename .. " [movie]"
        end
        
        mp.set_property("title", title)
    end
end

function take_custom_screenshot()
    local video_path = mp.get_property("path")
    local video_directory = utils.split_path(video_path)
    local video_name = mp.get_property("filename/no-ext")
    
    local screenshot_template = string.format("%s/%s_screenshot_%%04d.png", video_directory, video_name)
    
    local i = 1
    local screenshot_path = string.format(screenshot_template, i)
    
    while utils.file_info(screenshot_path) do
        i = i + 1
        screenshot_path = string.format(screenshot_template, i)
    end
    
    mp.commandv("screenshot-to-file", screenshot_path)
    mp.osd_message(string.format("Screenshot saved: %s", screenshot_path))
end

function test()
end

function resize_to_video()
    -- Print debug information
    print("Double-click triggered resize function")
    
    local video_width = mp.get_property_number("video-params/w")
    local video_height = mp.get_property_number("video-params/h")
    
    print("Video width: " .. tostring(video_width))
    print("Video height: " .. tostring(video_height))
    
    if video_width and video_height then
        local success, err = pcall(function()
            mp.set_property_number("window-width", video_width)
            mp.set_property_number("window-height", video_height)
        end)
        
        if not success then
            print("Error setting window size: " .. tostring(err))
        else
            print("Window resize successful")
        end
    else
        print("Could not retrieve video dimensions")
    end
end

mp.register_event("file-loaded", on_file_loaded)

mp.add_key_binding(nil, "take-custom-screenshot", take_custom_screenshot)
mp.add_key_binding("KP_DEL", "delete_current_file", delete_current_file)

mp.register_script_message("test", test)
mp.register_script_message("resize-to-video", resize_to_video)

mp.register_script_message("display_current_display_settings", display_current_display_settings)
mp.register_script_message("toggle_contrast_gamma", toggle_contrast_gamma)
mp.register_script_message("toggle-saturation", create_toggler("saturation"))
mp.register_script_message("toggle-contrast", create_toggler("contrast"))
mp.register_script_message("toggle-gamma", create_toggler("gamma"))

mp.add_key_binding("\\", "display-ab-state", custom_ab_loop)
mp.add_key_binding("[", "set-ab-point-a", function() set_ab_point("ab-loop-a") end)
mp.add_key_binding("]", "set-ab-point-b", function() set_ab_point("ab-loop-b") end)

mp.add_key_binding("ctrl+c", "copy-frame", copy_frame_to_clipboard) 
