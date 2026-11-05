-- UI kit: small themed building blocks for our own frames (windows, buttons, inputs, scroll areas, menu).
-- Every widget paints itself through Theme.Bind, so theme, accent and font changes reach open windows live.
-- Frames are plain (never secure), so they work in combat. Named frames (needed for ESC) all start with the addon name.
local _, ns = ...
local L = ns.L
local Theme = ns.Theme
local Paint, Bind, Box, Refresh = Theme.Paint, Theme.Bind, Theme.Box, Theme.Refresh

local Kit = {}
ns.Kit = Kit

local HEADER_H = 26
local WHEEL_STEP = 30

---------------------------------------------------------------------------
-- Text, dividers, hints, tooltips
---------------------------------------------------------------------------

-- Colour of a text token; the accent as text uses its readable variant (a class or own accent may be too pale).
function Kit.TextToken(T, key)
    if key == "accent" then return T.accentText or T.accent end
    return T[key] or T.text
end

-- Font string in the addon font (EUI's when loaded). colorKey = token name; false leaves the color to the owner (buttons, tabs).
function Kit.Text(parent, size, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs.fnSize = size or 12
    if colorKey ~= false then fs.fnColor = colorKey or "text" end
    fs:SetJustifyH("LEFT")
    Bind(fs, function(self, T)
        -- fnFont: a fixed font file for this string (font previews), else the addon font
        if not (self.fnFont and self:SetFont(self.fnFont, self.fnSize, "") ~= false) then Theme.SetFont(self, self.fnSize) end
        if self.fnColor then Paint(self, Kit.TextToken(T, self.fnColor)) end
    end)
    return fs
end

-- Shows text in a given font file (nil = addon font). A font the client loads for the first time may draw with the
-- fallback for one frame, so the text is set again on the next frame.
function Kit.ShowInFont(fs, file, text)
    fs.fnFont = file
    local function Apply()
        Refresh(fs)
        fs:SetText("")
        fs:SetText(text or "")
    end
    Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Apply) end
end

function Kit.SetTextColor(fs, colorKey)
    fs.fnColor = colorKey
    Refresh(fs)
end

function Kit.SetTextSize(fs, size)
    fs.fnSize = size
    Refresh(fs)
end

-- 1px line in the border color; vertical = true for a column separator.
function Kit.Divider(parent, vertical)
    local line = parent:CreateTexture(nil, "ARTWORK")
    Theme.Crisp(line)
    if vertical then line:SetWidth(1) else line:SetHeight(1) end
    Bind(line, function(self, T) Paint(self, T.border) end)
    return line
end

-- Centered dim text for empty states.
function Kit.Hint(parent, text)
    local fs = Kit.Text(parent, 12, "textDim")
    fs:SetPoint("LEFT", 12, 0)
    fs:SetPoint("RIGHT", -12, 0)
    fs:SetJustifyH("CENTER")
    fs:SetText(text or "")
    return fs
end

-- content: string, { title, line, ... } or function(frame) returning either.
function Kit.Tooltip(frame, content, anchor)
    frame:HookScript("OnEnter", function(self)
        local lines = content
        if type(lines) == "function" then lines = lines(self) end
        if not lines then return end
        if type(lines) == "string" then lines = { lines } end
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(lines[1], 1, 1, 1)
        for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.82, 0.82, 0.82, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Highlight layer shown by the engine while the mouse is over a button.
local function Hover(button)
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    Bind(hl, function(self, T) Paint(self, T.hover) end)
    button.hl = hl
    return hl
end

-- Plain themed frame with fill and edge (role lets the classic theme use Blizzard art).
function Kit.Panel(parent, bgKey, edgeKey, role)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Bind(f, function(self, T) Box(self, T, bgKey, edgeKey, role) end)
    return f
end

---------------------------------------------------------------------------
-- Glyphs: vector icons drawn with lines, so they take any theme color and need no image files
---------------------------------------------------------------------------

local function Circle(cx, cy, r, steps)
    local segs = {}
    for i = 0, steps - 1 do
        local a1, a2 = (i / steps) * 2 * math.pi, ((i + 1) / steps) * 2 * math.pi
        segs[#segs + 1] = { cx + r * math.cos(a1), cy + r * math.sin(a1), cx + r * math.cos(a2), cy + r * math.sin(a2) }
    end
    return segs
end

-- Segments in a unit square, origin bottom left.
local LOCK_BODY = { { 0.25, 0.12, 0.75, 0.12 }, { 0.75, 0.12, 0.75, 0.52 }, { 0.75, 0.52, 0.25, 0.52 },
    { 0.25, 0.52, 0.25, 0.12 } }

local GLYPHS = {
    close = { { 0.22, 0.22, 0.78, 0.78 }, { 0.22, 0.78, 0.78, 0.22 } },
    plus = { { 0.5, 0.18, 0.5, 0.82 }, { 0.18, 0.5, 0.82, 0.5 } },
    minus = { { 0.18, 0.5, 0.82, 0.5 } },
    up = { { 0.2, 0.36, 0.5, 0.66 }, { 0.5, 0.66, 0.8, 0.36 } },
    down = { { 0.2, 0.64, 0.5, 0.34 }, { 0.5, 0.34, 0.8, 0.64 } },
    left = { { 0.64, 0.2, 0.34, 0.5 }, { 0.34, 0.5, 0.64, 0.8 } },
    right = { { 0.36, 0.2, 0.66, 0.5 }, { 0.66, 0.5, 0.36, 0.8 } },
    back = { { 0.18, 0.5, 0.82, 0.5 }, { 0.18, 0.5, 0.42, 0.74 }, { 0.18, 0.5, 0.42, 0.26 } },
    check = { { 0.18, 0.5, 0.42, 0.26 }, { 0.42, 0.26, 0.84, 0.74 } },
    grip = { { 0.3, 0.12, 0.88, 0.7 }, { 0.5, 0.12, 0.88, 0.5 }, { 0.7, 0.12, 0.88, 0.3 } },
    search = Circle(0.43, 0.57, 0.24, 14),
    gear = Circle(0.5, 0.5, 0.2, 12),
    -- "fit all": four frame corners around a small box
    fit = { { 0.12, 0.88, 0.36, 0.88 }, { 0.12, 0.88, 0.12, 0.64 }, { 0.88, 0.88, 0.64, 0.88 }, { 0.88, 0.88, 0.88, 0.64 },
        { 0.12, 0.12, 0.36, 0.12 }, { 0.12, 0.12, 0.12, 0.36 }, { 0.88, 0.12, 0.64, 0.12 }, { 0.88, 0.12, 0.88, 0.36 },
        { 0.36, 0.38, 0.64, 0.38 }, { 0.64, 0.38, 0.64, 0.62 }, { 0.64, 0.62, 0.36, 0.62 }, { 0.36, 0.62, 0.36, 0.38 } },
    lock = { { 0.35, 0.52, 0.35, 0.72 }, { 0.35, 0.72, 0.42, 0.82 }, { 0.42, 0.82, 0.58, 0.82 },
        { 0.58, 0.82, 0.65, 0.72 }, { 0.65, 0.72, 0.65, 0.52 } },
    unlock = { { 0.35, 0.52, 0.35, 0.8 }, { 0.35, 0.8, 0.42, 0.9 }, { 0.42, 0.9, 0.58, 0.9 },
        { 0.58, 0.9, 0.65, 0.8 }, { 0.65, 0.8, 0.65, 0.7 } },
    ignore = Circle(0.5, 0.5, 0.36, 16),
    checkbox = { { 0.2, 0.2, 0.8, 0.2 }, { 0.8, 0.2, 0.8, 0.8 }, { 0.8, 0.8, 0.2, 0.8 }, { 0.2, 0.8, 0.2, 0.2 },
        { 0.32, 0.5, 0.46, 0.35 }, { 0.46, 0.35, 0.7, 0.65 } },
    bullets = { { 0.12, 0.74, 0.26, 0.74 }, { 0.38, 0.74, 0.88, 0.74 }, { 0.12, 0.5, 0.26, 0.5 },
        { 0.38, 0.5, 0.88, 0.5 }, { 0.12, 0.26, 0.26, 0.26 }, { 0.38, 0.26, 0.88, 0.26 } },
}
for _, kind in ipairs({ "lock", "unlock" }) do
    for _, seg in ipairs(LOCK_BODY) do table.insert(GLYPHS[kind], seg) end
end
table.insert(GLYPHS.ignore, { 0.25, 0.75, 0.75, 0.25 })
table.insert(GLYPHS.search, { 0.6, 0.4, 0.82, 0.18 })
for i = 0, 7 do -- gear teeth
    local a = i / 8 * 2 * math.pi
    table.insert(GLYPHS.gear, { 0.5 + 0.3 * math.cos(a), 0.5 + 0.3 * math.sin(a), 0.5 + 0.4 * math.cos(a),
        0.5 + 0.4 * math.sin(a) })
end
Kit.GLYPHS = GLYPHS


-- Size of one physical screen pixel in frame's own units (UI scale and frame scales included).
local function PixelUnit(frame)
    local factor
    if PixelUtil and type(PixelUtil.GetPixelToUIUnitFactor) == "function" then
        factor = PixelUtil.GetPixelToUIUnitFactor()
    elseif type(GetPhysicalScreenSize) == "function" then
        local _, h = GetPhysicalScreenSize()
        if type(h) == "number" and h > 0 then factor = 768 / h end
    end
    local scale = frame:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return (type(factor) == "number" and factor > 0 and factor or 1) / scale
end

-- Glyphs are rasterized onto the real pixel grid (n x n physical pixels, stroke t pixels) and drawn as pixel-snapped
-- textures: anti-aliased line objects at fractional positions looked blurry. Strokes are hinted (odd widths on pixel
-- centers, even widths on pixel edges), partial pixels get one of three alpha steps. Results are cached per size.
local raster = {}
local SUB = 4 -- subsamples per pixel and axis

local function Rasterize(kind, n, t)
    local key = kind .. ":" .. n .. ":" .. t
    if raster[key] then return raster[key] end
    local segs = GLYPHS[kind] or GLYPHS.close
    local half = t / 2
    local odd = t % 2 == 1
    local function Hint(v)
        local p = v * n
        if odd then
            p = math.floor(p) + 0.5
            return math.max(0.5, math.min(n - 0.5, p))
        end
        p = math.floor(p + 0.5)
        return math.max(1, math.min(n - 1, p))
    end
    local cover = {}
    for _, seg in ipairs(segs) do
        local x1, y1, x2, y2 = Hint(seg[1]), Hint(seg[2]), Hint(seg[3]), Hint(seg[4])
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local ux, uy = 1, 0
        if len > 0 then ux, uy = dx / len, dy / len end
        local minX = math.max(0, math.floor(math.min(x1, x2) - half - 1))
        local maxX = math.min(n - 1, math.floor(math.max(x1, x2) + half + 1))
        local minY = math.max(0, math.floor(math.min(y1, y2) - half - 1))
        local maxY = math.min(n - 1, math.floor(math.max(y1, y2) + half + 1))
        for cy = minY, maxY do
            for cx = minX, maxX do
                local hits = 0
                for sy = 0, SUB - 1 do
                    local py = cy + (sy + 0.5) / SUB - y1
                    for sx = 0, SUB - 1 do
                        local px = cx + (sx + 0.5) / SUB - x1
                        local along = px * ux + py * uy             -- square caps: a box around the segment
                        local across = math.abs(px * uy - py * ux)
                        if across <= half and along >= -half and along <= len + half then hits = hits + 1 end
                    end
                end
                if hits > 0 then
                    local index = cy * n + cx
                    local c = hits / (SUB * SUB)
                    if c > (cover[index] or 0) then cover[index] = c end
                end
            end
        end
    end
    -- quantize and merge horizontal runs: { x, y, width, alpha }
    local runs = {}
    for cy = 0, n - 1 do
        local runX, runA
        for cx = 0, n do
            local c = cx < n and cover[cy * n + cx] or 0
            local a = (c >= 0.8 and 1) or (c >= 0.5 and 0.66) or (c >= 0.22 and 0.33) or 0
            if a ~= runA then
                if runA and runA > 0 then runs[#runs + 1] = { runX, cy, cx - runX, runA } end
                runX, runA = cx, a
            end
        end
    end
    raster[key] = runs
    return runs
end
Kit.RasterizeGlyph = Rasterize -- runs for (kind, pixels, stroke); used by the probe and the offline test

local glyphs = setmetatable({}, { __mode = "k" })

function Kit.Glyph(parent, kind, size, colorKey)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g.size = size
    g.cells = {}
    g.runs = {}
    g.colorKey = colorKey or "textDim"
    function g:Render()
        local unit = PixelUnit(self)
        local n = math.max(5, math.floor(self.size / unit + 0.5))
        local t = math.max(1, math.floor(n / 8 + 0.5))
        -- same parity for box and stroke keeps centered strokes symmetric (even: on a pixel edge, odd: on a center)
        if n % 2 ~= t % 2 then n = n - 1 end
        local runs = Rasterize(self.kind, n, t)
        local offset = (self.size - n * unit) / 2
        for i, r in ipairs(runs) do
            local cell = self.cells[i]
            if not cell then
                cell = self:CreateTexture(nil, "ARTWORK")
                Theme.Crisp(cell)
                self.cells[i] = cell
            end
            cell:ClearAllPoints()
            cell:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", offset + r[1] * unit, offset + r[2] * unit)
            cell:SetSize(r[3] * unit, unit)
            cell.alpha = r[4]
            cell:Show()
        end
        for i = #runs + 1, #self.cells do self.cells[i]:Hide() end
        self.runs = runs
        self.renderedUnit = unit
        Refresh(self)
    end
    -- Re-rasterize when the effective scale changed (UI scale, window scale setting).
    function g:CheckScale()
        if self.kind and PixelUnit(self) ~= self.renderedUnit then self:Render() end
    end
    function g:SetKind(newKind)
        self.kind = newKind
        self:Render()
    end
    function g:SetColorKey(key)
        self.colorKey = key
        Refresh(self)
    end
    Bind(g, function(self, T)
        local color = T[self.colorKey] or T.textDim
        for i = 1, #self.runs do Paint(self.cells[i], color, self.cells[i].alpha) end
    end)
    g:HookScript("OnShow", g.CheckScale)
    glyphs[g] = true
    g:SetKind(kind)
    return g
end

-- After a scale change: every glyph re-checks its pixel grid.
function Kit.RefreshGlyphs()
    for g in pairs(glyphs) do g:CheckScale() end
end

local scaleWatch = CreateFrame("Frame")
scaleWatch:RegisterEvent("UI_SCALE_CHANGED")
scaleWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatch:SetScript("OnEvent", function() Kit.RefreshGlyphs() end)

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local VARIANTS = {
    normal = { bg = "control", edge = "border", text = "text" },
    primary = { bg = "accent", text = "onAccent" },
    danger = { bg = "control", edge = "danger", text = "danger" },
    ghost = { text = "textDim" },
}

local function PaintButton(b, T)
    local v = VARIANTS[b.variant] or VARIANTS.normal
    Box(b, T, v.bg, v.edge, v.bg == "control" and "button" or nil)
    Paint(b.label, T[v.text], b:IsEnabled() and 1 or 0.45)
end

-- Text button. variant: "normal" | "primary" | "danger" | "ghost".
function Kit.Button(parent, w, text, onClick, h, variant)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 100, h or 22)
    b.variant = variant or "normal"
    b.label = Kit.Text(b, 12, false)
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.label:SetText(text or "")
    Hover(b)
    b.onClick = onClick
    b:SetScript("OnClick", function(self, button)
        if self.onClick then self.onClick(self, button) end
    end)
    b:SetScript("OnEnable", Refresh)
    b:SetScript("OnDisable", Refresh)
    function b:SetLabel(newText) self.label:SetText(newText or "") end
    function b:SetVariant(newVariant)
        self.variant = newVariant
        Refresh(self)
    end
    Bind(b, PaintButton)
    return b
end

-- Destructive action: the first click arms (label turns into "Sure?"), a second click within 3 s confirms.
function Kit.ConfirmButton(parent, w, text, onConfirm, h)
    local b = Kit.Button(parent, w, text, nil, h, "normal")
    b.baseText = text
    b.armed = 0
    local function Disarm(self)
        if self.armed == 0 then return end
        self.armed = 0
        self:SetLabel(self.baseText)
        self:SetVariant("normal")
    end
    b.onClick = function(self)
        if self.armed > 0 then
            Disarm(self)
            onConfirm(self)
            return
        end
        self.armed = (self.armToken or 0) + 1
        self.armToken = self.armed
        local token = self.armed
        self:SetLabel(L["Sure?"])
        self:SetVariant("danger")
        C_Timer.After(3, function() if self.armed == token then Disarm(self) end end)
    end
    b:HookScript("OnHide", Disarm)
    function b:SetBaseText(newText)
        self.baseText = newText
        if self.armed == 0 then self:SetLabel(newText) end
    end
    return b
end

-- Square icon button: kind is a glyph name (see Kit.GLYPHS) or a texture path. SetActive tints it with the accent.
function Kit.IconButton(parent, size, kind, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    Hover(b)
    if GLYPHS[kind] then
        b.glyph = Kit.Glyph(b, kind, math.floor(size * 0.7 + 0.5), "textDim")
        b.glyph:SetPoint("CENTER")
    else
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetTexture(kind)
        b.icon:SetPoint("CENTER")
        b.icon:SetSize(size * 0.8, size * 0.8)
    end
    local function Tint(self)
        if not self.glyph then return end
        local key = self.colorOverride or (self.active and "accent") or (self.hovered and "text") or "textDim"
        self.glyph:SetColorKey(key)
    end
    b:SetScript("OnEnter", function(self) self.hovered = true; Tint(self) end)
    b:SetScript("OnLeave", function(self) self.hovered = false; Tint(self) end)
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    function b:SetActive(on)
        self.active = on and true or false
        Tint(self)
    end
    function b:SetColorOverride(key) -- e.g. "danger"
        self.colorOverride = key
        Tint(self)
    end
    function b:SetGlyph(newKind)
        if self.glyph then self.glyph:SetKind(newKind) end
    end
    if tip then Kit.Tooltip(b, tip, "ANCHOR_TOP") end
    return b
end

-- Color square for the accent quick picks and the color picker. color = { r, g, b }.
function Kit.Swatch(parent, size, color, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", 2, -2)
    b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    Hover(b)
    function b:SetColor(c)
        self.color = c
        self.fill:SetColorTexture(c[1], c[2], c[3], 1)
    end
    function b:SetSelected(on)
        self.selected = on and true or false
        Refresh(self)
    end
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    Bind(b, function(self, T) Box(self, T, nil, self.selected and "text" or "border") end)
    b:SetColor(color or { 1, 1, 1 })
    return b
end

---------------------------------------------------------------------------
-- Inputs
---------------------------------------------------------------------------

-- Selection color of an edit box: the accent, so marked text is visible on every theme.
function Kit.PaintSelection(edit, T)
    local c = T and T.accent
    if c and type(edit.SetHighlightColor) == "function" then
        edit:SetHighlightColor(c[1], c[2], c[3], 0.55)
    end
end

-- The engine's own caret is not visible on every theme/background, so edit boxes get a caret of their own: a thin
-- text-colored bar that follows OnCursorChanged and blinks while the box has focus.
-- Call it AFTER the edit box's own SetScript calls: SetScript replaces a handler together with its hooks.
function Kit.AttachCaret(edit)
    local caret = edit:CreateTexture(nil, "OVERLAY", nil, 7)
    edit.fnCaret = caret
    caret:SetWidth(2)
    caret:SetHeight(14)
    caret:Hide()
    Bind(caret, function(self, T) Paint(self, T.text) end)
    local elapsed = 0
    local function Place(_, x, y, _, h)
        if type(x) ~= "number" then return end
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", edit, "TOPLEFT", x, y)
        caret:SetHeight(math.max(8, h or 14))
        elapsed = 0
        if edit:HasFocus() then caret:Show() end
    end
    edit:HookScript("OnCursorChanged", Place)
    edit:HookScript("OnEditFocusGained", function()
        elapsed = 0
        caret:Show()
    end)
    edit:HookScript("OnEditFocusLost", function() caret:Hide() end)
    edit:HookScript("OnHide", function() caret:Hide() end)
    edit:HookScript("OnUpdate", function(_, dt)
        if not edit:HasFocus() then return end
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            caret:SetShown(not caret:IsShown())
        end
    end)
    return caret
end

-- Single-line input. opts: placeholder, maxLetters, size, onChange(text, userInput), onEnter(text), numeric.
function Kit.EditBox(parent, w, h, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w or 140, h or 22)
    local e = CreateFrame("EditBox", nil, f)
    e:SetPoint("TOPLEFT", 6, 0)
    e:SetPoint("BOTTOMRIGHT", -6, 0)
    e:SetAutoFocus(false)
    e:SetMultiLine(false)
    if opts.maxLetters then e:SetMaxLetters(opts.maxLetters) end
    if opts.numeric then e:SetNumeric(true) end
    f.edit = e
    f.placeholder = Kit.Text(f, opts.size or 12, "textDim")
    f.placeholder:SetPoint("LEFT", 6, 0)
    f.placeholder:SetPoint("RIGHT", -6, 0)
    f.placeholder:SetWordWrap(false)
    f.placeholder:SetText(opts.placeholder or "")

    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", function(self)
        if opts.onEnter then opts.onEnter(self:GetText()) end
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusGained", function() f.focused = true; Refresh(f) end)
    e:SetScript("OnEditFocusLost", function() f.focused = false; Refresh(f) end)
    e:SetScript("OnTextChanged", function(self, userInput)
        f.placeholder:SetShown(self:GetText() == "" and not f.focused)
        if opts.onChange then opts.onChange(self:GetText(), userInput) end
    end)
    Kit.AttachCaret(e) -- after the SetScript calls above
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() e:SetFocus() end)

    function f:SetText(text) self.edit:SetText(text or "") end
    function f:GetText() return self.edit:GetText() end
    function f:SetFocus() self.edit:SetFocus() end
    function f:ClearFocus() self.edit:ClearFocus() end
    Bind(f, function(self, T)
        Box(self, T, "inputBg", "border", "input")
        if self.focused then Theme.Edge(self, T.accent) end
        Theme.SetFont(self.edit, opts.size or 12)
        Paint(self.edit, T.text)
        Kit.PaintSelection(self.edit, T)
        self.placeholder:SetShown(self.edit:GetText() == "" and not self.focused)
    end)
    return f
end

-- Checkbox row for our own windows (settings pages use the switch rows in UI/KitForms.lua).
function Kit.Checkbox(parent, text, get, set, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    b.box = Kit.Panel(b, "inputBg", "border", "input")
    b.box:SetSize(14, 14)
    b.box:SetPoint("LEFT", 0, 0)
    b.mark = Kit.Glyph(b.box, "check", 12, "accent")
    b.mark:SetPoint("CENTER")
    b.label = Kit.Text(b, size or 12, "text")
    b.label:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
    b.label:SetText(text or "")
    function b:Update()
        self.mark:SetShown(get() and true or false)
        self:SetWidth(20 + self.label:GetStringWidth())
    end
    b:SetScript("OnClick", function(self)
        set(not get())
        self:Update()
    end)
    Bind(b, function(self) self:Update() end)
    return b
end

---------------------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------------------

-- Thin themed scroll bar on the right edge of owner. onScroll(value) receives the new offset.
local function ScrollBar(owner, onScroll)
    local bar = CreateFrame("Frame", nil, owner)
    bar:SetWidth(5)
    bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.thumb = CreateFrame("Button", nil, bar)
    bar.thumb:SetWidth(5)
    bar.thumb.tex = bar.thumb:CreateTexture(nil, "ARTWORK")
    bar.thumb.tex:SetAllPoints()
    bar.offset, bar.max, bar.ratio = 0, 0, 1
    Bind(bar, function(self, T)
        Paint(self.track, T.track)
        Paint(self.thumb.tex, T.thumb)
    end)
    function bar:Update(offset, maxOffset, ratio)
        self.offset, self.max, self.ratio = offset, maxOffset, ratio
        if maxOffset <= 0 then
            self:Hide()
            return
        end
        self:Show()
        local trackH = self:GetHeight()
        local thumbH = math.max(16, trackH * math.min(1, ratio))
        self.thumb:SetHeight(thumbH)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self, "TOP", 0, -(trackH - thumbH) * offset / maxOffset)
    end
    bar.thumb:SetScript("OnMouseDown", function(thumb)
        local _, y = GetCursorPosition()
        thumb.dragY, thumb.dragOffset = y / thumb:GetEffectiveScale(), bar.offset
        thumb:SetScript("OnUpdate", function(self)
            local _, cy = GetCursorPosition()
            local travel = bar:GetHeight() - self:GetHeight()
            if travel <= 0 then return end
            local delta = (self.dragY - cy / self:GetEffectiveScale()) * bar.max / travel
            onScroll(self.dragOffset + delta)
        end)
    end)
    bar.thumb:SetScript("OnMouseUp", function(thumb) thumb:SetScript("OnUpdate", nil) end)
    bar.thumb:SetScript("OnHide", function(thumb) thumb:SetScript("OnUpdate", nil) end)
    return bar
end

-- Free-form scrolling content: put children on area.child and call area:SetContentHeight(h).
function Kit.ScrollArea(parent)
    local f = CreateFrame("Frame", nil, parent)
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    f.scroll, f.child = sf, child
    local function MaxOffset() return math.max(0, child:GetHeight() - sf:GetHeight()) end
    function f:SetOffset(value)
        local maxOffset = MaxOffset()
        value = math.max(0, math.min(maxOffset, value or 0))
        sf:SetVerticalScroll(value)
        local view = sf:GetHeight()
        self.bar:Update(value, maxOffset, view / math.max(view, child:GetHeight()))
    end
    function f:SetContentHeight(h)
        child:SetHeight(math.max(1, h))
        self:SetOffset(sf:GetVerticalScroll())
    end
    function f:GetOffset() return sf:GetVerticalScroll() end
    f.bar = ScrollBar(f, function(value) f:SetOffset(value) end)
    sf:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w)
        f:SetOffset(self:GetVerticalScroll())
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta) self:SetOffset(sf:GetVerticalScroll() - delta * WHEEL_STEP) end)
    return f
end

local function PaintRow(row, T)
    Paint(row.sel, T.select)
    Paint(row.mark, T.accent)
end

-- Virtual list with pooled rows. opts:
--   create(row)                   add font strings etc. once per pooled row
--   update(row, item, index)      fill a row
--   onClick(row, item, button)    left/right click
--   isSelected(item)              selection marker (accent bar + tint)
function Kit.ScrollList(parent, rowHeight, opts)
    local f = CreateFrame("Frame", nil, parent)
    f.rowHeight, f.items, f.offset, f.rows, f.visible = rowHeight, {}, 0, {}, 0
    f.bar = ScrollBar(f, function(value) f:SetOffset(math.floor(value + 0.5)) end)

    local function NewRow(index)
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", -10, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetPoint("TOPLEFT")
        row.mark:SetPoint("BOTTOMLEFT")
        row.mark:SetWidth(2)
        Hover(row)
        if opts.isSelected then Bind(row, PaintRow) else row.mark:Hide() end
        row:SetScript("OnClick", function(self, button)
            if opts.onClick and self.item ~= nil then opts.onClick(self, self.item, button) end
        end)
        if opts.create then opts.create(row) end
        return row
    end

    function f:Refresh()
        local count = #self.items
        local maxOffset = math.max(0, count - self.visible)
        if self.offset > maxOffset then self.offset = maxOffset end
        for i = 1, self.visible do
            local row, index = self.rows[i], self.offset + i
            local item = self.items[index]
            row.item, row.index = item, index
            if item ~= nil then
                local selected = opts.isSelected and opts.isSelected(item) and true or false
                row.sel:SetShown(selected)
                if opts.isSelected then row.mark:SetShown(selected) end
                if opts.update then opts.update(row, item, index) end
                row:Show()
            else
                row:Hide()
            end
        end
        for i = self.visible + 1, #self.rows do self.rows[i]:Hide() end
        self.bar:Update(self.offset, maxOffset, self.visible / math.max(1, count))
    end

    function f:Layout()
        self.visible = math.max(0, math.floor(self:GetHeight() / rowHeight))
        for i = #self.rows + 1, self.visible do self.rows[i] = NewRow(i) end
        self:Refresh()
    end

    function f:SetItems(items)
        self.items = items or {}
        self:Refresh()
    end

    function f:SetOffset(value)
        self.offset = math.max(0, math.min(math.max(0, #self.items - self.visible), value or 0))
        self:Refresh()
    end

    -- Scroll just enough to show item index.
    function f:ScrollTo(index)
        if index <= self.offset then
            self:SetOffset(index - 1)
        elseif index > self.offset + self.visible then
            self:SetOffset(index - self.visible)
        end
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta) self:SetOffset(self.offset - delta * 3) end)
    f:SetScript("OnSizeChanged", function(self) self:Layout() end)
    return f
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- Tab strip with an accent underline. items = { { key, label }, ... }; onSelect(key).
function Kit.Tabs(parent, items, onSelect, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(h or 24)
    f.buttons, f.order = {}, {}
    f.baseline = Kit.Divider(f)
    f.baseline:SetPoint("BOTTOMLEFT")
    f.baseline:SetPoint("BOTTOMRIGHT")
    for i, item in ipairs(items) do
        local key = item[1]
        local b = CreateFrame("Button", nil, f)
        b.key = key
        b.text = Kit.Text(b, 12, false)
        b.text:SetPoint("LEFT", 4, 1)
        b.text:SetPoint("RIGHT", -4, 1)
        b.text:SetJustifyH("CENTER")
        b.text:SetWordWrap(false)
        b.text:SetText(item[2])
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 6, 0)
        b.line:SetPoint("BOTTOMRIGHT", -6, 0)
        b.line:SetHeight(2)
        b:SetScript("OnEnter", function(self) self.hovered = true; Refresh(self) end)
        b:SetScript("OnLeave", function(self) self.hovered = false; Refresh(self) end)
        b:SetScript("OnClick", function(self) f:Select(self.key) end)
        Bind(b, function(self, T)
            local active = f.selected == self.key
            Paint(self.text, (active or self.hovered) and T.text or T.textDim)
            Paint(self.line, T.accent)
            self.line:SetShown(active)
        end)
        f.buttons[key] = b
        f.order[i] = b
    end
    local function Layout(self)
        local w = self:GetWidth() / math.max(1, #self.order)
        for i, b in ipairs(self.order) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (i - 1) * w, 0)
            b:SetSize(w, self:GetHeight())
        end
    end
    f:SetScript("OnSizeChanged", Layout)
    function f:Select(key, silent)
        if not self.buttons[key] then return end
        self.selected = key
        for _, b in ipairs(self.order) do Refresh(b) end
        if onSelect and not silent then onSelect(key) end
    end
    function f:SetLabel(key, text)
        if self.buttons[key] then self.buttons[key].text:SetText(text) end
    end
    return f
end

---------------------------------------------------------------------------
-- Glow strip (popup: player has notes / is ignored)
---------------------------------------------------------------------------

-- Pulsing gradient along one edge of owner. opts: side "BOTTOM"|"TOP", height, colorKey ("accent" | "danger").
function Kit.Glow(owner, opts)
    opts = opts or {}
    local side = opts.side == "TOP" and "TOP" or "BOTTOM"
    local g = CreateFrame("Frame", nil, owner)
    g:SetHeight(opts.height or 12)
    g:SetPoint(side .. "LEFT")
    g:SetPoint(side .. "RIGHT")
    g:SetFrameLevel(owner:GetFrameLevel() + 5)
    g.colorKey = opts.colorKey or "accent"
    g.fade = g:CreateTexture(nil, "OVERLAY")
    g.fade:SetAllPoints()
    g.edge = g:CreateTexture(nil, "OVERLAY", nil, 1)
    g.edge:SetPoint(side .. "LEFT")
    g.edge:SetPoint(side .. "RIGHT")
    g.edge:SetHeight(2)
    Bind(g, function(self, T)
        local c = T[self.colorKey] or T.accent
        Paint(self.edge, c)
        self.fade:SetColorTexture(1, 1, 1, 1)
        -- VERTICAL gradients run bottom (first color) to top; strongest at the glowing edge.
        local ok = type(CreateColor) == "function" and pcall(function()
            local near, far = CreateColor(c[1], c[2], c[3], 0.5), CreateColor(c[1], c[2], c[3], 0)
            if side == "BOTTOM" then
                self.fade:SetGradient("VERTICAL", near, far)
            else
                self.fade:SetGradient("VERTICAL", far, near)
            end
        end)
        if not ok then self.fade:SetColorTexture(c[1], c[2], c[3], 0.25) end
    end)
    g.anim = g:CreateAnimationGroup()
    g.anim:SetLooping("BOUNCE")
    local pulse = g.anim:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.25)
    pulse:SetDuration(1.1)
    pulse:SetSmoothing("IN_OUT")
    function g:SetColorKey(key)
        self.colorKey = key
        Refresh(self)
    end
    function g:Play()
        self:Show()
        if not self.anim:IsPlaying() then self.anim:Play() end
    end
    function g:Stop()
        self.anim:Stop()
        self:Hide()
    end
    g:Hide()
    return g
end

---------------------------------------------------------------------------
-- Context menu (one shared frame)
---------------------------------------------------------------------------

local menu, blocker

local function MenuRow(index)
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 20)
    row:SetPoint("RIGHT", -4, 0)
    Hover(row)
    row.check = Kit.Glyph(row, "check", 12, "accent")
    row.check:SetPoint("LEFT", 4, 0)
    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(10, 10)
    row.swatch:SetPoint("LEFT", 5, 0)
    row.text = Kit.Text(row, 12, "text")
    row.text:SetPoint("LEFT", 22, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        local item = self.item
        Kit.CloseMenu()
        if item and item.func then item.func(item) end
    end)
    row:SetScript("OnEnter", function(self) Kit.ShowFontPreview(self, self.item) end)
    row:SetScript("OnLeave", function() Kit.ShowFontPreview(nil) end)
    return row
