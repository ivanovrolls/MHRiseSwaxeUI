# Switch Axe UI Mod — Field Extraction Guide

A guide to identifying live game state fields in Monster Hunter Rise using REFramework's Lua scripting environment. This documents the process used to map Switch Axe (internally called **Slash Axe** due to Japanese translation) gameplay states to their underlying field names, which are required to build a custom HUD.

---

## Prerequisites

Before starting, you will need the following installed and working:

- **Monster Hunter Rise** (Steam)
- **REFramework** — install by placing `dinput8.dll` in your game's root folder (same directory as `MonsterHunterRise.exe`). Available on Nexus Mods, [here](https://www.nexusmods.com/monsterhunterrise/mods/26?tab=files&file_id=14689).
- A text editor (Notepad, VS Code, etc.)
- Your Lua scripts placed in `MonsterHunterRise\reframework\autorun\`

To open the REFramework overlay in-game, press the **Insert** key. To reload scripts without restarting the game, go to **ScriptRunner → Reset Scripts** in the overlay menu.

If something goes wrong, check `MonsterHunterRise\re2_framework_log.txt` for error output.

---

## Overview

Monster Hunter Rise does not publicly document its internal game object structure. To build a custom weapon HUD, you will need to find which fields on the player object correspond to the gameplay states you want to display. States such as current phial gauge level, sword/axe mode, and amp state.

The process has three stages:

1. **Access the player object** via the `snow.player.PlayerManager` singleton
2. **Dump all fields** from the player object and its child objects to a readable output
3. **Observe field changes** during specific gameplay interactions to identify which fields map to which states

---

## Stage 1: Accessing the Player Object

In Rise, the local player is accessed through the `PlayerManager` singleton. The correct access pattern is:

```lua
local playerManager = sdk.get_managed_singleton("snow.player.PlayerManager")
local playerID = playerManager:call("getMasterPlayerID")
local player = playerManager:get_field("PlayerList"):call("get_Item", playerID)
```

> **Important:** `getMasterPlayerID` returns the index of the local player in the `PlayerList` array. This only returns a valid result when you are loaded into a quest!!! You should primarily look to test and observe fields within **quests**.

The player object's full type is `snow.player.PlayerQuestBase`. All weapon-specific fields are stored directly on this object rather than in a separate weapon component.

> **Note on naming:** The Switch Axe is referred to as the **Slash Axe** throughout the game files. All relevant fields use `SlashAxe`, `Bottle`, or `Slash` in their names. This is a localisation difference between the Japanese and Western releases of the game.

---

## Stage 2: The dataExtract.lua Script

The extraction script reads every field on the player object and displays them in a live REFramework imgui window. Fields that are object pointers (shown as `sol.REManagedObject*:...` or `sol.sdk::SystemArray*:...` with shifting hex addresses) are skipped, as they cannot be read as primitive values directly.

### Full Script

Save this as `reframework\autorun\dataExtract.lua`. The folders should automatically have been created in the game's root directory after extracting the REFramework .dll and running the game once. The script:

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

### Running the Script

1. Save the file to `reframework\autorun\dataExtract.lua`
2. Launch the game and load into a quest with your Switch Axe equipped
3. Press **Insert** to open the REFramework overlay
4. you should see the **SA Field Dumper** window
5. The window updates every frame, so all values are live

> **Tip:** If you make changes to the script, you do not need to restart the game. Go to **ScriptRunner → Reset Scripts** in the REFramework overlay to reload all scripts instantly.

### Filtering Fields

The full field list is very long. You can narrow it down by adding a keyword filter inside the loop:

```lua
-- Replace the loop body condition with this to filter by keyword
local nameLower = name:lower()
if nameLower:find("bottle") or nameLower:find("slash") or nameLower:find("awake") then
    -- display field
end
```

You can also filter for specific fields:
```lua
local nameLower = name:lower()
if nameLower:find("isenableelementcountereffects") then
    -- display field
end
```

Useful keywords for the Switch Axe: `bottle`, `slash`, `awake`, `gauge`, `axe`, `sword`, `element`, `swing`.

### Logging to File

The imgui window text cannot be selected or copied. You can use `log.info()` to write to `re2_framework_log.txt`:

```lua
-- Add this inside the field loop, gated by a "logged" flag so it only fires once
if not logged then
    log.info("[SA_DUMP] " .. name .. " = " .. valStr)
