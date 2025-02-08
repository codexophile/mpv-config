local utils = require 'mp.utils'
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

-- Script options
local opts = {
    font_size = 20,
    font_color = "FFFFFF",
    background_color = "000000",
    background_alpha = "80",
    margin_x = 10,
    margin_y = 10,
    chapter_fade_timeout = 3
}
options.read_options(opts)

function get_current_chapter_title()
    local chapter_list = mp.get_property_native("chapter-list")
    local current_chapter = mp.get_property_number("chapter")
    
    if chapter_list and current_chapter ~= nil and #chapter_list > 0 then
        -- Always show "Chapter X" since we can see the titles are empty
        return string.format("Chapter %d / %d", current_chapter + 1, #chapter_list)
    end
    return ""
end

function get_playback_percentage()
    local position = mp.get_property_number("percent-pos", 0)
    return string.format("%.1f%%", position)
end

function get_remaining_time()
    local duration = mp.get_property_number("duration", 0)
    local position = mp.get_property_number("time-pos", 0)
    local speed = mp.get_property_number("speed", 1)
    
    local remaining_time = duration - position
    local apparent_remaining_time = remaining_time / speed
    
    local function format_time(seconds)
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    end
    
    return string.format("%s | %s", 
        format_time(remaining_time),
        format_time(apparent_remaining_time))
end

function get_frame_rate()
    local fps = mp.get_property_number("estimated-vf-fps", 0)
    return string.format("%.1f FPS", fps)
end

function get_video_dimensions()
    -- Get native video dimensions
    local video_w = mp.get_property_number("video-params/w", 0)
    local video_h = mp.get_property_number("video-params/h", 0)
    
    -- Get current window dimensions from osd-dimensions
    local osd_dim = mp.get_property_native("osd-dimensions")
    if not osd_dim then return "N/A" end
    
    local window_w = osd_dim.w
    local window_h = osd_dim.h
    
    -- Avoid division by zero
    if video_w == 0 or video_h == 0 then return "N/A" end
    
    -- Calculate scaling percentage
    local scale_w = (window_w / video_w) * 100
    local scale_h = (window_h / video_h) * 100
    
    -- Format the dimensions string
    return string.format("%dx%d → %dx%d (%.1f%%)", 
        video_w, video_h,
        math.floor(window_w), math.floor(window_h),
        (scale_w + scale_h) / 2)  -- Average scale percentage
end

function create_ass_header(alignment)
    return string.format(
        "{\\a%d\\fs%d\\1c&H%s\\b1\\bord2\\3c&H%s\\3a&H%s}",
        alignment,
        opts.font_size,
        opts.font_color,
        opts.background_color,
        opts.background_alpha
    )
end

function draw_elements()
    local ass = assdraw.ass_new()
    local w, h = mp.get_osd_size()
    
    -- Draw video dimensions
    ass:new_event()
    ass:append(create_ass_header(3))
    ass:pos(w - opts.margin_x, h - opts.margin_y - opts.font_size * 4 - 20)
    ass:append(get_video_dimensions())
    
    -- Draw percentage
    ass:new_event()
    ass:append(create_ass_header(3))
    ass:pos(w - opts.margin_x, h - opts.margin_y - opts.font_size * 2 - 10)
    ass:append(get_playback_percentage())

    -- Draw frame rate
    ass:new_event()
    ass:append(create_ass_header(3))
    ass:pos(w - opts.margin_x, h - opts.margin_y - opts.font_size * 3 - 15)
    ass:append(get_frame_rate())
    
    -- Draw remaining time
    ass:new_event()
    ass:append(create_ass_header(3))
    ass:pos(w - opts.margin_x, h - opts.margin_y - opts.font_size - 5)
    ass:append(get_remaining_time())
    
    -- Draw chapter number
    local chapter_text = get_current_chapter_title()
    if chapter_text ~= "" then
        ass:new_event()
        ass:append(create_ass_header(3))
        ass:pos(w - opts.margin_x, h - opts.margin_y)
        ass:append(chapter_text)
    end
    
    mp.set_osd_ass(w, h, ass.text)
end

-- Update more frequently to ensure chapter info is always visible
mp.observe_property("chapter", "number", function(_, current_chapter)
    draw_elements()
end)
mp.observe_property("estimated-vf-fps", "number", draw_elements)
mp.observe_property("time-pos", "number", draw_elements)
mp.observe_property("video-params/w", "number", draw_elements)
mp.observe_property("video-params/h", "number", draw_elements)
mp.observe_property("osd-dimensions", "native", draw_elements)
mp.register_event("file-loaded", function()
    draw_elements()
end)