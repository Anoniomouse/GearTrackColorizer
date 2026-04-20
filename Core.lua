local addonName, ns = ...

local TRACK_ALIASES = ns.TRACK_ALIASES
local GEAR_SLOTS    = ns.GEAR_SLOTS
local SLOT_NAMES    = ns.SLOT_NAMES

-- ── DB initialisation ──────────────────────────────────────────────────────

local function InitDB()
    GearTrackColorizerDB = GearTrackColorizerDB or {}
    local db = GearTrackColorizerDB
    if db.enabled      == nil then db.enabled      = true end
    if db.bagBorders   == nil then db.bagBorders   = true end
    if db.borderThickness == nil then
        db.borderThickness = ns.DEFAULT_BORDER_THICKNESS
    end
    -- Seed per-track colors from defaults, preserving any saved customisations
    db.colors = db.colors or {}
    for trackName, def in pairs(ns.TRACK_DEFAULTS) do
        if not db.colors[trackName] then
            db.colors[trackName] = {def[1], def[2], def[3]}
        end
    end
end

-- ── Hidden scan tooltip ────────────────────────────────────────────────────

local scanTT = CreateFrame("GameTooltip", "GearTrackColorizerScanTT", nil, "GameTooltipTemplate")
scanTT:SetOwner(WorldFrame, "ANCHOR_NONE")

-- ── Track detection ────────────────────────────────────────────────────────

local function GetTrackColor(itemLink)
    if not itemLink or not GearTrackColorizerDB then return nil end
    local dbColors = GearTrackColorizerDB.colors

    -- C_ItemUpgrade API (most reliable)
    if C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeInfo then
        local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeInfo, itemLink)
        if ok and info and info.trackName and dbColors[info.trackName] then
            return dbColors[info.trackName], info.trackName
        end
    end

    -- Fallback: parse hidden tooltip text for known track names
    scanTT:ClearLines()
    if not pcall(function() scanTT:SetHyperlink(itemLink) end) then return nil end

    for i = 1, scanTT:NumLines() do
        local region = _G["GearTrackColorizerScanTTTextLeft" .. i]
        local line   = region and region:GetText()
        if line then
            for trackName, aliases in pairs(TRACK_ALIASES) do
                for _, alias in ipairs(aliases) do
                    if line:find(alias) and dbColors[trackName] then
                        return dbColors[trackName], trackName
                    end
                end
            end
        end
    end
    return nil
end

ns.GetTrackColor = GetTrackColor

-- ── Border rendering (shared by equipped slots and bag buttons) ────────────

local function SetItemBorder(frame, r, g, b)
    if not frame then return end
    local t = GearTrackColorizerDB.borderThickness

    if not frame.gtcBorder then
        local e = {}
        for _, side in ipairs({"top", "bottom", "left", "right"}) do
            e[side] = frame:CreateTexture(nil, "OVERLAY")
            e[side]:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        frame.gtcBorder = e
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

    for _, tex in pairs(e) do
        if r then
            tex:SetVertexColor(r, g, b)
            tex:Show()
        else
            tex:Hide()
        end
    end
end

ns.SetItemBorder = SetItemBorder

-- ── Equipped gear slots (Character frame) ─────────────────────────────────

local function UpdateAllSlots()
    if not GearTrackColorizerDB.enabled then return end
    for _, slotID in ipairs(GEAR_SLOTS) do
        local slotFrame = _G[SLOT_NAMES[slotID] or ""]
        if slotFrame then
            local color = GetTrackColor(GetInventoryItemLink("player", slotID))
            if color then
                SetItemBorder(slotFrame, color[1], color[2], color[3])
            else
                SetItemBorder(slotFrame, nil)
            end
        end
    end
end

local function ClearAllSlots()
    for _, slotID in ipairs(GEAR_SLOTS) do
        local slotFrame = _G[SLOT_NAMES[slotID] or ""]
        if slotFrame and slotFrame.gtcBorder then
            SetItemBorder(slotFrame, nil)
        end
    end
end

ns.UpdateAllSlots = UpdateAllSlots
ns.ClearAllSlots  = ClearAllSlots

-- ── Tooltip coloring ───────────────────────────────────────────────────────

local function HookTooltip(tooltip)
    tooltip:HookScript("OnTooltipSetItem", function(self)
        if not GearTrackColorizerDB.enabled then return end
        local _, itemLink = self:GetItem()
        if not itemLink then return end
        local color, trackName = GetTrackColor(itemLink)
        if not color then return end

        local nameLine = _G[self:GetName() .. "TextLeft1"]
        if nameLine then nameLine:SetTextColor(color[1], color[2], color[3]) end

        local line2 = _G[self:GetName() .. "TextLeft2"]
        if line2 and not (line2:GetText() or ""):find(trackName) then
            self:AddLine(string.format("|cff%02x%02x%02xTrack: %s|r",
                color[1] * 255, color[2] * 255, color[3] * 255, trackName))
        end
    end)
end

HookTooltip(GameTooltip)
HookTooltip(ItemRefTooltip)
HookTooltip(ShoppingTooltip1)
HookTooltip(ShoppingTooltip2)

-- ── Events ─────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "?"
        local status  = GearTrackColorizerDB.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
        print(string.format("|cffffcc00GearTrackColorizer|r v%s  [%s]", version, status))
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.1, UpdateAllSlots)
    end
end)

hooksecurefunc("CharacterFrame_OnShow", function() UpdateAllSlots() end)

-- ── Slash commands ─────────────────────────────────────────────────────────

SLASH_GEARTRACKCOLORIZER1 = "/gtc"
SLASH_GEARTRACKCOLORIZER2 = "/geartrack"
SlashCmdList["GEARTRACKCOLORIZER"] = function(msg)
    msg = strtrim(msg:lower())
    if msg == "on" then
        GearTrackColorizerDB.enabled = true
        UpdateAllSlots()
        ns.UpdateAllBagButtons()
        print("|cff00ff00GearTrackColorizer:|r Enabled.")
    elseif msg == "off" then
        GearTrackColorizerDB.enabled = false
        ClearAllSlots()
        ns.ClearAllBagButtons()
        print("|cff00ff00GearTrackColorizer:|r Disabled.")
    elseif msg == "reload" or msg == "refresh" then
        UpdateAllSlots()
        ns.UpdateAllBagButtons()
        print("|cff00ff00GearTrackColorizer:|r Refreshed.")
    else
        print("|cff00ff00GearTrackColorizer|r  /gtc on | off | reload")
    end
end
