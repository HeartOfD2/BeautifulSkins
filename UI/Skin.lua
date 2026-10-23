-- Generic restyling helpers for the flat look: own background and 1 px border, template buttons, check boxes, close
-- buttons, scroll bars, input boxes, backdrops and text colours. Nothing of the skinned addon is replaced: template art
-- is faded out (alpha 0), colours are re-applied after the addon sets its own (post-hooks), and our state lives in weak
-- tables, never on the addon's frames. Every helper is idempotent.
local _, ns = ...
local C = ns.Colors
local T = ns.T

local Skin = {}
ns.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }

local function Weak() return setmetatable({}, { __mode = "k" }) end

local own = Weak()     -- frame -> { bg, edges, hover }
local hooks = Weak()   -- object -> { [method] = true }
local busy = Weak()    -- object -> true while we re-apply (our own call must not trigger the hook again)
local done = Weak()    -- object -> kind it was skinned as
local wantBg = Weak()  -- backdrop frame -> colour the addon asked for last

Skin.done = done

-- hooksecurefunc once per object and method.
function Skin.Hook(obj, method, fn)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return end
    local h = hooks[obj]
    if not h then
        h = {}
        hooks[obj] = h
    end
    if h[method] then return end
    h[method] = true
    hooksecurefunc(obj, method, fn)
end

-- Runs fn(obj) with the busy flag set, so post-hooks on obj ignore our own calls.
function Skin.Quiet(obj, fn, ...)
    busy[obj] = true
    local ok, err = pcall(fn, obj, ...)
    busy[obj] = nil
    if not ok then geterrorhandler()(err) end
end

function Skin.IsBusy(obj)
    return busy[obj] == true
end

local function Fade(region)
    if T(region) and region.SetAlpha then region:SetAlpha(0) end
end
Skin.Fade = Fade

local function Named(obj, suffix)
    local name = obj.GetName and obj:GetName()
    return name and rawget(_G, name .. suffix) or nil
end

-- ------------------------------------------------------------------------------------------------- flat panel

-- Own background and 1 px border on frame (created once, recoloured on every call).
function Skin.Flat(frame, color, alpha, border)
    local d = own[frame] or {}
    own[frame] = d
    if not d.bg then
        d.edges = {}
        d.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetAllPoints(frame)
        for i = 1, 4 do d.edges[i] = frame:CreateTexture(nil, "BORDER", nil, 7) end
        local e = d.edges
        e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(1)
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
        e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(1)
        e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
    end
    local c = color or C.panel
    d.bg:SetColorTexture(c[1], c[2], c[3], alpha or C.panelAlpha)
    local b = border or C.border
    for i = 1, 4 do d.edges[i]:SetColorTexture(b[1], b[2], b[3], b[4] or 1) end
    d.bg:Show()
    for i = 1, 4 do d.edges[i]:Show() end
    return d
end

function Skin.HideFlat(frame)
    local d = own[frame]
    if not (d and d.bg) then return end
    d.bg:Hide()
    for i = 1, 4 do d.edges[i]:Hide() end
end

-- Accent overlay while the mouse is over frame.
function Skin.Hover(frame, alpha)
    local d = own[frame] or {}
    own[frame] = d
    if d.hover then return end
    d.hover = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    d.hover:SetPoint("TOPLEFT", 1, -1)
    d.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    d.hover:Hide()
    frame:HookScript("OnEnter", function()
        local r, g, b = ns.Accent()
        d.hover:SetColorTexture(r, g, b, alpha or 0.22)
        d.hover:Show()
    end)
    frame:HookScript("OnLeave", function() d.hover:Hide() end)
end

-- ------------------------------------------------------------------------------------------------- text

local function Goldish(r, g, b)
    return r > 0.85 and g > 0.6 and g < 0.92 and b < 0.35
end

-- Colour we show instead of the one the addon asked for, or nil to keep it: dark text (written for parchment) becomes
-- light, the classic gold of headings becomes the accent; quality colours and white stay.
function Skin.MapTextColor(r, g, b)
    if type(r) ~= "number" or ns.IsSecret(r) then return nil end
    -- "dark" by the brightest channel, so blue and purple item names (dark by luminance) keep their colour
    if math.max(r, g or 0, b or 0) < 0.5 then return C.text[1], C.text[2], C.text[3] end
    if Goldish(r, g, b) then
        local ar, ag, ab = ns.Accent()
        return ns.Mix(ar, 1, 0.15), ns.Mix(ag, 1, 0.15), ns.Mix(ab, 1, 0.15)
    end
    return nil
end

