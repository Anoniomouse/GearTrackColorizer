local addonName, ns = ...

-- Display order for UI
ns.TRACK_ORDER = {"Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth"}

-- Default RGB colors per upgrade track
ns.TRACK_DEFAULTS = {
    ["Explorer"]   = {0.62, 0.62, 0.62},  -- Gray
    ["Adventurer"] = {0.12, 1.00, 0.00},  -- Green
    ["Veteran"]    = {0.00, 0.44, 1.00},  -- Blue
    ["Champion"]   = {0.64, 0.21, 0.93},  -- Purple
    ["Hero"]       = {1.00, 0.87, 0.00},  -- Yellow
    ["Myth"]       = {0.90, 0.80, 0.50},  -- Artifact gold
}

ns.DEFAULT_BORDER_THICKNESS = 3

-- Track name aliases that may appear in tooltip text
ns.TRACK_ALIASES = {
    ["Explorer"]   = {"Explorer"},
    ["Adventurer"] = {"Adventurer"},
    ["Veteran"]    = {"Veteran"},
    ["Champion"]   = {"Champion"},
    ["Hero"]       = {"Hero"},
    ["Myth"]       = {"Myth"},
}

-- Inventory slot IDs that have upgrade tracks (no shirt/tabard/relic slots)
ns.GEAR_SLOTS = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}

-- Character frame slot names in slot ID order
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
