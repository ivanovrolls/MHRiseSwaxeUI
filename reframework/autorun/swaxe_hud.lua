--main.lua
--transplanted Swaxe UI from Wilds
--vanilla Switch Axe gauge is hidden via via.gui.GUI component disable

-- ===========================================================
-- CONFIG change to match resolution, change scale to change ui size
-- ============================================================
local SCREEN_WIDTH = 2560
local SCREEN_HEIGHT = 1440

local IMG_W = 242
local IMG_H = 39
local SCALE = 1.5

local DISP_W = IMG_W * SCALE
local DISP_H = IMG_H * SCALE

-- ============================================================
-- COLOURS
-- ============================================================
local function argb(a, r, g, b)
    return (a << 24) | (r << 16) | (g << 8) | b
end

local GAUGE_FULL = argb(255,255, 200, 20)  --warm gold
local GAUGE_LOW = argb(255, 220, 60, 30)  --burnt orange when low
local ELEM_ON = argb(255, 0, 220, 200)  --cyan
local SWORD_BUILD = argb(200, 60, 60,  200)  --indigo buildup
local SWORD_AMP = argb(255, 160, 60, 255)  --violet active
local INACTIVE = argb(50, 30, 30, 40 )
local SWORD_LABEL = argb(255, 80, 160, 255)
local AXE_LABEL = argb(255, 200, 130, 50)
local TEXT_DIM = argb(170, 150, 150, 160)
local RELOAD_YES = argb(255, 220, 60,  30 )
local RELOAD_NO = argb(255, 80, 200, 120)
local TEXT_BG = argb(130, 0, 0, 0)

local FLASH_THRESHOLD = 0.20
local FLASH_SPEED = 3.0

-- ============================================================
-- SLOT GEOMETRY
-- both bottom elements: y=20 to y=34 only //if you change it the bars will bleed
-- fill is right to left (r2L) — rows ordered from indicator tip to handle
-- ============================================================
local MAIN_BAR = {x1=18, x2=212, y=10, h=5} --switch gauge bar

local ELEM_LEFT = { --power axe mode bar
    {y=26, x1=52,  x2=65 },
    {y=27, x1=53,  x2=74 },
    {y=28, x1=55,  x2=83 },
    {y=29, x1=57,  x2=84 },
    {y=30, x1=60,  x2=124},
    {y=31, x1=63,  x2=124},
    {y=32, x1=67,  x2=124},
    {y=33, x1=72,  x2=118},
}

local ELEM_RIGHT = { --sword amp bar
    {y=22, x1=185, x2=201},
    {y=25, x1=137, x2=225},
    {y=26, x1=138, x2=223},
    {y=27, x1=138, x2=220},
    {y=28, x1=139, x2=217},
    {y=29, x1=139, x2=214},
    {y=30, x1=140, x2=209},
    {y=31, x1=140, x2=201},
}

-- ============================================================
-- PLAYER ACCESS
-- reaches into the games' memory to find player object and read values from it
-- ============================================================
local playerManager = sdk.get_managed_singleton("snow.player.PlayerManager")

local function getPlayer()
    if not playerManager then return nil end
    local ok, playerID = pcall(function()
        return playerManager:call("getMasterPlayerID")
    end)
    if not ok or not playerID or playerID > 4 then return nil end
    local ok2, playerList = pcall(function()
        return playerManager:get_field("PlayerList")
    end)
    if not ok2 or not playerList then return nil end
    local ok3, player = pcall(function()
        return playerList:call("get_Item", playerID)
    end)
    if not ok3 then return nil end
    return player
end

local function getField(obj, name, default)
    local ok, val = pcall(function() return obj:get_field(name) end)
    if ok and val ~= nil then return val end
    return default
end

--returns true only when HUD should be visible
--1. Player is in a quest (not hub/lobby) PlayerQuestBase only exists in quests
--2. Player has Swaxe equipped; type name contains "SlashAxe"
local function shouldShowHUD(player)
    if not player then return false end

    local ok, isQuest = pcall(function()
        return player:get_type_definition():is_a("snow.player.PlayerQuestBase")
    end)
    if not ok or not isQuest then return false end

    local typeName = player:get_type_definition():get_full_name()
    if not typeName:find("SlashAxe") then return false end

    return true
end

-- ============================================================
-- VANILLA HUD SUPPRESSION
-- finds the via.gui.GUI component on the S_AxeGauge GameObject
-- and disables it each frame while our HUD is active
-- re-enables it when leaving a quest or switching weapons
-- so other parts of the game are not affected
-- ============================================================
local vanillaGuiComponent = nil  --cached reference

