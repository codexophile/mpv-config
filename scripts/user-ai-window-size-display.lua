-- Script to display window size as percentage of original video size
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local options = require 'mp.options'

-- State variables
local original_width = nil
local original_height = nil

-- Options
local opts = {
    duration = 1.5,
    position = "top-right"
}
options.read_options(opts)

-- Function to calculate and display size percentage
function calculate_size_percentage()
    if not original_width or not original_height then
        msg.info("Original dimensions not available")
        return
    end

    -- Get current window size
    local current_width = mp.get_property_number("osd-width")
    local current_height = mp.get_property_number("osd-height")
    
    if not current_width or not current_height then
        msg.info("Could not get current window dimensions")
        return
    end
    
    -- Calculate percentages
    local width_percent = math.floor((current_width / original_width) * 100)
    local height_percent = math.floor((current_height / original_height) * 100)
    
    -- Create display message
    local message = string.format("Size: %d%% x %d%%", width_percent, height_percent)
    
    -- Show OSD message
    mp.osd_message(message, opts.duration)
end

-- Function to store original video dimensions
function store_original_dimensions()
    -- Try to get video dimensions
    original_width = mp.get_property_number("video-params/w")
    original_height = mp.get_property_number("video-params/h")
    
    if not original_width or not original_height then
        msg.info("Trying fallback method for dimensions")
        original_width = mp.get_property_number("width")
        original_height = mp.get_property_number("height")
    end
    
    if original_width and original_height then
        msg.info(string.format("Original dimensions stored: %dx%d", original_width, original_height))
    else
        msg.error("Could not get video dimensions")
    end
end

-- Set up event handlers
mp.register_event("file-loaded", store_original_dimensions)
mp.observe_property("osd-width", "native", calculate_size_percentage)
mp.observe_property("osd-height", "native", calculate_size_percentage)
mp.add_key_binding("Alt+r", "show_size_percentage", calculate_size_percentage)

-- Print confirmation that script loaded
msg.info("Size percentage script loaded")