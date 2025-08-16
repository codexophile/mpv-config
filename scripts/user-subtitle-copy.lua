-- Word-level clickable subtitle copy & hover highlight
-- NOTE: This is a best-effort geometric approximation and may not perfectly match libass layout,
-- especially with complex ASS styling, embedded fonts, karaoke, ruby, RTL scripts, or no-space languages.

local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

-- ================= Clipboard =================
local function copy_to_clipboard(text)
    if not text or text == '' then return end
    text = text:gsub('"', '\\"')
    text = text:gsub('\r', ' '):gsub('\n', ' ') -- single line
    local args = { 'cmd.exe', '/d', '/c', 'echo ' .. text .. ' | clip' }
    utils.subprocess({ args = args, cancellable = false })
end

local function copy_full_sub()
    local sub_text = mp.get_property('sub-text')
    if sub_text then copy_to_clipboard(sub_text) end
end

mp.add_key_binding('ctrl+shift+c', 'copy_subtitle', copy_full_sub)

-- ================= Word parsing & geometry =================
---@class WordBox
---@field word string
---@field x number  -- left
---@field y number  -- top
---@field w number
---@field h number

local current_words = {}        -- flat array of WordBox
local hovered_index = nil       -- index in current_words
local osd_overlay = mp.create_osd_overlay('ass-events')
local last_sub_id = 0
local msg = require 'mp.msg'

-- Config (simple heuristics)
local cfg = {
    max_words = 400,          -- safety limit
    highlight_color = '&H220000FF', -- BGR with alpha (semi-transparent red fill)
    highlight_border_color = '&H000000FF',
    border = 2,
    manual_y_offset = 0,      -- user tweak (pixels), positive = down
    measure_space_cache = true,
}

-- Measurement overlay (compute_bounds)
local measure_osd = mp.create_osd_overlay('ass-events')
measure_osd.compute_bounds = true
measure_osd.hidden = true

local space_width_cache = nil
local word_width_cache = {}

local function ass_escape(text)
    return text:gsub('\\','\\\\'):gsub('{','\\{'):gsub('}','\\}')
end

local function measure_text(text)
    local w,h = 0,0
    local ow,oh = mp.get_osd_size()
    measure_osd.res_x, measure_osd.res_y = ow, oh
    measure_osd.data = '{\\an7}' .. ass_escape(text)
    local res = measure_osd:update()
    if res and res.x0 and res.x1 then
        w = res.x1 - res.x0
        h = res.y1 - res.y0
    end
    return w,h
end

local function get_space_width()
    if space_width_cache and cfg.measure_space_cache then return space_width_cache end
    local w = measure_text(' ')
    space_width_cache = w
    return w
end

local function get_word_width(word)
    local cached = word_width_cache[word]
    if cached then return cached end
    local w = measure_text(word)
    word_width_cache[word] = w
    return w
end

local function strip_ass_tags(s)
    -- remove simple ASS override tags {\...}
    return (s or ''):gsub('{[^}]-}', '')
end

local function split_lines(s)
    local t = {}
    for line in (s .. '\n'):gmatch('([^\n]*)\n') do table.insert(t, line) end
    return t
end

local punctuation_pattern = '^[%p]+([%w].-[%w])[%p]+$'

local function normalize_word(raw)
    if raw == '' then return '' end
    -- trim punctuation edges but keep internal (e.g., don't break can't)
    local w = raw:match('^%p*(.-)%p*$') or raw
    return w
end

