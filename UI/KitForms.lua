-- Form building blocks for settings pages in our options window: section header, switch, slider, dropdown,
-- button row, color button, palette and text. Same rules as UI/Kit.lua: plain frames, painted through Theme.Bind, so
-- theme and accent changes reach them live. Each *Row returns a frame with :Update() (re-read the value) and a
-- height in row.rowHeight.
local _, ns = ...
local L = ns.L
local Theme, Kit = ns.Theme, ns.Kit
local Paint, Bind, Box, Refresh = Theme.Paint, Theme.Bind, Theme.Box, Theme.Refresh

local CONTROL_W = 220

---------------------------------------------------------------------------
-- Color picker (defensive: the API differs between client generations)
---------------------------------------------------------------------------

-- Opens the game's color picker. onPick(r, g, b) runs while the color changes and with the old color on cancel.
-- Returns false when the picker is not available (V-N15).
function Kit.PickColor(initial, onPick)
    if not (ColorPickerFrame and type(ColorPickerFrame.SetupColorPickerAndShow) == "function") then return false end
    initial = initial or { 1, 1, 1 }
    local ok = pcall(function()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = initial[1], g = initial[2], b = initial[3], hasOpacity = false,
            swatchFunc = function() onPick(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function(previous)
                if type(previous) == "table" and previous.r then onPick(previous.r, previous.g, previous.b) end
            end,
        })
    end)
    return ok
end

local function SameColor(a, r, g, b)
    return a and r and math.abs(a[1] - r) < 0.004 and math.abs(a[2] - g) < 0.004 and math.abs(a[3] - b) < 0.004
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

-- On/off switch: accent track with a light knob when on, a dim track when off.
function Kit.Switch(parent, get, set)
    local s = CreateFrame("Button", nil, parent, "BackdropTemplate")
    s:SetSize(34, 18)
    s.knob = s:CreateTexture(nil, "ARTWORK")
    s.knob:SetSize(12, 12)
    Bind(s, function(self, T)
        local on = get() and true or false
        Box(self, T, on and "accent" or "inputBg", on and nil or "border")
        Paint(self.knob, on and T.onAccent or T.textDim)
        self.knob:ClearAllPoints()
        if on then self.knob:SetPoint("RIGHT", -3, 0) else self.knob:SetPoint("LEFT", 3, 0) end
    end)
    s:SetScript("OnClick", function(self)
        set(not get())
        Refresh(self)
    end)
    function s:Update() Refresh(self) end
    return s
end

local function Decimals(step)
    if step >= 1 then return 0 end
    if step >= 0.1 then return 1 end
    return 2
end

-- Horizontal slider with a value readout. Values snap to step.
function Kit.Slider(parent, minValue, maxValue, step, get, set, w)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or CONTROL_W, 20)
    local digits = Decimals(step)
    local function Snap(value)
        value = minValue + math.floor((value - minValue) / step + 0.5) * step
        return math.max(minValue, math.min(maxValue, value))
    end
    local function Format(value) return ("%." .. digits .. "f"):format(value) end

    f.value = Kit.Text(f, 12, "text")
    f.value:SetPoint("RIGHT")
    f.value:SetWidth(40)
    f.value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, f)
    s:SetPoint("LEFT")
    s:SetPoint("RIGHT", -48, 0)
    s:SetHeight(16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step)
    if s.SetObeyStepsByValue then s:SetObeyStepsByValue(true) end
    s:EnableMouse(true)
    f.slider = s
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetHeight(4)
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.thumb = s:CreateTexture(nil, "OVERLAY")
    s.thumb:SetSize(8, 16)
    s:SetThumbTexture(s.thumb)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetHeight(4)
    s.fill:SetPoint("LEFT", s.track, "LEFT")
    s.fill:SetPoint("RIGHT", s.thumb, "CENTER")
    Bind(f, function(self, T)
        Paint(s.track, T.track)
        Paint(s.fill, T.accent)
        Paint(s.thumb, T.text)
    end)

    s:SetScript("OnValueChanged", function(_, value)
        value = Snap(value)
        f.value:SetText(Format(value))
        if not f.updating then set(value) end
    end)
    function f:Update()
        local value = Snap(tonumber(get()) or minValue)
        self.updating = true
        s:SetValue(value)
        self.updating = false
        self.value:SetText(Format(value))
    end
    f:Update()
    return f
end

