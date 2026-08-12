local addonName, ns = ...

-- ── SavedVariables initialisation ─────────────────────────────────────────

local function InitDB()
    GearTrackColorizerDB = GearTrackColorizerDB or {}
    local db = GearTrackColorizerDB

    if db.enabled         == nil then db.enabled         = true end
    if db.bagBorders      == nil then db.bagBorders      = true end
    if db.borderThickness == nil then db.borderThickness = ns.DEFAULT_BORDER_THICKNESS end
    if db.inspectBorders  == nil then db.inspectBorders  = true end

    db.colors = db.colors or {}
    db.trackEnabled = db.trackEnabled or {}
    for _, name in ipairs(ns.TRACK_ORDER) do
        if db.trackEnabled[name] == nil then db.trackEnabled[name] = true end
    end

    -- On a defaults-version bump, reseed every color whose saved value still
    -- matches the OLD stock color (user-customised colors are left untouched).
    -- On first install (no version saved) just seed everything.
    local versionChanged = (db.defaultsVersion or 0) ~= ns.DEFAULTS_VERSION
    for _, name in ipairs(ns.TRACK_ORDER) do
        local d = ns.TRACK_DEFAULTS[name]
        if not db.colors[name] or versionChanged then
            db.colors[name] = {d[1], d[2], d[3]}
        end
    end
    db.defaultsVersion = ns.DEFAULTS_VERSION
end

-- ── Hidden scan tooltip ────────────────────────────────────────────────────
-- Used to read item tooltip text without displaying anything on screen.
-- TooltipDataProcessor fires for this tooltip too — guard against it in every
-- PostCall callback to prevent GetTrackColor from recursing into itself.

local scanTT = CreateFrame("GameTooltip", "GearTrackColorizerScanTT", nil, "GameTooltipTemplate")
scanTT:SetOwner(WorldFrame, "ANCHOR_NONE")

-- ── Track detection ────────────────────────────────────────────────────────
-- Priority order:
--   1. Legendary quality (item quality 5) → Legendary color.
--   2. Profession gear (PROFESSION equip location) → item quality color.
--   3. ilvl vs current season thresholds → track color.
--      Myth-ilvl items additionally check tooltip for X/X fraction → Maxed.
-- Classifying by ilvl (not tooltip track name) ensures S1 gear gets its
-- correct S2-relative color rather than its old S1 track color.
--
-- ClassifyItem does the expensive work (GetItemInfo + tooltip scan) and caches
-- the result by itemLink. Track classification is immutable for a given link.
-- GetTrackColor is called on every update and reads colors fresh from DB so
-- user color/toggle changes take effect immediately without clearing the cache.

local scanCache = {}  -- [itemLink] = key string, or false for "no color"