end
```

Then search for `[SA_DUMP]` in `re2_framework_log.txt` to find all the captured lines. Keep in mind that the log tends to be a huge file can cause issues opening or skimming through it, I personally just preffered to copy the lines to a text file manually. 

> **Note:** REFramework's Lua environment does not support absolute file paths or shell commands. `io.open` only works with paths relative to the game root, and `os.execute` is not available. The log file approach is the most reliable way to capture output.

---

## Stage 3: Annotating Fields Through Gameplay Observation

Once the script is running and you can see the live field values, the next step is to identify which fields correspond to each gameplay state. The method is straightforward: perform a specific action in-game and watch for fields that change.

### How to Observe Changes

Because the imgui window updates every frame, you can watch values change in real time. The key is to be deliberate and perform one action at a time so you can attribute each change to the right cause. This repo includes my own conclusions as to which field tracks what, but I may be wrong for some of them as it is hard to tell in some cases.

Work through each of the gameplay states below and note down which fields change and what values they take.

---

### Gameplay States to Test

#### Sword / Axe Mode

| Action | What to look for |
|---|---|
| Start in axe mode (default) | Note all boolean fields that are `false` |
| Press A to switch to sword mode | Look for a boolean that flips to `true` |
| Switch back to axe mode | Confirm it flips back to `false` |

**Finding:** `GroupSlashAxe` — `true` in sword mode, `false` in axe mode.

---

#### Phial/Switch Gauge

| Action | What to look for |
|---|---|
| Enter sword mode and attack | Watch for a numeric field counting down |
| Leave sword mode and wait | Watch for the same field recovering |
| Let the gauge get low | Look for a threshold-related field |

**Finding:** `_BottleGauge` is the live gauge value (0–100). `_BottelGaugeLow` (note the typo in the game files) is the low threshold at 37 — the point at which the vanilla UI turns the gauge red.

---

#### Elemental Buildup: Two Arrows State

This is the state indicated by two arrows appearing beside the gauge in the vanilla UI, signalling that you can perform an Elemental Burst.

| Action | What to look for |
|---|---|
| Stay in axe mode doing nothing | Establish baseline — note any timer fields at 0.0 |
| Switch to sword mode and attack until arrows appear | Look for a field that jumps from 0.0 to a large value |
| Wait for the window to expire | Confirm the field counts back down to 0.0 |

**Finding:** `_BottleAwakeAssistTimer` — jumps to `3600.0` when the two arrows appear and counts down. Use `> 0` as the boolean check for the arrow state.

> **Note:** Several fields that appeared to be candidates (`_BottleElementValue`, `<IsEnableElementCounterEffect>k__BackingField`) did not change during testing. `_BottleElementValue` is a static config value. Always verify by observation rather than assuming from the name alone.

---

#### Amp State — Blue Glow (Charged Sword)

This is the state where the sword glows blue and you have the damage boost active.

| Action | What to look for |
|---|---|
| Enter sword mode — no amp | Establish baseline |
| Activate amp (ZR in sword mode after buildup) | Look for a field that jumps from 0.0 to a non-zero value |
| Watch while amped | Look for a field counting down |
| Let amp expire | Confirm the field returns to 0.0 |

**Finding:** `_BottleAwakeGauge` jumps to `70.0` on activation (it does not build up gradually — it is set directly). `_BottleAwakeDurationTimer` counts down from `2700.0` to `0.0` while amp is active. Use `_BottleAwakeDurationTimer / 2700.0` to draw a duration bar.

---

### Reading Child Objects

Some fields are not on the player object directly but on a child object. In this mod's case, `_PlayerUserDataSlashAxe` is a child object containing static config values (max gauge, reduce times, etc.). To dump its fields, access it explicitly:

```lua
local userData = player:get_field("_PlayerUserDataSlashAxe")
if userData then
    local fields = userData:get_type_definition():get_fields()
    for i, field in ipairs(fields) do
        -- same field reading loop as above
    end
end
```

> **Important:** Child objects accessed this way tend to contain static configuration rather than live state. If none of the values change during gameplay, the live state is elsewhere. In this mod's case, all live state was on the parent player object.

---

## Field Reference Summary

The table below summarises all confirmed fields for the Switch Axe HUD. See `sa_field_reference.docx` for the full annotated reference including all extracted fields.

| UI Element | Field | Type | Notes |
|---|---|---|---|
| Sword / Axe mode | `GroupSlashAxe` | bool | `true` = sword mode |
| Phial gauge | `_BottleGauge` | float | Range 0–100 |
| Phial gauge low threshold | `_BottelGaugeLow` | float | 37 — note typo in field name |
| Two arrows (elemental window) | `_BottleAwakeAssistTimer` | float | `> 0` = arrows active, max 3600.0 |
| Amp active (blue glow) | `_BottleAwakeGauge` | float | `> 0` = amped, jumps to 70.0 |
| Amp duration remaining | `_BottleAwakeDurationTimer` | float | Counts down from 2700.0 |
| Amp shell count (max) | `_BottleAwakeShellMaxCount` | int | Always 4 |

---

## Common Issues

**The imgui window does not appear.**
Make sure you are using `re.on_frame` and not `re.on_draw_ui`. The latter only renders when the REFramework overlay is open.

**`imgui.begin` gives a "not callable" error.**
REFramework renames imgui functions that clash with Lua reserved words. Use `imgui.begin_window()` and `imgui.end_window()` instead of `imgui.begin()` and `imgui.end()`.

**No player ID found.**
You must be loaded into an active quest. The player object is not present in the hub or the lobby.

**Field values are not changing.**
You may be reading from a child object that contains static config rather than live state. Go back to dumping the parent player object and look for changes there instead.

**No log file is being created.**
REFramework does not support absolute file paths in `io.open`. Use `log.info()` and read from `re2_framework_log.txt` in the game root instead.

---

## Notes on the REFramework Lua Environment

- `io.open` supports relative paths from the game root only — no absolute paths, no `C:/` etc.
- `os.execute` and `io.popen` are not available — you cannot spawn a CMD window or run shell commands
- imgui text rendered with `imgui.text()` is not selectable — use `log.info()` or an imgui input field if you need to copy output
- Scripts in `reframework\autorun\` are loaded automatically on game start and can be reloaded at any time via **ScriptRunner → Reset Scripts** without restarting the game
