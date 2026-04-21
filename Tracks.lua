local addonName, ns = ...

ns.DISPLAY_NAME = "Gear Track Colorizer"

-- Ordered list for settings UI rows
-- "Maxed" and "Legendary" are status overrides, not real upgrade tracks.
ns.TRACK_ORDER = {"Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth", "Maxed", "Legendary"}

-- Default RGB colors. Orange is reserved for Legendaries.
ns.TRACK_DEFAULTS = {
    Explorer   = {0.62, 0.62, 0.62},  -- Gray
    Adventurer = {0.12, 1.00, 0.00},  -- Green
    Veteran    = {0.00, 0.44, 1.00},  -- Blue
    Champion   = {0.64, 0.21, 0.93},  -- Purple
    Hero       = {1.00, 0.87, 0.00},  -- Yellow
    Myth       = {1.00, 0.10, 0.10},  -- Red
    Maxed      = {1.00, 1.00, 1.00},  -- White  (Myth at max upgrade — nothing left to do)
    Legendary  = {1.00, 0.50, 0.00},  -- Orange (#FF8000)
}

ns.DEFAULT_BORDER_THICKNESS = 4  -- pixels, range 1-6

-- Bump this whenever TRACK_DEFAULTS colors change. InitDB detects the mismatch
-- and reseeds all colors that the user has not customised away from stock.
-- Increment this number each time you change a default color.
ns.DEFAULTS_VERSION = 4

-- Aliases searched in tooltip lines. "Maxed" and "Legendary" are detected by
-- other means (X/X pattern and item quality), so their alias lists are empty.
-- Word-boundary patterns prevent "Hero" matching "Heroic", etc.
ns.TRACK_ALIASES = {
    Explorer   = {"Explorer"},
    Adventurer = {"Adventurer"},
    Veteran    = {"Veteran"},
    Champion   = {"Champion"},
    Hero       = {"Hero"},
    Myth       = {"Myth"},
    Maxed      = {},
    Legendary  = {},
}

-- Item level thresholds for crafted gear (shows quality stars, not track names).
-- Midnight Season 1 values — checked highest-first.
ns.ILVL_TRACK_THRESHOLDS = {
    {276, "Myth"},
    {263, "Hero"},
    {250, "Champion"},
    {237, "Veteran"},
    {224, "Adventurer"},
    {0,   "Explorer"},
}

-- Inventory slot IDs with upgrade tracks (excludes shirt 4, tabard 19)
ns.GEAR_SLOTS = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}

-- Character frame slot button names keyed by slot ID
ns.SLOT_NAMES = {
    [1]  = "CharacterHeadSlot",
    [2]  = "CharacterNeckSlot",
    [3]  = "CharacterShoulderSlot",
    [5]  = "CharacterChestSlot",
    [6]  = "CharacterWaistSlot",
    [7]  = "CharacterLegsSlot",
    [8]  = "CharacterFeetSlot",
    [9]  = "CharacterWristSlot",
    [10] = "CharacterHandsSlot",
    [11] = "CharacterFinger0Slot",
    [12] = "CharacterFinger1Slot",
    [13] = "CharacterTrinket0Slot",
    [14] = "CharacterTrinket1Slot",
    [15] = "CharacterBackSlot",
    [16] = "CharacterMainHandSlot",
    [17] = "CharacterSecondaryHandSlot",
}
