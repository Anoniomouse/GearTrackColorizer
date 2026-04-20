# GearTrackColorizer — Design & Requirements

WoW version: **12.0.1** (interface 120001)  
Source reference: `wow-ui-source` @ 12.0.1.66838

---

## 1. Purpose

Color-code every equipped gear slot (character frame) and every bag item slot
with a thin border that reflects the item's **upgrade track** — Explorer,
Adventurer, Veteran, Champion, Hero, or Myth — so the player can see their
gear progression at a glance without opening the item upgrade UI.

---

## 2. Requirements

| # | Requirement |
|---|-------------|
| R1 | Equipped gear slots on the character frame receive a colored border. |
| R2 | Bag item slots receive the same colored border. |
| R3 | Borders work regardless of which bag addon is installed. |
| R4 | Item tooltips show the item name re-colored in the track color and a "Track: X" badge line. |
| R5 | Colors are fully customizable per track via the in-game settings panel. |
| R6 | Border thickness is adjustable (1–6 px) via the settings panel. |
| R7 | Bag borders can be toggled independently of slot borders. |
| R8 | All settings persist across sessions via SavedVariables. |
| R9 | Settings panel opens from Esc → Interface → AddOns AND from the minimap addon compartment. |
| R10 | A login chat message shows addon version and enabled status. |
| R11 | `/gtc on\|off\|reload` slash commands for quick toggling. |

---

## 3. Track Colors (defaults)

| Track | Color | Hex |
|-------|-------|-----|
| Explorer | Gray | `#9E9E9E` |
| Adventurer | Green | `#1EFF00` |
| Veteran | Blue | `#0070FF` |
| Champion | Purple | `#A336ED` |
| Hero | Yellow | `#FFDE00` |
| Myth | Artifact gold | `#E6CC80` |

**Orange is reserved for Legendary items** and must not be used.

---

## 4. Architecture

### 4.1 File load order (TOC)

```
Tracks.lua    — constants: defaults, TRACK_ORDER, TRACK_ALIASES, slot maps
Core.lua      — DB init, detection, border rendering, tooltip, events, slash
Bags.lua      — bag button detection, cache, bag-specific hooks
Settings.lua  — in-game settings panel, color pickers, Settings API registration
```

### 4.2 Shared namespace (`ns`)

All cross-file symbols go through the second vararg (`ns`):

| Symbol | Set in | Used in |
|--------|--------|---------|
| `ns.TRACK_ORDER` | Tracks | Settings |
| `ns.TRACK_DEFAULTS` | Tracks | Core (InitDB), Settings (reset) |
| `ns.TRACK_ALIASES` | Tracks | Core (detection) |
| `ns.DEFAULT_BORDER_THICKNESS` | Tracks | Core (InitDB) |
| `ns.GEAR_SLOTS` | Tracks | Core |
| `ns.SLOT_NAMES` | Tracks | Core |
| `ns.GetTrackColor` | Core | Bags |
| `ns.SetItemBorder` | Core | Bags |
| `ns.UpdateAllSlots` | Core | Settings, slash |
| `ns.ClearAllSlots` | Core | Settings, slash |
| `ns.UpdateAllBagButtons` | Bags | Core (slash), Settings |
| `ns.ClearAllBagButtons` | Bags | Core (slash), Settings |

### 4.3 SavedVariables (`GearTrackColorizerDB`)

```lua
{
    enabled         = true,
    bagBorders      = true,
    borderThickness = 3,          -- integer 1–6
    colors = {
        Explorer   = {r, g, b},
        Adventurer = {r, g, b},
        Veteran    = {r, g, b},
        Champion   = {r, g, b},
        Hero       = {r, g, b},
        Myth       = {r, g, b},
    }
}
```

---

## 5. API Constraints (12.0.1)

### 5.1 Track detection

`C_ItemUpgrade` has **no function that accepts an item link and returns a track
name**. The full API as of 12.0.1:

- `GetItemUpgradeItemInfo()` — no args; returns info for the item currently
  loaded into the upgrade UI. Fields: `currUpgrade`, `maxUpgrade`, `minItemLevel`,
  `maxItemLevel`, `upgradeLevelInfos[]`, etc. **No `trackName` field.**
- All other `C_ItemUpgrade` functions deal with the UI state, not arbitrary links.

**Conclusion:** Tooltip-line scanning is the only cross-patch method to detect
track names from an arbitrary item link. Use a hidden `GameTooltipTemplate` frame,
call `:SetHyperlink(itemLink)`, then search text lines for known track name strings.

### 5.2 Tooltip hooks

`OnTooltipSetItem` was **removed as a hookable script in 12.0**. Use:

