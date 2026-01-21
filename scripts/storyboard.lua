-- storyboard.lua
--
-- Displays a visual storyboard (contact sheet) of the video.
-- Clicking a thumbnail jumps to that timestamp.
--
-- Keybind: 'b' to toggle.

local options = {
    -- Key to toggle the storyboard
    key = "b",

    -- Grid dimensions
    rows = 4,
    cols = 5,

    -- Resolution of individual thumbnails (lower = much faster generation)
    -- Recommended speeds: 160x90 (fastest), 240x135 (faster), 320x180 (balanced), 480x270 (quality)
    -- Going from 320x180 to 160x90 cuts generation time roughly in half
    thumb_w = 240,
    thumb_h = 135,

    -- Output format (png is most compatible; jpg can be faster but may fail on some builds)
    format = "png",

    -- PNG compression level (0-9): 0=fastest, 9=best compression
    -- Lower value = faster generation. 3-4 is good balance
    png_compression = 3,

    -- Encoder quality hint (some mpv builds ignore MJPEG quality options)
    -- If you want guaranteed quality control, consider using png.
    quality = 90,
    
    -- Speed optimizations (set to true for faster generation at slight quality cost)
    fast_mode = true,

    -- Path to mpv executable (defaults to 'mpv')
    mpv_path = "mpv",
    
    -- Save storyboards permanently next to video files?
    save_with_video = true,
    
    -- Cache storyboards to avoid regeneration?
    cache_enabled = true,
    
    -- Key to force regeneration of storyboard
    regenerate_key = "B",  -- Shift+b to force regenerate
    
    -- Show timestamp on thumbnails? (handled by mpv filter)
    -- Note: This increases generation time slightly due to font rendering
    timestamps = true
}

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- Clean up temp file on exit
local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
local generated_paths = {}
local temp_conversion_files = {}  -- Track temporary conversion files only

-- Cache directory for storyboards
local cache_dir = temp_dir .. "\\mpv_storyboard_cache"

-- Generate storyboard filename based on video and settings
local function get_storyboard_filename(video_path)
    -- Get video directory and base name
    local dir, filename = utils.split_path(video_path)
    local basename = filename:gsub("%.%w+$", "")  -- Remove extension
    
    -- Create storyboard filename with grid settings
    local sb_name = string.format("%s.storyboard_%dx%d_%dx%d.png", 
        basename, options.cols, options.rows, options.thumb_w, options.thumb_h)
    
    return dir, sb_name
end

-- Get output paths for storyboard
local function get_storyboard_paths(video_path)
    if options.save_with_video then
        -- Save next to video file
        local dir, sb_name = get_storyboard_filename(video_path)
        local png_path = utils.join_path(dir, sb_name)
        local bgra_name = sb_name:gsub("%.png$", ".bgra")
        local bgra_path = utils.join_path(dir, bgra_name)
        return png_path, bgra_path, true  -- true = permanent
    else
        -- Use temp directory
        local pid = utils.getpid()
        local png_path = temp_dir .. "\\mpv_storyboard_" .. pid .. ".png"
        local bgra_path = temp_dir .. "\\mpv_storyboard_" .. pid .. ".bgra"
        return png_path, bgra_path, false  -- false = temporary
    end
end

local function ensure_cache_dir()
    if options.cache_enabled then
        local attr = utils.file_info(cache_dir)
        if not attr or not attr.is_dir then
            os.execute("mkdir \"" .. cache_dir .. "\" 2>nul")
        end
    end
end

-- Generate a cache key from video path (using simple hash of the path and grid config)
local function get_cache_key(path)
    local key = path .. "_" .. options.cols .. "x" .. options.rows .. "_" .. options.thumb_w .. "x" .. options.thumb_h
    -- Replace problematic characters
    key = key:gsub("[\\/:*?\"<>|]", "_")
    return key
end

-- Get cached storyboard paths if they exist
local function get_cached_storyboard(path)
    if not options.cache_enabled then return nil end
    
    ensure_cache_dir()
    local cache_key = get_cache_key(path)
    local cache_png = cache_dir .. "\\" .. cache_key .. ".png"
    local cache_bgra = cache_dir .. "\\" .. cache_key .. ".bgra"
    
    -- Check if both files exist
    local png_info = utils.file_info(cache_png)
    local bgra_info = utils.file_info(cache_bgra)
    
    if png_info and bgra_info then
        msg.info("Storyboard: Using cached storyboard")
        return cache_png, cache_bgra
    end
    
    return nil
