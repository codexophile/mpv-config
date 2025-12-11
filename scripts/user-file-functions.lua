local mp = require 'mp'
local utils = require 'mp.utils'

mp.msg.info('user-file-functions.lua loaded')

-- Configuration
local EXTRACTOR_URLS = {
  source = {
    pornhub = 'https://www.pornhub.com/view_video.php?viewkey=%s',
    youtube = 'https://www.youtube.com/watch?v=%s',
    xhamster = 'https://xhamster.com/videos/%s',
    instagram = 'https://www.instagram.com/p/%s',
    tiktok = 'https://www.tiktok.com/video/%s',
  },
  op = {
    facebook = 'https://www.facebook.com/%s',
    instagram = 'https://www.instagram.com/%s',
    pornhub = 'https://www.pornhub.com/%s/videos',
    twitter = 'https://twitter.com/%s',
    youtube = 'https://www.youtube.com/%s/videos/',
    xhamster = 'https://xhamster.com/creators/%s/exclusive',
    tiktok = 'https://www.tiktok.com/@%s',
  }
}

-- Find Vivaldi browser executable
local function get_vivaldi_path()
  local paths = {
    'C:\\Program Files\\Vivaldi\\Application\\vivaldi.exe',
    'C:\\Program Files (x86)\\Vivaldi\\Application\\vivaldi.exe',
    os.getenv('ProgramFiles') .. '\\Vivaldi\\Application\\vivaldi.exe',
    os.getenv('ProgramFiles(x86)') .. '\\Vivaldi\\Application\\vivaldi.exe',
    'C:\\Users\\' .. os.getenv('USERNAME') .. '\\AppData\\Local\\Vivaldi\\Application\\vivaldi.exe',
  }
  
  for _, path in ipairs(paths) do
    local f = io.open(path)
    if f then
      io.close(f)
      return path
    end
  end
  return nil
end

-- Open URL in Vivaldi
local function run_in_private_profile(url)
  local browser_path = get_vivaldi_path()
  if not browser_path then
    mp.osd_message('Vivaldi not found')
    return false
  end
  
  mp.msg.info('Opening URL: ' .. url)
  local command = string.format('start "" "%s" "%s"', browser_path, url)
  os.execute(command)
  return true
end

-- Find and open source URL
local function find_source(video_id, extractor)
  mp.msg.info(string.format('find_source: video_id=%s, extractor=%s', video_id, extractor))
  local url_template = EXTRACTOR_URLS.source[extractor:lower()]
  if url_template then
    local url = string.format(url_template, video_id)
    mp.msg.info('Opening source: ' .. url)
    run_in_private_profile(url)
  else
    mp.msg.warn('No source URL template found for: ' .. extractor)
    mp.osd_message('No source URL for: ' .. extractor)
  end
end

-- Find and open OP/creator URL
local function find_op(op_username, extractor)
  mp.msg.info(string.format('find_op: op_username=%s, extractor=%s', op_username, extractor))
  extractor = extractor:lower()
  local url_template = EXTRACTOR_URLS.op[extractor]
  
  if url_template then
    -- Special handling for pornhub: replace '?' with '/'
    if extractor == 'pornhub' then
      op_username = op_username:gsub('?', '/')
    end
    
    local url = string.format(url_template, op_username)
    mp.msg.info('Opening OP: ' .. url)
    run_in_private_profile(url)
  else
    mp.msg.warn('No OP URL template found for: ' .. extractor)
    mp.osd_message('No OP URL for: ' .. extractor)
  end
end

-- Extract extractor and IDs from filename
local function parse_filename(filename)
  -- We need to capture what's INSIDE the parentheses as extractor
  -- Pattern: (content_in_parens) then capture what comes after
  mp.msg.info('Parsing filename: ' .. filename)
  
  -- Match: (TikTok)6967608909246778626
  -- This captures "TikTok" and "6967608909246778626"
  local extractor, ids = filename:match('%(([^)]+)%)%s*(%S+)')
  mp.msg.info(string.format('Regex result - extractor: %s, ids: %s', extractor or 'nil', ids or 'nil'))
  
  if extractor and ids then
    mp.msg.info(string.format('Match found - extractor: %s, ids: %s', extractor, ids))
    return extractor, ids
  end
  
  mp.msg.warn('No match for filename: ' .. filename)
  return nil, nil
