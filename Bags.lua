local addonName, ns = ...

-- ── Bag button coloring ────────────────────────────────────────────────────
-- Two strategies:
--
-- 1. Blizzard bags: container:EnumerateValidItems() — only yields buttons when
--    the bag frame is actually shown. We guard with IsShown() and hook OnShow
--    so UpdateAllBagButtons is called the moment a bag opens.
--
-- 2. Third-party bag addons (Bagnon, etc.): EnumerateFrames cache + hover hook.

local BLIZZARD_CONTAINERS = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
}

-- ── Equippable gear filter ─────────────────────────────────────────────────
-- Only typeID 2 (Weapon) and typeID 4 (Armor) are upgrade-track gear.
-- This excludes bags (typeID 1), consumables (0), reagents (5), trade goods (7),
-- recipes (9), and anything else that isn't actual wearable equipment.

local function IsUpgradeableGear(itemLink)
    if not itemLink then return false end
    local equipLoc, typeID
    pcall(function()
        equipLoc = select(9,  GetItemInfo(itemLink))
        typeID   = select(12, GetItemInfo(itemLink))
    end)
    return equipLoc and equipLoc ~= "" and (typeID == 2 or typeID == 4)
end

-- ── GetBagSlot (third-party addons) ───────────────────────────────────────

local function GetBagSlot(frame)
    if frame.GetBagID then
        local okB, bag  = pcall(frame.GetBagID, frame)
        local okS, slot = pcall(frame.GetID,    frame)
        if okB and okS
            and type(bag)  == "number" and type(slot) == "number"
            and bag >= 0   and slot > 0
        then
            return bag, slot
        end
    end
    if type(frame.bag) == "number" and type(frame.slot) == "number"
        and frame.bag >= 0 and frame.slot > 0
    then
        return frame.bag, frame.slot
    end
    local nameOk, fname = pcall(frame.GetName, frame)
    if nameOk and type(fname) == "string" then
        local fi, si = fname:match("ContainerFrame(%d+)Item(%d+)")
        if fi then return tonumber(fi) - 1, tonumber(si) end
    end
    return nil, nil
end

-- ── Third-party cache ──────────────────────────────────────────────────────

local thirdPartyCache = {}
local cacheStale      = true

local function RebuildThirdPartyCache()
    wipe(thirdPartyCache)
    local blizzardFrames = {}
    for _, name in ipairs(BLIZZARD_CONTAINERS) do
        local cf = _G[name]
        if cf then blizzardFrames[cf] = true end
    end
    local frame = EnumerateFrames()
    while frame do
        local forbidOk, forbidden = pcall(frame.IsForbidden, frame)
        if forbidOk and not forbidden and not blizzardFrames[frame] then
            local bag, slot = GetBagSlot(frame)
            if bag and slot then
                thirdPartyCache[frame] = {bag, slot}
            end
        end
        frame = EnumerateFrames(frame)
    end
    cacheStale = false
end

-- ── Color a single button ──────────────────────────────────────────────────

local function ColorButton(button, bag, slot)
    local info     = C_Container and C_Container.GetContainerItemInfo(bag, slot)
    local itemLink = info and info.hyperlink

    if not IsUpgradeableGear(itemLink) then
        if button.gtcBorder then ns.SetItemBorder(button, nil) end
        return
    end

    local color = ns.GetTrackColor(itemLink)
    if color then
        ns.SetItemBorder(button, color[1], color[2], color[3])
    elseif button.gtcBorder then
        ns.SetItemBorder(button, nil)
    end
end

-- ── UpdateAllBagButtons ────────────────────────────────────────────────────

local function UpdateAllBagButtons()
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    -- Strategy 1: Blizzard containers.
    -- EnumerateValidItems only has active buttons while the frame is shown.
    for _, name in ipairs(BLIZZARD_CONTAINERS) do
        local cf = _G[name]
        if cf and cf.IsShown and cf:IsShown() and cf.EnumerateValidItems then
            for _, button in cf:EnumerateValidItems() do
                if button then
                    ColorButton(button, button:GetBagID(), button:GetID())
                end
            end
        end
    end

    -- Strategy 2: Third-party addon frames
    if cacheStale then RebuildThirdPartyCache() end
    for frame, bagSlot in pairs(thirdPartyCache) do
        local visOk, visible = pcall(frame.IsVisible, frame)
        if visOk and visible then
            ColorButton(frame, bagSlot[1], bagSlot[2])
        end
    end
end

local function ClearAllBagButtons()
    for _, name in ipairs(BLIZZARD_CONTAINERS) do
        local cf = _G[name]
        if cf and cf.IsShown and cf:IsShown() and cf.EnumerateValidItems then
            for _, button in cf:EnumerateValidItems() do
                if button and button.gtcBorder then ns.SetItemBorder(button, nil) end
            end
        end
    end
    for frame in pairs(thirdPartyCache) do
        if frame.gtcBorder then ns.SetItemBorder(frame, nil) end
    end
end

ns.UpdateAllBagButtons = UpdateAllBagButtons
ns.ClearAllBagButtons  = ClearAllBagButtons

-- ── Tooltip-owner hook ─────────────────────────────────────────────────────

local function ApplyBorderFromTooltipOwner(tooltip, _data)
    if tooltip == _G["GearTrackColorizerScanTT"] then return end
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    local owner = tooltip:GetOwner()
    if not owner then return end

    local typeOk, objType = pcall(owner.GetObjectType, owner)
    if not typeOk or objType ~= "Button" then return end

    local bag, slot = GetBagSlot(owner)
    if not bag then return end

    ColorButton(owner, bag, slot)

    -- First discovery of this frame: rebuild the full cache so every visible
    -- button in the same addon window also gets colored without needing a hover.
    -- (ArkInventory and similar addons only render frames when their window is
    -- open, so EnumerateFrames finds them only after the user interacts once.)
    if not thirdPartyCache[owner] then
        cacheStale = true
        C_Timer.After(0, UpdateAllBagButtons)
    end
    thirdPartyCache[owner] = {bag, slot}
end

if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ApplyBorderFromTooltipOwner)
elseif GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", function(self)
        ApplyBorderFromTooltipOwner(self)
    end)
end

-- ── Events ────────────────────────────────────────────────────────────────

local bagFrame = CreateFrame("Frame")
bagFrame:RegisterEvent("ADDON_LOADED")
bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bagFrame:RegisterEvent("BAG_OPEN")
bagFrame:RegisterEvent("BAG_CLOSED")
bagFrame:RegisterEvent("BAG_UPDATE")

local updatePending = false
local function ScheduleUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(0.1, function()
        updatePending = false
        UpdateAllBagButtons()
    end)
end

-- Hook each Blizzard container frame's OnShow so UpdateAllBagButtons fires
-- the moment a bag opens (EnumerateValidItems is ready at that point).
local function HookContainerOnShow(cf)
    if cf and cf.HookScript then
        cf:HookScript("OnShow", function() UpdateAllBagButtons() end)
    end
end

bagFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_UIPanels_Game" then
        for _, name in ipairs(BLIZZARD_CONTAINERS) do
            HookContainerOnShow(_G[name])
        end

    elseif event == "BAG_OPEN" then
        cacheStale = true
        ScheduleUpdate()

    elseif event == "BAG_CLOSED" then
        cacheStale = true

    elseif event == "BAG_UPDATE_DELAYED" then
        ScheduleUpdate()

    elseif event == "BAG_UPDATE" then
        ScheduleUpdate()
    end
end)