end

-- Save generated storyboard to cache
local function cache_storyboard(path, png_path, bgra_path)
    if not options.cache_enabled then return end
    
    ensure_cache_dir()
    local cache_key = get_cache_key(path)
    local cache_png = cache_dir .. "\\" .. cache_key .. ".png"
    local cache_bgra = cache_dir .. "\\" .. cache_key .. ".bgra"
    
    -- Copy files to cache
    if png_path and utils.file_info(png_path) then
        os.execute("copy \"" .. png_path .. "\" \"" .. cache_png .. "\" >nul 2>&1")
    end
    if bgra_path and utils.file_info(bgra_path) then
        os.execute("copy \"" .. bgra_path .. "\" \"" .. cache_bgra .. "\" >nul 2>&1")
    end
end

local function get_output_path(fmt)
    local pid = utils.getpid()
    if fmt == "png" then
        return temp_dir .. "\\mpv_storyboard_" .. pid .. ".png", temp_dir .. "\\mpv_storyboard_" .. pid .. ".bgra"
    else
        return temp_dir .. "\\mpv_storyboard_" .. pid .. ".jpg", nil
    end
end

local storyboard_active = false
local pending_process = nil

-- Helper to detect OS (borrowed logic from thumbfast/others)
local function is_windows()
    return package.config:sub(1,1) == "\\"
end

local function cleanup()
    -- Only clean up temporary conversion files, not permanent storyboards
    for _, path in ipairs(temp_conversion_files) do
        os.remove(path)
    end
end

-- Input handling: Map mouse click to timestamp
local function click_handler()
    if not storyboard_active then return end

    local mouse_pos = mp.get_property_native("mouse-pos")
    if not mouse_pos then return end

    -- Get the actual video dimensions to calculate proper cell size
    local sb_width = options.cols * options.thumb_w
    local sb_height = options.rows * options.thumb_h

    -- Normalize click position to [0, 1] range relative to storyboard dimensions
    local norm_x = mouse_pos.x / sb_width
    local norm_y = mouse_pos.y / sb_height

    -- Clamp to valid range
    norm_x = math.max(0, math.min(1, norm_x))
    norm_y = math.max(0, math.min(1, norm_y))

    -- Determine which cell was clicked
    local col = math.floor(norm_x * options.cols)
    local row = math.floor(norm_y * options.rows)

    -- Clamp values
    if col >= options.cols then col = options.cols - 1 end
    if row >= options.rows then row = options.rows - 1 end

    local total_cells = options.rows * options.cols
    local cell_index = (row * options.cols) + col

    -- Calculate timestamp
    local duration = mp.get_property_number("duration")
    if not duration then return end

    -- The tiling filter captures frames at even intervals
    -- Time = (index / total_cells) * duration
    -- We add a half-interval offset to land in the middle of the scene represented by the thumb
    local interval = duration / total_cells
    local seek_time = (cell_index * interval) + (interval / 2)

    mp.commandv("seek", seek_time, "absolute", "exact")
    
    -- Close storyboard after click
    toggle_storyboard(false)
end

local function close_storyboard()
    mp.commandv("overlay-remove", 1)
    mp.remove_key_binding("storyboard_click")
    mp.remove_key_binding("storyboard_close_esc")
    storyboard_active = false
end

