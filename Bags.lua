local addonName, ns = ...

-- ── Bag button coloring ────────────────────────────────────────────────────
-- Borders are applied lazily on hover (one item at a time, no bulk scan).
-- On bag updates only existing borders are checked and cleared if the item
-- in that slot changed — no tooltip scanning on update events.

local BLIZZARD_CONTAINERS = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
}

-- ── Equippable gear filter ─────────────────────────────────────────────────

local function IsUpgradeableGear(itemLink)
    if not itemLink then return false end
    local equipLoc, typeID
    pcall(function()
        equipLoc = select(9,  GetItemInfo(itemLink))
        typeID   = select(12, GetItemInfo(itemLink))
    end)
    local isProfession = equipLoc and equipLoc:find("PROFESSION") ~= nil
    return equipLoc and equipLoc ~= "" and (typeID == 2 or typeID == 4 or isProfession)
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

-- ── Known third-party frames (discovered lazily on hover) ─────────────────
local thirdPartyCache = {}

-- ── Color a single button ──────────────────────────────────────────────────

local function ColorButton(button, bag, slot)
    local info     = C_Container and C_Container.GetContainerItemInfo(bag, slot)
    local itemLink = info and info.hyperlink

    -- Track the item link we last classified so the clear pass can detect changes.
    button.gtcClassifiedLink = itemLink

    if not IsUpgradeableGear(itemLink) then
        if button.gtcBorder then ns.SetItemBorder(button, nil) end
        return
    end

    local color = ns.GetTrackColor(itemLink)
    if color then
        ns.SetItemBorder(button, color[1], color[2], color[3], color[4])
    elseif button.gtcBorder then
        ns.SetItemBorder(button, nil)
    end
end

-- ── ClearChangedButtons ────────────────────────────────────────────────────
-- Fast pass (no tooltip scan) that removes borders from buttons whose slot
-- item has changed since the border was last applied.

local function ClearChangedButtons()
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    for _, name in ipairs(BLIZZARD_CONTAINERS) do
        local cf = _G[name]
        if cf and cf.IsShown and cf:IsShown() and cf.EnumerateValidItems then
            for _, button in cf:EnumerateValidItems() do
                if button and button.gtcBorder then
                    local info = C_Container and C_Container.GetContainerItemInfo(
                        button:GetBagID(), button:GetID())
                    local link = info and info.hyperlink
                    if link ~= button.gtcClassifiedLink then
                        ns.SetItemBorder(button, nil)
                        button.gtcClassifiedLink = link
                    end
                end
            end
        end
    end

    for frame in pairs(thirdPartyCache) do
        if frame.gtcBorder then
            local bag, slot = GetBagSlot(frame)
            if bag and slot then
                local info = C_Container and C_Container.GetContainerItemInfo(bag, slot)
                local link = info and info.hyperlink
                if link ~= frame.gtcClassifiedLink then
                    ns.SetItemBorder(frame, nil)
                    frame.gtcClassifiedLink = link
                end
            end
        end
    end
end

-- ── UpdateAllBagButtons / ClearAllBagButtons (called from Settings.lua) ───
-- UpdateAll re-colors already-bordered frames with current DB colors and scans
-- newly hovered frames; used when the user changes colors or toggles borders.
-- ClearAll removes every border (used when bag borders are disabled).

local function UpdateAllBagButtons()
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    for _, name in ipairs(BLIZZARD_CONTAINERS) do
        local cf = _G[name]
        if cf and cf.IsShown and cf:IsShown() and cf.EnumerateValidItems then
            for _, button in cf:EnumerateValidItems() do
                if button and button.gtcBorder then
                    ColorButton(button, button:GetBagID(), button:GetID())
                end
            end
        end
    end

    for frame in pairs(thirdPartyCache) do
        local visOk, visible = pcall(frame.IsVisible, frame)
        if visOk and visible and frame.gtcBorder then
            local bag, slot = GetBagSlot(frame)
            if bag and slot then ColorButton(frame, bag, slot) end
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
-- Fires on every item tooltip. Colors just the hovered button — no bulk scan,
-- no EnumerateFrames. Registers the frame for future clear passes.

local function ApplyBorderFromTooltipOwner(tooltip, _data)
    if tooltip == _G["GearTrackColorizerScanTT"] then return end
    if not GearTrackColorizerDB
        or not GearTrackColorizerDB.enabled
        or not GearTrackColorizerDB.bagBorders
    then return end

    local owner = tooltip:GetOwner()
    if not owner then return end

    local bag, slot = GetBagSlot(owner)
    if not bag then return end

    thirdPartyCache[owner] = true
    ColorButton(owner, bag, slot)
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
bagFrame:RegisterEvent("BAG_CLOSED")

local clearPending = false
local function ScheduleClear()
    if clearPending then return end
    clearPending = true
    C_Timer.After(0.1, function()
        clearPending = false
        ClearChangedButtons()
    end)
end

bagFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_UIPanels_Game" then
        -- nothing needed; hover hook handles coloring

    elseif event == "BAG_CLOSED" then
        -- Frames may be recycled; wipe lazy cache so stale entries don't linger.
        wipe(thirdPartyCache)

    elseif event == "BAG_UPDATE_DELAYED" then
        ScheduleClear()
    end
end)
