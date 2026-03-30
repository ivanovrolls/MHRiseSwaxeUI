-- minimal.lua
-- Minimal triple bar Swaxe HUD for MHRise
-- Note: The vanilla Switch Axe UI will still be visible
-- Hiding it via Lua alone is not straightforward and is left as a future task

-- ============================================================
-- CONFIG — change to match your resolution
-- ============================================================
local SCREEN_WIDTH  = 2560
local SCREEN_HEIGHT = 1440

local HUD_W = 400
local HUD_H = 160
local HUD_X = (SCREEN_WIDTH / 2) - (HUD_W / 2)
local HUD_Y = SCREEN_HEIGHT - HUD_H - 80

-- ============================================================
-- COLOURS
-- Helper: colour(r, g, b, a) — all values 0-255
-- ============================================================
local function colour(r, g, b, a)
    a = a or 255
    return (a << 24) | (b << 16) | (g << 8) | r
end

local COL_GAUGE_NORMAL = colour(80,  200, 120, 255)  -- Green
local COL_GAUGE_LOW    = colour(220, 60,  60,  255)  -- Red when low
local COL_GAUGE_BG     = colour(30,  30,  30,  200)  -- Bar background
local COL_AMP_ACTIVE   = colour(80,  160, 255, 255)  -- Blue amp
local COL_AMP_BG       = colour(20,  20,  60,  200)  -- Amp bar background
local COL_ARROWS       = colour(255, 200, 50,  255)  -- Gold arrows
local COL_ARROWS_BG    = colour(40,  35,  10,  200)  -- Arrow bar background
local COL_SWORD_MODE   = colour(80,  160, 255, 255)  -- Sword mode label
local COL_AXE_MODE     = colour(180, 100, 40,  255)  -- Axe mode label
local COL_TEXT         = colour(255, 255, 255, 255)  -- White
local COL_TEXT_DIM     = colour(160, 160, 160, 255)  -- Dimmed
local COL_RELOAD_YES   = colour(220, 60,  60,  255)  -- Red dot = reload required
local COL_RELOAD_NO    = colour(80,  200, 120, 255)  -- Green dot = no reload

-- ============================================================
-- PLAYER ACCESS
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
-- DRAW
-- ============================================================

local function drawBar(x, y, w, h, fraction, colFg, colBg, label, labelCol)
    fraction = math.max(0, math.min(1, fraction))
    draw.filled_rect(x, y, w, h, colBg)
    if fraction > 0 then
        draw.filled_rect(x, y, w * fraction, h, colFg)
    end
    draw.outline_rect(x, y, w, h, colour(255, 255, 255, 40), 1)
    if label then
        draw.text(label, x + 6, y + (h / 2) - 7, labelCol or COL_TEXT)
    end
end

re.on_frame(function()
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

    local isAmped = awakeGauge > 0
    local arrowsActive = assistTimer > 0
    local reloadRequired = bottleGauge <= 36

    local gaugeFraction = bottleGauge / 100
    local arrowFraction = assistTimer / assistTimerMax
    local ampFraction = awakeDuration / awakeDurationMax

    local gaugeColour = (bottleGauge <= bottleGaugeLow) and COL_GAUGE_LOW or COL_GAUGE_NORMAL

    local cx = HUD_X
    local cy = HUD_Y
    local barW = HUD_W
    local barH = 14

    -- MODE LABEL
    draw.text(isSwordMode and "SWORD MODE" or "AXE MODE", cx, cy,
        isSwordMode and COL_SWORD_MODE or COL_AXE_MODE)

    -- RELOAD INDICATOR DOT
    local dotX = cx + 140
    local dotY = cy + 8
    local dotR = 6
    draw.filled_circle(dotX, dotY, dotR, reloadRequired and COL_RELOAD_YES or COL_RELOAD_NO, 12)
    draw.outline_circle(dotX, dotY, dotR, colour(255, 255, 255, 60), 12)
    draw.text(reloadRequired and "RELOAD" or "NO RELOAD", dotX + dotR + 5, cy,
        reloadRequired and COL_RELOAD_YES or COL_TEXT_DIM)

    cy = cy + 20

    -- SWITCH GAUGE
    draw.text("SWITCH GAUGE", cx, cy, COL_TEXT_DIM)
    cy = cy + 14
    drawBar(cx, cy, barW, barH, gaugeFraction, gaugeColour, COL_GAUGE_BG,
        string.format("%d / 100", bottleGauge), COL_TEXT)
    cy = cy + barH + 10

    -- RELOAD LIMIT
    draw.text("ELEMENT AMP", cx, cy, arrowsActive and COL_ARROWS or COL_TEXT_DIM)
    cy = cy + 14
    drawBar(cx, cy, barW, barH,
        arrowsActive and arrowFraction or 0,
        COL_ARROWS, COL_ARROWS_BG,
        arrowsActive and string.format("%.0f%%", arrowFraction * 100) or "Not active",
        arrowsActive and colour(30, 20, 5, 255) or COL_TEXT_DIM)
    cy = cy + barH + 10

    -- AMPED CHARGE
    draw.text("SWORD AMP", cx, cy, isAmped and COL_AMP_ACTIVE or COL_TEXT_DIM)
    cy = cy + 14
    drawBar(cx, cy, barW, barH,
        isAmped and ampFraction or 0,
        COL_AMP_ACTIVE, COL_AMP_BG,
        isAmped and string.format("%.0f%%", ampFraction * 100) or "Not active",
        isAmped and colour(10, 20, 50, 255) or COL_TEXT_DIM)
end)