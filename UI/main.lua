-- main.lua
-- Transplanted Swaxe UI from Wilds
-- Note: The vanilla Switch Axe UI will still be visible
-- Hiding it via Lua alone is not straightforward and is left as a future task

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

-- ============================================================
-- HUD STATE
-- ============================================================
local hudX = (SCREEN_WIDTH / 2) - (DISP_W / 2)
local hudY = SCREEN_HEIGHT - DISP_H - 100
local hudVisible = true
local dragging = false
local dsMX, dsMY, dsHX, dsHY = 0, 0, 0, 0

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
    local globalX2 = -math.huge --find overall x boundary
    for _, row in ipairs(rows) do
        if row.x1 < globalX1 then globalX1 = row.x1 end
        if row.x2 > globalX2 then globalX2 = row.x2 end
    end

    local fillBoundary = globalX1 + (globalX2 - globalX1) * math.min(1, fraction) --how far we have filled
    
    --draw row clipped to boundary
    for _, row in ipairs(rows) do
        --background for full row
        d2d.fill_rect(sx(row.x1), sy(row.y), sw(row.x2 - row.x1), sw(1), bgCol)
        
        local clipX2 = math.min(row.x2, fillBoundary)
        if clipX2 > row.x1 then
            d2d.fill_rect(sx(row.x1), sy(row.y), sw(clipX2 - row.x1), sw(1), col)
        end
    end
end

-- ============================================================
-- D2D api allows me to import the image for the UI
-- ============================================================
local swaxeImage = nil
local labelFont = nil
local smallFont = nil