end

-- Font preview beside the menu: the hovered font's name and a sample sentence in that font.
local preview
function Kit.ShowFontPreview(row, item)
    if not (row and item and item.font) then
        if preview then preview:Hide() end
        return
    end
    if not preview then
        preview = CreateFrame("Frame", nil, menu, "BackdropTemplate")
        preview:SetSize(320, 62)
        preview:SetFrameStrata("FULLSCREEN_DIALOG")
        preview:SetFrameLevel(menu:GetFrameLevel() + 5)
        preview:SetClampedToScreen(true)
        Bind(preview, function(self, T) Box(self, T, "popup", "border", "popup") end)
        preview.name = Kit.Text(preview, 20, "text")
        preview.name:SetPoint("TOPLEFT", 12, -10)
        preview.name:SetPoint("RIGHT", -12, 0)
        preview.name:SetWordWrap(false)
        preview.sample = Kit.Text(preview, 13, "textDim")
        preview.sample:SetPoint("TOPLEFT", preview.name, "BOTTOMLEFT", 0, -6)
        preview.sample:SetPoint("RIGHT", -12, 0)
        preview.sample:SetWordWrap(false)
    end
    Kit.ShowInFont(preview.name, item.font, item.text)
    Kit.ShowInFont(preview.sample, item.font, L["The quick brown fox jumps over the lazy dog. 0123456789"])
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", row, "TOPRIGHT", 10, 18)
    preview:Show()
