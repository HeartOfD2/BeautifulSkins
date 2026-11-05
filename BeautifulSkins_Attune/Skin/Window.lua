-- Window skin: gives Attune's window a flat frame in the active theme. Attune's bronze chrome, its bottom buttons and its
-- title bar stay in place but are hidden; our header (symbol, title, view switch, options, close), status strip, survey
-- button and size grip sit on top and call Attune's own handlers. Attune's window is created once and never pooled, so
-- these changes are permanent for the session (undone only when the module is disabled after repeated errors).
local _, ns = ...
local L, A, Theme, Kit, Skin = ns.L, ns.Attune, ns.Theme, ns.Kit, ns.Skin
local Paint, Bind, Box, Refresh = Theme.Paint, Theme.Bind, Theme.Box, Theme.Refresh

local BORDER, HEADER_H, STATUS_H = 1, 40, 24
local LOGO = "Interface\\Icons\\INV_Scroll_03"
local SCALE_MIN, SCALE_MAX = 0.7, 1.3

local W -- our frames, built once
local menuLabel = setmetatable({}, { __mode = "k" }) -- survey menu button -> our label on it

local function Setting(key, default)
    local settings = ns.db and ns.db.settings
    if settings and settings[key] ~= nil then return settings[key] end
    return default
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

-- Two-way switch in a framed box. labels = { first, second }; onPick(index).
local function Segment(parent, labels, onPick)
    local seg = Kit.Panel(parent, "inputBg", "border")
    seg:SetHeight(24)
    seg.buttons = {}
    local width, previous = BORDER * 2, nil
    for index, label in ipairs(labels) do
        local b = CreateFrame("Button", nil, seg)
        b:SetHeight(24 - BORDER * 2)
        b.fill = b:CreateTexture(nil, "BACKGROUND")
        b.fill:SetAllPoints()
        b.under = b:CreateTexture(nil, "ARTWORK")
        b.under:SetPoint("BOTTOMLEFT")
        b.under:SetPoint("BOTTOMRIGHT")
        b.under:SetHeight(2)
        b.label = Kit.Text(b, 12, false)
        b.label:SetPoint("CENTER")
        b.label:SetText(label or "")
        b:SetWidth(math.max(64, b.label:GetStringWidth() + 24))
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 0, 0) else b:SetPoint("LEFT", seg, "LEFT", BORDER, 0) end
        previous = b
        width = width + b:GetWidth()
        Bind(b, function(self, T)
            local on = self.active
            Paint(self.fill, T.accentSoft)
            self.fill:SetShown(on and true or false)
            Paint(self.under, T.accent)
            self.under:SetShown(on and true or false)
            Paint(self.label, (on or self.hovered) and T.text or T.textDim)
        end)
        b:SetScript("OnEnter", function(self) self.hovered = true; Refresh(self) end)
        b:SetScript("OnLeave", function(self) self.hovered = false; Refresh(self) end)
        b:SetScript("OnClick", function() onPick(index) end)
        seg.buttons[index] = b
    end
    seg:SetWidth(width)
    function seg:SetActive(index)
        for i, b in ipairs(self.buttons) do
            b.active = i == index
            Refresh(b)
        end
    end
    return seg
end

-- The switch for Attune's "Next" window carries its state: accent while the window is on, dim while it is off.
local function UpdateNextButton()
    local button = W and W.header and W.header.nextWin
    if button then button:SetActive(A.NextWindowShown()) end
end

-- What this Attune offers decides which of the two extra header buttons are shown, and that is looked at on every
-- refresh, not once: our window is built the first time Attune opens its own, and Attune fills in parts of itself
-- later (its broker, for one). The visible buttons are chained left of our gear, so a hidden one leaves no gap.
local function LayoutHeader()
    local h = W and W.header
    if not h or not h.attuneGear then return end
    local options, nextWindow = A.CanOpenAttuneOptions(), A.HasNextWindow()
    h.attuneGear:SetShown(options)
    h.nextWin:SetShown(nextWindow)
    local left = h.gear
    if options then
        h.attuneGear:ClearAllPoints()
        h.attuneGear:SetPoint("RIGHT", left, "LEFT", -2, 0)
        left = h.attuneGear
    end
    if nextWindow then
        h.nextWin:ClearAllPoints()
        h.nextWin:SetPoint("RIGHT", left, "LEFT", -2, 0)
    end
    UpdateNextButton()
end