end

-- Store state
local current_extractor = nil
local current_ids = nil

-- Create buttons for source and OP
local function add_buttons()
  local path = mp.get_property('path')
  if not path then 
    mp.msg.debug('No path available')
    return 
  end
  
  mp.msg.info('File loaded: ' .. path)
  
  -- Get filename from path
  local filename = path:match('([^/\\]+)$')
  if not filename then 
    mp.msg.debug('Could not extract filename from path')
    return 
  end
  
  mp.msg.info('Extracted filename: ' .. filename)
  
  -- Try to match the pattern
  local extractor, ids = parse_filename(filename)
  if not extractor or not ids then 
    mp.msg.debug('Pattern did not match')
    return 
  end
  
  -- Store for button callbacks
  current_extractor = extractor
  current_ids = ids
  
  mp.msg.info(string.format('Pattern matched! Extractor: %s, IDs: %s', extractor, ids))
  mp.osd_message(string.format('Found: %s (o: op, s: source)', extractor))
end

-- Event handlers
mp.register_event('file-loaded', function()
  mp.msg.info('=== file-loaded event ===')
  add_buttons()
end)

-- Key bindings for buttons
mp.add_key_binding('o', 'find-op-button', function()
  mp.msg.info('find-op-button (o) pressed')
  if current_extractor and current_ids then
    local op_username = current_ids:match('^([^|]+)') or current_ids
    find_op(op_username, current_extractor)
    mp.osd_message(string.format('Opening OP: %s on %s', op_username, current_extractor))
  else
    mp.msg.warn('No valid extractor/IDs parsed from filename')
    mp.osd_message('No matching filename pattern')
  end
end, {repeatable=false})

mp.add_key_binding('s', 'find-source-button', function()
  mp.msg.info('find-source-button (s) pressed')
  if current_extractor and current_ids then
    local video_id = current_ids:match('|(.+)$') or current_ids
    find_source(video_id, current_extractor)
    mp.osd_message(string.format('Opening source: %s on %s', video_id, current_extractor))
  else
    mp.msg.warn('No valid extractor/IDs parsed from filename')
    mp.osd_message('No matching filename pattern')
  end
end, {repeatable=false})

-- Register button definitions with uosc
mp.register_script_message('uosc-button-op', function()
  if current_extractor and current_ids then
    local op_username = current_ids:match('^([^|]+)') or current_ids
    find_op(op_username, current_extractor)
  end
end)

mp.register_script_message('uosc-button-source', function()
  if current_extractor and current_ids then
    local video_id = current_ids:match('|(.+)$') or current_ids
    find_source(video_id, current_extractor)
  end
end)

-- Create OSD buttons
local osd = mp.create_osd_overlay('ass-events')
local buttons_visible = false

local function show_buttons()
  if not (current_extractor and current_ids) then return end
  
  local ass_text = [[{\q1\pos(100,100)\bord1\1c&H00FF00&\3c&H000000&}OP  |  SOURCE]]
  osd.data = ass_text
  osd.res_x = mp.get_property_number('dwidth', 1920)
  osd.res_y = mp.get_property_number('dheight', 1080)
  osd:update()
  buttons_visible = true
end

local function hide_buttons()
  osd.data = ''
  osd:update()
  buttons_visible = false
end

-- Show buttons when file loads with matching pattern
local original_add_buttons = add_buttons
function add_buttons()
  original_add_buttons()
  show_buttons()
end

-- Hide buttons when file unloads
mp.register_event('end-file', function()
  hide_buttons()
  current_extractor = nil
  current_ids = nil
end)
