local options = require 'mp.options'
local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'

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

local function format_time(seconds)
    local safe_seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(safe_seconds / 3600)
    local minutes = math.floor((safe_seconds % 3600) / 60)
    local secs = safe_seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

function get_current_chapter_title()
    local chapter_list = mp.get_property_native("chapter-list")
    local current_chapter = mp.get_property_number("chapter")

    if chapter_list and current_chapter ~= nil and #chapter_list > 0 then
        local chapter_info = chapter_list[current_chapter + 1]
        if chapter_info and chapter_info.title and chapter_info.title ~= "" then
            return string.format("Chapter %d: %s", current_chapter + 1, chapter_info.title)
        end
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

    local remaining_time = math.max(0, duration - position)
    local apparent_remaining_time = speed > 0 and remaining_time / speed or 0

    return string.format("%s | %s",
        format_time(remaining_time),
        format_time(apparent_remaining_time))
end

function get_frame_rate()
    local fps = mp.get_property_number("estimated-vf-fps", 0)
    return string.format("%.1f FPS", fps)
end

function get_elapsed_time()
    local position = mp.get_property_number("time-pos", 0)
    return format_time(position)
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

function get_playtime_tracker()
    local seconds = mp.get_property_native("user-data/playtime-tracker/seconds", 0)
    local seconds_num = tonumber(seconds) 
    local seconds_int = math.floor((seconds_num)+0.5)
    return seconds_int 
end

function get_time_saved_so_far()
  local current_time = mp.get_property_number("time-pos", 0)
  local current_time_num = tonumber(current_time)
  local current_time_int = math.floor((current_time_num)+0.5)
  local current_play_time = get_playtime_tracker()
  local time_saved = current_time_int - current_play_time
  return time_saved
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

function draw_line(ass, w, y, text)
    ass:new_event()
    ass:append(create_ass_header(3))
    ass:pos(w - opts.margin_x, y)
    ass:append(text)
end

function draw_elements()
    mp.commandv("script-message", "playtime-tracker-get")

    local ass = assdraw.ass_new()
    local w, h = mp.get_osd_size()
    local base_y = h - opts.margin_y
    local line_h = opts.font_size + 6

    local lines = {
        get_video_dimensions(),
        get_frame_rate(),
        "⌚ " .. format_time(get_playtime_tracker()),
        "🛟 " .. format_time(get_time_saved_so_far()),
        get_elapsed_time() .. " " .. get_playback_percentage(),
        get_remaining_time()
    }

    local chapter_title = get_current_chapter_title()
    if chapter_title ~= "" then
        table.insert(lines, chapter_title)
    end

    local line_count = #lines
    for index, text in ipairs(lines) do
        local y = math.max(
            opts.margin_y + opts.font_size,
            base_y - line_h * (line_count - index)
        )
        draw_line(ass, w, y, text)
    end

    mp.set_osd_ass(w, h, ass.text)
end

-- Update more frequently to ensure chapter info is always visible
mp.observe_property("chapter", "number", function(_, _)
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