end

local function EnsureMenu()
    if menu then return end
    blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:RegisterForClicks("AnyUp")
    blocker:SetScript("OnClick", function() Kit.CloseMenu() end)
    blocker:Hide()
    menu = CreateFrame("Frame", ns.name .. "Menu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.rows = {}
    menu:SetScript("OnHide", function() blocker:Hide() end)
    menu:Hide()
    table.insert(UISpecialFrames, ns.name .. "Menu")
    Bind(menu, function(self, T) Box(self, T, "popup", "border", "popup") end)
end

-- items = { { text, func(item), checked, disabled, color = { r, g, b }, title = true }, ... }
function Kit.OpenMenu(anchor, items)
    EnsureMenu()
    menu.fnCtx = Theme.CtxOf(anchor)
    Refresh(menu)
    local width = anchor:GetWidth()
    for i, item in ipairs(items) do
        local row = menu.rows[i] or MenuRow(i)
        menu.rows[i] = row
        row.item = item
        -- font menus show each name in its own font; other menus use the addon font
        Kit.ShowInFont(row.text, item.font, item.text)
        row.check:SetShown(item.checked and not item.color and true or false)
        row.swatch:SetShown(item.color ~= nil)
        if item.color then row.swatch:SetColorTexture(item.color[1], item.color[2], item.color[3], 1) end
        row:SetEnabled(not (item.disabled or item.title))
        Kit.SetTextColor(row.text, item.title and "header" or (item.disabled and "textDim" or "text"))
        row:Show()
        width = math.max(width, row.text:GetStringWidth() + 40)
    end
    for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(math.min(width, 320), #items * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    blocker:Show()
    menu:Show()
end

function Kit.CloseMenu()
    if preview then preview:Hide() end
    if menu then menu:Hide() end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function PaintWindow(win, T)
    Box(win, T, "bg", "border", "window")
    local inset, pad = T.inset or 1, T.pad or 8
    local header = win.header
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", inset, -inset)
    header:SetPoint("TOPRIGHT", -inset, -inset)
    header:SetHeight(win.headerHeight)
    local flat = not (T.backdrop and T.backdrop.window)
    Paint(header.fill, T.bgAlt)
    header.fill:SetShown(flat)
    header.line:SetShown(flat)
    win.content:ClearAllPoints()
    win.content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", pad, -pad)
    win.content:SetPoint("BOTTOMRIGHT", -inset - pad, inset + pad)
end

-- Top-level themed window. opts:
--   name           global frame name (enables ESC via UISpecialFrames unless escape = false)
--   title, w, h, minW, minH, maxW, maxH, resizable, strata, ctx ("user" | "eui")
--   headerHeight, closeButton (default true), dragAnywhere
--   geometry       saved table with point, w, h, scale (written on move/resize)
--   onShow, onHide
function Kit.Window(opts)
    local win = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    win:Hide() -- hidden before any script is set, so onHide does not fire on creation
    win.fnCtx = opts.ctx or "user"
    win.geo = opts.geometry
    win.headerHeight = opts.headerHeight or HEADER_H
    win.minW, win.minH = opts.minW or 180, opts.minH or 120
    win:SetSize(opts.w or 320, opts.h or 380)
    win:SetFrameStrata(opts.strata or "MEDIUM")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    if opts.resizable then
        win:SetResizable(true)
        if win.SetResizeBounds then
            win:SetResizeBounds(win.minW, win.minH, opts.maxW or 900, opts.maxH or 900)
        end
    end

    local header = CreateFrame("Frame", nil, win)
    win.header = header
    header.fill = header:CreateTexture(nil, "BACKGROUND", nil, -6)
    header.fill:SetAllPoints()
    header.line = Kit.Divider(header)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")

    win.title = Kit.Text(header, 13, "header")
    win.title:SetPoint("LEFT", 10, 0)
    win.title:SetWordWrap(false)
    win.title:SetText(opts.title or "")
    win.tools = {} -- header buttons, right to left
    win.content = CreateFrame("Frame", nil, win)

    local function DragStart()
        win:StartMoving()
    end
    local function DragStop()
        win:StopMovingOrSizing()
        win:SaveGeometry()
    end
    local dragHandle = opts.dragAnywhere and win or header
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", DragStart)
    dragHandle:SetScript("OnDragStop", DragStop)

    -- Header tool buttons are laid out from the right; the title stops before the last one.
    function win:AddTool(kind, onClick, tip)
        local b = Kit.IconButton(header, 18, kind, onClick, tip)
        local prev = self.tools[#self.tools]
        if prev then
            b:SetPoint("RIGHT", prev, "LEFT", -2, 0)
        else
            b:SetPoint("RIGHT", -5, 0)
        end
        self.tools[#self.tools + 1] = b
        self.title:SetPoint("RIGHT", b, "LEFT", -6, 0)
        return b
    end
    if opts.closeButton ~= false then
        win.closeButton = win:AddTool("close", function() win:Hide() end, L["Close"])
    end

    if opts.resizable then
        local grip = CreateFrame("Button", nil, win)
        grip:SetSize(14, 14)
        grip:SetPoint("BOTTOMRIGHT", -2, 2)
        grip:SetFrameLevel(win:GetFrameLevel() + 10)
        grip.glyph = Kit.Glyph(grip, "grip", 12, "textDim")
        grip.glyph:SetPoint("CENTER")
        grip:SetScript("OnEnter", function(self) self.glyph:SetColorKey("accent") end)
        grip:SetScript("OnLeave", function(self) self.glyph:SetColorKey("textDim") end)
        grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", DragStop)
        win.grip = grip
    end

    function win:SetTitle(text) self.title:SetText(text or "") end

    function win:SaveGeometry()
        local g = self.geo
        if not g then return end
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then g.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) } end
        g.w = math.floor(self:GetWidth() + 0.5)
        g.h = math.floor(self:GetHeight() + 0.5)
    end

    function win:ApplyGeometry()
        local g = self.geo or {}
        self:ClearAllPoints()
        if type(g.point) == "table" and g.point[1] then
            self:SetPoint(g.point[1], UIParent, g.point[2] or g.point[1], g.point[3] or 0, g.point[4] or 0)
        else
            self:SetPoint(opts.point or "CENTER")
        end
        if g.w and g.h then self:SetSize(math.max(self.minW, g.w), math.max(self.minH, g.h)) end
        self:SetScale(math.max(0.5, math.min(2, g.scale or 1)))
    end

    function win:SetScaleSaved(scale)
        scale = math.max(0.5, math.min(2, scale or 1))
        self:SetScale(scale)
        if self.geo then self.geo.scale = scale end
        Kit.RefreshGlyphs()
    end

    win:SetScript("OnShow", function(self)
        Theme.CheckLive()
        if opts.onShow then opts.onShow(self) end
    end)
    win:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        Kit.CloseMenu()
        if opts.onHide then opts.onHide(self) end
    end)
    if opts.name and opts.escape ~= false then table.insert(UISpecialFrames, opts.name) end

    Bind(win, PaintWindow)
    win:ApplyGeometry()
    return win
end