-- Generate the filter string for the background process
local function get_vf_string(duration, fmt)
    local total_thumbs = options.rows * options.cols
    
    -- Calculate FPS required to produce exactly N frames over the duration
    -- fps = N / Duration
    local fps = total_thumbs / duration
    
    local vf = ""
    
    -- 1. FPS filter: Drops frames to match the count we need
    vf = vf .. "fps=" .. fps .. ","
    
    -- 2. Scale: Resize for performance and grid fit
    -- Use faster scaling algorithm in fast mode
    local scale_flags = options.fast_mode and "fast_bilinear" or "bicubic"
    vf = vf .. "scale=" .. options.thumb_w .. ":" .. options.thumb_h .. ":flags=" .. scale_flags .. ","

    -- 2.5. Format: MJPEG expects full-range YUV, ensure compatible format
    if fmt == "jpg" then
        vf = vf .. "format=yuvj420p,"
    end
    
    -- 3. Drawtext (optional): Burn timestamps
    if options.timestamps then
        -- Escape colons for the filter string
        local time_expr = "%{pts:hms}"
        if is_windows() then
            -- Windows escaping for subprocess can be messy, simplifying
            -- Often safer to omit complex text filters on Windows without robust escaping
        else
            vf = vf .. "drawtext=text='"..time_expr.."':fontsize=24:fontcolor=white:bordercolor=black:borderw=2:x=5:y=5,"
        end
    end

    -- 4. Tile: Stitch them into one grid
    vf = vf .. "tile=" .. options.cols .. "x" .. options.rows
    
    return vf
end

-- Convert PNG to BGRA format for overlay display
local function convert_png_to_bgra(png_path, bgra_path)
    local ffmpeg_args = {
        "ffmpeg",
        "-i", png_path,
        "-f", "rawvideo",
        "-pix_fmt", "bgra",
        "-y",
        bgra_path
    }
    
    local convert_result = mp.command_native({
        name = "subprocess",
        playback_only = false,
        args = ffmpeg_args,
        capture_stdout = true,
        capture_stderr = true
    })
    
    return convert_result.status == 0
end

-- Display storyboard overlay
local function display_storyboard(png_path, bgra_path)
    storyboard_active = true
    
    -- Calculate storyboard dimensions (cols × thumb_w, rows × thumb_h)
    local sb_width = options.cols * options.thumb_w
    local sb_height = options.rows * options.thumb_h
    
    -- Add overlay
    mp.command_native({
        "overlay-add", 
        1, 
        0, 0,  -- x, y position
        bgra_path,
        0,  -- offset
        "bgra",  -- pixel format
        sb_width, sb_height,  -- width, height
        sb_width * 4  -- stride (BGRA: 4 bytes per pixel)
    })

    -- Enable mouse interaction
    mp.add_forced_key_binding("MBTN_LEFT", "storyboard_click", click_handler)
    mp.add_forced_key_binding("ESC", "storyboard_close_esc", function() toggle_storyboard(false) end)
end

