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
local RESET_X     = COL_X + SWATCH_SIZE + 120  -- 164  (leaves 110 px for label)
local ENABLE_X    = RESET_X + 90               -- 254  (after 60 px reset button + gap)

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

local function MakeToggle(parent, labelText, x, y, getter, setter)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetPoint("TOPLEFT", x, y - 4)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT",     2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(1, 1, 1, 0.15)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    label:SetText(labelText)

    local function Refresh()
        local on = getter()
        fill:SetVertexColor(on and 0.2 or 0.25, on and 0.85 or 0.25, on and 0.2 or 0.25)
    end
    Refresh()

    btn:SetScript("OnClick", function()
        local on = not getter()
        setter(on)
        Refresh()
    end)

    return btn
end

-- Coloured square that opens the system colour picker on click.
-- A grey base sits behind the fill so partial transparency is visible.
local function MakeSwatch(parent, trackName, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    btn:SetPoint("TOPLEFT", x, y)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0)

    local gray = btn:CreateTexture(nil, "BORDER")
    gray:SetPoint("TOPLEFT",     1, -1)
    gray:SetPoint("BOTTOMRIGHT", -1, 1)
    gray:SetTexture("Interface\\Buttons\\WHITE8X8")
    gray:SetVertexColor(0.5, 0.5, 0.5)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT",     1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")

    local function Refresh()
        local c = GearTrackColorizerDB.colors[trackName]
        fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1.0)
    end
    Refresh()

    btn:SetScript("OnClick", function()
        local c    = GearTrackColorizerDB.colors[trackName]
        local prev = {c[1], c[2], c[3], c[4] or 1.0}

        local function ApplyPicker()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            GearTrackColorizerDB.colors[trackName] = {r, g, b, a}
            fill:SetVertexColor(r, g, b, a)
            ns.UpdateAllSlots()
            ns.UpdateAllBagButtons()
        end

        ColorPickerFrame:SetupColorPickerAndShow({
            r          = c[1], g = c[2], b = c[3],
            opacity    = c[4] or 1.0,
            hasOpacity = true,
            swatchFunc  = ApplyPicker,
            opacityFunc = ApplyPicker,
            cancelFunc = function()
                GearTrackColorizerDB.colors[trackName] = {prev[1], prev[2], prev[3], prev[4]}
                fill:SetVertexColor(prev[1], prev[2], prev[3], prev[4])
                ns.UpdateAllSlots()
                ns.UpdateAllBagButtons()
            end,
        })
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to change color", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha(1.0)
        GameTooltip:Hide()
    end)
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
    MakeToggle(panel, "Enable addon", COL_X, curY,
        function() return GearTrackColorizerDB.enabled end,
        function(v)
            GearTrackColorizerDB.enabled = v
            if v then ns.UpdateAllSlots() ns.UpdateAllBagButtons()
            else       ns.ClearAllSlots() ns.ClearAllBagButtons() end
        end)
    curY = curY - ROW_H

    -- Bag borders toggle
    MakeToggle(panel, "Color borders in bags", COL_X, curY,
        function() return GearTrackColorizerDB.bagBorders end,
        function(v)
            GearTrackColorizerDB.bagBorders = v
            if v then ns.UpdateAllBagButtons()
            else       ns.ClearAllBagButtons() end
        end)
    curY = curY - ROW_H

    -- Inspect frame toggle
    MakeToggle(panel, "Color borders in inspect frame", COL_X, curY,
        function() return GearTrackColorizerDB.inspectBorders end,
        function(v)
            GearTrackColorizerDB.inspectBorders = v
            if v then ns.UpdateInspectSlots()
            else       ns.ClearInspectSlots() end
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
    local colorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    colorHeader:SetPoint("TOPLEFT", COL_X - 8, curY)
    colorHeader:SetWidth(40)
    colorHeader:SetJustifyH("CENTER")
    colorHeader:SetText("Color")

    local trackHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    trackHeader:SetPoint("TOPLEFT", LABEL_X, curY)
    trackHeader:SetWidth(80)
    trackHeader:SetJustifyH("CENTER")
    trackHeader:SetText("Track")
    local showHideHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    showHideHeader:SetPoint("TOPLEFT", ENABLE_X - 28, curY)
    showHideHeader:SetWidth(80)
    showHideHeader:SetJustifyH("CENTER")
    showHideHeader:SetText("Show/Hide")

    local resetHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    resetHeader:SetPoint("TOPLEFT", RESET_X, curY)
    resetHeader:SetWidth(60)
    resetHeader:SetJustifyH("CENTER")
    resetHeader:SetText("Reset")
    curY = curY - 22

    for _, trackName in ipairs(ns.TRACK_ORDER) do
        local def    = ns.TRACK_DEFAULTS[trackName]
        local swatch = MakeSwatch(panel, trackName, COL_X, curY)
        swatches[trackName] = swatch

        -- Track name label
        MakeLabel(panel, trackName, LABEL_X, curY - 4)

        -- Reset button
        MakeButton(panel, "Reset", 60, RESET_X, curY + 1, function()
            GearTrackColorizerDB.colors[trackName] = {def[1], def[2], def[3]}
            swatch.Refresh()
            ns.UpdateAllSlots()
            ns.UpdateAllBagButtons()
        end)

        -- Eye icon toggle: bright = enabled, desaturated = disabled
        -- Small colored LED indicator: green = enabled, dark grey = disabled
        local toggleBtn = CreateFrame("Button", nil, panel)
        toggleBtn:SetSize(18, 18)
        toggleBtn:SetPoint("TOPLEFT", ENABLE_X + 3, curY + 2)

        local tBorder = toggleBtn:CreateTexture(nil, "BACKGROUND")
        tBorder:SetAllPoints()
        tBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
        tBorder:SetVertexColor(0, 0, 0)

        local tFill = toggleBtn:CreateTexture(nil, "ARTWORK")
        tFill:SetPoint("TOPLEFT",     2, -2)
        tFill:SetPoint("BOTTOMRIGHT", -2, 2)
        tFill:SetTexture("Interface\\Buttons\\WHITE8X8")

        local tHl = toggleBtn:CreateTexture(nil, "HIGHLIGHT")
        tHl:SetAllPoints()
        tHl:SetTexture("Interface\\Buttons\\WHITE8X8")
        tHl:SetVertexColor(1, 1, 1, 0.15)

        local function RefreshToggle()
            local on = GearTrackColorizerDB.trackEnabled[trackName] ~= false
            if on then
                tFill:SetVertexColor(0.2, 0.85, 0.2)
            else
                tFill:SetVertexColor(0.25, 0.25, 0.25)
            end
        end
        RefreshToggle()

        toggleBtn:SetScript("OnClick", function()
            local on = GearTrackColorizerDB.trackEnabled[trackName] ~= false
            GearTrackColorizerDB.trackEnabled[trackName] = not on
            RefreshToggle()
            ns.UpdateAllSlots()
            ns.UpdateAllBagButtons()
        end)
        toggleBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local on = GearTrackColorizerDB.trackEnabled[trackName] ~= false
            GameTooltip:SetText(on and "Click to hide " .. trackName .. " borders"
                                    or "Click to show " .. trackName .. " borders", 1, 1, 1)
            GameTooltip:Show()
        end)
        toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        curY = curY - ROW_H
    end

    curY = curY - 6

    MakeButton(panel, "Reset All Colors", 130, COL_X, curY, function()
        for _, name in ipairs(ns.TRACK_ORDER) do
            local d = ns.TRACK_DEFAULTS[name]
            GearTrackColorizerDB.colors[name] = {d[1], d[2], d[3]}  -- alpha resets to 1.0 (nil)
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
