local addonName, ns = ...

-- ── SavedVariables initialisation ─────────────────────────────────────────

local function InitDB()
    GearTrackColorizerDB = GearTrackColorizerDB or {}
    local db = GearTrackColorizerDB

    if db.enabled         == nil then db.enabled         = true end
    if db.bagBorders      == nil then db.bagBorders      = true end
    if db.borderThickness == nil then db.borderThickness = ns.DEFAULT_BORDER_THICKNESS end

    -- Seed per-track colors from defaults while preserving user customisations
    db.colors = db.colors or {}
    for _, name in ipairs(ns.TRACK_ORDER) do
        if not db.colors[name] then
            local d = ns.TRACK_DEFAULTS[name]
            db.colors[name] = {d[1], d[2], d[3]}
        end
    end
end

-- ── Hidden scan tooltip ────────────────────────────────────────────────────
-- Used to read item tooltip text without displaying anything on screen.
-- IMPORTANT: TooltipDataProcessor fires for this tooltip too. Any callback
-- that calls GetTrackColor must guard against scanTT (see ApplyTooltipColor).

local scanTT = CreateFrame("GameTooltip", "GearTrackColorizerScanTT", nil, "GameTooltipTemplate")
scanTT:SetOwner(WorldFrame, "ANCHOR_NONE")

-- ── Track detection ────────────────────────────────────────────────────────
-- The C_ItemUpgrade API has no function that accepts an item link and returns
-- a track name (GetItemUpgradeItemInfo() takes no args, works only for the
-- upgrade UI, and has no trackName field). Tooltip scanning is the sole
-- reliable method. See DESIGN.md §5.1.

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
            for _, trackName in ipairs(ns.TRACK_ORDER) do
                for _, alias in ipairs(ns.TRACK_ALIASES[trackName]) do
                    -- Word-boundary pattern: prevents "Hero" matching "Heroic"
                    if line:find("%f[%a]" .. alias .. "%f[%A]") and dbColors[trackName] then
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
-- Four thin OVERLAY-layer edge textures. We intentionally avoid button.IconBorder
-- (BORDER layer) because SetItemButtonQuality() resets its color to the item's
-- quality color on every frame refresh, which would fight our track color.
-- OVERLAY sits above BORDER and ARTWORK without conflicting with either.
--
-- Anchors are re-applied on every call so thickness changes take effect
-- immediately without needing to destroy and recreate textures.

local function SetItemBorder(frame, r, g, b)
    if not frame then return end
    local t = GearTrackColorizerDB.borderThickness

    if not frame.gtcBorder then
        frame.gtcBorder = {}
        for _, side in ipairs({"top", "bottom", "left", "right"}) do
            local tex = frame:CreateTexture(nil, "OVERLAY")
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

    -- Left/right are inset by t on each end to avoid overlapping the corners
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
            tex:SetVertexColor(r, g, b)
            tex:Show()
        end
    else
        for _, tex in pairs(e) do
            tex:Hide()
        end
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
                SetItemBorder(frame, color[1], color[2], color[3])
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
-- OnTooltipSetItem was removed in 12.0. TooltipDataProcessor.AddTooltipPostCall
-- fires for every item tooltip including our hidden scanTT — guard against it
-- to stop GetTrackColor from recursing into itself.
-- Never call tooltip:Show() here; it re-fires the processor pipeline and causes
-- a C stack overflow when other addons (ElvUI, Rarity, etc.) are also hooked.

local function ApplyTooltipColor(tooltip, _data)
    if tooltip == scanTT then return end
    if not GearTrackColorizerDB or not GearTrackColorizerDB.enabled then return end

    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    local color, trackName = GetTrackColor(itemLink)
    if not color then return end

    local ttName = tooltip:GetName()
    local nameLine = ttName and _G[ttName .. "TextLeft1"]
    if nameLine then
        nameLine:SetTextColor(color[1], color[2], color[3])
    end

    local line2 = ttName and _G[ttName .. "TextLeft2"]
    if line2 and not (line2:GetText() or ""):find(trackName, 1, true) then
        tooltip:AddLine(string.format("|cff%02x%02x%02xTrack: %s|r",
            color[1] * 255, color[2] * 255, color[3] * 255, trackName))
    end
end

if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ApplyTooltipColor)
else
    -- Legacy fallback for clients that still expose OnTooltipSetItem
    local function TryHook(tt)
        if tt and type(tt.HookScript) == "function" and tt:HasScript("OnTooltipSetItem") then
            tt:HookScript("OnTooltipSetItem", function(self) ApplyTooltipColor(self) end)
        end
    end
    TryHook(GameTooltip)
    TryHook(ItemRefTooltip)
    for _, tt in ipairs(GameTooltip.shoppingTooltips or {}) do TryHook(tt) end
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
        local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local version = getMeta and getMeta(addonName, "Version") or "?"
        local status  = GearTrackColorizerDB.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
        print(string.format("|cffffcc00GearTrackColorizer|r v%s  [%s]", version, status))

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.1, UpdateAllSlots)
    end
end)

-- CharacterFrame:HookScript is safer than hooksecurefunc("CharacterFrame_OnShow")
-- because it doesn't depend on the global function existing in every patch.
if CharacterFrame then
    CharacterFrame:HookScript("OnShow", UpdateAllSlots)
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