-- Button that opens a menu of choices. values() returns { key = label }, { key, ... } (order).
function Kit.Dropdown(parent, w, values, get, set)
    local b = Kit.Button(parent, w or CONTROL_W, "", nil, 22)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -22, 0)
    b.label:SetJustifyH("LEFT")
    b.arrow = Kit.Glyph(b, "down", 10, "textDim")
    b.arrow:SetPoint("RIGHT", -7, 0)
    function b:Update()
        local labels, _, fonts = values()
        local key = get()
        -- font choices show the chosen name in its font
        Kit.ShowInFont(self.label, fonts and fonts[key], labels[key] or (key ~= nil and tostring(key)) or "")
    end
    b.onClick = function(self)
        local labels, order, fonts = values()
        local current = get()
        local items = {}
        for _, key in ipairs(order) do
            items[#items + 1] = { text = labels[key], checked = key == current, font = fonts and fonts[key], func = function()
                set(key)
                self:Update()
            end }
        end
        Kit.OpenMenu(self, items)
    end
    b:Update()
    return b
end

-- Color square that opens the game's color picker. get() -> r, g, b; set(r, g, b).
function Kit.ColorButton(parent, get, set, size)
    local sw = Kit.Swatch(parent, size or 22, { get() }, function(self)
        local r, g, b = get()
        local opened = Kit.PickColor({ r, g, b }, function(nr, ng, nb)
            set(nr, ng, nb)
            self:SetColor({ nr, ng, nb })
        end)
        if not opened then ns.Say(L["The color picker is not available in this client."]) end
    end)
    function sw:Update() self:SetColor({ get() }) end
    return sw
end

-- Row of color squares. get() -> r, g, b of the chosen one or nil; set(r, g, b).
function Kit.Palette(parent, colors, get, set, size)
    size = size or 18
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(#colors * (size + 2), size)
    f.swatches = {}
    for i, c in ipairs(colors) do
        local sw = Kit.Swatch(f, size, c, function(self)
            set(self.color[1], self.color[2], self.color[3])
            f:Update()
        end)
        sw:SetPoint("LEFT", (i - 1) * (size + 2), 0)
        f.swatches[i] = sw
    end
    function f:Update()
        local r, g, b = get()
        for _, sw in ipairs(self.swatches) do sw:SetSelected(SameColor(sw.color, r, g, b)) end
    end
    -- the chosen color may change from elsewhere (picker, EUI page): follow every repaint
    Bind(f, function(self) self:Update() end)
    return f
end

---------------------------------------------------------------------------
-- Rows (label left, control right)
---------------------------------------------------------------------------

local function Row(parent, text, tip, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or 44)
    row.rowHeight = height or 44
    row.label = Kit.Text(row, 12, "text")
    row.label:SetPoint("LEFT", 4, 0)
    row.label:SetWordWrap(false)
    row.label:SetText(text or "")
    if tip then
        row.tipLines = { text ~= "" and text or tip, text ~= "" and tip or nil }
        row:EnableMouse(true)
        Kit.Tooltip(row, row.tipLines, "ANCHOR_TOPLEFT")
    end
    function row:Update() if self.control and self.control.Update then self.control:Update() end end
    return row
end

local function PlaceControl(row, control, x)
    control:SetPoint("RIGHT", row, "RIGHT", x or -4, 0)
    row.label:SetPoint("RIGHT", control, "LEFT", -12, 0)
    row.control = control
    -- keep the row tooltip when the pointer rests on the control
    if row.tipLines then Kit.Tooltip(control, row.tipLines, "ANCHOR_TOPLEFT") end
    return row
end

-- Upper-case section title in the accent color with a line below.
function Kit.SectionHeader(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(34)
    row.rowHeight = 34
    row.label = Kit.Text(row, 11, "accent")
    row.label:SetPoint("BOTTOMLEFT", 4, 8)
    row.label:SetPoint("RIGHT", -4, 0)
    row.label:SetText(text or "")
    row.line = Kit.Divider(row)
    row.line:SetPoint("BOTTOMLEFT", 4, 2)
    row.line:SetPoint("BOTTOMRIGHT", -4, 2)
    function row:Update() end
    return row
end

function Kit.ToggleRow(parent, text, get, set, tip)
    local row = Row(parent, text, tip)
    local sw = Kit.Switch(row, get, set)
    PlaceControl(row, sw)
    -- a click on the label toggles too
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function() sw:Click() end)
    return row
end

function Kit.SliderRow(parent, text, minValue, maxValue, step, get, set, tip)
    local row = Row(parent, text, tip)
    return PlaceControl(row, Kit.Slider(row, minValue, maxValue, step, get, set))
end

function Kit.DropdownRow(parent, text, values, get, set, tip)
    local row = Row(parent, text, tip)
    return PlaceControl(row, Kit.Dropdown(row, CONTROL_W, values, get, set))
end

function Kit.ButtonRow(parent, text, onClick, tip, label)
    local row = Row(parent, label or "", tip)
    local b = Kit.Button(row, CONTROL_W, text, function() onClick() end, 24)
    return PlaceControl(row, b)
end

function Kit.ColorRow(parent, text, get, set, tip)
    local row = Row(parent, text, tip)
    return PlaceControl(row, Kit.ColorButton(row, get, set, 22))
end

function Kit.PaletteRow(parent, text, colors, get, set, tip)
    local row = Row(parent, text, tip)
    return PlaceControl(row, Kit.Palette(row, colors, get, set, 18))
end

-- Theme gallery: every theme as a small card drawn in its own colours (window, header strip, text, accent), the active
-- one framed in the current accent. Columns follow the width (row:Measure()); get() -> key, set(key).
local CARD_MIN_W, CARD_H, LABEL_H, GAP = 104, 50, 18, 8

local function Edges(frame, size)
    local t = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, size }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, size },
        { "TOPLEFT", "BOTTOMLEFT", size, nil }, { "TOPRIGHT", "BOTTOMRIGHT", size, nil } }) do
        local e = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetPoint(spec[1])
        e:SetPoint(spec[2])
        if spec[3] then e:SetWidth(spec[3]) else e:SetHeight(spec[4]) end
        t[i] = e
    end
    return t
