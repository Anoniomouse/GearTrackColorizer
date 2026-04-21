local addonName, ns = ...

-- ── Settings panel ────────────────────────────────────────────────────────
-- Registered via Settings.RegisterCanvasLayoutCategory (12.0 API).
-- Opens from: Esc → Interface → AddOns → GearTrackColorizer
--         and: minimap addon compartment (puzzle-piece button)

local PANEL_W     = 700
local PANEL_H     = 640
local COL_X       = 20
local ROW_H       = 38
local SWATCH_SIZE = 24
local LABEL_X     = COL_X + SWATCH_SIZE + 10   -- 54
local RESET_X     = COL_X + SWATCH_SIZE + 170  -- 214  (leaves 160 px for label)

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
local function MakeSwatch(parent, trackName, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    btn:SetPoint("TOPLEFT", x, y)

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

-- ── Track row labels ──────────────────────────────────────────────────────

local TRACK_NOTES = {
    Maxed      = "|cffaaaaaa— Myth at max upgrade|r",
    Legendary  = "|cffaaaaaa— quality 5 items|r",
}

-- Splits addonName across the six real track colors (Explorer → Myth).
-- "GearTrackColorizer" = 18 chars, 6 tracks × 3 chars each — perfect split.
local function MakeColoredTitle()
    local name       = ns.DISPLAY_NAME  -- "Gear Track Colorizer"
    local realTracks = {"Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth"}
    local stops      = {}
    for _, trackName in ipairs(realTracks) do
        stops[#stops + 1] = ns.TRACK_DEFAULTS[trackName]
    end
    local n      = #name
    local result = ""
    for i = 1, n do
        -- Map character position to [0, #stops-1]
        local t     = (i - 1) / (n - 1) * (#stops - 1)
        local lo    = math.floor(t) + 1
        local hi    = math.min(lo + 1, #stops)
        local frac  = t - (lo - 1)
        local r = stops[lo][1] + (stops[hi][1] - stops[lo][1]) * frac
        local g = stops[lo][2] + (stops[hi][2] - stops[lo][2]) * frac
        local b = stops[lo][3] + (stops[hi][3] - stops[lo][3]) * frac
        local ch = name:sub(i, i)
        if i == 1 then
            -- No color code on 'G' so the string sorts alphabetically.
            result = result .. ch
        else
            local hex = string.format("%02x%02x%02x",
                math.floor(r * 255 + 0.5),
                math.floor(g * 255 + 0.5),
                math.floor(b * 255 + 0.5))
            result = result .. "|cff" .. hex .. ch .. "|r"
        end
    end
    return result
end

-- ── Build panel contents ──────────────────────────────────────────────────

local swatches = {}

local function BuildPanel()
    local curY = -16

    MakeLabel(panel, MakeColoredTitle(), COL_X, curY, "GameFontNormalLarge")
    curY = curY - 34

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
    curY = curY - 24

    local slider = CreateFrame("Slider", "GearTrackColorizerThicknessSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", COL_X + 8, curY)
    slider:SetWidth(200)
    slider:SetMinMaxValues(1, 6)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("1")
    _G[slider:GetName() .. "High"]:SetText("6")

    local sliderText = _G[slider:GetName() .. "Text"]
    sliderText:ClearAllPoints()
    sliderText:SetPoint("TOP", slider, "BOTTOM", 0, -4)

    -- SetScript BEFORE SetValue so OnValueChanged fires during init,
    -- which calls UpdateAllSlots with the correct saved thickness.
    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        GearTrackColorizerDB.borderThickness = val
        sliderText:SetText(val .. " px")
        ns.UpdateAllSlots()
        ns.UpdateAllBagButtons()
    end)
    slider:SetValue(GearTrackColorizerDB.borderThickness)
    curY = curY - 50

    -- Track color rows
    MakeLabel(panel, "Track Colors", COL_X, curY, "GameFontNormalLarge")
    curY = curY - 30

    -- Column headers
    MakeLabel(panel, "Color",  COL_X,    curY, "GameFontNormalSmall")
    MakeLabel(panel, "Track",  LABEL_X,  curY, "GameFontNormalSmall")
    MakeLabel(panel, "Reset",  RESET_X,  curY, "GameFontNormalSmall")
    curY = curY - 22

    for _, trackName in ipairs(ns.TRACK_ORDER) do
        local def    = ns.TRACK_DEFAULTS[trackName]
        local swatch = MakeSwatch(panel, trackName, COL_X, curY)
        swatches[trackName] = swatch

        -- Track name label
        MakeLabel(panel, trackName, LABEL_X, curY - 4)

        -- Optional note (dimmed, right of the name)
        local note = TRACK_NOTES[trackName]
        if note then
            local noteLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            noteLabel:SetPoint("LEFT", LABEL_X + 80, curY - 4)  -- offset right of name
            noteLabel:SetText(note)
        end

        -- Reset button
        MakeButton(panel, "Reset", 60, RESET_X, curY + 1, function()
            GearTrackColorizerDB.colors[trackName] = {def[1], def[2], def[3]}
            swatch.Refresh()
            ns.UpdateAllSlots()
            ns.UpdateAllBagButtons()
        end)

        curY = curY - ROW_H
    end

    curY = curY - 6

    MakeButton(panel, "Reset All Colors", 130, COL_X, curY, function()
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

    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, ns.DISPLAY_NAME)
    panel.name = ns.DISPLAY_NAME
    Settings.RegisterAddOnCategory(settingsCategory)
    -- Patch display name to colored after registration so sort position (set at
    -- registration time) stays alphabetical while the sidebar shows gradient text.
    local coloredName = MakeColoredTitle()
    settingsCategory.name = coloredName
    panel.name = coloredName

    if AddonCompartment then
        AddonCompartment.RegisterAddon({
            text         = ns.DISPLAY_NAME,
            icon         = "Interface\\Icons\\INV_Misc_Gear_01",
            notCheckable = true,
            func = function()
                Settings.OpenToCategory(settingsCategory)
            end,
            funcOnEnter = function(_, inputData)
                local anchor = (inputData and inputData.rootDescription) or UIParent
                GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
                GameTooltip:SetText(ns.DISPLAY_NAME, 1, 1, 1)
                GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end,
            funcOnLeave = function() GameTooltip:Hide() end,
        })
    end
end)
