local addonName, ns = ...

-- ── Settings panel ────────────────────────────────────────────────────────
-- Registered via Settings.RegisterCanvasLayoutCategory (12.0 API).
-- Opens from: Esc → Interface → AddOns → GearTrackColorizer
--         and: minimap addon compartment (puzzle-piece button)
--
-- IMPORTANT: panel must have an explicit size and start hidden.
-- Registration happens on PLAYER_LOGIN — both the DB and Settings API are
-- guaranteed ready at that point.

local PANEL_W     = 700
local PANEL_H     = 560
local COL_X       = 16
local ROW_H       = 36
local SWATCH_SIZE = 24

local panel = CreateFrame("Frame")
panel.name  = addonName
panel:SetSize(PANEL_W, PANEL_H)
panel:Hide()

-- ── Widget helpers ────────────────────────────────────────────────────────

local function MakeLabel(parent, text, x, y, template)
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
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return cb
end

-- Coloured square that opens the system colour picker on click.
-- Stores a Refresh() method so Reset buttons can revert the swatch colour.
local function MakeSwatch(parent, trackName, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    btn:SetPoint("TOPLEFT", x, y)

    -- Thin black border behind the fill
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT",     1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")

    local function Refresh()
        local c = GearTrackColorizerDB.colors[trackName]
        fill:SetVertexColor(c[1], c[2], c[3])
    end
    Refresh()

    btn:SetScript("OnClick", function()
        local c    = GearTrackColorizerDB.colors[trackName]
        local prev = {c[1], c[2], c[3]}

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
                GearTrackColorizerDB.colors[trackName] = {prev[1], prev[2], prev[3]}
                fill:SetVertexColor(prev[1], prev[2], prev[3])
                ns.UpdateAllSlots()
                ns.UpdateAllBagButtons()
            end,
        })
    end)

    btn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
    btn:SetScript("OnLeave", function(self) self:SetAlpha(1.0) end)
    btn.Refresh = Refresh
    return btn
end

local function MakeButton(parent, text, w, x, y, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, 22)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- ── Build panel contents ──────────────────────────────────────────────────

local swatches = {}  -- [trackName] = swatch, used by Reset All

local function BuildPanel()
    local curY = -16

    MakeLabel(panel, "GearTrackColorizer", COL_X, curY, "GameFontNormalLarge")
    curY = curY - 32

    -- Enable toggle
    MakeCheckbox(panel, "Enable addon", COL_X, curY,
        function() return GearTrackColorizerDB.enabled end,
        function(v)
            GearTrackColorizerDB.enabled = v
            if v then ns.UpdateAllSlots() ns.UpdateAllBagButtons()
            else       ns.ClearAllSlots() ns.ClearAllBagButtons() end
        end)
    curY = curY - ROW_H

    -- Bag borders toggle
    MakeCheckbox(panel, "Color borders in bags", COL_X, curY,
        function() return GearTrackColorizerDB.bagBorders end,
        function(v)
            GearTrackColorizerDB.bagBorders = v
            if v then ns.UpdateAllBagButtons()
            else       ns.ClearAllBagButtons() end
        end)
    curY = curY - ROW_H

    -- Border thickness slider
    MakeLabel(panel, "Border Thickness", COL_X, curY)
    curY = curY - 22

    local slider = CreateFrame("Slider", "GearTrackColorizerThicknessSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", COL_X + 4, curY)
    slider:SetWidth(200)
    slider:SetMinMaxValues(1, 6)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(GearTrackColorizerDB.borderThickness)
    _G[slider:GetName() .. "Low"]:SetText("1")
    _G[slider:GetName() .. "High"]:SetText("6")
    _G[slider:GetName() .. "Text"]:SetText(GearTrackColorizerDB.borderThickness .. " px")

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        GearTrackColorizerDB.borderThickness = val
        _G[self:GetName() .. "Text"]:SetText(val .. " px")
        ns.UpdateAllSlots()
        ns.UpdateAllBagButtons()
    end)
    curY = curY - 44

    -- Track color rows
    MakeLabel(panel, "Track Colors", COL_X, curY, "GameFontNormalLarge")
    curY = curY - 28

    for _, trackName in ipairs(ns.TRACK_ORDER) do
        local def    = ns.TRACK_DEFAULTS[trackName]
        local swatch = MakeSwatch(panel, trackName, COL_X, curY)
        swatches[trackName] = swatch

        MakeLabel(panel, trackName, COL_X + SWATCH_SIZE + 8, curY + 5)

        MakeButton(panel, "Reset", 70, COL_X + SWATCH_SIZE + 90, curY, function()
            GearTrackColorizerDB.colors[trackName] = {def[1], def[2], def[3]}
            swatch.Refresh()
            ns.UpdateAllSlots()
            ns.UpdateAllBagButtons()
        end)

        curY = curY - ROW_H
    end

    curY = curY - 8

    MakeButton(panel, "Reset All Colors", 120, COL_X, curY, function()
        for _, name in ipairs(ns.TRACK_ORDER) do
            local d = ns.TRACK_DEFAULTS[name]
            GearTrackColorizerDB.colors[name] = {d[1], d[2], d[3]}
            if swatches[name] then swatches[name].Refresh() end
        end
        ns.UpdateAllSlots()
        ns.UpdateAllBagButtons()
    end)
end

-- ── Register with Settings API and addon compartment ─────────────────────

local settingsCategory

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BuildPanel()

    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, addonName)
    Settings.RegisterAddOnCategory(settingsCategory)

    -- Minimap puzzle-piece compartment button (guarded; may not exist in all patches)
    if AddonCompartment then
        AddonCompartment.RegisterAddon({
            text         = addonName,
            icon         = "Interface\\Icons\\INV_Misc_Gear_01",
            notCheckable = true,
            func = function()
                Settings.OpenToCategory(settingsCategory)
            end,
            funcOnEnter = function(_, inputData)
                local anchor = (inputData and inputData.rootDescription) or UIParent
                GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
                GameTooltip:SetText(addonName, 1, 1, 1)
                GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end,
            funcOnLeave = function() GameTooltip:Hide() end,
        })
    end
end)