local function Build(parts)
    local host = parts.host
    local w = { host = host, paint = {}, menuLabels = {} }
    local base = host:GetFrameLevel()

    -- window fill and 1 px edge, below everything Attune draws
    w.back = Skin.Mine(CreateFrame("Frame", nil, host))
    w.back:SetAllPoints(host)
    w.back:SetFrameLevel(base + 1)
    Bind(w.back, function(self, T) Box(self, T, "bg", "border") end)
    w.paint[#w.paint + 1] = w.back

    -- header: symbol, title, view switch | options, close. Dragging it moves Attune's window.
    local header = Skin.Mine(CreateFrame("Frame", nil, host))
    w.header = header
    header:SetPoint("TOPLEFT", host, "TOPLEFT", BORDER, -BORDER)
    header:SetPoint("TOPRIGHT", host, "TOPRIGHT", -BORDER, -BORDER)
    header:SetHeight(HEADER_H)
    header:SetFrameLevel(base + 40)
    header:EnableMouse(true)
    header.fill = header:CreateTexture(nil, "BACKGROUND")
    header.fill:SetAllPoints()
    header.line = Kit.Divider(header)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    Bind(header, function(self, T) Paint(self.fill, T.bgAlt) end)
    header:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then A.StartMoving() end
    end)
    header:SetScript("OnMouseUp", function() A.StopMoving() end)
    header:SetScript("OnHide", function() A.StopMoving() end)

    header.logo = header:CreateTexture(nil, "ARTWORK")
    header.logo:SetSize(22, 22)
    header.logo:SetPoint("LEFT", header, "LEFT", 10, 0)
    header.logo:SetTexture(LOGO)
    header.logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    header.title = Kit.Text(header, 14, "text")
    header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, 0)
    header.title:SetText("Attune")

    local listName, resultsName = A.ViewNames()
    w.seg = Segment(header, { listName or L["Attunes"], resultsName or L["Results"] }, function(index)
        A.SwitchView(index == 1)
    end)
    w.seg:SetPoint("LEFT", header.title, "RIGHT", 14, 0)
    w.paint[#w.paint + 1] = w.seg

    header.close = Kit.IconButton(header, 28, "close", function() A.CloseWindow() end, L["Close"])
    header.close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    header.close:HookScript("OnEnter", function(self) self:SetColorOverride("danger") end)
    header.close:HookScript("OnLeave", function(self) self:SetColorOverride(nil) end)
    header.gear = Kit.IconButton(header, 28, "gear", function() ns.OpenOptions() end, L["Skin options"])
    header.gear:SetPoint("RIGHT", header.close, "LEFT", -2, 0)
    -- Left of ours: Attune's own options, then the switch for Attune's "Next" window. Both are built whatever this
    -- Attune offers right now; LayoutHeader places and shows them (its comment says why). The switch asks for its
    -- tooltip when it is hovered, so it can use Attune's own name for that window once Attune has it.
    header.attuneGear = Kit.IconButton(header, 28, "gear", function() A.OpenAttuneOptions() end,
        L["Attune's own options"])
    header.nextWin = Kit.IconButton(header, 28, "bullets", function()
        A.ToggleNextWindow()
        UpdateNextButton()
    end, function()
        local name = A.NextWindowName()
        return name and L["Show or hide %s"]:format(name) or L["Show or hide Attune's list of next steps"]
    end)
    header.attuneGear:Hide()
    header.nextWin:Hide()
    w.paint[#w.paint + 1] = header

    -- status strip: top line under Attune's status text (which keeps its own frame); controls above it
    local strip = Skin.Mine(CreateFrame("Frame", nil, host))
    w.strip = strip
    strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", BORDER, BORDER)
    strip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -BORDER, BORDER)
    strip:SetHeight(STATUS_H)
    strip:SetFrameLevel(base + 2)
    strip.line = Kit.Divider(strip)
    strip.line:SetPoint("TOPLEFT")
    strip.line:SetPoint("TOPRIGHT")

    local ctl = Skin.Mine(CreateFrame("Frame", nil, host))
    w.ctl = ctl
    ctl:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", BORDER, BORDER)
    ctl:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -BORDER, BORDER)
    ctl:SetHeight(STATUS_H)
    ctl:SetFrameLevel(base + 40)

    ctl.grip = Kit.Glyph(ctl, "grip", 12, "textDim")
    ctl.grip:SetPoint("BOTTOMRIGHT", ctl, "BOTTOMRIGHT", -5, 5)

    local survey = Kit.Button(ctl, 70, A.SurveyName() or L["Survey"], function() A.ClickButton(A.SurveyButton()) end, 18)
    w.survey = survey
    survey:SetPoint("RIGHT", ctl.grip, "LEFT", -10, 0)
    survey.label:ClearAllPoints()
    survey.label:SetPoint("LEFT", survey, "LEFT", 8, 0)
    survey.label:SetPoint("RIGHT", survey, "RIGHT", -20, 0)
    survey.label:SetJustifyH("LEFT")
    survey.arrow = Kit.Glyph(survey, "down", 10, "textDim")
    survey.arrow:SetPoint("RIGHT", survey, "RIGHT", -6, 0)
    survey:SetWidth(math.max(64, survey.label:GetStringWidth() + 34))
    -- Attune's survey button shows its hint in the status bar on hover: forward enter and leave
    survey:HookScript("OnEnter", function() A.RunScript(A.SurveyButton(), "OnEnter") end)
    survey:HookScript("OnLeave", function() A.RunScript(A.SurveyButton(), "OnLeave") end)

    return w
