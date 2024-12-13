-- Dark Scene Detection and Auto-Adjustment Script for MPV
-- Save as dark_scene_detection.lua

local options = {
    -- Threshold for dark scene detection (0-100)
    darkness_threshold = 10,
    
    -- Adjustment values
    dark_contrast = 100,
    dark_gamma = 1,
    
    -- Default values
    default_contrast = 0,
    default_gamma = 1.0,
    
    -- Minimum number of consecutive dark frames to trigger
    frame_threshold = 5
}

local dark_mode_active = false
local dark_frame_count = 0

-- Function to get frame brightness using video-params
function get_frame_brightness()
    local brightness = mp.get_property_number("estimated-vf-fps")
    if brightness then
        -- mp.msg.info("[user_ai_dark_scene_detection] Current brightness: " .. brightness)
    end
    return brightness
end

-- Function to adjust video settings with hysteresis
function adjust_settings(is_dark)
    if is_dark then
        dark_frame_count = dark_frame_count + 1
    else
        dark_frame_count = 0
    end

    -- Only switch to dark mode after several consecutive dark frames
    if dark_frame_count >= options.frame_threshold and not dark_mode_active then
        mp.set_property_number("contrast", options.dark_contrast)
        mp.set_property_number("gamma", options.dark_gamma)
        dark_mode_active = true
        mp.osd_message("Dark scene detected - Adjusting settings")
    -- Switch back to normal immediately when bright
    elseif dark_frame_count == 0 and dark_mode_active then
        mp.set_property_number("contrast", options.default_contrast)
        mp.set_property_number("gamma", options.default_gamma)
        dark_mode_active = false
        mp.osd_message("Normal brightness - Resetting settings")
    end
end

-- Main processing function
function check_scene()
    local brightness = get_frame_brightness()
    if brightness then
        adjust_settings(brightness < options.darkness_threshold)
    end
end

-- Register script
mp.register_event("tick", check_scene)

-- Reset settings when video changes
mp.register_event("file-loaded", function()
    dark_mode_active = false
    dark_frame_count = 0
    mp.set_property_number("contrast", options.default_contrast)
    mp.set_property_number("gamma", options.default_gamma)
end)

-- Add key binding to toggle debug info
mp.add_key_binding("Ctrl+Alt+d", "toggle-dark-scene-debug", function()
    local brightness = get_frame_brightness()
    mp.osd_message(string.format(
        "Dark Scene Debug:\nDark mode: %s\nCurrent brightness: %.2f\nDark frame count: %d\nThreshold: %d",
        dark_mode_active and "active" or "inactive",
        brightness or 0,
        dark_frame_count,
        options.darkness_threshold
    ))
end)