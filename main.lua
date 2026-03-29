re.on_frame(function()
    imgui.set_next_window_pos(Vector2f.new(100, 100), 1)
    imgui.set_next_window_size(Vector2f.new(400, 200), 1)
    if imgui.begin_window("Test!") then
        imgui.set_window_font_size(32)
        imgui.text("Lua is working!")
    end
    imgui.end_window()
end)