local addonName, ns = ...

-- ── Settings panel ────────────────────────────────────────────────────────
--
-- Registered as a canvas-layout category so we have full layout control.
-- Opens via Esc → Interface → AddOns → GearTrackColorizer.

local PANEL_W, PANEL_H = 600, 500
local COL1_X           = 16
local ROW_H            = 36
local SWATCH_SIZE      = 24

local panel = CreateFrame("Frame")
panel.name  = addonName
panel:SetSize(700, 560)
panel:Hide()   -- WoW shows/hides it; don't let it float over the game world

-- ── Helpers ───────────────────────────────────────────────────────────────

local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeCheckbox(parent, labelText, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.text:SetText(labelText)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    return cb
end

-- Coloured square that opens the system colour picker on click
local function MakeSwatch(parent, trackName, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    btn:SetPoint("TOPLEFT", x, y)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")

    local border = btn:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")

    btn.fill = fill

    local function Refresh()
        local c = GearTrackColorizerDB.colors[trackName]
        fill:SetVertexColor(c[1], c[2], c[3])
    end
    Refresh()

    btn:SetScript("OnClick", function()
        local c    = GearTrackColorizerDB.colors[trackName]
        local prev = {r = c[1], g = c[2], b = c[3]}

        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3],
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                GearTrackColorizerDB.colors[trackName] = {r, g, b}
                fill:SetVertexColor(r, g, b)
                ns.UpdateAllSlots()
                ns.UpdateAllBagButtons()
            end,
            cancelFunc = function()
                GearTrackColorizerDB.colors[trackName] = {prev.r, prev.g, prev.b}
                fill:SetVertexColor(prev.r, prev.g, prev.b)
                ns.UpdateAllSlots()
                ns.UpdateAllBagButtons()
            end,
        })
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha(1)
    end)

    btn.Refresh = Refresh
    return btn
end

local function MakeResetButton(parent, text, x, y, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- ── Build panel contents ──────────────────────────────────────────────────

local swatches = {}  -- [trackName] = swatch widget, for Reset All

local function BuildPanel()
    local db = GearTrackColorizerDB

    local curY = -16

    Header(panel, "GearTrackColorizer", COL1_X, curY)
    curY = curY - 32

    -- Enable toggle
    MakeCheckbox(panel, "Enable addon", COL1_X, curY,
        function() return db.enabled end,
        function(v)
            db.enabled = v
            if v then ns.UpdateAllSlots() ns.UpdateAllBagButtons()
            else       ns.ClearAllSlots() ns.ClearAllBagButtons() end
        end)
    curY = curY - ROW_H

    -- Bag borders toggle
    MakeCheckbox(panel, "Color borders in bags", COL1_X, curY,
        function() return db.bagBorders end,
        function(v)
            db.bagBorders = v
            if v then ns.UpdateAllBagButtons()
            else       ns.ClearAllBagButtons() end
        end)
    curY = curY - ROW_H + 4

    -- Border thickness slider
    Label(panel, "Border Thickness", COL1_X, curY)
    curY = curY - 20

    local slider = CreateFrame("Slider", "GearTrackColorizerThicknessSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", COL1_X + 4, curY)
    slider:SetWidth(200)
    slider:SetMinMaxValues(1, 6)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(db.borderThickness)
    _G[slider:GetName() .. "Low"]:SetText("1")
    _G[slider:GetName() .. "High"]:SetText("6")
    _G[slider:GetName() .. "Text"]:SetText(db.borderThickness .. " px")

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        db.borderThickness = val
        _G[self:GetName() .. "Text"]:SetText(val .. " px")
        ns.UpdateAllSlots()
        ns.UpdateAllBagButtons()
    end)
    curY = curY - 40

    -- Track colour rows
    Label(panel, "Track Colors", COL1_X, curY, "GameFontNormalLarge")
    curY = curY - 28

    for _, trackName in ipairs(ns.TRACK_ORDER) do
        local def = ns.TRACK_DEFAULTS[trackName]

        Label(panel, trackName, COL1_X + SWATCH_SIZE + 8, curY + 6)

        local swatch = MakeSwatch(panel, trackName, COL1_X, curY)
        swatches[trackName] = swatch

        MakeResetButton(panel, "Reset", COL1_X + SWATCH_SIZE + 90, curY + 1, function()
            db.colors[trackName] = {def[1], def[2], def[3]}
            swatch.Refresh()
            ns.UpdateAllSlots()
            ns.UpdateAllBagButtons()
        end)

        curY = curY - ROW_H
    end

    curY = curY - 8

    -- Reset all colours
    MakeResetButton(panel, "Reset All", COL1_X, curY, function()
        for trackName2, def2 in pairs(ns.TRACK_DEFAULTS) do
            db.colors[trackName2] = {def2[1], def2[2], def2[3]}
            if swatches[trackName2] then swatches[trackName2].Refresh() end
        end
        ns.UpdateAllSlots()
        ns.UpdateAllBagButtons()
    end)
end

-- ── Register with Settings API + Addon Compartment ───────────────────────
--
-- PLAYER_LOGIN: DB and Settings API are both fully ready.
-- Settings.RegisterAddOnCategory  → Esc > Interface > AddOns list
-- AddonCompartment.RegisterAddon  → puzzle-piece button near the minimap

local settingsCategory  -- upvalue so the compartment func can reference it

local settingsFrame = CreateFrame("Frame")
settingsFrame:RegisterEvent("PLAYER_LOGIN")
settingsFrame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    self:UnregisterEvent("PLAYER_LOGIN")

    BuildPanel()

    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    Settings.RegisterAddOnCategory(settingsCategory)

    -- Addon compartment (puzzle-piece / grid icon near minimap)
    if AddonCompartment then
        AddonCompartment.RegisterAddon({
            text         = addonName,
            icon         = "Interface\\Icons\\INV_Misc_Gear_01",
            notCheckable = true,
            func = function()
                Settings.OpenToCategory(settingsCategory)
            end,
            funcOnEnter  = function(_, inputData)
                GameTooltip:SetOwner(inputData and inputData.rootDescription or UIParent, "ANCHOR_LEFT")
                GameTooltip:SetText(addonName, 1, 1, 1)
                GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end,
            funcOnLeave  = function() GameTooltip:Hide() end,
        })
    end
end)