end

---------------------------------------------------------------------------
-- Attune's own parts: hide what we replace, move what stays
---------------------------------------------------------------------------

local function Conceal(parts)
    local host = parts.host
    if parts.chrome then Skin.HideFrame(host, parts.chrome) end
    if parts.titleFrame then Skin.HideFrame(host, parts.titleFrame) end
    if parts.closeButton then Skin.Conceal(host, parts.closeButton) end
    local results, survey = A.ResultsButton(), A.SurveyButton()
    if results then Skin.Conceal(host, results) end
    if survey then
        Skin.Conceal(host, survey)
        Skin.Remember(host, "survey-points", function()
            local points = Skin.Points(survey)
            return function() Skin.RestorePoints(survey, points) end
        end)
        survey:ClearAllPoints()
        survey:SetAllPoints(W.survey) -- Attune's own anchor target for its menu stays next to our button
    end
    -- the size grip's drawn lines (the frame itself keeps resizing)
    if parts.sizerSE then
        for _, region in ipairs({ parts.sizerSE:GetRegions() }) do Skin.Alpha(host, region, 0) end
    end
end

-- Content area: edge to edge in the list view (below the search strip when the search is on); with some air in the
-- results view.
local function PlaceContent(parts, list)
    local host, content = parts.host, parts.content
    Skin.Remember(host, content, function()
        local points = Skin.Points(content)
        return function() Skin.RestorePoints(content, points) end
    end)
    local room = list and Skin.SearchRoom() or 0
    local key = (list and "list" or "results") .. room
    if W.placed == key then return end
    W.placed = key
    local padX, padTop, padBottom = list and 0 or 12, list and room or 10, list and 0 or 8
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", host, "TOPLEFT", BORDER + padX, -(BORDER + HEADER_H + padTop))
    content:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(BORDER + padX), BORDER + STATUS_H + padBottom)
end

-- Places the content area again (the search strip appeared or went away).
function Skin.PlaceContent()
    if not W then return end
    local parts = A.WindowParts()
    if parts then PlaceContent(parts, A.IsListView()) end
end

-- Height the search strip takes below the header in the list view. Set by the search module; 0 without it.
local searchRoom = 0
function Skin.SearchRoom()
    return searchRoom
end

function Skin.SetSearchRoom(height)
    searchRoom = tonumber(height) or 0
end

local function StyleStatus(parts)
    local host, bar, text = parts.host, parts.statusBar, parts.statusText
    if not bar then return end
    Skin.Remember(host, bar, function()
        local points = Skin.Points(bar)
        return function() Skin.RestorePoints(bar, points) end
    end)
    local reserved = W.survey:GetWidth() + 10 + 22 + 8
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", BORDER + 4, BORDER)
    bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(BORDER + reserved), BORDER)
    bar:SetHeight(STATUS_H - 1)
    if type(bar.SetBackdrop) == "function" then bar:SetBackdrop(nil) end
    if text and Skin.Once(text, "style") then
        text:ClearAllPoints()
        text:SetPoint("LEFT", bar, "LEFT", 6, 0)
        text:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        Skin.NoShadow(host, text)
        Bind(text, function(self, T)
            Theme.SetFont(self, 11)
            Paint(self, T.textDim)
        end)
    end
end

