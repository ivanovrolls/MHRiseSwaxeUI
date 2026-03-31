# Switch Axe UI Mod — MHRise Wilds-Style HUD

A custom Switch Axe HUD for Monster Hunter Rise that replaces the vanilla gauge UI with a transplanted Switch Axe UI image extracted from Monster Hunter Wilds. The mod uses REFramework's Lua scripting and D2D plugin to draw coloured bars behind a transparent PNG image, which shows through the bar slots in the artwork. All three gauges — Switch Gauge, Power Axe mode, and Sword Amp charge — are tracked using live game state fields accessed directly from the game's memory.

---

## What the Mod Does

The mod draws three bars behind a custom weapon UI image:

**Switch Gauge (main horizontal bar)**
Tracks `_BottleGauge` (0–100). Fills left to right with warm gold. Turns burnt orange when the gauge drops to or below the reload threshold (`_BottelGaugeLow`). The notch visible in the image marks this threshold visually.

**Power Axe Mode (bottom left curved blade)**
Tracks `_BottleAwakeAssistTimer`. The bar appears and stays full (teal/cyan) while the two-arrows window is active. Pulses slowly between deep teal and bright cyan while active. Flashes rapidly when nearly expired.

**Sword Amp Charge (bottom right curved blade)**
Tracks `_BottleAwakeGauge` and `_BottleAwakeDurationTimer`. While building toward amp, the bar fills gradually with a flat dark teal. When sword amp activates, both this bar and the Power Axe bar switch to a pulsing  aqua. Both flash rapidly when amp is nearly expired.

**Additional features:**
- Fades in when entering a quest with Switch Axe equipped, fades out on return to hub/camp or weapon switch
- Vanilla Switch Axe gauge is hidden automatically while the custom HUD is active and restored when you switch weapons or leave the quest
- "AMPED!" text flashes briefly on activation
- Drag and drop positioning with persistent save across sessions and game restarts
- Scale and resolution configurable via the REFramework overlay menu

---

## Installation

### Requirements