local function getVanillaGuiComponent()
    if vanillaGuiComponent then return vanillaGuiComponent end
    local guiManager = sdk.get_managed_singleton("snow.gui.GuiManager")
    if not guiManager then return nil end
    local ok, weaponUI = pcall(function()
        return guiManager:get_field("guiHudWeaponUIObject")
    end)
    if not ok or not weaponUI then return nil end
    local ok2, components = pcall(function()
        return weaponUI:call("get_Components")
    end)
    if not ok2 or not components then return nil end
    local count = components:call("get_Count")
    for i = 0, count - 1 do
        local c = components:call("get_Item", i)
        if c and c:get_type_definition():get_full_name() == "via.gui.GUI" then
            vanillaGuiComponent = c
            return vanillaGuiComponent
        end
    end
    return nil
end

local function setVanillaHudVisible(visible)
    local c = getVanillaGuiComponent()
    if not c then return end
    pcall(function() c:call("set_Enabled", visible) end)
end

-- ============================================================
-- POSITION PERSISTENCE
-- saves hudX/hudY to reframework/data/swaxe_hud.json
-- loads on startup so position survives resets and game restarts
-- ============================================================
local CONFIG_FILE = "swaxe_hud.json"

local function savePosition()
    json.dump_file(CONFIG_FILE, { x = hudX, y = hudY })
end

local function loadPosition()
    local data = json.load_file(CONFIG_FILE)
    if data and type(data.x) == "number" and type(data.y) == "number" then
        hudX = data.x
        hudY = data.y
    end
end

-- ============================================================
-- HUD STATE
-- ============================================================
local hudX = (SCREEN_WIDTH / 2) - (DISP_W / 2)
local hudY = SCREEN_HEIGHT - DISP_H - 100
local hudVisible = true
local dragging = false
local dsMX, dsMY, dsHX, dsHY = 0, 0, 0, 0

--load saved position immediately, overwriting the defaults above if a save exists
loadPosition()

-- ============================================================
-- FADE STATE
-- fadeCurrent: 0.0 = fully hidden, 1.0 = fully visible
-- fadeTarget:  what we are animating toward
-- ============================================================
local fadeCurrent = 0.0
local fadeTarget  = 0.0
local FADE_SPEED  = 3.0  -- full fade takes ~0.33s

-- ============================================================
-- AMPED FLASH STATE
-- shows "AMPED!" text briefly when sword amp activates
-- ============================================================
local ampedFlashTimer    = 0.0
local AMPED_FLASH_DURATION = 2.5
local wasAmped           = false

local function sx(ix) return hudX + ix * SCALE end
local function sy(iy) return hudY + iy * SCALE end
local function sw(iw) return iw * SCALE end

--fill row right to left (1.0 = full fill)
--used for elemental amp bar
local function drawRowRTL(row, fraction, col)
    if fraction <= 0 then return end
    local rw = row.x2 - row.x1
    local fillW = rw * math.min(1, fraction)
    d2d.fill_rect(sx(row.x2 - fillW), sy(row.y), sw(fillW), sw(1), col)
end

--fill set of rows l2r in single horizontal sweep
--each row only draws portion up to x boundary
--makes the bar appear to fill l2r across curved shape.
local function drawCurvedLTR(rows, fraction, col, bgCol)
    if #rows == 0 then return end
    local globalX1 = math.huge
    local globalX2 = -math.huge
    for _, row in ipairs(rows) do
        if row.x1 < globalX1 then globalX1 = row.x1 end
        if row.x2 > globalX2 then globalX2 = row.x2 end
    end
    local fillBoundary = globalX1 + (globalX2 - globalX1) * math.min(1, fraction)
    for _, row in ipairs(rows) do
        d2d.fill_rect(sx(row.x1), sy(row.y), sw(row.x2 - row.x1), sw(1), bgCol)
        local clipX2 = math.min(row.x2, fillBoundary)
        if clipX2 > row.x1 then
            d2d.fill_rect(sx(row.x1), sy(row.y), sw(clipX2 - row.x1), sw(1), col)
        end
    end
end

-- ============================================================
-- D2D
-- ============================================================
local swaxeImage = nil
local labelFont  = nil
local smallFont  = nil
local ampedFont  = nil