-- Collect tooltip lines for itemLink without touching any visible frame.
-- C_TooltipInfo.GetHyperlink (Dragonflight+) returns data directly from the
-- item cache as a plain Lua table — no frame update, no layout cost.
-- Falls back to the hidden scan tooltip for safety.
local function GetTooltipLines(itemLink)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tipData = C_TooltipInfo.GetHyperlink(itemLink)
        if tipData and tipData.lines and #tipData.lines > 0 then
            local out = {}
            for _, ld in ipairs(tipData.lines) do
                if ld.leftText  then out[#out + 1] = ld.leftText  end
                if ld.rightText then out[#out + 1] = ld.rightText end
            end
            return out
        end
        -- C_TooltipInfo returned nothing — fall through to the scan tooltip which
        -- can force-load tooltip data that C_TooltipInfo can't reach yet.
    end
    -- Hidden GameTooltip frame: slower but triggers a full tooltip data load.
    scanTT:ClearLines()
    local ok = pcall(function() scanTT:SetHyperlink(itemLink) end)
    if not ok or scanTT:NumLines() == 0 then return nil end
    local out = {}
    for i = 1, scanTT:NumLines() do
        local r = _G["GearTrackColorizerScanTTTextLeft" .. i]
        local t = r and r:GetText()
        if t then out[#out + 1] = t end
    end
    return #out > 0 and out or nil
end

local function ClassifyItem(itemLink)
    local cached = scanCache[itemLink]
    if cached ~= nil then return cached end

    local quality, itemLevel, equipLoc
    pcall(function()
        local t = {GetItemInfo(itemLink)}
        quality   = t[3]
        itemLevel = t[4]
        equipLoc  = t[9]
    end)
    if quality == nil then return nil end  -- data not loaded; retry later

    -- 1. Legendary
    if quality == 5 then
        scanCache[itemLink] = "Legendary"
        return "Legendary"
    end

    -- 2. Profession gear (PROFESSION equip location, no upgrade track).
    if equipLoc and equipLoc:find("PROFESSION") and quality >= 2 then
        local key = "Q" .. tostring(quality)
        scanCache[itemLink] = key
        return key
    end

    -- 3. Classify by ilvl against current season thresholds.
    --    Using ilvl means S1 gear gets its correct S2-relative color instead of
    --    being over-colored by the old tooltip track name.
    if itemLevel and itemLevel > 0 then
        for _, entry in ipairs(ns.ILVL_TRACK_THRESHOLDS) do
            if itemLevel >= entry[1] then
                local trackName = entry[2]
                -- Myth-ilvl items: check for fully-upgraded X/X fraction.
                if trackName == "Myth" then
                    local lines = GetTooltipLines(itemLink)
                    if lines then
                        for _, line in ipairs(lines) do
                            local curr, max = line:match("(%d+)/(%d+)")
                            if curr and tonumber(curr) == tonumber(max)
                                and tonumber(max) >= 5
                            then
                                scanCache[itemLink] = "Maxed"
                                return "Maxed"
                            end
                        end
                    end
                end
                scanCache[itemLink] = trackName
                return trackName
            end
        end
    end

    scanCache[itemLink] = false
    return false
end

local function GetTrackColor(itemLink)
    if not itemLink or not GearTrackColorizerDB then return nil end
    local dbColors = GearTrackColorizerDB.colors
    local te       = GearTrackColorizerDB.trackEnabled

    local key = ClassifyItem(itemLink)
    if not key then return nil end

    -- Profession gear encoded as "Q<quality>" → derive color from quality each call.
    if key:sub(1, 1) == "Q" then
        local qual = tonumber(key:sub(2))
        local qr, qg, qb
        pcall(function() qr, qg, qb = GetItemQualityColor(qual) end)
        if qr then return {qr, qg, qb}, "Crafted" end
        return nil
    end

    -- All other keys are track names (Explorer … Maxed, Legendary).
    if te and te[key] == false then return nil end
    if dbColors[key] then return dbColors[key], key end
    return nil
end

ns.GetTrackColor = GetTrackColor

-- ── Border rendering ───────────────────────────────────────────────────────
-- Four thin OVERLAY-layer edge textures (sublevel 7) avoid IconBorder (BORDER layer)
-- because SetItemButtonQuality() resets its color to the item quality on every refresh.
-- Sublevel 7 ensures our textures render above third-party addon borders (e.g.
-- EllesmereUI uses sublevel 2). Anchors re-applied on every call so thickness changes
-- take effect immediately.

local function SetItemBorder(frame, r, g, b, a)
    if not frame then return end
    local t = GearTrackColorizerDB.borderThickness

    if not frame.gtcBorder then
        frame.gtcBorder = {}
        -- Child frame at level +100 renders above EllesmereUI's character-sheet
        -- overlay panels (which sit at CharacterFrame level +50) and above
        -- EllesmereUI's inspect borders (OVERLAY sublevel 7 on the slot frame).
        local bf = CreateFrame("Frame", nil, frame)
        bf:SetAllPoints()
        bf:SetFrameLevel(frame:GetFrameLevel() + 100)
        frame.gtcBorderFrame = bf
        for _, side in ipairs({"top", "bottom", "left", "right"}) do
            local tex = bf:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            frame.gtcBorder[side] = tex
        end
    end

    local e = frame.gtcBorder

    e.top:SetHeight(t)
    e.top:ClearAllPoints()
    e.top:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    e.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    e.bottom:SetHeight(t)
    e.bottom:ClearAllPoints()
    e.bottom:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    e.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    e.left:SetWidth(t)
    e.left:ClearAllPoints()
    e.left:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, -t)
    e.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0,  t)

    e.right:SetWidth(t)
    e.right:ClearAllPoints()
    e.right:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, -t)
    e.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  t)

    if r then
        for _, tex in pairs(e) do
            tex:SetVertexColor(r, g, b, a or 1.0)
            tex:Show()
        end
        -- Suppress third-party borders (e.g. EllesmereUI) that share IconBorder.
        if frame.IconBorder then frame.IconBorder:Hide() end
    else
        for _, tex in pairs(e) do
            tex:Hide()
        end
        if frame.IconBorder then frame.IconBorder:Show() end
    end
