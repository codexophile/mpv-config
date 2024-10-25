-- Load MPV's core and set up bindings
local utils = require 'mp.utils'

-- Function to copy text to clipboard
function copy_to_clipboard(text)
    -- Escape special characters for cmd
    text = text:gsub('"', '\\"')
    text = text:gsub('\n', ' ')
    -- Use Windows built-in clip.exe to copy text to clipboard
    local args = { "cmd.exe", "/d", "/c", "echo " .. text .. " | clip" }
    -- local args = { "pwsh", "-command", "Set-Clipboard ", text }
    utils.subprocess({ args = args, cancellable = false })
end

function on_click()
    local sub_text = mp.get_property("sub-text")
    if sub_text then
        copy_to_clipboard(sub_text)
    end
end

mp.add_key_binding("ctrl+shift+c", "copy_subtitle", on_click)