d2d.register(function()
    swaxeImage = d2d.Image.new("swaxe_ui.png")
    labelFont  = d2d.Font.new("Arial", 13)
    smallFont  = d2d.Font.new("Arial", 11)
    ampedFont  = d2d.Font.new("Arial Bold", 18)
end,

function()
    local dt = 1.0 / 60.0

    --update fade target FIRST before any early returns
    local player = getPlayer()
    fadeTarget = (hudVisible and shouldShowHUD(player)) and 1.0 or 0.0

    --step fade toward target
    if fadeCurrent < fadeTarget then
        fadeCurrent = math.min(fadeTarget, fadeCurrent + FADE_SPEED * dt)
    elseif fadeCurrent > fadeTarget then
        fadeCurrent = math.max(fadeTarget, fadeCurrent - FADE_SPEED * dt)
    end

    --nothing to draw if fully faded out
    if fadeCurrent <= 0.001 then return end

    local fade = fadeCurrent

    local swordEffect = getField(player, "_SwordEffect", nil)
    local isSwordMode = swordEffect ~= nil
    local bottleGauge = getField(player, "_BottleGauge", 0)
    local bottleGaugeLow = getField(player, "_BottelGaugeLow", 37)
    local assistTimer = getField(player, "_BottleAwakeAssistTimer", 0)
    local assistTimerMax = 3600.0
    local awakeGauge = getField(player, "_BottleAwakeGauge", 0)
    local awakeDuration = getField(player, "_BottleAwakeDurationTimer", 0)
    local awakeDurationMax = math.max(1, getField(player, "_BottleAwakeDurationTime", 2700))
    local awakeGaugeMax = 70.0

    local isAmped = awakeGauge > 0 and awakeDuration > 0
    local isBuildingAmp = awakeGauge > 0 and awakeDuration <= 0
    local arrowsActive = assistTimer > 0
    local reloadRequired = bottleGauge <= 36

    local gaugeFraction = math.max(0, math.min(1, bottleGauge / 100.0))
    local arrowFraction = math.max(0, math.min(1, assistTimer / assistTimerMax))
    local ampFraction = math.max(0, math.min(1, awakeDuration / awakeDurationMax))
    local buildFraction = math.max(0, math.min(1, awakeGauge / awakeGaugeMax))

    --detect transition into amped state and start flash timer
    if isAmped and not wasAmped then
        ampedFlashTimer = AMPED_FLASH_DURATION
    end
    wasAmped = isAmped

    if ampedFlashTimer > 0 then
        ampedFlashTimer = ampedFlashTimer - dt
    end

    local t = os.clock()
    local pulse = (math.sin(t * FLASH_SPEED * math.pi * 2) + 1) / 2

    local arrowLow = arrowsActive and arrowFraction < FLASH_THRESHOLD
    local ampLow  = isAmped and ampFraction < FLASH_THRESHOLD

    local function fadeArgb(a, r, g, b)
        return argb(math.floor(a * fade), r, g, b)
    end

    -- elemental colour: teal normally, flashes bright cyan when low
    local elemCol
    if arrowLow then
        local g = math.floor(220 + (255-220) * pulse)
        local b = math.floor(200 + (255-200) * pulse)
        local r = math.floor(0 + 80 * pulse)
        elemCol = fadeArgb(255, r, g, b)
    else
        elemCol = fadeArgb(255, 0, 220, 200)
    end

    --sword colour: indigo -> violet active -> flashes violet when low
    local swordCol, swordFraction
    if isAmped then
        if ampLow then
            local r = math.floor(160 + (220-160) * pulse)
            local g = math.floor(60  + (160-60)  * pulse)
            swordCol = fadeArgb(255, r, g, 255)
        else
            swordCol = fadeArgb(255, 160, 60, 255)
        end
        swordFraction = 1.0
    elseif isBuildingAmp then
        swordCol      = fadeArgb(200, 60, 60, 200)
        swordFraction = buildFraction
    else
        swordCol      = fadeArgb(200, 60, 60, 200)
        swordFraction = 0
    end

    local elemFraction = arrowsActive and 1.0 or 0.0
    local gaugeCol = reloadRequired
        and fadeArgb(255, 220, 60, 30)
        or  fadeArgb(255, 255, 200, 20)
    local inactiveCol = fadeArgb(50, 30, 30, 40)

    --ain gauge bar
    local barW = MAIN_BAR.x2 - MAIN_BAR.x1
    d2d.fill_rect(sx(MAIN_BAR.x1), sy(MAIN_BAR.y), sw(barW), sw(MAIN_BAR.h), inactiveCol)
    if gaugeFraction > 0 then
        d2d.fill_rect(sx(MAIN_BAR.x1), sy(MAIN_BAR.y),
            sw(barW * gaugeFraction), sw(MAIN_BAR.h), gaugeCol)
    end

    --power axe / elem amp
    for _, row in ipairs(ELEM_LEFT) do
        d2d.fill_rect(sx(row.x1), sy(row.y), sw(row.x2-row.x1), sw(1), inactiveCol)
    end
    if arrowsActive then
        for _, row in ipairs(ELEM_LEFT) do
            drawRowRTL(row, elemFraction, elemCol)
        end
    end

    --sword amp mode
    drawCurvedLTR(ELEM_RIGHT, swordFraction, swordCol, inactiveCol)

    --image
    d2d.image(swaxeImage, hudX, hudY, DISP_W, DISP_H, math.floor(fade * 255))

    --mode indicator
    local labelY = hudY + DISP_H + 5
    d2d.fill_rect(hudX, labelY-1, 108, 17, fadeArgb(130, 0, 0, 0))
    d2d.text(labelFont, isSwordMode and "SWORD MODE" or "AXE MODE",
        hudX+3, labelY,
        isSwordMode and fadeArgb(255, 80, 160, 255) or fadeArgb(255, 200, 130, 50))

    --"AMPED!" flash above the HUD when sword amp activates
    if ampedFlashTimer > 0 then
        local ampedFade = math.min(1.0, ampedFlashTimer / 0.4) * fade
        if ampedFlashTimer < 0.5 then
            ampedFade = (ampedFlashTimer / 0.5) * fade
        end
        local ar = math.floor(160 + (255-160) * pulse)
        local ag = math.floor(60  + (200-60)  * pulse)
        local ampedCol = argb(math.floor(255 * ampedFade), ar, ag, 255)
        local ampedBg  = argb(math.floor(160 * ampedFade), 0, 0, 0)
        local ampedX   = hudX + (DISP_W / 2) - 35
        local ampedY   = hudY - 26
        d2d.fill_rect(ampedX - 4, ampedY - 2, 82, 22, ampedBg)
        d2d.text(ampedFont, "AMPED!", ampedX, ampedY, ampedCol)
    end
end)

