--- viewzoom.lua
--- Zoom into the video and pan around without resizing the player window.
---
--- Script-bindings (usable from input.conf or uosc buttons):
---   viewzoom/toggle   fit <-> 100% (native pixel size)
---   viewzoom/zoom-in, viewzoom/zoom-out
---   viewzoom/pan-left, pan-right, pan-up, pan-down
---   viewzoom/reset
---
--- Defaults: Ctrl+0 toggle, Ctrl+= / Ctrl+- zoom, Alt+arrows pan,
--- right-drag pans while zoomed, Ctrl+left-drag remains supported, and Ctrl+wheel
--- zooms toward the cursor.

local mp = require("mp")
local options = require("mp.options")

---@class ViewZoomOptions
---@field zoom_step number Zoom change per step, in log2 units (0.1 is about 7%).
---@field pan_step number Keyboard pan distance as a fraction of the window size.
---@field max_zoom number Maximum zoom in log2 units (5 is 32x).
---@field fallback_zoom number Log2 zoom used by toggle when 100% is not larger than fit.
---@field clamp boolean Keep the video from being panned outside the window.
---@field reset_on_load boolean Reset zoom and pan when a new file loads.
---@field osd boolean Show the zoom level on the OSD.
local opts = {
    zoom_step = 0.1,
    pan_step = 0.05,
    max_zoom = 5,
    fallback_zoom = 1,
    clamp = true,
    reset_on_load = true,
    osd = true,
}
options.read_options(opts, "viewzoom") -- script-opts/viewzoom.conf

--- Clamp a number to a range.
---@param v number Value to clamp.
---@param lo number Lower bound.
---@param hi number Upper bound.
---@return number clamped The clamped value.
local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

---@class Geometry
---@field W number OSD (window) width in pixels.
---@field H number OSD (window) height in pixels.
---@field dw number Native display width of the video in pixels (rotation-aware).
---@field dh number Native display height of the video in pixels (rotation-aware).
---@field bw number Video width in pixels when fitted to the window (zoom 0).
---@field bh number Video height in pixels when fitted to the window (zoom 0).

--- Compute window/video geometry at zoom 0 (fit to window).
---@return Geometry|nil geometry Nil when no video is loaded yet.
local function get_geometry()
    local W = mp.get_property_number("osd-width", 0)
    local H = mp.get_property_number("osd-height", 0)
    local p = mp.get_property_native("video-params")
    if W <= 0 or H <= 0 or not p or not p.dw or not p.dh then
        return nil
    end
    local dw, dh = p.dw, p.dh
    if (mp.get_property_number("video-rotate", 0) % 180) ~= 0 then
        dw, dh = dh, dw
    end
    local scale = math.min(W / dw, H / dh)
    return { W = W, H = H, dw = dw, dh = dh, bw = dw * scale, bh = dh * scale }
end

--- Show the current zoom (relative to fit) on the OSD.
local function show_osd()
    if not opts.osd then return end
    local z = mp.get_property_number("video-zoom", 0)
    mp.osd_message(string.format("Zoom: %d%%", math.floor(2 ^ z * 100 + 0.5)))
end

--- Apply zoom and pan, clamping so the video can't leave the window.
---@param g Geometry Geometry from get_geometry().
---@param zoom number Target zoom in log2 units.
---@param px number Target video-pan-x.
---@param py number Target video-pan-y.
local function apply(g, zoom, px, py)
    zoom = clamp(zoom, 0, opts.max_zoom)
    local k = 2 ^ zoom
    if opts.clamp then
        local sw, sh = g.bw * k, g.bh * k
        local mx = math.max(0, (sw - g.W) / (2 * sw))
        local my = math.max(0, (sh - g.H) / (2 * sh))
        px, py = clamp(px, -mx, mx), clamp(py, -my, my)
    end
    mp.set_property_number("video-zoom", zoom)
    mp.set_property_number("video-pan-x", px)
    mp.set_property_number("video-pan-y", py)
end

--- Reset to fit-to-window.
local function reset()
    mp.set_property_number("video-zoom", 0)
    mp.set_property_number("video-pan-x", 0)
    mp.set_property_number("video-pan-y", 0)
end