```lua
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    -- fires for ALL tooltips (GameTooltip, ItemRef, shopping, scan tooltips, etc.)
end)
```

**Critical:** `TooltipDataProcessor` fires for the hidden scan tooltip too.
Guard against it by name (`tooltip == scanTT`) to prevent infinite recursion.

**Never call `tooltip:Show()` inside a PostCall callback** — `Show()` re-fires
the data processor pipeline and causes a C stack overflow with other addons
(ElvUI, Rarity, etc.) also hooked into the same pipeline.

### 5.3 Item button border

Source: `Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua`

Item buttons (bag slots, character frame slots) have an `IconBorder` texture
and these helpers:

```lua
SetItemButtonBorder(button, "Interface\\Common\\WhiteIconFrame")  -- enable border
SetItemButtonBorderVertexColor(button, r, g, b)                   -- color it
SetItemButtonBorder(button)                                        -- clear it
```

**Do NOT use these for track coloring.** `SetItemButtonQuality()` calls
`SetItemButtonBorderVertexColor` on every refresh and will override the track
color with the quality color (gray/green/blue/purple/orange). Use independent
OVERLAY textures instead (see §5.4).

### 5.4 Custom border rendering

Create four thin `OVERLAY` textures along the frame edges. This layer is above
`IconBorder` (BORDER layer) and quality overlays (ARTWORK layer) but does not
conflict with them:

```lua
-- top/bottom: SetHeight(t), anchored TOPLEFT→TOPRIGHT / BOTTOMLEFT→BOTTOMRIGHT
-- left/right:  SetWidth(t),  anchored with -t/+t Y insets to avoid corner overlap
-- Texture: "Interface\\Buttons\\WHITE8X8" (solid 1×1 white, tinted via SetVertexColor)
```

Re-apply anchors on every call so thickness changes take effect immediately
without needing to rebuild textures.

### 5.5 Bag button slot detection

Source: `Blizzard_ItemButton/Shared/ItemButtonTemplate.lua`

```lua
ItemButtonMixin:GetBagID()  → self.bagID   (bag container index, 0 = backpack)
frame:GetID()               → slot index within the bag
```

**`GetSlotID()` does not exist.** Use `GetID()` for the slot.

Detection order for cross-addon compatibility:
1. `frame.GetBagID` method + `frame:GetID()` — Blizzard ItemButtonMixin (12.0)
2. `frame.bag` / `frame.slot` fields — Bagnon and similar
3. Frame name pattern `"ContainerFrame(%d+)Item(%d+)"` — legacy

### 5.6 Settings API

```lua
-- Create a canvas (fully custom layout):
local category = Settings.RegisterCanvasLayoutCategory(panel, addonName)
Settings.RegisterAddOnCategory(category)

-- Open to a specific category:
Settings.OpenToCategory(category)
```

Panel frame **must have an explicit size set** (`panel:SetSize(w, h)`) or the
canvas scroll area has no dimensions. Panel must start hidden (`panel:Hide()`).

Register on `PLAYER_LOGIN`, not `ADDON_LOADED` — the Settings API and DB are
both guaranteed ready at that point.

### 5.7 Addon compartment

```lua
if AddonCompartment then
    AddonCompartment.RegisterAddon({
        text = addonName,
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        notCheckable = true,
        func = function() Settings.OpenToCategory(settingsCategory) end,
    })
end
```

### 5.8 Removed globals (12.0)

| Removed | Replacement |
|---------|-------------|
| `GetAddOnMetadata` | `C_AddOns.GetAddOnMetadata` |
| `OnTooltipSetItem` hook script | `TooltipDataProcessor.AddTooltipPostCall` |
| `ContainerFrameItemButton_Update` | Removed; no direct replacement |
| `ShoppingTooltip1/2` globals | `GameTooltip.shoppingTooltips[]` |

---

## 6. Known Limitations

- **Localization:** Track name detection relies on English tooltip text
  (`"Explorer"`, `"Adventurer"`, etc.). Non-English clients will not see
  borders/tooltip colors. Fix requires locale-specific alias tables.
- **Bank bags:** Bag ID range check currently excludes negative bag IDs
  (bank, reagent bank). Bank item borders are not shown.
- **Third-party bags:** Addons whose item buttons expose neither `GetBagID()`
  nor `.bag`/`.slot` fields and don't follow `ContainerFrame` naming will not
  receive proactive borders, but will receive borders on tooltip hover via the
  `TooltipDataProcessor` hook.
- **Season changes:** Track names in tooltips may change between expansion
  seasons. The `TRACK_ALIASES` table in `Tracks.lua` must be updated if
  Blizzard renames tracks.