- **Monster Hunter Rise** (Steam)
- **REFramework** — place `dinput8.dll` in your game root folder (`MonsterHunterRise.exe` directory). Available on [Nexus Mods](https://www.nexusmods.com/monsterhunterrise/mods/26).
- **reframework-d2d** — required for image and drawing support. Place `reframework-d2d.dll` in `reframework\plugins\` and `reframework-d2d.lua` in `reframework\autorun\`. Available on [Nexus Mods](https://www.nexusmods.com/monsterhunterrise/mods/2726).

### File Placement

Copy the following files into your game directory:

```
MonsterHunterRise\
└── reframework\
    ├── autorun\
    │   └── swaxe_hud.lua          ← the main script
    └── images\
        └── swaxe_ui.png           ← the UI image
```

> **Important:** The script must load **after** `reframework-d2d.lua` or the image API will not be available. REFramework loads autorun scripts alphabetically. Name your script starting with `s` or later to ensure it loads after `reframework-d2d.lua` (which starts with `r`).

### First Run

1. Launch Monster Hunter Rise
2. The HUD will not appear in the hub, this is expected
3. Load into a quest with your Switch Axe equipped
4. The HUD will fade in automatically
5. Press **Insert** to open the REFramework overlay if you want to adjust scale or reposition

---

## Configuration

Open the REFramework overlay (Insert key) and expand **Switch Axe HUD**:

| Setting | Description |
|---|---|
| Show HUD | Toggle the HUD on/off |
| Scale | Resize the HUD (0.5x–3.0x). Default is 1.5x |
| Screen Width / Height | Set your resolution so Reset Position centres correctly |
| Reset Position | Snap the HUD back to the default bottom-centre position |

**Drag and drop:** Click and hold anywhere on the HUD image while in a quest to drag it to a new position. Position is saved automatically when you release.

**Resolution:** The default config is set to 2560×1440. If you are on a different resolution, update `SCREEN_WIDTH` and `SCREEN_HEIGHT` at the top of the script, or use the sliders in the REFramework menu and click Reset Position to recentre.

---

## HUD Behaviour Reference

| State | Left bar | Right bar |
|---|---|---|
| Idle (in Hub or camp) | Hidden | Hidden |
| Power Axe mode active | Full, ember orange -> gold pulse | Dark teal fill (proportional to buildup) |
| Sword Amp active | Full, aqua pulse | Full, aqua pulse |
| Either bar nearly expired | Fast flash (same colour, faster) | Fast flash |
| Reload threshold reached | - | - |

---

## Field Extraction Guide

This section documents the process used to identify the live game state fields that power the HUD. Monster Hunter Rise does not publicly document its internal game object structure, so fields must be found by accessing the player object via REFramework's Lua environment and observing which values change during specific gameplay actions.

### Prerequisites

- REFramework installed and working
- A text editor
- Lua scripts placed in `MonsterHunterRise\reframework\autorun\`

Press **Insert** in-game to open the REFramework overlay. Go to **ScriptRunner  ->  Reset Scripts** to reload scripts without restarting. Check `MonsterHunterRise\re2_framework_log.txt` for error output.

---

### Stage 1: Accessing the Player Object

In Rise, the local player is accessed through the `PlayerManager` singleton:

```lua
local playerManager = sdk.get_managed_singleton("snow.player.PlayerManager")
local playerID = playerManager:call("getMasterPlayerID")
local player = playerManager:get_field("PlayerList"):call("get_Item", playerID)
```

> **Important:** `getMasterPlayerID` only returns a valid result when loaded into an active quest. The player object is not present in the hub or lobby.

The player object's full type is `snow.player.PlayerQuestBase`. All Switch Axe fields are stored directly on this object.

> **Note on naming:** The Switch Axe is called the **Slash Axe** throughout the game files due to the Japanese-to-English localisation. All relevant fields use `SlashAxe`, `Bottle`, or `Slash` in their names.

---

### Stage 2: The Field Dumper Script

Save this as `reframework\autorun\dataExtract.lua` and load into a quest:

```lua
local playerManager = sdk.get_managed_singleton("snow.player.PlayerManager")

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

        imgui.text("Player: " .. player:get_type_definition():get_full_name())
        imgui.separator()

        local fields = player:get_type_definition():get_fields()
        for i, field in ipairs(fields) do
            local name = field:get_name()
            local success, val = pcall(function()
                return player:get_field(name)
            end)
            if success and val ~= nil then
                local valStr = tostring(val)
                if not valStr:find("sol%.") then
                    imgui.text(name .. " = " .. valStr)
                end
            end
        end
    end
    imgui.end_window()
end)
```

To narrow the field list to Switch Axe relevant fields, add a keyword filter inside the loop:

```lua
local nameLower = name:lower()
if nameLower:find("bottle") or nameLower:find("slash") or nameLower:find("awake") then
    -- display field
end
```

To log to file instead of the imgui window (useful since imgui text cannot be copied):

```lua
if not logged then
    log.info("[SA_DUMP] " .. name .. " = " .. valStr)