--- Zoom by a log2 delta, optionally keeping the point under the cursor fixed.
---@param delta number Log2 zoom change (positive zooms in).
---@param at_cursor? boolean Zoom toward the mouse pointer instead of the center.
local function zoom_by(delta, at_cursor)
    local g = get_geometry()
    if not g then return end
    local z0 = mp.get_property_number("video-zoom", 0)
    local z1 = clamp(z0 + delta, 0, opts.max_zoom)
    local px = mp.get_property_number("video-pan-x", 0)
    local py = mp.get_property_number("video-pan-y", 0)
    if at_cursor then
        local m = mp.get_property_native("mouse-pos")
        if m then
            local cx, cy = m.x - g.W / 2, m.y - g.H / 2
            px = px + cx * (1 / (g.bw * 2 ^ z1) - 1 / (g.bw * 2 ^ z0))
            py = py + cy * (1 / (g.bh * 2 ^ z1) - 1 / (g.bh * 2 ^ z0))
        end
    end
    apply(g, z1, px, py)
    show_osd()
end

--- Pan the video by a fraction of the window size (positive moves the video right/down).
---@param fx number Horizontal distance as a fraction of window width.
---@param fy number Vertical distance as a fraction of window height.
local function pan_by(fx, fy)
    local g = get_geometry()
    if not g then return end
    local z = mp.get_property_number("video-zoom", 0)
    if z <= 0 then return end
    local k = 2 ^ z
    local px = mp.get_property_number("video-pan-x", 0) + fx * g.W / (g.bw * k)
    local py = mp.get_property_number("video-pan-y", 0) + fy * g.H / (g.bh * k)
    apply(g, z, px, py)
end

--- Toggle between fit-to-window and 100% (1:1 native pixels).
local function toggle()
    local g = get_geometry()
    if not g then return end
    if mp.get_property_number("video-zoom", 0) > 0.001 then
        reset()
    else
        local native = math.log(g.dw / g.bw) / math.log(2)
        if native < 0.05 then native = opts.fallback_zoom end
        apply(g, native, 0, 0)
    end
    show_osd()
end

-- Mouse drag panning ----------------------------------------------------------

---@type {x:number, y:number}|nil
local drag_last = nil

mp.observe_property("mouse-pos", "native", function(_, m)
    if not drag_last or not m then return end
    local g = get_geometry()
    if not g then return end
    local dx, dy = m.x - drag_last.x, m.y - drag_last.y
    drag_last = { x = m.x, y = m.y }
    pan_by(dx / g.W, dy / g.H)
end)

local function handle_drag(e)
    if e.event == "down" then
        if mp.get_property_number("video-zoom", 0) <= 0 then return end
        local m = mp.get_property_native("mouse-pos")
        if m then drag_last = { x = m.x, y = m.y } end
    elseif e.event == "up" then
        drag_last = nil
    end
end

mp.add_key_binding("Ctrl+MBTN_LEFT", "pan-drag-ctrl", handle_drag, { complex = true })
mp.add_key_binding("MBTN_RIGHT", "pan-drag-right", handle_drag, { complex = true })

-- Script messages ---------------------------------------------------------------
-- Invoke with: script-message-to viewzoom <name> [optional-number]

--- Parse an optional numeric argument sent with a script message.
---@param arg string|nil Raw argument string (may be nil).
---@param default number Value used when arg is missing or not a number.
---@return number value The parsed number or the default.
local function num_arg(arg, default)
    return tonumber(arg) or default
end

mp.register_script_message("toggle", toggle)
mp.register_script_message("reset", function() reset(); show_osd() end)

--- Zoom in. Optional arg: log2 step (default: 2 x zoom_step).
mp.register_script_message("zoom-in", function(step)
    zoom_by(num_arg(step, opts.zoom_step * 2))
end)

--- Zoom out. Optional arg: log2 step (default: 2 x zoom_step).
mp.register_script_message("zoom-out", function(step)
    zoom_by(-num_arg(step, opts.zoom_step * 2))
end)

--- Zoom in/out toward the mouse pointer. Optional arg: log2 step.
mp.register_script_message("zoom-in-cursor", function(step)
    zoom_by(num_arg(step, opts.zoom_step), true)
end)
mp.register_script_message("zoom-out-cursor", function(step)
    zoom_by(-num_arg(step, opts.zoom_step), true)
end)

--- Pan the view. Optional arg: distance as a fraction of the window.
mp.register_script_message("pan-left", function(d) pan_by(num_arg(d, opts.pan_step), 0) end)
mp.register_script_message("pan-right", function(d) pan_by(-num_arg(d, opts.pan_step), 0) end)
mp.register_script_message("pan-up", function(d) pan_by(0, num_arg(d, opts.pan_step)) end)
mp.register_script_message("pan-down", function(d) pan_by(0, -num_arg(d, opts.pan_step)) end)
mp.register_event("file-loaded", function()
    if opts.reset_on_load then reset() end
end)