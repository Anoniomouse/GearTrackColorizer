local addonName, ns = ...

-- ── Bag button detection ───────────────────────────────────────────────────
-- Source-confirmed APIs (Blizzard_ItemButton/Shared/ItemButtonTemplate.lua):
--   ItemButtonMixin:GetBagID()  → returns self.bagID  (the bag container index)
--   frame:GetID()               → returns the slot index within the bag
--   GetSlotID() does NOT exist on item buttons — do not call it.
--
-- Detection priority:
--   1. GetBagID() method + GetID() — Blizzard ItemButtonMixin (default bags, 12.0)
--   2. .bag / .slot fields         — Bagnon and similar addons
--   3. Frame name pattern          — legacy ContainerFrame naming

local bagButtonCache = {}  -- [frame] = {bagID, slotID}
local cacheStale     = true

local function GetBagSlot(frame)
    -- Method 1: Blizzard ItemButtonMixin (GetBagID returns self.bagID; slot is GetID)
    if frame.GetBagID then
        local bag  = frame:GetBagID()
        local slot = frame:GetID()
        if bag ~= nil and slot and slot > 0 then return bag, slot end
    end
    -- Method 2: Bagnon-style fields
    if frame.bag ~= nil and frame.slot ~= nil and frame.slot > 0 then
        return frame.bag, frame.slot
    end
    -- Method 3: Legacy ContainerFrame naming (ContainerFrame1Item3 → bag 0, slot 3)
    local name = frame:GetName()
    if name then
        local fi, si = name:match("ContainerFrame(%d+)Item(%d+)")
        if fi then return tonumber(fi) - 1, tonumber(si) end
    end
    return nil, nil
end

-- ── Cache management ───────────────────────────────────────────────────────
-- EnumerateFrames() is expensive; run it once per bag-open session only.

local function RebuildCache()
    wipe(bagButtonCache)
    local frame = EnumerateFrames()
    while frame do
        if not frame:IsForbidden() then
            local bag, slot = GetBagSlot(frame)
            -- Accept any non-nil bag ID (includes backpack 0, bags 1-4, reagent 5,
            -- and future expansion slots). Exclude bank (negative IDs) for now.
            if bag and slot and bag >= 0 then
                bagButtonCache[frame] = {bag, slot}
            end
        end
        frame = EnumerateFrames(frame)
    end
    cacheStale = false
end

-- ── Apply / clear borders on cached bag buttons ────────────────────────────

local function UpdateAllBagButtons()
    if not GearTrackColorizerDB or
       not GearTrackColorizerDB.enabled or
       not GearTrackColorizerDB.bagBorders then return end
    if cacheStale then RebuildCache() end

    for frame, bagSlot in pairs(bagButtonCache) do
        if frame:IsVisible() then
            local info     = C_Container and C_Container.GetContainerItemInfo(bagSlot[1], bagSlot[2])
            local itemLink = info and info.hyperlink
            local color    = ns.GetTrackColor(itemLink)
            if color then
                ns.SetItemBorder(frame, color[1], color[2], color[3])
            elseif frame.gtcBorder then
                ns.SetItemBorder(frame, nil)
            end
        end
    end
end

local function ClearAllBagButtons()
    for frame in pairs(bagButtonCache) do
        if frame.gtcBorder then ns.SetItemBorder(frame, nil) end
    end
end

ns.UpdateAllBagButtons = UpdateAllBagButtons
ns.ClearAllBagButtons  = ClearAllBagButtons

-- ── Blizzard default bag hook (pre-12.0 only) ─────────────────────────────
-- ContainerFrameItemButton_Update was removed in 12.0. Guard ensures this
-- only runs on older clients where the function still exists.

if ContainerFrameItemButton_Update then
    hooksecurefunc("ContainerFrameItemButton_Update", function(button)
        if not GearTrackColorizerDB or
           not GearTrackColorizerDB.enabled or
           not GearTrackColorizerDB.bagBorders then return end

        local bag, slot = GetBagSlot(button)
        if not bag then return end

        local info     = C_Container and C_Container.GetContainerItemInfo(bag, slot)
        local itemLink = info and info.hyperlink
        local color    = ns.GetTrackColor(itemLink)
        if color then
            ns.SetItemBorder(button, color[1], color[2], color[3])
        elseif button.gtcBorder then
            ns.SetItemBorder(button, nil)
        end
    end)
end

-- ── Tooltip owner hook (third-party bag addons) ────────────────────────────
-- When any bag addon shows an item tooltip, colour the button that owns it.
-- ApplyBorderFromTooltipOwner is registered SEPARATELY from Core.lua's
-- ApplyTooltipColor — both can coexist under TooltipDataProcessor.
-- Guard against scanTT to avoid the same recursion risk as Core.lua.

local function ApplyBorderFromTooltipOwner(tooltip, _data)
    if tooltip == _G["GearTrackColorizerScanTT"] then return end  -- recursion guard
    if not GearTrackColorizerDB or
       not GearTrackColorizerDB.enabled or
       not GearTrackColorizerDB.bagBorders then return end

    local owner = tooltip:GetOwner()
    if not owner or not owner.IsObjectType or not owner:IsObjectType("Button") then return end

    local bag, slot = GetBagSlot(owner)
    if not bag then return end

    local info     = C_Container and C_Container.GetContainerItemInfo(bag, slot)
    local itemLink = info and info.hyperlink
    local color    = ns.GetTrackColor(itemLink)
    if color then ns.SetItemBorder(owner, color[1], color[2], color[3]) end
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
bagFrame:RegisterEvent("BAG_UPDATE")
bagFrame:RegisterEvent("BAG_OPEN")
bagFrame:RegisterEvent("BAG_CLOSED")

local updatePending = false
local function ScheduleUpdate()
    if updatePending then return end
    updatePending = true
    C_Timer.After(0.2, function()
        updatePending = false
        UpdateAllBagButtons()
    end)
end

bagFrame:SetScript("OnEvent", function(self, event)
    if event == "BAG_OPEN" then
        cacheStale = true
        ScheduleUpdate()
    elseif event == "BAG_CLOSED" then
        cacheStale = true
    elseif event == "BAG_UPDATE" then
        ScheduleUpdate()
    end
end)
