-- Helpers shared by the skin modules: undo lists for pooled widgets, hook-once marks, colour-code handling.
-- Attune's list is an AceGUI widget that is pooled across addons, so everything changed on such a widget is remembered
-- and taken back when the widget is released (see Skin.Remember / Skin.Undo). Frames Attune owns for good (its window,
-- buttons, menu) may be changed permanently.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

---------------------------------------------------------------------------
-- Once-marks and undo lists (weak: a forgotten widget costs nothing)
---------------------------------------------------------------------------

local marks = setmetatable({}, { __mode = "k" })
local undo = setmetatable({}, { __mode = "k" })

-- Frames and regions of ours that sit inside Attune's window (roots only; their children are ours too), so the probe
-- can tell our drawing from Attune's.
local mine = setmetatable({}, { __mode = "k" })

function Skin.Mine(object)
    mine[object] = true
    return object
end

function Skin.IsMine(object)
    return mine[object] == true
end

-- true the first time for this (object, tag), false afterwards.
function Skin.Once(object, tag)
    local set = marks[object]
    if not set then
        set = {}
        marks[object] = set
    end
    if set[tag] then return false end
    set[tag] = true
    return true
end

-- One key per (object, kind of change): two kinds of change on the same object (its text colour and its backdrop, say)
-- must both be remembered.
local keys = setmetatable({}, { __mode = "k" })

local function Key(object, kind)
    local set = keys[object]
    if not set then
        set = {}
        keys[object] = set
    end
    local key = set[kind]
    if not key then
        key = {}
        set[kind] = key
    end
    return key
end

-- Opens the undo list of an owner (a pooled widget); a skinned widget always has one.
function Skin.Begin(owner)
    local list = undo[owner]
    if not list then
        list = { keys = {} }
        undo[owner] = list
    end
    return list
end

function Skin.IsSkinned(owner)
    return undo[owner] ~= nil
end

-- capture() runs only the first time per key and returns the function that takes the change back.
function Skin.Remember(owner, key, capture)
    local list = Skin.Begin(owner)
    if list.keys[key] then return false end
    list.keys[key] = true
    local restore = capture()
    if restore then list[#list + 1] = restore end
    return true
end

-- Takes back everything remembered for the owner, newest first. A failing step does not stop the others.
function Skin.Undo(owner)
    local list = undo[owner]
    if not list then return end
    undo[owner] = nil
    for i = #list, 1, -1 do
        local ok, err = pcall(list[i])
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Remembered changes on single regions and frames
---------------------------------------------------------------------------

-- Alpha of a region or frame (restored on Undo).
function Skin.Alpha(owner, region, alpha)
    if type(region) ~= "table" or type(region.SetAlpha) ~= "function" then return end
    Skin.Remember(owner, Key(region, "alpha"), function()
        local previous = region:GetAlpha()
        return function() region:SetAlpha(type(previous) == "number" and previous or 1) end
    end)
    region:SetAlpha(alpha)
end

-- Backdrop colours of a BackdropTemplate frame: fill / edge = { r, g, b, a } or nil to leave one alone.
function Skin.Backdrop(owner, frame, fill, edge)
    if type(frame) ~= "table" or type(frame.SetBackdropColor) ~= "function" then return end
    Skin.Remember(owner, Key(frame, "backdrop"), function()
        local fr, fg, fb, fa = frame:GetBackdropColor()
        local er, eg, eb, ea = frame:GetBackdropBorderColor()
        return function()
            if type(fr) == "number" then frame:SetBackdropColor(fr, fg, fb, fa) end
            if type(er) == "number" then frame:SetBackdropBorderColor(er, eg, eb, ea) end
        end
    end)
    if fill then frame:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1) end
    if edge then frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1) end
end