-- ============================================================
-- REFramework menu
-- ============================================================
re.on_draw_ui(function()
    if imgui.tree_node("Switch Axe HUD") then
        local c, v = imgui.checkbox("Show HUD", hudVisible)
        if c then hudVisible = v end

        imgui.spacing()

        local scaleChanged, newScale = imgui.slider_float("Scale", SCALE, 0.5, 3.0, "%.1fx")
        if scaleChanged then
            SCALE  = newScale
            DISP_W = IMG_W * SCALE
            DISP_H = IMG_H * SCALE
        end

        local wChanged, newW = imgui.drag_int("Screen Width",  SCREEN_WIDTH,  1, 800, 7680)
        if wChanged then SCREEN_WIDTH = newW end
        local hChanged, newH = imgui.drag_int("Screen Height", SCREEN_HEIGHT, 1, 600, 4320)
        if hChanged then SCREEN_HEIGHT = newH end

        imgui.spacing()

        imgui.text(string.format("Position: %.0f, %.0f", hudX, hudY))
        if imgui.button("Reset Position") then
            hudX = (SCREEN_WIDTH/2) - (DISP_W/2)
            hudY = SCREEN_HEIGHT - DISP_H - 100
            savePosition()
        end

        imgui.tree_pop()
    end
end)

-- ============================================================
-- drag n drop + vanilla HUD suppression
-- ============================================================
re.on_frame(function()
    --drag n drop
    local mouse = imgui.get_mouse()
    if not mouse then return end
    local mx, my = mouse.x, mouse.y
    local over = mx >= hudX and mx <= hudX+DISP_W and my >= hudY and my <= hudY+DISP_H
    if imgui.is_mouse_clicked(0) and over then
        dragging = true
        dsMX, dsMY, dsHX, dsHY = mx, my, hudX, hudY
    end
    if dragging then
        if imgui.is_mouse_down(0) then
            hudX = dsHX + (mx - dsMX)
            hudY = dsHY + (my - dsMY)
        else
            dragging = false
            savePosition()
        end
    end

    --vanilla HUD suppression
    --disable the vanilla gauge when swaxe HUD is active
    --re-enable when leave quest os wtich weapons
    --so other weapon types and hub UI are never affected
    local player = getPlayer()
    local shouldShow = shouldShowHUD(player)
    if shouldShow then
        setVanillaHudVisible(false)
    else
        setVanillaHudVisible(true)
        vanillaGuiComponent = nil
    end
end)