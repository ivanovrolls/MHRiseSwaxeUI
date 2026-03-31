local playerManager = sdk.get_managed_singleton("snow.player.PlayerManager")
local logged = false

re.on_frame(function()
    imgui.set_next_window_pos(Vector2f.new(50, 50), 1)
    imgui.set_next_window_size(Vector2f.new(600, 600), 1)
    if imgui.begin_window("SA Field Dumper") then
        if not playerManager then
            imgui.text("No PlayerManager")
            imgui.end_window()
            return
        end
        local playerID = playerManager:call("getMasterPlayerID")
        if not playerID or playerID > 4 then
            imgui.text("No player ID - load into a quest")
            imgui.end_window()
            return
        end
        local player = playerManager:get_field("PlayerList"):call("get_Item", playerID)
        if not player then
            imgui.text("No player")
            imgui.end_window()
            return
        end
        imgui.text("Player found: " .. player:get_type_definition():get_full_name())
        imgui.separator()
        local fields = player:get_type_definition():get_fields()
        for i, field in ipairs(fields) do
            local name = field:get_name()
            local nameLower = name:lower()
            if nameLower:find("weapon") or nameLower:find("axe") or
               nameLower:find("gauge") or nameLower:find("amp") or
               nameLower:find("awake") or nameLower:find("mode") or
               nameLower:find("sword") or nameLower:find("slash") or
               nameLower:find("bottle") or nameLower:find("isenableelementcountereffect") then
                local success, val = pcall(function()
                    return player:get_field(name)
                end)
                if success then
                    imgui.text(name .. " = " .. tostring(val))
                    if not logged then
                        log.info("[SA_DUMP] " .. name .. " = " .. tostring(val))
                    end
                end
            end
        end
        logged = true
    end
    imgui.end_window()
end)