local function generate_storyboard(format_override, is_retry, force_regenerate)
    local path = mp.get_property("path")
    local duration = mp.get_property_number("duration")

    if not path or not duration then
        mp.osd_message("Storyboard: No video/duration found", 2)
        return
    end

    -- Check if storyboard already exists (unless force_regenerate)
    if not force_regenerate then
        local png_path, bgra_path, is_permanent = get_storyboard_paths(path)
        
        -- If permanent storyboard exists, use it directly
        if is_permanent then
            local png_info = utils.file_info(png_path)
            
            if png_info then
                msg.info("Storyboard: Using existing storyboard")
                mp.osd_message("Loading storyboard...", 1)
                
                -- Check if BGRA exists, if not convert from PNG (fast operation)
                local bgra_info = utils.file_info(bgra_path)
                if not bgra_info then
                    msg.info("Storyboard: Converting PNG to BGRA...")
                    if not convert_png_to_bgra(png_path, bgra_path) then
                        msg.error("Failed to convert PNG to BGRA")
                        mp.osd_message("Storyboard conversion failed", 3)
                        return
                    end
                    -- Track BGRA as temporary for cleanup
                    table.insert(temp_conversion_files, bgra_path)
                end
                
                display_storyboard(png_path, bgra_path)
                return
            end
        end
        
        -- Check cache second
        local cached_png, cached_bgra = get_cached_storyboard(path)
        if cached_png and cached_bgra then
            mp.osd_message("Loading storyboard...", 1)
            display_storyboard(cached_png, cached_bgra)
            return
        end
    else
        mp.osd_message("Regenerating storyboard...", 30)
    end

    if not force_regenerate then
        mp.osd_message("Generating storyboard...", 30)
    end
    
    local fmt = format_override or options.format
    local png_path, bgra_path, is_permanent = get_storyboard_paths(path)
    
    if not is_permanent then
        table.insert(generated_paths, png_path)
    end
    if bgra_path then 
        -- BGRA conversion file is always temporary
        table.insert(temp_conversion_files, bgra_path)
    end

    msg.info("Storyboard: path=" .. path .. ", duration=" .. duration)
    msg.info("Storyboard: output_path=" .. png_path)
    msg.info("Storyboard: permanent=" .. tostring(is_permanent))

    -- Prepare command arguments
    -- We spawn a new mpv instance to process the video in the background
    local vf_string = get_vf_string(duration, fmt)
    local args = {
        options.mpv_path,
        path,
        "--no-config",
        "--msg-level=ffmpeg=error",  -- Allow error messages through
        "--ytdl=no",
        "--audio=no",
        "--sub=no",
        "--frames=1", -- Stop after one image (the tiled storyboard) is produced
        "--vf=" .. vf_string,
        "--ovc=" .. (fmt == "jpg" and "mjpeg" or "png"),
        "--o=" .. png_path
    }
    
    -- PNG compression settings (for faster generation)
    if fmt == "png" then
        table.insert(args, "--ovcopts=compression=" .. options.png_compression)
    end
    
    -- Speed optimizations
    if options.fast_mode then
        table.insert(args, "--hwdec=auto")  -- Hardware decoding
        table.insert(args, "--sws-scaler=fast-bilinear")  -- Faster scaling
        table.insert(args, "--profile=fast")  -- Fast profile
        table.insert(args, "--vd-lavc-fast")  -- Fast video decoding
        table.insert(args, "--vd-lavc-skiploopfilter=all")  -- Skip deblocking
        table.insert(args, "--vd-lavc-threads=0")  -- Auto thread count
    end
    
    if fmt == "jpg" then
        -- Some builds lack MJPEG options; keep args minimal for compatibility.
    end

    -- Log the full command for debugging
    msg.info("Storyboard: vf=" .. vf_string)
    msg.info("Storyboard: codec=" .. (fmt == "jpg" and "mjpeg" or "png"))
    msg.info("Storyboard: output=" .. png_path)
    msg.info("Storyboard: Full command: " .. table.concat(args, " "))

    -- Async subprocess
    pending_process = mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        args = args,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        pending_process = nil
        mp.osd_message("", 0) -- Clear "Generating" message

        if success and result.status == 0 then
            -- If PNG, convert to raw BGRA for overlay
            if fmt == "png" and bgra_path then
                if not convert_png_to_bgra(png_path, bgra_path) then
                    msg.error("Failed to convert PNG to BGRA")
                    mp.osd_message("Storyboard conversion failed", 3)
                    return
                end
            end
            
            -- Cache the storyboard if not permanent
            if not is_permanent and options.cache_enabled then
                cache_storyboard(path, png_path, bgra_path)
            end
            
            -- Display the image
            display_storyboard(png_path, bgra_path)
        else
            if (not is_retry) and fmt == "jpg" then
                msg.warn("Storyboard: JPG failed, retrying with PNG")
                generate_storyboard("png", true)
                return
            end
            msg.error("Storyboard generation failed!")
            msg.error("Success: " .. tostring(success))
            if result then
                msg.error("Status: " .. tostring(result.status))
                if result.stdout then msg.error("STDOUT: " .. result.stdout) end
                if result.stderr then msg.error("STDERR: " .. result.stderr) end
            end
            if error then msg.error("Error: " .. tostring(error)) end
            mp.osd_message("Storyboard failed - check console", 5)
        end
    end)
end

function toggle_storyboard(force_state, force_regenerate)
    if force_state == false then
        close_storyboard()
        return
    end

    if storyboard_active then
        close_storyboard()
    else
        -- Don't allow multiple processes
        if pending_process then 
            mp.osd_message("Storyboard generation in progress...", 2)
            return 
        end
        generate_storyboard(nil, false, force_regenerate)
    end
end

mp.add_key_binding(options.key, "toggle_storyboard", toggle_storyboard)
mp.add_key_binding(options.regenerate_key, "regenerate_storyboard", function()
    toggle_storyboard(nil, true)
end)
mp.register_event("shutdown", cleanup)