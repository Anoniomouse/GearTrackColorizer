local addonName, ns = ...

-- ── SavedVariables initialisation ─────────────────────────────────────────

local function InitDB()
    GearTrackColorizerDB = GearTrackColorizerDB or {}
    local db = GearTrackColorizerDB

    if db.enabled         == nil then db.enabled         = true end
    if db.bagBorders      == nil then db.bagBorders      = true end
    if db.borderThickness == nil then db.borderThickness = ns.DEFAULT_BORDER_THICKNESS end

    db.colors = db.colors or {}

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
--   1. Legendary quality (item quality 5) → Legendary color, skips track scan.
--   2. Tooltip line scan for track name aliases.
--   3. Maxed: tooltip scan found "Myth" AND any line has X/X with equal numbers
--      (upgrade fraction = max). Only Myth items show the Maxed color.
--   4. ilvl fallback for crafted gear (quality stars, no track name in tooltip).

local function GetTrackColor(itemLink)
    if not itemLink or not GearTrackColorizerDB then return nil end
    local dbColors = GearTrackColorizerDB.colors

    -- 1. Legendary items override everything (quality 5 = orange in WoW)
    local quality
    pcall(function() quality = select(3, GetItemInfo(itemLink)) end)
    if quality == 5 and dbColors["Legendary"] then
        return dbColors["Legendary"], "Legendary"
    end

    -- 2 & 3. Tooltip scan
    scanTT:ClearLines()
    local ok = pcall(function() scanTT:SetHyperlink(itemLink) end)
    if not ok or scanTT:NumLines() == 0 then return nil end

    local foundTrack = nil
    local isMaxed    = false

    for i = 1, scanTT:NumLines() do
        local region = _G["GearTrackColorizerScanTTTextLeft" .. i]
        local line   = region and region:GetText()
        if line then
            -- Detect fully-upgraded fraction (X/X) on any tooltip line
            if not isMaxed then
                local curr, max = line:match("(%d+)/(%d+)")
                if curr and tonumber(curr) == tonumber(max) then
                    isMaxed = true
                end
            end

            -- Match track name (aliases only; Maxed and Legendary have none)
            if not foundTrack then
                for _, trackName in ipairs(ns.TRACK_ORDER) do
                    for _, alias in ipairs(ns.TRACK_ALIASES[trackName]) do
                        if line:find("%f[%a]" .. alias .. "%f[%A]") and dbColors[trackName] then
                            foundTrack = trackName
                            break
                        end
                    end
                    if foundTrack then break end
                end
            end
        end
    end

    if foundTrack then
        -- Maxed only applies to Myth items at their upgrade cap
        if foundTrack == "Myth" and isMaxed and dbColors["Maxed"] then
            return dbColors["Maxed"], "Maxed"
        end
        return dbColors[foundTrack], foundTrack
    end

    -- 4. Crafted gear fallback: tooltip shows stars (★), not a track name.
    --    Use item level against Midnight S1 thresholds.
    local itemLevel
    pcall(function() itemLevel = select(4, GetItemInfo(itemLink)) end)
    if itemLevel and itemLevel > 0 then
        for _, entry in ipairs(ns.ILVL_TRACK_THRESHOLDS) do
            if itemLevel >= entry[1] then
                local trackName = entry[2]
                if dbColors[trackName] then
                    return dbColors[trackName], trackName
                end
            end
        end
    end

    return nil
end

ns.GetTrackColor = GetTrackColor

-- ── Border rendering ───────────────────────────────────────────────────────
-- Four thin OVERLAY-layer edge textures avoid IconBorder (BORDER layer) because
-- SetItemButtonQuality() resets its color to the item quality on every refresh.
-- Anchors re-applied on every call so thickness changes take effect immediately.

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
    if line2 and not (line2:GetText() or ""):find(trackName, 1, true) then
        tooltip:AddLine(string.format("|cff%02x%02x%02xTrack: %s|r",
            color[1] * 255, color[2] * 255, color[3] * 255, trackName))
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

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            InitDB()
        elseif arg1 == "Blizzard_UIPanels_Game" then
            TryHookCharacterFrame()
        end

    elseif event == "PLAYER_LOGIN" then
        local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
        local version = getMeta and getMeta(addonName, "Version") or "?"
        local status  = GearTrackColorizerDB.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"
        print(string.format("|cffffcc00Gear Track Colorizer|r v%s  [%s]", version, status))
        TryHookCharacterFrame()
        -- Proactively apply borders after a short delay so slot frame globals
        -- are guaranteed to exist (Blizzard_UIPanels_Game may load at startup).
        C_Timer.After(1.0, UpdateAllSlots)
        C_Timer.After(1.0, function() ns.UpdateAllBagButtons() end)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        C_Timer.After(0.1, UpdateAllSlots)
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
        print("|cff00ff00Gear Track Colorizer|r  /gtc on | off | reload")
    end
end