d2d.register(function()
    swaxeImage = d2d.Image.new("swaxe_ui.png")
    labelFont = d2d.Font.new("Arial", 13)
    smallFont = d2d.Font.new("Arial", 11)
end,

function()
    if not hudVisible then return end
    local player = getPlayer()
    if not player then return end

    local swordEffect = getField(player, "_SwordEffect", nil)
    local isSwordMode = swordEffect ~= nil
    local bottleGauge = getField(player, "_BottleGauge", 0)
    local bottleGaugeLow = getField(player, "_BottelGaugeLow", 37)
    local assistTimer = getField(player, "_BottleAwakeAssistTimer", 0)
    local assistTimerMax = 3600.0
    local awakeGauge = getField(player, "_BottleAwakeGauge", 0)
    local awakeDuration = getField(player, "_BottleAwakeDurationTimer", 0)
    local awakeDurationMax = getField(player, "_BottleAwakeDurationTime", 2700)
    local awakeGaugeMax = 70.0

    local isAmped = awakeGauge > 0 and awakeDuration > 0
    local isBuildingAmp = awakeGauge > 0 and awakeDuration <= 0
    local arrowsActive = assistTimer > 0
    local reloadRequired = bottleGauge <= 36

    local gaugeFraction = math.max(0, math.min(1, bottleGauge / 100.0))
    local arrowFraction = math.max(0, math.min(1, assistTimer / assistTimerMax))
    local ampFraction = math.max(0, math.min(1, awakeDuration / awakeDurationMax))
    local buildFraction = math.max(0, math.min(1, awakeGauge / awakeGaugeMax))

    local t = os.clock()
    local pulse = (math.sin(t * FLASH_SPEED * math.pi * 2) + 1) / 2

    --flash when low
    --bar stays full, colour pulses like in wilds
    local arrowLow  = arrowsActive and arrowFraction < FLASH_THRESHOLD
    local ampLow    = isAmped      and ampFraction   < FLASH_THRESHOLD

    --elemental colour: teal normally, flashes bright cyan when low
    local elemCol
    if arrowLow then
        local g = math.floor(220 + (255-220) * pulse)
        local b = math.floor(200 + (255-200) * pulse)
        local r = math.floor(0 + 80 * pulse)
        elemCol = argb(255, r, g, b)
    else
        elemCol = ELEM_ON
    end

    --sword colour: indigo -> violet active -> flashes violet when low
    local swordCol, swordFraction
    if isAmped then
        if ampLow then
            local r = math.floor(160 + (220-160) * pulse)
            local g = math.floor(60  + (160-60)  * pulse)
            swordCol = argb(255, r, g, 255)
        else
            swordCol = SWORD_AMP
        end
        --bar stays full when amp is active
        swordFraction = 1.0
    elseif isBuildingAmp then
        swordCol = SWORD_BUILD
        swordFraction = buildFraction
    else
        swordCol = SWORD_BUILD
        swordFraction = 0
    end

    -- Elemental bar stays FULL when active, only flashes when low
    local elemFraction = arrowsActive and 1.0 or 0.0

    local gaugeCol = reloadRequired and GAUGE_LOW or GAUGE_FULL

    --main gauge bar
    local barW = MAIN_BAR.x2 - MAIN_BAR.x1
    d2d.fill_rect(sx(MAIN_BAR.x1), sy(MAIN_BAR.y), sw(barW), sw(MAIN_BAR.h), INACTIVE)
    if gaugeFraction > 0 then
        d2d.fill_rect(sx(MAIN_BAR.x1), sy(MAIN_BAR.y),
            sw(barW * gaugeFraction), sw(MAIN_BAR.h), gaugeCol)
    end

    --power axe / elem amp
    for _, row in ipairs(ELEM_LEFT) do
        d2d.fill_rect(sx(row.x1), sy(row.y), sw(row.x2-row.x1), sw(1), INACTIVE)
    end
    if arrowsActive then
        for _, row in ipairs(ELEM_LEFT) do
            drawRowRTL(row, elemFraction, elemCol)
        end
    end

    --sword amp mode
    drawCurvedLTR(ELEM_RIGHT, swordFraction, swordCol, INACTIVE)

    --d2d api to import image
    d2d.image(swaxeImage, hudX, hudY, DISP_W, DISP_H)

    -- --labels on ui and reload indicator (not working rn)
    -- local labelY = hudY + DISP_H + 5

    -- d2d.fill_rect(hudX, labelY-1, 108, 17, TEXT_BG)
    -- d2d.text(labelFont, isSwordMode and "SWORD MODE" or "AXE MODE",
    --     hudX+3, labelY, isSwordMode and SWORD_LABEL or AXE_LABEL)

    -- local dotCX = hudX + 116
    -- local dotCY = labelY + 7
    -- d2d.fill_ellipse(dotCX, dotCY, 5, 5, reloadRequired and RELOAD_YES or RELOAD_NO)
    -- d2d.outline_ellipse(dotCX, dotCY, 5, 5, 1, argb(80, 255, 255, 255))
    -- d2d.fill_rect(dotCX+8, labelY-1, 78, 17, TEXT_BG)
    -- d2d.text(smallFont, reloadRequired and "RELOAD" or "NO RELOAD",
    --     dotCX+10, labelY, reloadRequired and RELOAD_YES or TEXT_DIM)

    -- local pctX = hudX + DISP_W + 6
    -- d2d.text(smallFont,
    --     string.format("SWITCH %d%%", math.floor(gaugeFraction*100)),
    --     pctX, sy(10), reloadRequired and GAUGE_LOW or TEXT_DIM)
    -- d2d.text(smallFont,
    --     arrowsActive and string.format("E.AMP %d%%", math.floor(arrowFraction*100)) or "E.AMP —",
    --     pctX, sy(26), arrowsActive and elemCol or TEXT_DIM)

    -- local sLabel = isAmped      and string.format("S.AMP %d%%",  math.floor(ampFraction*100))
    --            or isBuildingAmp and string.format("BUILD %d%%",  math.floor(buildFraction*100))
    --            or "S.AMP —"
    -- d2d.text(smallFont, sLabel, pctX, sy(32),
    --     isAmped and swordCol or (isBuildingAmp and SWORD_BUILD or TEXT_DIM))

    --mode indicator
    local labelY = hudY + DISP_H + 5
    d2d.fill_rect(hudX, labelY-1, 108, 17, TEXT_BG)
    d2d.text(labelFont, isSwordMode and "SWORD MODE" or "AXE MODE",
        hudX+3, labelY, isSwordMode and SWORD_LABEL or AXE_LABEL)

end)

-- ============================================================
-- REFramework menu
-- the buttons to rest position and show/hide ui
-- ============================================================
re.on_draw_ui(function()
    if imgui.tree_node("Switch Axe HUD") then
        local c, v = imgui.checkbox("Show HUD", hudVisible)
        if c then hudVisible = v end
        imgui.text(string.format("Position: %.0f, %.0f", hudX, hudY))
        if imgui.button("Reset Position") then
            hudX = (SCREEN_WIDTH/2) - (DISP_W/2)
            hudY = SCREEN_HEIGHT - DISP_H - 100
        end
        imgui.tree_pop()
    end
end)

-- ============================================================
-- drag n drop
-- ============================================================
re.on_frame(function()
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
        end
    end
end)