end

ns.SetItemBorder = SetItemBorder

-- ── Equipped gear slots (character frame) ──────────────────────────────────

local function UpdateAllSlots()
    if not GearTrackColorizerDB or not GearTrackColorizerDB.enabled then return end
    for _, slotID in ipairs(ns.GEAR_SLOTS) do
        local frame = _G[ns.SLOT_NAMES[slotID] or ""]
        if frame then
            local color = GetTrackColor(GetInventoryItemLink("player", slotID))
            if color then
                SetItemBorder(frame, color[1], color[2], color[3], color[4])
            else
                SetItemBorder(frame, nil)
            end
        end
    end
end

local function ClearAllSlots()
    for _, slotID in ipairs(ns.GEAR_SLOTS) do
        local frame = _G[ns.SLOT_NAMES[slotID] or ""]
        if frame and frame.gtcBorder then
            SetItemBorder(frame, nil)
        end
    end
end

ns.UpdateAllSlots = UpdateAllSlots
ns.ClearAllSlots  = ClearAllSlots

-- ── Tooltip coloring ───────────────────────────────────────────────────────
-- Never call tooltip:Show() here — it re-fires the processor pipeline and
-- causes a C stack overflow when addons like ElvUI/Rarity are also hooked.

local function ApplyTooltipColor(tooltip, _data)
    if tooltip == scanTT then return end
    if not GearTrackColorizerDB or not GearTrackColorizerDB.enabled then return end

    if type(tooltip.GetItem) ~= "function" then return end
    local ok, _, itemLink = pcall(tooltip.GetItem, tooltip)
    if not ok or not itemLink then return end

    local color, trackName = GetTrackColor(itemLink)
    if not color then return end

    local ttName = tooltip:GetName()
    local line2 = ttName and _G[ttName .. "TextLeft2"]
    local hasTrack = false
    if line2 then
        pcall(function() hasTrack = (line2:GetText() or ""):find(trackName, 1, true) ~= nil end)
    end
    if not hasTrack then
        tooltip:AddLine(string.format("|c%02x%02x%02x%02xTrack: %s|r",
            math.floor((color[4] or 1.0) * 255 + 0.5),
            math.floor(color[1] * 255 + 0.5),
            math.floor(color[2] * 255 + 0.5),
            math.floor(color[3] * 255 + 0.5),
            trackName))
    end
end

if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ApplyTooltipColor)
else
    local function TryHook(tt)
        if tt and type(tt.HookScript) == "function" and tt:HasScript("OnTooltipSetItem") then
            tt:HookScript("OnTooltipSetItem", function(self) ApplyTooltipColor(self) end)
        end
    end
    TryHook(GameTooltip)
    TryHook(ItemRefTooltip)
    for _, tt in ipairs(GameTooltip.shoppingTooltips or {}) do TryHook(tt) end
end

-- ── Inspect frame slots ────────────────────────────────────────────────────

local function UpdateInspectSlots()
    if not GearTrackColorizerDB or not GearTrackColorizerDB.enabled then return end
    if not GearTrackColorizerDB.inspectBorders then return end
    if not InspectFrame or not InspectFrame:IsShown() then return end
    local unit = InspectFrame.unit
    if not unit or not UnitExists(unit) then return end
    for _, slotID in ipairs(ns.GEAR_SLOTS) do
        local frame = _G[ns.INSPECT_SLOT_NAMES[slotID] or ""]
        if frame then
            local color = GetTrackColor(GetInventoryItemLink(unit, slotID))
            if color then
                SetItemBorder(frame, color[1], color[2], color[3])
            else
                SetItemBorder(frame, nil)
            end
        end
    end
