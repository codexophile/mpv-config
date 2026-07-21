mp.register_script_message("open-in-imdb", function()
  local filename = mp.get_property("filename")
    mp.osd_message( "Opening IMDb page for: " .. filename)
end)