end
```

Search for `[SA_DUMP]` in `re2_framework_log.txt` to find the output.

---

### Stage 3: Identifying Fields Through Gameplay

Run the dumper script and perform specific actions one at a time, watching for fields that change. The following observations led to the field mappings used in this mod.

#### Switch Gauge

Deplete the gauge in sword mode and watch for a numeric field counting down from 100. Let it recover and confirm it climbs back up.

**Finding:** `_BottleGauge` - live gauge value 0–100. `_BottelGaugeLow` (note the typo in the game files). Static threshold at 37 (visually 32), the point at which the vanilla UI turns red.

#### Power Axe Mode (Two Arrows State)

Switch to sword mode and attack until the two arrows appear beside the gauge. Watch for a timer field jumping from 0.

**Finding:** `_BottleAwakeAssistTimer` jumps to 3600.0 when arrows appear and counts down to 0. Use `> 0` as the active check.

#### Sword Amp

Build up and activate sword amp (ZR after elemental buildup in sword mode). Watch for fields that change on activation and count down while active.

**Finding:** `_BottleAwakeGauge` jumps to 70.0 on activation (does not build gradually). `_BottleAwakeDurationTimer` counts down from 2700.0 while amp is active. Use `_BottleAwakeDurationTimer / 2700.0` for a duration bar.

#### Weapon Drawn / Mode Detection

The player object type name contains `SlashAxe` only when a Switch Axe is equipped. The `PlayerQuestBase` type only exists during quests. Both are used together to show the HUD only when appropriate:

```lua
player:get_type_definition():is_a("snow.player.PlayerQuestBase")  --in a quest
player:get_type_definition():get_full_name():find("SlashAxe")      --correct weapon
```

---

### Field Reference Summary

| UI Element | Field | Type | Notes |
|---|---|---|---|
| Switch Gauge | `_BottleGauge` | float | Range 0–100 |
| Reload threshold | `_BottelGaugeLow` | float | 37 (typo is in the game files) |
| Power Axe mode window | `_BottleAwakeAssistTimer` | float | `> 0` = active, max 3600.0 |
| Sword Amp active | `_BottleAwakeGauge` | float | `> 0` = amped, jumps to 70.0 |
| Sword Amp duration | `_BottleAwakeDurationTimer` | float | Counts down from 2700.0 |
| Max amp duration | `_BottleAwakeDurationTime` | float | Static config 2700.0 |
| Amp shell count | `_BottleAwakeShellMaxCount` | int | Always 4 |

---

## Vanilla HUD Suppression

The vanilla Switch Axe gauge is hidden by finding its `via.gui.GUI` component via `snow.gui.GuiManager` and calling `set_Enabled(false)` on it each frame while the custom HUD is active. It is re-enabled automatically when you leave a quest or switch to a different weapon, so no other weapon's UI is affected.

This approach was found by using REFramework's **Object Explorer** (Developer Tools -> Object Explorer -> Singletons -> `snow.gui.GuiManager`) to locate the `guiHudWeaponUIObject` field, which points to a GameObject named `S_AxeGauge` containing a `via.gui.GUI` component.

---

## Common Issues

**HUD does not appear after loading into a quest.**
Make sure the script filename comes after `reframework-d2d.lua` alphabetically in the autorun folder. If in doubt, rename it to something starting with `s`.

**HUD appears but image is missing / bars draw with no image.**
Confirm `swaxe_ui.png` is in `reframework\images\` and that `reframework-d2d` is installed correctly.

**Vanilla gauge is still visible.**
The suppression works by disabling a GUI component each frame. If it is still visible, the `guiHudWeaponUIObject` field may have changed in a game update. Check the REFramework log for errors from `getVanillaGuiComponent`.

**HUD position resets every session.**
Confirm `reframework\data\swaxe_hud.json` is being created after you drag the HUD. If it is not, the `json.dump_file` call may be failing, check the log.

**The imgui dumper window does not appear.**
Make sure you are using `re.on_frame` and not `re.on_draw_ui`. The latter only renders when the REFramework overlay is open.

**No player ID found in the dumper.**
You must be loaded into an active quest. The player object does not exist in the hub.

---

## Notes on the REFramework Lua Environment

- `io.open` supports relative paths from the game root only — no absolute paths
- `os.execute` and `io.popen` are not available
- imgui text rendered with `imgui.text()` is not selectable — use `log.info()` if you need to copy output
- Scripts in `reframework\autorun\` load automatically on game start and can be reloaded via **ScriptRunner  ->  Reset Scripts** without restarting the game
- `sdk.get_managed_singleton` should be called fresh each frame rather than cached at script load time — the singleton may not be initialised yet when the script first runs