end

local function ClearInspectSlots()
    for _, slotID in ipairs(ns.GEAR_SLOTS) do
        local frame = _G[ns.INSPECT_SLOT_NAMES[slotID] or ""]
        if frame and frame.gtcBorder then
            SetItemBorder(frame, nil)
        end
    end
end

ns.UpdateInspectSlots = UpdateInspectSlots
ns.ClearInspectSlots  = ClearInspectSlots

local inspectFrameHooked = false
local function TryHookInspectFrame()
    if inspectFrameHooked or not InspectFrame then return end
    InspectFrame:HookScript("OnShow", UpdateInspectSlots)
    InspectFrame:HookScript("OnHide", ClearInspectSlots)
    inspectFrameHooked = true
    if InspectFrame:IsShown() then
        UpdateInspectSlots()
    end
end

-- ── CharacterFrame hook ─────────────────────────────────────────────────────
-- Blizzard_UIPanels_Game is demand-loaded on first character frame open, so
-- CharacterFrame is nil until then. We hook it when its addon fires ADDON_LOADED
-- and immediately apply borders if the frame is already visible.

local charFrameHooked = false
local function TryHookCharacterFrame()
    if charFrameHooked or not CharacterFrame then return end
    CharacterFrame:HookScript("OnShow", UpdateAllSlots)
    charFrameHooked = true
    if CharacterFrame:IsShown() then
        UpdateAllSlots()
    end
end

-- ── Events ─────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("INSPECT_READY")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            InitDB()
        elseif arg1 == "Blizzard_UIPanels_Game" then
            TryHookCharacterFrame()
        elseif arg1 == "Blizzard_InspectUI" then
            TryHookInspectFrame()
        end

    elseif event == "PLAYER_LOGIN" then
        local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local version = getMeta and getMeta(addonName, "Version") or "?"
        local status  = GearTrackColorizerDB.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
        print(string.format("|cffffcc00Gear Track Colorizer|r %s  [%s]", version, status))
        TryHookCharacterFrame()
        -- Apply borders after item cache warms up. Two passes: one early for
        -- fast logins, one later as a safety net for slow or cold caches.
        C_Timer.After(2.0, UpdateAllSlots)
        C_Timer.After(2.0, function() ns.UpdateAllBagButtons() end)
        C_Timer.After(5.0, UpdateAllSlots)
        C_Timer.After(5.0, function() ns.UpdateAllBagButtons() end)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.1, UpdateAllSlots)

    elseif event == "INSPECT_READY" then
        if InspectFrame and InspectFrame.unit and UnitGUID(InspectFrame.unit) == arg1 then
            UpdateInspectSlots()
        end
    end
end)

-- ── Slash commands ─────────────────────────────────────────────────────────

SLASH_GEARTRACKCOLORIZER1 = "/gtc"
SLASH_GEARTRACKCOLORIZER2 = "/geartrack"
SlashCmdList["GEARTRACKCOLORIZER"] = function(msg)
    msg = strtrim(msg:lower())
    if msg == "on" then
        GearTrackColorizerDB.enabled = true
        UpdateAllSlots()
        ns.UpdateAllBagButtons()
        print("|cff00ff00Gear Track Colorizer:|r Enabled.")
    elseif msg == "off" then
        GearTrackColorizerDB.enabled = false
        ClearAllSlots()
        ns.ClearAllBagButtons()
        print("|cff00ff00Gear Track Colorizer:|r Disabled.")
    elseif msg == "reload" or msg == "refresh" then
        UpdateAllSlots()
        ns.UpdateAllBagButtons()
        print("|cff00ff00Gear Track Colorizer:|r Refreshed.")
    else
        print("|cffffcc00Gear Track Colorizer|r commands:")
        print("  |cffaaaaaa/gtc on|r      — enable addon")
        print("  |cffaaaaaa/gtc off|r     — disable addon")
        print("  |cffaaaaaa/gtc reload|r  — force refresh all borders")
    end
end