-- Every text of a menu button but our label is hidden, not faded: on hover the button gives its text the highlight
-- font object again, which sets the alpha back to 1 (Attune's yellow words showed next to ours).
local function HideMenuTexts(button)
    local host = W.host
    if type(button.GetFontString) == "function" then
        local fs = button:GetFontString()
        if fs ~= menuLabel[button] then Skin.HideFrame(host, fs) end
    end
    for _, region in ipairs({ button:GetRegions() }) do
        if region ~= menuLabel[button] and region:GetObjectType() == "FontString" then Skin.HideFrame(host, region) end
    end
end

-- Attune's survey menu is an AceGUI group that Attune keeps for good: restyle it and let it open upwards.
local function StyleSurveyMenu()
    local menu = A.SurveyMenu()
    local widget = menu and menu.obj
    if type(widget) ~= "table" then return end
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMRIGHT", W.survey, "TOPRIGHT", 0, 4)
    menu:SetFrameStrata("DIALOG")
    if not Skin.Once(menu, "style") then return end
    local border = A.SurveyMenuBorder()
    if border then
        Skin.ClearBackdrop(W.host, border)
        Skin.Boxed(border, "popup", "border")
        W.paint[#W.paint + 1] = border
    end
    for _, child in ipairs(type(widget.children) == "table" and widget.children or {}) do
        local b = child.frame
        if type(b) == "table" and type(b.GetRegions) == "function" then
            Skin.StripTextures(b)
            -- the button's own text keeps its place (Attune sets it) but is hidden; ours shows the same words
            local fs = type(b.GetFontString) == "function" and b:GetFontString() or nil
            local label = Kit.Text(b, 12, "text")
            label:SetPoint("LEFT", b, "LEFT", 10, 0)
            label:SetPoint("RIGHT", b, "RIGHT", -10, 0)
            label:SetWordWrap(false)
            label:SetText(fs and fs:GetText() or "")
            menuLabel[b] = label
            W.menuLabels[#W.menuLabels + 1] = label
            HideMenuTexts(b)
            A.HookScript(b, "OnEnter", HideMenuTexts, "window")
            A.HookScript(b, "OnLeave", HideMenuTexts, "window")
            local hover = b:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            Bind(hover, function(self, T) Paint(self, T.hover) end)
        end
    end
end

---------------------------------------------------------------------------
-- Scale
---------------------------------------------------------------------------

local function ApplyScale()
    local host = A.MainFrame()
    if not host or not W then return end
    local scale = tonumber(Setting("windowScale", 1)) or 1
    scale = math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
    if math.abs((host:GetScale() or 1) - scale) < 0.001 then return end
    host:SetScale(scale)
    local menu = A.SurveyMenu()
    if menu then menu:SetScale(scale) end
    -- thin lines and glyphs snap to the pixel grid of the new effective scale
    for _, frame in ipairs(W.paint) do Refresh(frame) end
    Kit.RefreshGlyphs()
end

-- Window scale 0.7-1.3 (setting windowScale); applies at once.
function Skin.SetWindowScale(value)
    value = tonumber(value)
    if not value or not ns.db then return end
    ns.db.settings.windowScale = math.max(SCALE_MIN, math.min(SCALE_MAX, value))
    ApplyScale()
end

function Skin.WindowScale()
    return math.max(SCALE_MIN, math.min(SCALE_MAX, tonumber(Setting("windowScale", 1)) or 1))
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local function OnView()
    local parts = A.WindowParts()
    if not parts or not W then return end
    local list = A.IsListView()
    W.seg:SetActive(list and 1 or 2)
    PlaceContent(parts, list)
end

local function Apply()
    local parts = A.WindowParts()
    if not parts then return end
    if not W then W = Build(parts) end
    Conceal(parts) -- only after our own parts exist: an error before this point leaves Attune's frame usable
    StyleStatus(parts)
    StyleSurveyMenu()
    if parts.sizerSE and Skin.Once(parts.sizerSE, "grip") then
        A.HookScript(parts.sizerSE, "OnEnter", function() W.ctl.grip:SetColorKey("accent") end, "window")
        A.HookScript(parts.sizerSE, "OnLeave", function() W.ctl.grip:SetColorKey("textDim") end, "window")
    end
    LayoutHeader()
    OnView()
    ApplyScale()
end

-- Frames the tests and other skin modules may look at.
function Skin.Window()
    return W
end

ns.Modules.Register("window", {
    requires = { "Frame", "ToggleView", "MainFrame", "Chrome", "Survey", "ResultsButton", "WindowParts", "Texts" },
    setting = "window",
    Enable = function()
        A.On("window", Apply, "window")
        A.On("view", OnView, "window")
        if A.MainFrame() then Apply() end
    end,
    Disable = function()
        local host = A.MainFrame()
        if host then Skin.Undo(host) end
        if W then
            W.back:Hide(); W.header:Hide(); W.strip:Hide(); W.ctl:Hide()
            for _, label in ipairs(W.menuLabels) do label:Hide() end -- Attune's own texts are back (Undo)
        end
        Skin.Unbox(A.SurveyMenuBorder()) -- its own backdrop is back (Undo)
    end,
})
