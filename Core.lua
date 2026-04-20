local addonName, ns = ...

local TRACK_ALIASES = ns.TRACK_ALIASES
local GEAR_SLOTS    = ns.GEAR_SLOTS
local SLOT_NAMES    = ns.SLOT_NAMES

-- ── DB initialisation ──────────────────────────────────────────────────────

local function InitDB()
    GearTrackColorizerDB = GearTrackColorizerDB or {}
    local db = GearTrackColorizerDB
    if db.enabled         == nil then db.enabled         = true end
    if db.bagBorders      == nil then db.bagBorders      = true end
    if db.borderThickness == nil then db.borderThickness = ns.DEFAULT_BORDER_THICKNESS end
    db.colors = db.colors or {}
    for trackName, def in pairs(ns.TRACK_DEFAULTS) do
        if not db.colors[trackName] then
            db.colors[trackName] = {def[1], def[2], def[3]}
        end
    end
end

-- ── Hidden scan tooltip ────────────────────────────────────────────────────
-- Used to read tooltip lines without displaying anything.
-- IMPORTANT: ApplyTooltipColor guards against this tooltip to prevent
-- TooltipDataProcessor from recursing back into GetTrackColor.

local scanTT = CreateFrame("GameTooltip", "GearTrackColorizerScanTT", nil, "GameTooltipTemplate")
scanTT:SetOwner(WorldFrame, "ANCHOR_NONE")

-- ── Track detection ────────────────────────────────────────────────────────
-- C_ItemUpgrade has no API that accepts an item link and returns a track name.
-- (GetItemUpgradeItemInfo() takes no args and only works for the upgrade UI.)
-- Tooltip-line scanning is the only reliable cross-patch detection method.

local function GetTrackColor(itemLink)
    if not itemLink or not GearTrackColorizerDB then return nil end
    local dbColors = GearTrackColorizerDB.colors

    scanTT:ClearLines()
    local ok = pcall(function() scanTT:SetHyperlink(itemLink) end)
    if not ok or scanTT:NumLines() == 0 then return nil end

    for i = 1, scanTT:NumLines() do
        local region = _G["GearTrackColorizerScanTTTextLeft" .. i]
        local line   = region and region:GetText()
        if line then
            for trackName, aliases in pairs(TRACK_ALIASES) do
                for _, alias in ipairs(aliases) do
                    if line:find(alias, 1, true) and dbColors[trackName] then
                        return dbColors[trackName], trackName
                    end
                end
            end
        end
    end
    return nil
end

ns.GetTrackColor = GetTrackColor

-- ── Border rendering ───────────────────────────────────────────────────────
-- Four thin edge-textures at OVERLAY layer. Intentionally avoids button.IconBorder
-- because SetItemButtonQuality() resets IconBorder color to item quality color,
-- which would fight with our track color on every frame refresh.

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

-- ── Equipped gear slots ────────────────────────────────────────────────────

local function UpdateAllSlots()
    if not GearTrackColorizerDB or not GearTrackColorizerDB.enabled then return end
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
-- TooltipDataProcessor.AddTooltipPostCall fires for every tooltip, including
-- our hidden scanTT. Guard against scanTT to prevent GetTrackColor recursing
-- into itself via the data processor.
-- Do NOT call tooltip:Show() here — it re-fires the data processor pipeline.

local function ApplyTooltipColor(tooltip, _data)
    if tooltip == scanTT then return end  -- recursion guard
    if not GearTrackColorizerDB or not GearTrackColorizerDB.enabled then return end

    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    local color, trackName = GetTrackColor(itemLink)
    if not color then return end

    local name = tooltip:GetName()
    local nameLine = _G[name .. "TextLeft1"]
    if nameLine then nameLine:SetTextColor(color[1], color[2], color[3]) end

    local line2 = _G[name .. "TextLeft2"]
    if line2 and not (line2:GetText() or ""):find(trackName, 1, true) then
        tooltip:AddLine(string.format("|cff%02x%02x%02xTrack: %s|r",
            color[1] * 255, color[2] * 255, color[3] * 255, trackName))
    end
end

if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ApplyTooltipColor)
else
    local function HookTooltip(tt)
        if tt and tt.HookScript and tt:HasScript("OnTooltipSetItem") then
            tt:HookScript("OnTooltipSetItem", function(self) ApplyTooltipColor(self) end)
        end
    end
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
    for _, tt in ipairs(GameTooltip.shoppingTooltips or {}) do HookTooltip(tt) end
end

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
        local getmeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local version = getmeta(addonName, "Version") or "?"
        local status  = GearTrackColorizerDB.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
        print(string.format("|cffffcc00GearTrackColorizer|r v%s  [%s]", version, status))
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.1, UpdateAllSlots)
    end
end)

-- CharacterFrame_OnShow may not exist in all patches; guard the hook
if CharacterFrame_OnShow then
    hooksecurefunc("CharacterFrame_OnShow", UpdateAllSlots)
end

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
