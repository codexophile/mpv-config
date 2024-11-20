-- selectable-subs.lua
local mp = require 'mp'
local utils = require 'mp.utils'
local opts = require 'mp.options'
local assdraw = require 'mp.assdraw'

local options = {
    key_toggle = 'Ctrl+Alt+c',
    mouse_btn = 'MBTN_LEFT',
    font_size = 35,  -- Match your mpv.conf font size
    background_alpha = '80',
}

opts.read_options(options)

local subtitle_overlay = mp.create_osd_overlay('ass-events')
local is_active = false
local current_subs = {}
local selected_text = ''

-- Function to escape ASS tags
local function escape_ass(str)
    if not str then return "" end
    return str:gsub('\\', '\\\\'):gsub('{', '\\{'):gsub('}', '\\}')
end

-- Function to convert window coordinates to video coordinates considering subtitle position
function window_to_video_coords(wx, wy)
    local video_width = mp.get_property_number('width', 0)
    local video_height = mp.get_property_number('height', 0)
    local window_width = mp.get_property_number('osd-width', 0)
    local window_height = mp.get_property_number('osd-height', 0)
    local sub_pos = mp.get_property_number('sub-pos', 100)
    
    -- Calculate scaling factors
    local scale_x = video_width / window_width
    local scale_y = video_height / window_height
    
    -- Convert coordinates
    local video_x = wx * scale_x
    local video_y = wy * scale_y
    
    -- Debug message for coordinates
    mp.osd_message(string.format("Click: %.1f, %.1f (Scale: %.2f, %.2f)", video_x, video_y, scale_x, scale_y), 1)
    
    return video_x, video_y
end

-- Function to create clickable region
local function create_clickable_region(text, x, y, w, h)
    local ass = assdraw.ass_new()
    
    -- Semi-transparent background for debugging
    ass:new_event()
    ass:pos(x, y)
    ass:append(string.format('{\\1a&H%s&\\1c&H0000FF&}', options.background_alpha))  -- Blue background
    ass:draw_start()
    ass:rect_cw(0, 0, w, h)
    ass:draw_stop()
    
    -- Add text
    ass:new_event()
    ass:pos(x, y)
    ass:append(string.format('{\\fs%d\\an7\\1c&HFFFFFF&\\3c&H000000&\\3a&H00&}', options.font_size))
    ass:append(escape_ass(text))
    
    return ass.text
end

-- Function to handle mouse clicks
function on_mouse_click()
    if not is_active then return end
    
    local mx, my = mp.get_mouse_pos()
    local video_x, video_y = window_to_video_coords(mx, my)
    
    -- Debug visualization of click regions
    local debug_msg = string.format("Click at: %.1f, %.1f\nRegions:", video_x, video_y)
    for i, sub in ipairs(current_subs) do
        debug_msg = debug_msg .. string.format("\nRegion %d: (%.1f,%.1f)-(%.1f,%.1f)", 
            i, sub.x, sub.y, sub.x + sub.w, sub.y + sub.h)
            
        if video_x >= sub.x and video_x <= (sub.x + sub.w) and
           video_y >= sub.y and video_y <= (sub.y + sub.h) then
            selected_text = sub.text
            if package.config:sub(1,1) == '\\' then  -- Windows
                mp.commandv('run', 'powershell', '-command', string.format('Set-Clipboard "%s"', selected_text))
            else  -- Linux/Unix
                mp.command(string.format([[run bash -c "echo -n '%s' | xclip -selection clipboard"]], selected_text:gsub("'", "'\\''"):gsub("\n", " ")))
            end
            mp.osd_message(string.format('Copied: %s', selected_text), 1)
            return
        end
    end
    mp.osd_message(debug_msg, 3)  -- Show debug info for 3 seconds
end

-- Function to handle subtitle updates
function on_subtitle_change(name, value)
    if not is_active then return end
    
    if not value then
        current_subs = {}
        subtitle_overlay.data = ""
        subtitle_overlay:update()
        return
    end
    
    current_subs = {}
    local video_width = mp.get_property_number('width', 0)
    local video_height = mp.get_property_number('height', 0)
    local sub_pos = mp.get_property_number('sub-pos', 100)
    
    -- Calculate base Y position based on sub-pos
    local base_y = (video_height * (100 - sub_pos) / 100)
    
    local lines = {}
    for line in value:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    local ass_text = ''
    local y_pos = base_y - (#lines * (options.font_size + 10))
    
    for i, line in ipairs(lines) do
        local w = video_width * 0.8
        local x = (video_width - w) / 2
        local h = options.font_size + 15  -- Increased height for better clickability
        
        table.insert(current_subs, {
            text = line,
            x = x,
            y = y_pos,
            w = w,
            h = h
        })
        
        ass_text = ass_text .. create_clickable_region(line, x, y_pos, w, h)
        y_pos = y_pos + h + 6
    end
    
    subtitle_overlay.data = ass_text
    subtitle_overlay:update()
end

-- Function to toggle the script
function toggle_script()
    is_active = not is_active
    if is_active then
        local track_list = mp.get_property_native("track-list")
        local has_subs = false
        for _, track in ipairs(track_list) do
            if track.type == "sub" and track.selected then
                has_subs = true
                break
            end
        end
        
        if not has_subs then
            mp.osd_message("No subtitle track selected!")
            is_active = false
            return
        end
        
        mp.observe_property('sub-text', 'string', on_subtitle_change)
        local current_text = mp.get_property('sub-text')
        on_subtitle_change('sub-text', current_text)
        mp.osd_message('Selectable subtitles enabled')
    else
        mp.unobserve_property(on_subtitle_change)
        subtitle_overlay.data = ''
        subtitle_overlay:update()
        mp.osd_message('Selectable subtitles disabled')
    end
end

-- Register key bindings
mp.add_key_binding(options.key_toggle, 'toggle-selectable-subs', toggle_script)
mp.add_forced_key_binding(options.mouse_btn, 'copy-subtitle', on_mouse_click)

-- Initial setup
subtitle_overlay.data = ""
subtitle_overlay:update()