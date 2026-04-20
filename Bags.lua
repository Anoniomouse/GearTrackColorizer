local addonName, ns = ...

-- ── Bag button detection ───────────────────────────────────────────────────
--
-- Different bag addons expose bag/slot differently:
--   Blizzard default  → GetBagID() / GetSlotID() methods
--   Bagnon            → .bag / .slot fields
--   Frame name        → "ContainerFrame%dItem%d" naming convention
--
-- We build a cache of known item button frames once (on first bag open) and
-- refresh it whenever bags open again.  EnumerateFrames() is expensive but
-- runs at most once per bag-open session.

local bagButtonCache = {}  -- [frame] = {bagID, slotID}
local cacheStale     = true

local function GetBagSlot(frame)
    if frame.GetBagID and frame.GetSlotID then
        local bag, slot = frame:GetBagID(), frame:GetSlotID()
        if bag and slot then return bag, slot end
    end
    if frame.bag ~= nil and frame.slot ~= nil then
        return frame.bag, frame.slot
    end
    local name = frame:GetName()
    if name then
        local fi, si = name:match("ContainerFrame(%d+)Item(%d+)")
        if fi then return tonumber(fi) - 1, tonumber(si) end
    end
    return nil, nil
end

local function RebuildCache()
    wipe(bagButtonCache)
    local frame = EnumerateFrames()
    while frame do
        if not frame:IsForbidden() then
            local bag, slot = GetBagSlot(frame)
            if bag and slot and bag >= -1 and bag <= 4 then
                bagButtonCache[frame] = {bag, slot}
            end
        end
        frame = EnumerateFrames(frame)
    end
    cacheStale = false
end

-- ── Apply / clear borders on all cached bag buttons ───────────────────────

local function UpdateAllBagButtons()
    if not GearTrackColorizerDB.enabled or not GearTrackColorizerDB.bagBorders then return end
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

-- ── Hook Blizzard default bag button updates ──────────────────────────────
--
-- ContainerFrameItemButton_Update fires for every Blizzard bag slot refresh.
-- Catching it here avoids needing BAG_UPDATE polling for the default UI.

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

-- ── Hook tooltip owner for third-party bag addons ─────────────────────────
--
-- When any bag addon shows a tooltip, color the button that owns it.
-- This catches addons whose item buttons we may not have cached.

GameTooltip:HookScript("OnTooltipSetItem", function(self)
    if not GearTrackColorizerDB or
       not GearTrackColorizerDB.enabled or
       not GearTrackColorizerDB.bagBorders then return end

    local owner = self:GetOwner()
    if not owner or not owner.IsObjectType or not owner:IsObjectType("Button") then return end

    local bag, slot = GetBagSlot(owner)
    if not bag then return end

    local info     = C_Container and C_Container.GetContainerItemInfo(bag, slot)
    local itemLink = info and info.hyperlink
    local color    = ns.GetTrackColor(itemLink)
    if color then
        ns.SetItemBorder(owner, color[1], color[2], color[3])
    end
end)

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
        cacheStale = true   -- bag addon may have created new frames
        ScheduleUpdate()
    elseif event == "BAG_CLOSED" then
        cacheStale = true
    elseif event == "BAG_UPDATE" then
        ScheduleUpdate()
    end
end)