local function build_word_boxes()
    current_words = {}
    hovered_index = nil
    local sub_text = mp.get_property('sub-text')
    if not sub_text or sub_text == '' then return end
    -- Reset caches if font-size changed (simple approach)
    local font_size = mp.get_property_number('sub-font-size') or 55
    if font_size ~= last_sub_id then -- reuse last_sub_id variable for simple invalidation
        word_width_cache = {}
        space_width_cache = nil
        last_sub_id = font_size
    end
    local dims = mp.get_property_native('osd-dimensions') or {}
    local dw, dh = (dims.w or 1280), (dims.h or 720)
    local mb = dims.mb or 0
    local mt = dims.mt or 0
    local sub_pos = mp.get_property_number('sub-pos') or 100 -- 0=top 100=bottom
    local usable_h = dh - mt - mb
    local space_w = get_space_width()

    -- basic bottom-centered block layout
    local plain = strip_ass_tags(sub_text)
    local lines = split_lines(plain)
    if #lines == 0 then return end
    msg.verbose('[user_subtitle_copy] lines:', #lines)

    -- measure each line width & height
    local line_metrics = {}
    local total_height = 0
    for i,line in ipairs(lines) do
        local w,h = measure_text(line == '' and ' ' or line)
        line_metrics[i] = {width = w, height = h}
        total_height = total_height + h
    end

    local block_height = total_height
    local y_top = mt + (usable_h - block_height) * (sub_pos / 100) + cfg.manual_y_offset
    msg.verbose(string.format('[user_subtitle_copy] dims: w=%d h=%d mt=%d mb=%d sub-pos=%d y_top=%.1f block_h=%.1f', dw, dh, mt, mb, sub_pos, y_top, block_height))

    local idx = 0
    local acc_height = 0
    for li,line in ipairs(lines) do
        local lm = line_metrics[li]
        local line_h = lm.height
        local line_w = lm.width
        local x_start = (dw - line_w) / 2
        local cursor_x = x_start
        for raw in line:gmatch('%S+') do
            local word = normalize_word(raw)
            if word ~= '' then
                local w_px = get_word_width(raw)
                idx = idx + 1
                if idx > cfg.max_words then break end
                table.insert(current_words, {
                    word = word,
                    x = cursor_x,
                    y = y_top + acc_height,
                    w = w_px,
                    h = line_h,
                })
                cursor_x = cursor_x + w_px + space_w
            else
                cursor_x = cursor_x + space_w
            end
        end
        acc_height = acc_height + line_h
        if idx > cfg.max_words then break end
    end
    msg.verbose(string.format('[user_subtitle_copy] built %d word boxes', #current_words))
end

-- ================= Hover highlight rendering =================
local function render_highlight()
    osd_overlay.res_x, osd_overlay.res_y = mp.get_osd_size()
    if not hovered_index or not current_words[hovered_index] then
        osd_overlay.data = ''
        osd_overlay.hidden = false
        osd_overlay:update()
        return
    end
    local wb = current_words[hovered_index]
    local a = assdraw.ass_new()
    -- draw rectangle behind word (slight padding)
    local pad_x = 4
    local pad_y = 2
    local x0 = wb.x - pad_x
    local y0 = wb.y - pad_y
    local x1 = wb.x + wb.w + pad_x
    local y1 = wb.y + wb.h - pad_y
    -- Escape backslashes for Lua so ASS tags remain intact
    -- Use explicit alpha on primary color (1a) to avoid unintended inheritance
    a:append(string.format([[{\an7\pos(0,0)\bord%d\shad0\1c%s\3c%s\1a&H40&}]], cfg.border, cfg.highlight_color, cfg.highlight_border_color))
    -- shape (vector drawing)
    a:append(string.format([[{\p1}m %d %d l %d %d %d %d %d %d{\p0}]], x0, y0, x1, y0, x1, y1, x0, y1))
    osd_overlay.data = a.text
    osd_overlay.hidden = false
    osd_overlay:update()
end

-- ================= Mouse handling =================
local function update_hover(mx, my)
    if not mx or not my then return end
    local prev = hovered_index
    hovered_index = nil
    for i, wb in ipairs(current_words) do
        if mx >= wb.x and mx <= wb.x + wb.w and my >= wb.y and my <= wb.y + wb.h then
            hovered_index = i
            break
        end
    end
    if prev ~= hovered_index then render_highlight() end
end

-- Observe mouse position
-- Observe property (may not fire on all builds) + fallback binding
mp.observe_property('mouse-pos', 'native', function(_, pos)
    if pos then update_hover(pos.x, pos.y) end
end)

-- Explicit mouse move binding (fires frequently while moving)
mp.add_forced_key_binding('MOUSE_MOVE', 'word_hover_move', function()
    local pos = mp.get_property_native('mouse-pos')
    if pos then update_hover(pos.x, pos.y) end
end)

-- Recompute word boxes when subtitle changes (dedupe by start time / text)
mp.observe_property('sub-text', 'string', function()
    build_word_boxes()
    render_highlight()
end)

-- Copy hovered word on left click
local function copy_hovered_word()
    if hovered_index and current_words[hovered_index] then
        copy_to_clipboard(current_words[hovered_index].word)
    end
end

mp.add_forced_key_binding('MOUSE_BTN0', 'copy_sub_word', copy_hovered_word)

-- Cleanup overlay on file end / subtitle clear
mp.register_event('end-file', function()
    current_words = {}
    hovered_index = nil
    if osd_overlay then osd_overlay.data = ''; osd_overlay:update() end
end)

-- Initial build if subtitle already present
build_word_boxes()
render_highlight()

-- Users can still press ctrl+shift+c for full line copy.
