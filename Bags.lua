local addonName, ns = ...

-- ── Bag button detection ───────────────────────────────────────────────────
-- Source: Blizzard_ItemButton/Shared/ItemButtonTemplate.lua (12.0.1.66838)
--   ItemButtonMixin:GetBagID() → self.bagID   (bag container index)
--   frame:GetID()              → slot index within that bag
--   GetSlotID() does NOT exist on item buttons.
--
-- EnumerateFrames() iterates every frame including unrelated addon frames
-- (damage meters, action bars, etc.) whose GetName() may return a FontString
-- widget instead of a Lua string, causing :match() to error.
-- Every frame method call that feeds into string operations is wrapped with
-- pcall and type-checked before use.

local bagButtonCache = {}  -- [frame] = {bagID, slotID}
local cacheStale     = true

-- Returns bagID, slotID from any item button regardless of addon source.
-- All method calls are pcall-wrapped and return-value types are validated
-- so that addon-overridden methods with unexpected return types never error.
local function GetBagSlot(frame)
    -- Method 1: Blizzard ItemButtonMixin (GetBagID → self.bagID; slot → GetID)
    if frame.GetBagID then
        local okB, bag  = pcall(frame.GetBagID, frame)
        local okS, slot = pcall(frame.GetID,    frame)
        if okB and okS
            and type(bag)  == "number"
            and type(slot) == "number"
            and bag  >= 0
            and slot >  0
        then
            return bag, slot
        end
    end

    -- Method 2: Bagnon-style plain fields (.bag / .slot)
    if type(frame.bag) == "number" and type(frame.slot) == "number"
        and frame.bag >= 0 and frame.slot > 0
    then
        return frame.bag, frame.slot
    end

    -- Method 3: Legacy ContainerFrame naming (ContainerFrame2Item5 → bag 1, slot 5)
    -- GetName() on some addon frames (e.g. Details! meter rows) returns a
    -- FontString widget, not a string. type() check is mandatory before :match().
    local nameOk, fname = pcall(frame.GetName, frame)
    if nameOk and type(fname) == "string" then
        local fi, si = fname:match("ContainerFrame(%d+)Item(%d+)")
        if fi then
            return tonumber(fi) - 1, tonumber(si)
        end
    end

    return nil, nil
end

-- ── Frame cache ────────────────────────────────────────────────────────────
-- Built once per bag-open session via EnumerateFrames (expensive but O(1)
-- per BAG_UPDATE afterwards). Marked stale on BAG_OPEN / BAG_CLOSED so that
-- third-party bag addons that create/destroy frames across sessions are handled.

local function RebuildCache()
    wipe(bagButtonCache)

    local frame = EnumerateFrames()
    while frame do
        -- IsForbidden() guards restricted frames; wrap in pcall in case the
        -- frame's metatable makes the call error (seen with some addon proxies)
        local forbidOk, forbidden = pcall(frame.IsForbidden, frame)
        if forbidOk and not forbidden then
            local bag, slot = GetBagSlot(frame)
            if bag and slot then
                bagButtonCache[frame] = {bag, slot}
            end
        end
        frame = EnumerateFrames(frame)
    end

    cacheStale = false
end

-- ── Apply / clear borders on cached bag buttons ────────────────────────────

local function UpdateAllBagButtons()
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    if cacheStale then RebuildCache() end

    for frame, bagSlot in pairs(bagButtonCache) do
        local visOk, visible = pcall(frame.IsVisible, frame)
        if visOk and visible then
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

-- ── Blizzard ContainerFrameItemButton_Update hook (pre-12.0 only) ──────────
-- Removed in 12.0; guard prevents error on current clients.

if ContainerFrameItemButton_Update then
    hooksecurefunc("ContainerFrameItemButton_Update", function(button)
        if not GearTrackColorizerDB
            or not GearTrackColorizerDB.enabled
            or not GearTrackColorizerDB.bagBorders
        then return end

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

-- ── Tooltip-owner hook (third-party bag addons) ────────────────────────────
-- Colours the button that owns the tooltip on hover, catching addons whose
-- frames are not in the cache. Registered separately from Core.lua's
-- ApplyTooltipColor — two PostCall registrations for the same type are allowed.
-- scanTT guard prevents the same recursion risk as Core.lua.

local function ApplyBorderFromTooltipOwner(tooltip, _data)
    if tooltip == _G["GearTrackColorizerScanTT"] then return end
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    local owner = tooltip:GetOwner()
    if not owner then return end

    -- Confirm owner is a Button (not a frame/fontstring/texture)
    local typeOk, objType = pcall(owner.GetObjectType, owner)
    if not typeOk or objType ~= "Button" then return end

    local bag, slot = GetBagSlot(owner)
    if not bag then return end

    local info     = C_Container and C_Container.GetContainerItemInfo(bag, slot)
    local itemLink = info and info.hyperlink
    local color    = ns.GetTrackColor(itemLink)
    if color then
        ns.SetItemBorder(owner, color[1], color[2], color[3])
        -- Also cache this frame for future BAG_UPDATE passes
        bagButtonCache[owner] = {bag, slot}
    end
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
