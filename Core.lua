local addonName, ns = ...

local TRACK_COLORS = ns.TRACK_COLORS
local TRACK_ALIASES = ns.TRACK_ALIASES
local GEAR_SLOTS = ns.GEAR_SLOTS
local SLOT_NAMES = ns.SLOT_NAMES

GearTrackColorizerDB = GearTrackColorizerDB or { enabled = true }

-- Hidden tooltip used for scanning item data without display side effects
local scanTT = CreateFrame("GameTooltip", "GearTrackColorizerScanTT", nil, "GameTooltipTemplate")
scanTT:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetTrackColor(itemLink)
    if not itemLink then return nil end

    -- Try C_ItemUpgrade API (most reliable when available)
    if C_ItemUpgrade and C_ItemUpgrade.GetItemUpgradeInfo then
        local ok, info = pcall(C_ItemUpgrade.GetItemUpgradeInfo, itemLink)
        if ok and info and info.trackName then
            local color = TRACK_COLORS[info.trackName]
            if color then return color, info.trackName end
        end
    end

    -- Fallback: scan tooltip lines for known track name strings
    scanTT:ClearLines()
    local ok = pcall(function() scanTT:SetHyperlink(itemLink) end)
    if not ok then return nil end

    for i = 1, scanTT:NumLines() do
        local leftText = _G["GearTrackColorizerScanTTTextLeft" .. i]
        local line = leftText and leftText:GetText()
        if line then
            for trackName, aliases in pairs(TRACK_ALIASES) do
                for _, alias in ipairs(aliases) do
                    if line:find(alias) then
                        local color = TRACK_COLORS[trackName]
                        if color then return color, trackName end
                    end
                end
            end
        end
    end

    return nil
end

-- Apply or clear a colored overlay on a character frame slot button
local function SetSlotOverlay(slotFrame, r, g, b)
    if not slotFrame then return end

    if not slotFrame.gtcOverlay then
        local overlay = slotFrame:CreateTexture(nil, "OVERLAY")
        overlay:SetAllPoints(slotFrame)
        overlay:SetTexture("Interface\\Buttons\\WHITE8X8")
        overlay:SetBlendMode("ADD")
        overlay:SetAlpha(0.25)
        slotFrame.gtcOverlay = overlay
    end

    if r then
        slotFrame.gtcOverlay:SetVertexColor(r, g, b)
        slotFrame.gtcOverlay:Show()
    else
        slotFrame.gtcOverlay:Hide()
    end
end

local function UpdateAllSlots()
    if not GearTrackColorizerDB.enabled then return end

    for _, slotID in ipairs(GEAR_SLOTS) do
        local slotName = SLOT_NAMES[slotID]
        local slotFrame = slotName and _G[slotName]
        if slotFrame then
            local itemLink = GetInventoryItemLink("player", slotID)
            local color = GetTrackColor(itemLink)
            if color then
                SetSlotOverlay(slotFrame, color[1], color[2], color[3])
            else
                SetSlotOverlay(slotFrame, nil)
            end
        end
    end
end

local function ClearAllSlots()
    for _, slotID in ipairs(GEAR_SLOTS) do
        local slotName = SLOT_NAMES[slotID]
        local slotFrame = slotName and _G[slotName]
        if slotFrame and slotFrame.gtcOverlay then
            slotFrame.gtcOverlay:Hide()
        end
    end
end

-- Tooltip hook: color the item name line by track
local function HookTooltip(tooltip)
    tooltip:HookScript("OnTooltipSetItem", function(self)
        if not GearTrackColorizerDB.enabled then return end

        local _, itemLink = self:GetItem()
        if not itemLink then return end

        local color, trackName = GetTrackColor(itemLink)
        if not color then return end

        local nameLine = _G[self:GetName() .. "TextLeft1"]
        if nameLine then
            nameLine:SetTextColor(color[1], color[2], color[3])
        end

        -- Append track badge to second line if not already present
        local line2 = _G[self:GetName() .. "TextLeft2"]
        if line2 then
            local existing = line2:GetText() or ""
            if not existing:find(trackName) then
                self:AddLine(string.format("|cff%02x%02x%02xTrack: %s|r",
                    color[1] * 255, color[2] * 255, color[3] * 255, trackName))
            end
        end
    end)
end

HookTooltip(GameTooltip)
HookTooltip(ItemRefTooltip)
HookTooltip(ShoppingTooltip1)
HookTooltip(ShoppingTooltip2)

-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Delay slightly so character frame slots exist
        C_Timer.After(1, function()
            if CharacterFrame and CharacterFrame:IsShown() then
                UpdateAllSlots()
            end
        end)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.1, UpdateAllSlots)
    end
end)

-- Update slots whenever the character frame opens
hooksecurefunc("CharacterFrame_OnShow", function()
    UpdateAllSlots()
end)

-- Slash command: /gtc or /geartrack
SLASH_GEARTRACKCOLORIZER1 = "/gtc"
SLASH_GEARTRACKCOLORIZER2 = "/geartrack"
SlashCmdList["GEARTRACKCOLORIZER"] = function(msg)
    msg = msg:lower():trim()
    if msg == "on" then
        GearTrackColorizerDB.enabled = true
        UpdateAllSlots()
        print("|cff00ff00GearTrackColorizer:|r Enabled.")
    elseif msg == "off" then
        GearTrackColorizerDB.enabled = false
        ClearAllSlots()
        print("|cff00ff00GearTrackColorizer:|r Disabled.")
    elseif msg == "reload" or msg == "refresh" then
        UpdateAllSlots()
        print("|cff00ff00GearTrackColorizer:|r Slots refreshed.")
    else
        print("|cff00ff00GearTrackColorizer|r commands:")
        print("  /gtc on     - Enable")
        print("  /gtc off    - Disable")
        print("  /gtc reload - Refresh slot colors")
    end
end