end

local function SetEdges(edges, c, a)
    for _, e in ipairs(edges) do e:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end
end

local function ThemeCard(row, entry)
    local card = CreateFrame("Button", nil, row)
    card.key = entry.key
    card.fill = card:CreateTexture(nil, "BACKGROUND")
    card.fill:SetPoint("TOPLEFT")
    card.fill:SetPoint("TOPRIGHT")
    card.fill:SetHeight(CARD_H)
    card.strip = card:CreateTexture(nil, "BORDER")
    card.strip:SetPoint("TOPLEFT", card.fill, "TOPLEFT", 0, 0)
    card.strip:SetPoint("TOPRIGHT", card.fill, "TOPRIGHT", 0, 0)
    card.strip:SetHeight(12)
    card.sample = card:CreateFontString(nil, "OVERLAY")
    card.sample:SetPoint("TOPLEFT", card.fill, "TOPLEFT", 9, -17)
    card.line = card:CreateTexture(nil, "ARTWORK")
    card.line:SetSize(34, 3)
    card.line:SetPoint("TOPLEFT", card.sample, "BOTTOMLEFT", 0, -5)
    card.pill = card:CreateTexture(nil, "ARTWORK")
    card.pill:SetSize(20, 8)
    card.pill:SetPoint("BOTTOMRIGHT", card.fill, "BOTTOMRIGHT", -8, 8)
    -- the frame lies around the swatch only, the name sits below it
    local box = CreateFrame("Frame", nil, card)
    box:SetPoint("TOPLEFT", card.fill, "TOPLEFT", -2, 2)
    box:SetPoint("BOTTOMRIGHT", card.fill, "BOTTOMRIGHT", 2, -2)
    card.ring = Edges(box, 2)
    card.thin = Edges(CreateFrame("Frame", nil, card), 1)
    local thinBox = card.thin[1]:GetParent()
    thinBox:SetAllPoints(card.fill)
    card.label = Kit.Text(card, 11, "textDim")
    card.label:SetPoint("TOPLEFT", card.fill, "BOTTOMLEFT", 1, -4)
    card.label:SetPoint("TOPRIGHT", card.fill, "BOTTOMRIGHT", -1, -4)
    card.label:SetWordWrap(false)
    card.label:SetText(entry.label)
    function card:SetEntry(e)
        self.key = e.key
        self.label:SetText(e.label)
    end
    card.hover = card:CreateTexture(nil, "HIGHLIGHT")
    card.hover:SetAllPoints(card.fill)
    card:SetScript("OnClick", function(self) row:Pick(self.key) end)
    card:SetScript("OnEnter", function(self)
        self.hovered = true
        self:Paint(self.active, self.accent)
    end)
    card:SetScript("OnLeave", function(self)
        self.hovered = false
        self:Paint(self.active, self.accent)
    end)
    Kit.Tooltip(card, function(self) return { self.label:GetText() } end, "ANCHOR_TOP")

    function card:Paint(active, accent)
        self.active, self.accent = active, accent
        local T = Theme.Tokens(self.key) or Theme.Get()
        -- hover tint in the card's own mode: white veils dark swatches, black shades light ones
        if T.mode == "light" then self.hover:SetColorTexture(0, 0, 0, 0.08) else self.hover:SetColorTexture(1, 1, 1, 0.08) end
        self.fill:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)
        self.strip:SetColorTexture(T.bgAlt[1], T.bgAlt[2], T.bgAlt[3], 1)
        Theme.SetFont(self.sample, 15)
        self.sample:SetText("Aa")
        self.sample:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
        self.line:SetColorTexture(T.textDim[1], T.textDim[2], T.textDim[3], 1)
        self.pill:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        SetEdges(self.thin, T.border, math.max(0.25, T.border[4] or 1))
        SetEdges(self.ring, accent, active and 1 or 0)
        self.label.fnColor = active and "accent" or (self.hovered and "text" or "textDim")
        Refresh(self.label)
    end
    return card