-- Colour of a font string (restored on Undo). color = { r, g, b, a } or nil to leave it alone.
function Skin.TextColor(owner, fs, color)
    if type(fs) ~= "table" or type(fs.SetTextColor) ~= "function" or not color then return end
    Skin.Remember(owner, Key(fs, "text"), function()
        local r, g, b, a = fs:GetTextColor()
        return function()
            if type(r) == "number" then fs:SetTextColor(r, g, b, a) end
        end
    end)
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- No text shadow on a font string or edit box (Blizzard's font objects draw one; on light themes it reads as a dark smear).
-- Restored on Undo.
function Skin.NoShadow(owner, fs)
    if type(fs) ~= "table" or type(fs.SetShadowOffset) ~= "function" or type(fs.SetShadowColor) ~= "function" then return end
    Skin.Remember(owner, Key(fs, "shadow"), function()
        local x, y = fs:GetShadowOffset()
        local r, g, b, a = fs:GetShadowColor()
        return function()
            if type(x) == "number" then fs:SetShadowOffset(x, y) end
            if type(r) == "number" then fs:SetShadowColor(r, g, b, a) end
        end
    end)
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
end

-- Text colour from the theme and no shadow: how every text of Attune's that stays visible is drawn.
function Skin.FlatText(owner, fs, color)
    Skin.TextColor(owner, fs, color)
    Skin.NoShadow(owner, fs)
end

-- Vertex colour (tint) of a texture (restored on Undo).
function Skin.VertexColor(owner, tex, color)
    if type(tex) ~= "table" or type(tex.SetVertexColor) ~= "function" or not color then return end
    Skin.Remember(owner, Key(tex, "vertex"), function()
        local r, g, b, a = tex:GetVertexColor()
        return function()
            if type(r) == "number" then tex:SetVertexColor(r, g, b, a) end
        end
    end)
    tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

-- Takes a frame's backdrop away (restored on Undo) so that a flat box of ours can be drawn on it instead.
function Skin.ClearBackdrop(owner, frame)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then return end
    Skin.Remember(owner, Key(frame, "clear"), function()
        local def = type(frame.GetBackdrop) == "function" and frame:GetBackdrop() or nil
        local fr, fg, fb, fa, er, eg, eb, ea
        if type(frame.GetBackdropColor) == "function" then
            fr, fg, fb, fa = frame:GetBackdropColor()
            er, eg, eb, ea = frame:GetBackdropBorderColor()
        end
        return function()
            if def then
                frame:SetBackdrop(def)
                if type(fr) == "number" then frame:SetBackdropColor(fr, fg, fb, fa) end
                if type(er) == "number" then frame:SetBackdropBorderColor(er, eg, eb, ea) end
            end
        end
    end)
    frame:SetBackdrop(nil)
end

-- A flat fill and 1 px edge drawn on one of Attune's own frames (never on pooled widgets), repainted with the theme.
-- Its regions are marked as ours for the window scan. bgKey / edgeKey are theme tokens or nil.
function Skin.Boxed(frame, bgKey, edgeKey)
    local Theme = ns.Theme
    Theme.Bind(frame, function(self, T)
        if not self.fnBoxOff then Theme.Box(self, T, bgKey, edgeKey) end
    end)
    local box = frame.fnBox
    if box then
        Skin.Mine(box.bg)
        for _, edge in ipairs(box.edges) do Skin.Mine(edge) end
    end
end

-- Takes the box back (module switched off): the pieces hide and stay hidden through theme changes.
function Skin.Unbox(frame)
    local box = type(frame) == "table" and frame.fnBox or nil
    if not box then return end
    frame.fnBoxOff = true
    box.bg:Hide()
    for _, edge in ipairs(box.edges) do edge:Hide() end
end

-- A thin themed scroll bar over one of Attune's own sliders (never a pooled one): the slider keeps working and stays
-- where it is, its art is made invisible, a 5 px track and a thumb of ours mirror it. Returns { track, thumb }, nil
-- when the slider has no thumb texture to follow. Call once per bar; its show/hide hooks run as module moduleId.
function Skin.ThinBar(owner, bar, horizontal, moduleId)
    local Theme = ns.Theme
    local thumbTex = type(bar) == "table" and type(bar.GetThumbTexture) == "function" and bar:GetThumbTexture() or nil
    if not thumbTex then return nil end
    for _, region in ipairs({ bar:GetRegions() }) do Skin.Alpha(owner, region, 0) end
    Skin.Alpha(owner, thumbTex, 0)
    for _, child in ipairs({ bar:GetChildren() }) do Skin.Conceal(owner, child) end
    local parent = bar:GetParent() or bar
    local s = { owner = owner }
    s.track = Skin.Mine(CreateFrame("Frame", nil, parent))
    s.thumb = Skin.Mine(CreateFrame("Frame", nil, parent))
    s.track.fill = s.track:CreateTexture(nil, "BACKGROUND")
    s.track.fill:SetAllPoints()
    s.thumb.fill = s.thumb:CreateTexture(nil, "BACKGROUND")
    s.thumb.fill:SetAllPoints()
    Theme.Bind(s.track, function(self, T) Theme.Paint(self.fill, T.track) end)
    Theme.Bind(s.thumb, function(self, T) Theme.Paint(self.fill, T.thumb) end)
    local level = bar:GetFrameLevel()
    s.track:SetFrameLevel(level + 1)
    s.thumb:SetFrameLevel(level + 2)
    s.track:SetFrameStrata(bar:GetFrameStrata())
    s.thumb:SetFrameStrata(bar:GetFrameStrata())
    s.track:ClearAllPoints()
    if horizontal then
        s.track:SetPoint("LEFT", bar, "LEFT", 0, 0)
        s.track:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        s.track:SetHeight(5)
        s.thumb:SetSize(math.max(16, thumbTex:GetWidth() or 16), 5)
    else
        s.track:SetPoint("TOP", bar, "TOP", 0, 0)
        s.track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
        s.track:SetWidth(5)
        s.thumb:SetSize(5, math.max(16, thumbTex:GetHeight() or 16))
    end
    s.thumb:ClearAllPoints()
    s.thumb:SetPoint("CENTER", thumbTex, "CENTER", 0, 0)
    local function Follow()
        local shown = bar:IsShown() and true or false
        s.track:SetShown(shown)
        s.thumb:SetShown(shown)
    end
    ns.Attune.HookScript(bar, "OnShow", Follow, moduleId)
    ns.Attune.HookScript(bar, "OnHide", Follow, moduleId)
    Follow()
    return s
end

-- Invisible and not clickable (restored on Undo). For Attune parts we replace with our own.
function Skin.Conceal(owner, frame)
    if type(frame) ~= "table" or type(frame.SetAlpha) ~= "function" then return end
    Skin.Remember(owner, Key(frame, "conceal"), function()
        local alpha = frame:GetAlpha()
        local mouse = type(frame.IsMouseEnabled) == "function" and frame:IsMouseEnabled() or nil
        return function()
            frame:SetAlpha(type(alpha) == "number" and alpha or 1)
            if mouse ~= nil and type(frame.EnableMouse) == "function" then frame:EnableMouse(mouse) end
        end
    end)
    frame:SetAlpha(0)
    if type(frame.EnableMouse) == "function" then frame:EnableMouse(false) end
end

-- Hidden (restored on Undo). Also for regions whose alpha the client sets back by itself (a button's text gets its
-- font object again on hover; a texture's colour alpha is its alpha).
function Skin.HideFrame(owner, frame)
    if type(frame) ~= "table" or type(frame.Hide) ~= "function" then return end
    Skin.Remember(owner, Key(frame, "hide"), function()
        local shown = frame:IsShown()
        return function() frame:SetShown(shown and true or false) end
    end)
    frame:Hide()
end

-- Every anchor of a frame as a list, and the way back.
function Skin.Points(frame)
    local list = {}
    local count = type(frame.GetNumPoints) == "function" and frame:GetNumPoints() or 0
    if type(count) ~= "number" then count = 0 end
    for i = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        if point then list[#list + 1] = { point, relativeTo, relativePoint, x, y } end
    end
    return list
end

function Skin.RestorePoints(frame, list)
    frame:ClearAllPoints()
    for _, p in ipairs(list) do frame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

-- Hides the texture art of a Blizzard button template (own frames of Attune only, no undo).
function Skin.StripTextures(frame)
    if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if type(region) == "table" and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Pixels and shapes
---------------------------------------------------------------------------

-- UI units per physical screen pixel at scale 1.
function Skin.PixelFactor()
    if PixelUtil and type(PixelUtil.GetPixelToUIUnitFactor) == "function" then
        local factor = PixelUtil.GetPixelToUIUnitFactor()
        if type(factor) == "number" and factor > 0 then return factor end
    end
    if type(GetPhysicalScreenSize) == "function" then
        local _, h = GetPhysicalScreenSize()
        if type(h) == "number" and h > 0 then return 768 / h end
    end
    return 1
end

-- Size of one physical pixel in a frame's own units (UI scale, window scale and chain zoom included).
function Skin.Pixel(frame)
    local scale = frame and frame:GetEffectiveScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return Skin.PixelFactor() / scale
end

-- Physical pixels per UI unit at the UI's own scale, rounded: 1 on usual screens, 2-3 on high-density ones.
-- Pixel measures of the design ("3 px at 100 %") are multiplied by it so they keep their weight there.
function Skin.Density()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return math.max(1, math.floor(scale / Skin.PixelFactor() + 0.5))
end

local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- Capsule (pill) on a frame of ours: a 1 px edge and a fill, each two round caps (circle mask) and a middle bar.
-- Without mask support the caps stay square. Call :Layout() after the frame's size changed, :SetColors(fill, edge).
function Skin.Pill(frame)
    local pill = { frame = frame, layers = {} }
    for index = 1, 2 do -- 1 = edge (outer), 2 = fill (inset by one pixel)
        local layer = {}
        for _, part in ipairs({ "left", "mid", "right" }) do
            local tex = frame:CreateTexture(nil, "BACKGROUND", nil, index)
            if part ~= "mid" and type(frame.CreateMaskTexture) == "function" and type(tex.AddMaskTexture) == "function" then
                local mask = frame:CreateMaskTexture()
                mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(tex)
                tex:AddMaskTexture(mask)
            end
            layer[part] = tex
        end
        pill.layers[index] = layer
    end
    function pill:Layout()
        local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
        local px = Skin.Pixel(frame)
        for index, layer in ipairs(self.layers) do
            local inset = index == 2 and px or 0
            local d = math.max(0, h - inset * 2)
            local cap = math.min(d, w - inset * 2)
            layer.left:ClearAllPoints()
            layer.left:SetPoint("LEFT", frame, "LEFT", inset, 0)
            layer.left:SetSize(cap, d)
            layer.right:ClearAllPoints()
            layer.right:SetPoint("RIGHT", frame, "RIGHT", -inset, 0)
            layer.right:SetSize(cap, d)
            layer.mid:ClearAllPoints()
            layer.mid:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + d / 2, -inset)
            layer.mid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(inset + d / 2), inset)
        end
    end
    function pill:SetColors(fill, edge)
        for _, tex in pairs(self.layers[1]) do ns.Theme.Paint(tex, edge or fill) end
        for _, tex in pairs(self.layers[2]) do ns.Theme.Paint(tex, fill) end
    end
    pill:Layout()
    return pill
end

---------------------------------------------------------------------------
-- Text and colour
---------------------------------------------------------------------------

-- Attune writes |cAARRGGBB ... |r into its list texts; the skin colours by theme instead.
function Skin.Plain(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

-- "|cffrrggbb" escape of a theme colour token ({ r, g, b, a }).
function Skin.Hex(color)
    local function Byte(v) return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5))) end
    return ("|cff%02x%02x%02x"):format(Byte(color[1]), Byte(color[2]), Byte(color[3]))
end

function Skin.Upper(text)
    local upper = _G.strupper or string.upper
    return upper(text)
end

-- Colour with its own alpha ({ r, g, b, a }).
function Skin.With(color, alpha)
    return { color[1], color[2], color[3], alpha }
end