local function FixText(fs, r, g, b, a)
    local nr, ng, nb = Skin.MapTextColor(r, g, b)
    if nr then Skin.Quiet(fs, fs.SetTextColor, nr, ng, nb, a or 1) end
end

-- Text colour rule on a FontString, now and whenever the addon sets a new colour.
function Skin.Text(fs)
    if done[fs] then return end
    done[fs] = "text"
    Skin.Hook(fs, "SetTextColor", function(self, r, g, b, a)
        if busy[self] then return end
        FixText(self, r, g, b, a)
    end)
    local r, g, b, a = fs:GetTextColor()
    FixText(fs, r, g, b, a)
end

-- ------------------------------------------------------------------------------------------------- font objects

local fontObjects = {}

-- A font object with the face and size fs has now and our colour for a button state.
local function StateFont(fs, state)
    local path, size, flags = fs:GetFont()
    if not path then return nil end
    local key = ("%s|%s|%s|%s"):format(path, tostring(size), tostring(flags), state)
    local fo = fontObjects[key]
    if not fo then
        fo = CreateFont(("BeautifulSkinsButtonFont%d"):format(#fontObjects + 1))
        fontObjects[#fontObjects + 1] = fo
        fontObjects[key] = fo
        fo:SetFont(path, size or 12, flags or "")
        fo:SetShadowOffset(1, -1)
        fo:SetShadowColor(0, 0, 0, 0.8)
        local c = state == "disabled" and C.dim or (state == "highlight" and { 1, 1, 1 } or C.text)
        fo:SetTextColor(c[1], c[2], c[3])
    end
    return fo
end

local function ButtonFonts(btn)
    local fs = btn.GetFontString and btn:GetFontString()
    if not fs then return end
    local normal, highlight, disabled = StateFont(fs, "normal"), StateFont(fs, "highlight"), StateFont(fs, "disabled")
    if normal and btn.SetNormalFontObject then
        btn:SetNormalFontObject(normal)
        btn:SetHighlightFontObject(highlight)
        btn:SetDisabledFontObject(disabled)
    end
end

-- ------------------------------------------------------------------------------------------------- widgets

local TEMPLATE_PARTS = { "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled",
    "HighlightLeft", "HighlightMiddle", "HighlightRight", "LeftSeparator", "RightSeparator" }

-- A button made from UIPanelButtonTemplate (or a look-alike with Left/Middle/Right).
function Skin.IsTemplateButton(btn)
    return (T(btn.Left) and T(btn.Middle) and T(btn.Right)) ~= nil or Named(btn, "Middle") ~= nil
end

function Skin.Button(btn)
    if done[btn] then return end
    done[btn] = "button"
    for _, part in ipairs(TEMPLATE_PARTS) do
        Fade(btn[part])
        Fade(Named(btn, part))
    end
    Fade(btn.GetNormalTexture and btn:GetNormalTexture())
    Fade(btn.GetPushedTexture and btn:GetPushedTexture())
    Fade(btn.GetHighlightTexture and btn:GetHighlightTexture())
    Fade(btn.GetDisabledTexture and btn:GetDisabledTexture())
    Skin.Flat(btn, C.control, 1)
    Skin.Hover(btn)
    ButtonFonts(btn)
end

function Skin.Check(check)
    if done[check] then return end
    done[check] = "check"
    Fade(check:GetNormalTexture())
    Fade(check:GetPushedTexture())
    Fade(check:GetHighlightTexture())
    Fade(check.GetDisabledTexture and check:GetDisabledTexture())
    local w = check:GetWidth() or 16
    local pad = (ns.CanAccess(w) and w >= 24) and 6 or 1
    local box = CreateFrame("Frame", nil, check)
    box:SetPoint("TOPLEFT", pad, -pad)
    box:SetPoint("BOTTOMRIGHT", -pad, pad)
    box:SetFrameLevel(math.max(0, check:GetFrameLevel() - 1))
    Skin.Flat(box, C.inset, 1, { 0.25, 0.25, 0.25 })
    local function Paint(tex, dim)
        if not tex then return end
        tex:SetTexture(WHITE)
        local r, g, b = ns.Accent()
        if dim then r, g, b = C.dim[1], C.dim[2], C.dim[3] end
        tex:SetVertexColor(r, g, b, 1)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
        tex:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    end
    Paint(check:GetCheckedTexture())
    Paint(check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture(), true)
    check:HookScript("OnEnter", function()
        local r, g, b = ns.Accent()
        own[box].edges[1]:SetColorTexture(r, g, b, 1)
        for i = 2, 4 do own[box].edges[i]:SetColorTexture(r, g, b, 1) end
    end)
    check:HookScript("OnLeave", function()
        for i = 1, 4 do own[box].edges[i]:SetColorTexture(0.25, 0.25, 0.25, 1) end
    end)
    local label = T(check.Text) or T(check.text) or Named(check, "Text")
    if label and label.GetTextColor then Skin.Text(label) end
end

function Skin.Close(btn)
    if done[btn] then return end
    done[btn] = "close"
    Fade(btn:GetNormalTexture())
    Fade(btn:GetPushedTexture())
    Fade(btn:GetHighlightTexture())
    Fade(btn.GetDisabledTexture and btn:GetDisabledTexture())
    for _, region in ipairs({ btn:GetRegions() }) do
        if region:GetObjectType() == "Texture" then Fade(region) end
    end
    local x = btn:CreateFontString(nil, "OVERLAY")
    ns.SetFont(x, STANDARD_TEXT_FONT, 18, "")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("\195\151") -- multiplication sign
    x:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
    btn:HookScript("OnEnter", function() x:SetTextColor(ns.Accent()) end)
    btn:HookScript("OnLeave", function() x:SetTextColor(C.soft[1], C.soft[2], C.soft[3]) end)
end

local function ScrollButton(bar, key, suffix)
    return T(bar[key]) or Named(bar, suffix)
end

function Skin.ScrollBar(bar)
    if done[bar] then return end
    done[bar] = "scrollbar"
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    for _, region in ipairs({ bar:GetRegions() }) do
        if region ~= thumb and region:GetObjectType() == "Texture" then Fade(region) end
    end
    for _, b in ipairs({ ScrollButton(bar, "ScrollUpButton", "ScrollUpButton"),
        ScrollButton(bar, "ScrollDownButton", "ScrollDownButton") }) do
        if b then
            for _, region in ipairs({ b:GetRegions() }) do Fade(region) end
            Fade(b:GetNormalTexture()); Fade(b:GetPushedTexture()); Fade(b:GetDisabledTexture()); Fade(b:GetHighlightTexture())
        end
    end
    local track = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    track:SetWidth(4)
    track:SetColorTexture(1, 1, 1, 0.06)
    if thumb then
        thumb:SetTexture(WHITE)
        local r, g, b = ns.Accent()
        thumb:SetVertexColor(r, g, b, 0.7)
        thumb:SetWidth(4)
    end
end

function Skin.EditBox(box)
    if done[box] then return end
    done[box] = "edit"
    for _, part in ipairs({ "Left", "Middle", "Right", "Mid" }) do
        Fade(T(box[part]))
        Fade(Named(box, part))
    end
    local holder = CreateFrame("Frame", nil, box)
    holder:SetPoint("TOPLEFT", -5, 0)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    holder:SetFrameLevel(math.max(0, box:GetFrameLevel() - 1))
    Skin.Flat(holder, C.inset, 1, { 0.25, 0.25, 0.25 })
end

-- ------------------------------------------------------------------------------------------------- backdrops

-- Colour we paint instead of a backdrop colour the addon asked for: dark fills become our greys, light fills (a
-- selected tab, a picked card) become a faint accent.
function Skin.MapFill(r, g, b, a)
    if type(r) ~= "number" or ns.IsSecret(r) then return C.panel[1], C.panel[2], C.panel[3], C.panelAlpha end
    local lum = ns.Luminance(r, g, b)
    if lum >= 0.3 then
        local ar, ag, ab = ns.Accent()
        return ar, ag, ab, 0.25
    end
    local v = ns.Clamp(0.035 + lum * 0.55, 0.035, 0.15, 0.067)
    return v, v, v, a or 1
end

local function PaintBackdrop(frame)
    local want = wantBg[frame] or { 0, 0, 0, 0.9 }
    local r, g, b, a = Skin.MapFill(want[1], want[2], want[3], want[4])
    Skin.Quiet(frame, function(f)
        f:SetBackdrop(FLAT)
        f:SetBackdropColor(r, g, b, a)
        f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
end

-- A BackdropTemplate frame: flat backdrop with our colours, kept after the addon sets its own again.
function Skin.Backdrop(frame)
    if done[frame] or not frame.SetBackdrop then return end
    local info = frame.backdropInfo
    if type(info) ~= "table" then return end
    done[frame] = "backdrop"
    if frame.GetBackdropColor then
        local r, g, b, a = frame:GetBackdropColor()
        if type(r) == "number" then wantBg[frame] = { r, g, b, a } end
    end
    if not (info.bgFile) then wantBg[frame] = { 0, 0, 0, 0 } end
    Skin.Hook(frame, "SetBackdrop", function(self, newInfo)
        if busy[self] then return end
        if type(newInfo) == "table" and not newInfo.bgFile then wantBg[self] = { 0, 0, 0, 0 } end
        PaintBackdrop(self)
    end)
    Skin.Hook(frame, "SetBackdropColor", function(self, r, g, b, a)
        if busy[self] then return end
        wantBg[self] = { r, g, b, a }
        PaintBackdrop(self)
    end)
    Skin.Hook(frame, "SetBackdropBorderColor", function(self)
        if busy[self] then return end
        Skin.Quiet(self, self.SetBackdropBorderColor, C.border[1], C.border[2], C.border[3], 1)
    end)
    PaintBackdrop(frame)
end

-- ------------------------------------------------------------------------------------------------- textures

-- A texture that must stay a flat colour (a parchment, a fill), also after the addon sets it again.
function Skin.Solid(tex, color, alpha)
    if not (T(tex) and tex.SetColorTexture) then return end
    local function Paint(self)
        Skin.Quiet(self, self.SetColorTexture, color[1], color[2], color[3], alpha or 1)
    end
    if done[tex] ~= "solid" then
        done[tex] = "solid"
        Skin.Hook(tex, "SetTexture", function(self) if not busy[self] then Paint(self) end end)
        Skin.Hook(tex, "SetColorTexture", function(self) if not busy[self] then Paint(self) end end)
        Skin.Hook(tex, "SetAtlas", function(self) if not busy[self] then Paint(self) end end)
    end
    Paint(tex)
end

-- A colour-fill texture (SetColorTexture) that keeps its role but gets our shade: every colour the addon sets is
-- mapped like a backdrop fill (dark fills become our greys, light ones a faint accent).
function Skin.Fill(tex)
    if not (T(tex) and tex.SetColorTexture) or done[tex] == "fill" or done[tex] == "solid" then return end
    done[tex] = "fill"
    Skin.Hook(tex, "SetColorTexture", function(self, r, g, b, a)
        if busy[self] then return end
        Skin.Quiet(self, self.SetColorTexture, Skin.MapFill(r, g, b, a))
    end)
    Skin.Quiet(tex, tex.SetColorTexture, C.inset[1], C.inset[2], C.inset[3], 1)
end

-- A texture that must stay invisible (a gold edge, a portrait ring).
function Skin.Hide(region)
    if not (T(region) and region.SetAlpha) then return end
    if done[region] ~= "hidden" then
        done[region] = "hidden"
        Skin.Hook(region, "SetAlpha", function(self, a)
            if busy[self] or a == 0 then return end
            Skin.Quiet(self, self.SetAlpha, 0)
        end)
    end
    Skin.Quiet(region, region.SetAlpha, 0)
end

-- ------------------------------------------------------------------------------------------------- tree walk

local function Children(frame)
    if not frame.GetChildren then return {} end
    return { frame:GetChildren() }
end

local function Regions(frame)
    if not frame.GetRegions then return {} end
    return { frame:GetRegions() }
end

-- visit(object, objectType) for frame, its regions and all descendants (forbidden or protected frames are skipped).
function Skin.Walk(frame, visit, depth)
    depth = depth or 0
    if depth > 30 or type(frame) ~= "table" then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    visit(frame, frame:GetObjectType())
    for _, region in ipairs(Regions(frame)) do
        visit(region, region:GetObjectType())
    end
    for _, child in ipairs(Children(frame)) do
        Skin.Walk(child, visit, depth + 1)
    end
end

-- The standard rule set for a whole window of another addon.
function Skin.Auto(object, kind)
    if done[object] then return end
    if kind == "FontString" then
        Skin.Text(object)
    elseif kind == "CheckButton" then
        if object.GetCheckedTexture and object:GetCheckedTexture() then Skin.Check(object) end
    elseif kind == "Button" then
        if Skin.IsTemplateButton(object) then
            Skin.Button(object)
        elseif object.backdropInfo then
            Skin.Backdrop(object)
            Skin.Hover(object, 0.15)
        end
    elseif kind == "Slider" then
        if object.GetThumbTexture and (T(object.ScrollUpButton) or Named(object, "ScrollUpButton")) then
            Skin.ScrollBar(object)
        end
    elseif kind == "EditBox" then
        if T(object.Left) or Named(object, "Left") or T(object.Middle) or Named(object, "Mid") then Skin.EditBox(object) end
    elseif kind == "Frame" then
        if object.backdropInfo then Skin.Backdrop(object) end
        if T(object.NineSlice) then Skin.Hide(object.NineSlice) end
    end
end
