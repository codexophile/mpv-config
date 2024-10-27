local utils = require 'mp.utils'
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

-- Script options
local opts = {
    font_size = 30,
    font_color = "FFFFFF",
    background_color = "000000",
    background_alpha = "80",
    margin_x = 10,
    margin_y = 10,
    chapter_fade_timeout = 3
}
options.read_options(opts)

-- Initialize variables
local chapter_timer = nil
local last_chapter_title = ""

function get_current_chapter_title()
    local chapter_list = mp.get_property_native("chapter-list")
    local current_chapter = mp.get_property_number("chapter")
    
    if chapter_list and current_chapter and chapter_list[current_chapter + 1] then
        return chapter_list[current_chapter + 1].title
    end
    return ""
end

function get_playback_percentage()
    local position = mp.get_property_number("percent-pos", 0)
    return string.format("%.1f%%", position)
end

function create_ass_header()
    return string.format(
        "{\\a7\\fs%d\\1c&H%s\\b1\\bord2\\3c&H%s\\3a&H%s}",
        opts.font_size,
        opts.font_color,
        opts.background_color,
        opts.background_alpha
    )
end

function draw_elements()
    local ass = assdraw.ass_new()
    local w, h = mp.get_osd_size()
    
    -- Draw chapter title (top left)
    if last_chapter_title ~= "" then
        ass:new_event()
        ass:pos(opts.margin_x, opts.margin_y)
        ass:append(create_ass_header())
        ass:append(last_chapter_title)
    end
    
    -- Draw percentage (top right)
    ass:new_event()
    ass:pos(w - opts.margin_x, opts.margin_y)
    ass:append(create_ass_header())
    ass:append(get_playback_percentage())
    
    -- Update OSD
    mp.set_osd_ass(w, h, ass.text)
end

function chapter_change(_, current_chapter)
    if current_chapter then
        last_chapter_title = get_current_chapter_title()
        if chapter_timer then
            chapter_timer:kill()
        end
        chapter_timer = mp.add_timeout(opts.chapter_fade_timeout, function()
            last_chapter_title = ""
            draw_elements()
        end)
    end
    draw_elements()
end

-- Register event handlers
mp.observe_property("chapter", "number", chapter_change)
mp.observe_property("time-pos", "number", draw_elements)
mp.register_event("file-loaded", function()
    last_chapter_title = get_current_chapter_title()
    draw_elements()
end)