end

function Kit.ThemeGalleryRow(parent, text, get, set, tip)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Kit.Text(row, 12, "text")
    row.label:SetPoint("TOPLEFT", 4, -6)
    row.label:SetText(text or "")
    if tip then
        row:EnableMouse(true)
        Kit.Tooltip(row, { text ~= "" and text or tip, text ~= "" and tip or nil }, "ANCHOR_TOPLEFT")
    end
    row.cards, row.all = {}, {}

    -- one card per theme; own themes come and go (theme editor), so the cards follow Theme.List()
    function row:Sync()
        local list = Theme.List()
        local same = #list == #self.cards
        for i, entry in ipairs(list) do
            if not same or self.cards[i].key ~= entry.key or self.cards[i].label:GetText() ~= entry.label then
                same = false
                break
            end
        end
        if same then return false end
        for _, card in ipairs(self.all) do card:Hide() end
        for i = #self.cards, 1, -1 do self.cards[i] = nil end
        for i, entry in ipairs(list) do
            local card = self.all[i]
            if not card then
                card = ThemeCard(row, entry)
                self.all[i] = card
            end
            card:SetEntry(entry)
            card:Show()
            self.cards[i] = card
        end
        return true
    end
    row:Sync()

    function row:Pick(key)
        if key ~= get() then set(key) end
        self:Update()
    end

    function row:Measure()
        local w = math.max(self:GetWidth() or 0, 2 * CARD_MIN_W + GAP + 8)
        local cols = math.max(2, math.floor((w - 8 + GAP) / (CARD_MIN_W + GAP)))
        local cardW = math.floor((w - 8 - (cols - 1) * GAP) / cols)
        local top = 28
        for i, card in ipairs(self.cards) do
            local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
            card:ClearAllPoints()
            card:SetSize(cardW, CARD_H + LABEL_H)
            card:SetPoint("TOPLEFT", self, "TOPLEFT", 4 + c * (cardW + GAP), -(top + r * (CARD_H + LABEL_H + GAP)))
        end
        local rows = math.ceil(#self.cards / cols)
        self.rowHeight = top + rows * (CARD_H + LABEL_H + GAP) + 4
        self:SetHeight(self.rowHeight)
        return self.rowHeight
    end

    function row:Update()
        if self:Sync() then self:Measure() end
        local current = get()
        local accent = Theme.Get().accent
        for _, card in ipairs(self.cards) do card:Paint(card.key == current, accent) end
    end

    -- repaint when the accent or the theme changes elsewhere
    Bind(row, function(self) self:Update() end)
    row:Measure()
    return row
end

-- Sample sentence in the chosen font inside a framed box (follows the font setting live).
function Kit.PreviewRow(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(48)
    row.rowHeight = 48
    row.box = Kit.Panel(row, "inputBg", "border", "input")
    row.box:SetPoint("TOPLEFT", 4, -4)
    row.box:SetPoint("BOTTOMRIGHT", -4, 4)
    row.text = Kit.Text(row.box, 16, "text")
    row.text:SetPoint("LEFT", 12, 0)
    row.text:SetPoint("RIGHT", -12, 0)
    row.text:SetWordWrap(false)
    row.text:SetText(text or "")
    function row:Update() end
    return row
end

-- Wrapped dim text; its height follows the width (row:Measure()). text is a string, or getText() returns it (re-read on
-- every row:Update()).
function Kit.TextRow(parent, text, getText)
    local row = CreateFrame("Frame", nil, parent)
    row.text = Kit.Text(row, 12, "textDim")
    row.text:SetPoint("TOPLEFT", 4, -4)
    row.text:SetPoint("TOPRIGHT", -4, -4)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    if row.text.SetSpacing then row.text:SetSpacing(3) end
    row.text:SetText(getText and getText() or text or "")
    function row:Measure()
        local h = math.floor((self.text:GetStringHeight() or 14) + 10 + 0.5)
        self.rowHeight = math.max(20, h)
        self:SetHeight(self.rowHeight)
        return self.rowHeight
    end
    function row:Update()
        if getText then self.text:SetText(getText() or "") end
    end
    row:Measure()
    return row
end
