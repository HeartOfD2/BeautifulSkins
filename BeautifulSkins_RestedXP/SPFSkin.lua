-- ShortestPathForever skin: the Journey section of SPF's tracker column and SPF's compass in the EllesmereUI look, the
-- routes and their markers on the minimap, the world map and the screen in the accent colour.
-- Only SPF's own frames are touched, through post-hooks and restyling; no SPF function is replaced and no key is
-- written onto SPF's frames (all state lives in weak tables here). Switching a part off gives SPF its own look back.
local _, ns = ...
local L = ns.L

local Mix, Try = ns.Mix, ns.Try

local TRACKER_NAME = "ShortestPathForeverObjectiveTracker" -- SPF's Journey module (ObjectiveTrackerModuleTemplate)
local COLUMN_NAME = "ForeverTrackerCompanion" -- the shared Forever column that hosts the module
local COMPASS_NAME = "ShortestPathForeverCompass" -- created by SPF the first time the compass is shown
local MINIMAP_NAME = "ShortestPathForeverMinimapRoute" -- SPF's route on the minimap (UI/Route.lua)
local SCREEN_PIN_NAME = "ShortestPathForeverDestinationPin" -- created by SPF the first time it is needed

-- EllesmereUI quest tracker defaults, used when its own settings cannot be read.
local QT_TITLE = { 1.0, 0.910, 0.471 }
local QT_BG = { 0.035, 0.035, 0.035 }
local QT_SIZE = { header = 13, title = 12, line = 10 }
local LINE_TEXT = { 0.72, 0.72, 0.72 } -- EUI objective grey
local LINE_DIM = { 0.45, 0.45, 0.45 } -- SPF's greyed rows
local WHITE = { 1, 1, 1 }

-- SPF's own compass colours and centre size (UI/Compass.lua, 1.35.0), put back when the compass skin is switched off;
-- the quieter green ones while a stop's area is reached (frame.arrived, since 1.25.0).
local SPF_TICK = { 0.72, 0.67, 0.55, 0.9 }
local SPF_CENTER = { 1, 0.82, 0, 1 }
local SPF_ARRIVED_TICK = { 0.6, 0.76, 0.58, 0.9 }
local SPF_ARRIVED_CENTER = { 0.62, 0.9, 0.55, 1 }
local SPF_CENTER_SIZE = { 2, 12 }

local function Weak() return setmetatable({}, { __mode = "k" }) end

local origFont = Weak()   -- FontString -> { obj, path, size, flags } before our first change
local origColor = Weak()  -- FontString -> { r, g, b } before our first change
local fontSig = Weak()    -- FontString -> signature of the font we applied (skip identical re-applies)
local baseStyle = Weak()  -- FontString -> colour style SPF asked for (before Blizzard's hover reversal)
local origAtlas = Weak()  -- Texture -> atlas we blanked
local hookedBlock = Weak()
local own = Weak()        -- SPF frame -> our textures on it { bg, divider } / { top, bottom }
local spfLine = Weak()    -- SPF's route line -> { r, g, b, a } SPF last gave it
local lineOwners = Weak() -- frame that holds route lines -> how many of them are hooked
local marks = Weak()      -- SPF's marker texture -> { r, g, b, desaturated, atlas, forced }
local seenPin = Weak()    -- SPF's world map pin -> true once hooked
local stopNumber = Weak() -- SPF's numbered stop pin -> { r, g, b } SPF gave its number

local S = {
    trackerHooked = false, compassHooked = false, compassAlpha = nil, busy = false,
    centerHooked = false, painting = false, -- the compass centre's paint hook, and our own paint of it
    minimapHooked = false, tint = nil, tinting = false, watcher = nil, wait = 0, mapLayer = nil, pinCount = nil,
    look = nil, canvasChildren = nil, layerWalks = 0, -- the canvas walks of FindLayer
}

-- ---------------------------------------------------------------------------------------------------------------
-- Settings and look sources

local function Cfg()
    return ns.db and ns.db.spfSkin
end

local function SkinAllowed()
    return not (ns.SkinningOff())
end

local function JourneyOn()
    local c = Cfg()
    return c ~= nil and c.journey == true and SkinAllowed()
end

local function CompassOn()
    local c = Cfg()
    return c ~= nil and c.compass == true and SkinAllowed()
end

local function MinimapRouteOn()
    local c = Cfg()
    return c ~= nil and c.minimapRoute == true and SkinAllowed()
end

-- EllesmereUIQuestTracker's settings (read only), so the Journey matches the quest list under it.
local function TrackerDb()
    local db = _G._EQT_DB
    local profile = type(db) == "table" and db.profile
    local qt = type(profile) == "table" and profile.questTracker
    if type(qt) == "table" then return qt end
end

local function Num(v, default)
    if type(v) == "number" and v == v then return v end
    return default
end

local function Sizes()
    local qt = TrackerDb() or {}
    return Num(qt.headerFontSize, QT_SIZE.header), Num(qt.titleFontSize, QT_SIZE.title), Num(qt.objectiveFontSize, QT_SIZE.line)
end

local function TitleColor()
    local qt = TrackerDb()
    if qt then return { Num(qt.titleR, QT_TITLE[1]), Num(qt.titleG, QT_TITLE[2]), Num(qt.titleB, QT_TITLE[3]) } end
    return QT_TITLE
end

-- The quest tracker's background when EllesmereUIQuestTracker is there, else the guide window colour.
local function BackgroundColor()
    local qt = TrackerDb()
    if qt and type(qt.bgR) == "number" then return Num(qt.bgR, QT_BG[1]), Num(qt.bgG, QT_BG[2]), Num(qt.bgB, QT_BG[3]) end
    local r, g, b = ns.CustomBackground()
    if r then return r, g, b end
    local p = ns.PANEL_BG
    return p[1], p[2], p[3]
end

local function WindowColor()
    local r, g, b = ns.CustomBackground()
    if r then return r, g, b end
    return 0x16 / 255, 0x16 / 255, 0x18 / 255
end

-- Font of the EllesmereUI quest tracker (falls back to the EUI skin font, then the game font).
local function TrackerFont()
    local E = _G.EllesmereUI
    local path, flags, shadow
    if type(E) == "table" then
        if type(E.GetFontPath) == "function" then path = Try(E.GetFontPath, "questTracker") end
        if type(E.GetFontOutlineFlag) == "function" then flags = Try(E.GetFontOutlineFlag, "questTracker") end
        if type(E.GetFontUseShadow) == "function" then shadow = Try(E.GetFontUseShadow, "questTracker") end
    end
    if type(path) ~= "string" or path == "" then path, flags = ns.Font() end
    if type(flags) ~= "string" then flags = "" end
    if shadow == nil then shadow = flags == "" end
    shadow = shadow and true or false
    return { path = path, flags = flags, shadow = shadow, sig = path .. "|" .. flags .. "|" .. tostring(shadow) .. "|" }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Font, colour and texture helpers (remember the original once, restore on demand)

local function RememberFont(fs)
    if origFont[fs] then return end
    local path, size, flags = fs:GetFont()
    origFont[fs] = { obj = fs:GetFontObject(), path = path, size = size, flags = flags }
end

-- Returns true when the font actually changed (the caller may need a new layout).
local function StyleFont(fs, size, font)
    if not fs then return false end
    local sig = font.sig .. size
    if fontSig[fs] == sig then return false end
    RememberFont(fs)
    local E = _G.EllesmereUI
    -- A drop shadow only renders when carried by a font object (EUI's PrimeFontShadow), so prime first, then SetFont.
    if type(E) == "table" and type(E.PrimeFontShadow) == "function" then pcall(E.PrimeFontShadow, fs, font.shadow) end
    ns.SetFont(fs, font.path, size, font.flags)
    fontSig[fs] = sig
    return true
end

local function RestoreFont(fs)
    local o = fs and origFont[fs]
    if not o then return end
    if o.obj then fs:SetFontObject(o.obj) end
    if o.path and o.size then ns.SetFont(fs, o.path, o.size, o.flags or "") end
    fontSig[fs] = nil
end

local function SetColor(fs, c, highlight)
    if not fs then return end
    if not origColor[fs] then
        local r, g, b = fs:GetTextColor()
        origColor[fs] = { r or 1, g or 1, b or 1 }
    end
    local r, g, b = c[1], c[2], c[3]
    if highlight then r, g, b = Mix(r, 1, 0.35), Mix(g, 1, 0.35), Mix(b, 1, 0.35) end
    fs:SetTextColor(r, g, b)
end

-- Back to the colour style Blizzard's tracker code last applied, else to the colour before our first change.
local function RestoreColor(fs)
    if not fs then return end
    local style = fs.colorStyle
    if type(style) == "table" and type(style.r) == "number" then
        fs:SetTextColor(style.r, style.g, style.b)
    elseif origColor[fs] then
        local c = origColor[fs]
        fs:SetTextColor(c[1], c[2], c[3])
    end
end

-- Blank a decorative texture (SetTexture("") as EllesmereUI does, which no fade animation can bring back).
local function Blank(tex)
    if not tex or not tex.SetTexture then return end
    if origAtlas[tex] == nil then
        local atlas = tex.GetAtlas and tex:GetAtlas()
        origAtlas[tex] = atlas or false
    end
    tex:SetTexture("")
end

local function Unblank(tex)
    local atlas = tex and origAtlas[tex]
    if atlas then tex:SetAtlas(atlas, true) end
    if tex then origAtlas[tex] = nil end
end

local function Tint(tex, r, g, b)
    if not tex then return end
    if tex.SetDesaturated then tex:SetDesaturated(r ~= nil) end
    if tex.SetVertexColor then tex:SetVertexColor(r or 1, g or 1, b or 1) end
end

local function OnePixel(tex, horizontal)
    if PixelUtil and PixelUtil.SetHeight and horizontal then
        PixelUtil.SetHeight(tex, 1)
    elseif PixelUtil and PixelUtil.SetWidth and not horizontal then
        PixelUtil.SetWidth(tex, 1)
    elseif horizontal then
        tex:SetHeight(1)
    else
        tex:SetWidth(1)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Journey (SPF's tracker module)

local layoutQueued = false

-- Line heights are measured when SPF sets a text; after a font change SPF lays the section out again.
local function RequestLayout()
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        local module = _G[TRACKER_NAME]
        if type(module) == "table" and type(module.MarkDirty) == "function" then pcall(module.MarkDirty, module) end
    end)
end

-- Our colour for a colour style SPF asked for; nil keeps Blizzard's (failed or time-limited lines).
local function LineColor(style)
    local C = OBJECTIVE_TRACKER_COLOR
    if C and style == C.NormalHighlight then -- SPF's current step
        local c = Cfg()
        if c and c.currentAccent then
            local r, g, b = ns.Accent()
            return { r, g, b }
        end
        return WHITE
    elseif style == GRAY_FONT_COLOR then
        return LINE_DIM
    elseif C and (style == C.Header or style == C.HeaderHighlight) then
        return TitleColor()
    elseif C and style ~= nil and style ~= C.Normal and style ~= C.Complete then
        return nil
    end
    return LINE_TEXT
end

local function StyleBlockText(block, fs, font)
    if not fs then return false end
    local _, titleSize, lineSize = Sizes()
    local isTitle = fs == block.HeaderText
    local changed = StyleFont(fs, isTitle and titleSize or lineSize, font)
    local C = OBJECTIVE_TRACKER_COLOR
    local style = baseStyle[fs] or (isTitle and C and C.Header) or (C and C.Normal)
    local color = LineColor(style)
    local highlight = block.isHighlighted and true or false
    if color then SetColor(fs, color, highlight) end
    local line = not isTitle and fs:GetParent()
    if line and line.Dash and line.Text == fs then
        changed = StyleFont(line.Dash, lineSize, font) or changed
        if color then SetColor(line.Dash, color, highlight) end
    end
    return changed
end

local function EachLine(block, fn)
    if type(block.usedLines) ~= "table" then return end
    for _, line in pairs(block.usedLines) do
        if type(line) == "table" and line.Text then fn(line) end
    end
end

local function StyleBlock(block, font)
    local changed = StyleBlockText(block, block.HeaderText, font)
    EachLine(block, function(line)
        changed = StyleBlockText(block, line.Text, font) or changed
    end)
    return changed
end

local function UnstyleBlock(block)
    for _, fs in ipairs({ block.HeaderText }) do
        RestoreFont(fs)
        RestoreColor(fs)
    end
    EachLine(block, function(line)
        RestoreFont(line.Text)
        RestoreColor(line.Text)
        if line.Dash then
            RestoreFont(line.Dash)
            RestoreColor(line.Dash)
        end
    end)
end

local function HookBlock(block)
    if hookedBlock[block] then return end
    hookedBlock[block] = true
    if type(block.SetStringText) == "function" then
        hooksecurefunc(block, "SetStringText", function(self, fs, _, _, colorStyle)
            if not fs then return end
            local C = OBJECTIVE_TRACKER_COLOR
            baseStyle[fs] = colorStyle or (C and C.Normal)
            if not JourneyOn() then return end
            if StyleBlockText(self, fs, TrackerFont()) then RequestLayout() end
        end)
    end
    if type(block.UpdateHighlight) == "function" then
        hooksecurefunc(block, "UpdateHighlight", function(self)
            if JourneyOn() then StyleBlock(self, TrackerFont()) end
        end)
    end
end

local function EachBlock(module, fn)
    local used = module.usedBlocks
    if type(used) ~= "table" then return end
    for _, byTemplate in pairs(used) do
        if type(byTemplate) == "table" then
            for _, block in pairs(byTemplate) do
                if type(block) == "table" then fn(block) end
            end
        end
    end
end

local function Decor(module)
    local d = own[module]
    if not d then
        d = {}
        d.bg = module:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetPoint("TOPLEFT", module, "TOPLEFT", -6, 4)
        d.bg:SetPoint("BOTTOMRIGHT", module, "BOTTOMRIGHT", 4, -6)
        d.divider = module:CreateTexture(nil, "ARTWORK")
        OnePixel(d.divider, true)
        own[module] = d
    end
    return d
end

-- The column's drag handle ("Forever tracker") shown while the column is detached: its label is the only
-- FontString of the column's own button.
local function GripLabel()
    local column = _G[COLUMN_NAME]
    if type(column) ~= "table" or type(column.GetChildren) ~= "function" then return end
    for _, child in ipairs({ column:GetChildren() }) do
        if child:GetObjectType() == "Button" then
            for _, region in ipairs({ child:GetRegions() }) do
                if region:GetObjectType() == "FontString" then return region end
            end
        end
    end
end

local function HeaderTextures(header)
    return header.Background, header.Shine, header.Glow
end

local function MinimizeTextures(button)
    if not button then return end
    return button.GetNormalTexture and button:GetNormalTexture(),
        button.GetPushedTexture and button:GetPushedTexture(),
        button.GetHighlightTexture and button:GetHighlightTexture()
end

local function StyleModule(module)
    local font = TrackerFont()
    local headerSize = Sizes()
    local r, g, b = ns.Accent()
    local header = module.Header
    if type(header) == "table" then
        local a, s, gl = HeaderTextures(header)
        Blank(a); Blank(s); Blank(gl)
        StyleFont(header.Text, headerSize, font)
        SetColor(header.Text, { r, g, b })
        local n, p, h = MinimizeTextures(header.MinimizeButton)
        Tint(n, r, g, b); Tint(p, r, g, b); Tint(h, r, g, b)
        local d = Decor(module)
        d.divider:ClearAllPoints()
        d.divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 7, 0)
        d.divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -1, 0)
        d.divider:SetColorTexture(r, g, b, 1)
        d.divider:Show()
        local opacity = ns.Clamp(Cfg().journeyBackground, 0, 100, 75) / 100
        local br, bgc, bb = BackgroundColor()
        d.bg:SetColorTexture(br, bgc, bb, opacity)
        d.bg:SetShown(opacity > 0)
    end
    local changed = false
    EachBlock(module, function(block)
        HookBlock(block)
        changed = StyleBlock(block, font) or changed
    end)
    local grip = GripLabel()
    if grip then
        StyleFont(grip, headerSize, font)
        SetColor(grip, { r, g, b })
    end
    if changed then RequestLayout() end
end

local function UnstyleModule(module)
    local header = module.Header
    if type(header) == "table" then
        local a, s, gl = HeaderTextures(header)
        Unblank(a); Unblank(s); Unblank(gl)
        RestoreFont(header.Text)
        if header.Text and origColor[header.Text] then
            local c = origColor[header.Text]
            header.Text:SetTextColor(c[1], c[2], c[3])
        end
        local n, p, h = MinimizeTextures(header.MinimizeButton)
        Tint(n); Tint(p); Tint(h)
    end
    local d = own[module]
    if d then
        d.bg:Hide()
        d.divider:Hide()
    end
    EachBlock(module, UnstyleBlock)
    local grip = GripLabel()
    if grip then
        RestoreFont(grip)
        if origColor[grip] then
            local c = origColor[grip]
            grip:SetTextColor(c[1], c[2], c[3])
        end
    end
    RequestLayout()
end

local journeyStyled = false

local function ApplyJourney()
    local module = _G[TRACKER_NAME]
    if type(module) ~= "table" or type(module.Update) ~= "function" then return false end
    if not S.trackerHooked then
        S.trackerHooked = true
        -- The shared column lays the module out through Update; new blocks and lines only appear there.
        hooksecurefunc(module, "Update", function(self)
            if JourneyOn() then StyleModule(self) end
        end)
    end
    if JourneyOn() then
        StyleModule(module)
        journeyStyled = true
    elseif journeyStyled then
        UnstyleModule(module)
        journeyStyled = false
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Compass

local function CompassFrame()
    local f = _G[COMPASS_NAME]
    if type(f) == "table" and type(f.ticks) == "table" then return f end
end

local function CompassDecor(f)
    local d = own[f]
    if not d and f.Backdrop then
        d = {}
        d.top = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        d.top:SetPoint("TOPLEFT", f.Backdrop, "TOPLEFT", 0, 0)
        d.top:SetPoint("TOPRIGHT", f.Backdrop, "TOPRIGHT", 0, 0)
        OnePixel(d.top, true)
        d.bottom = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        d.bottom:SetPoint("BOTTOMLEFT", f.Backdrop, "BOTTOMLEFT", 0, 0)
        d.bottom:SetPoint("BOTTOMRIGHT", f.Backdrop, "BOTTOMRIGHT", 0, 0)
        OnePixel(d.bottom, true)
        own[f] = d
    end
    return d
end

local function CompassAlpha()
    if S.compassAlpha then return S.compassAlpha end
    local v = ns.SPF and ns.SPF.Get and ns.SPF.Get("compassBackground")
    return ns.Clamp(v, 0, 100, 0) / 100
end

-- The band behind the marks: SPF's opacity, our window colour, a 1 px accent edge above and below.
local function StyleBackdrop(f)
    local tex = f.Backdrop
    if not tex then return end
    local alpha = CompassAlpha()
    local d = CompassDecor(f)
    S.busy = true
    if CompassOn() then
        local r, g, b = WindowColor()
        tex:SetColorTexture(r, g, b, alpha)
    else
        tex:SetColorTexture(0, 0, 0, alpha)
    end
    S.busy = false
    if d then
        local on = CompassOn() and alpha > 0 and tex:IsShown()
        local r, g, b = ns.Accent()
        for _, line in ipairs({ d.top, d.bottom }) do
            line:SetColorTexture(r, g, b, 0.8)
            line:SetShown(on and true or false)
        end
    end
end

local function HookCompass(f)
    if S.compassHooked then return end
    S.compassHooked = true
    local tex = f.Backdrop
    if tex then
        -- SPF sets the band's opacity through SetColorTexture(0, 0, 0, opacity) and SetShown.
        hooksecurefunc(tex, "SetColorTexture", function(_, _, _, _, a)
            if S.busy then return end
            if type(a) == "number" then S.compassAlpha = a end
            StyleBackdrop(f)
        end)
        hooksecurefunc(tex, "SetShown", function()
            if not S.busy then StyleBackdrop(f) end
        end)
    end
end

local function StyleCompass(f)
    local font = TrackerFont()
    local r, g, b = ns.Accent()
    for _, tick in ipairs(f.ticks) do
        local north = tick.angle == 0
        if north then
            tick:SetColorTexture(r, g, b, 1)
        elseif tick.major then
            tick:SetColorTexture(0.92, 0.92, 0.92, 0.9)
        else
            tick:SetColorTexture(0.75, 0.75, 0.75, 0.6)
        end
        if tick.label then
            StyleFont(tick.label, 11, font)
            SetColor(tick.label, north and { r, g, b } or { 0.92, 0.92, 0.92 })
        end
    end
    if f.Center then
        S.painting = true
        f.Center:SetColorTexture(r, g, b, 1)
        S.painting = false
        f.Center:SetSize(2, 8)
    end
    StyleFont(f.Distance, 11, font)
    SetColor(f.Distance, WHITE)
    StyleFont(f.Time, 11, font)
    SetColor(f.Time, { r, g, b })
    StyleFont(f.MoverHint, 11, font)
    -- The walking marks take the accent like our arrow; the destination pin is a marker (ApplyMarks).
    Tint(f.Bend, r, g, b)
    Tint(f.Next, r, g, b)
    StyleBackdrop(f)
end

local function UnstyleCompass(f)
    local tc = f.arrived and SPF_ARRIVED_TICK or SPF_TICK
    for _, tick in ipairs(f.ticks) do
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4])
        if tick.label then
            RestoreFont(tick.label)
            RestoreColor(tick.label)
        end
    end
    if f.Center then
        local cc = f.arrived and SPF_ARRIVED_CENTER or SPF_CENTER
        S.painting = true
        f.Center:SetColorTexture(cc[1], cc[2], cc[3], cc[4])
        S.painting = false
        f.Center:SetSize(SPF_CENTER_SIZE[1], SPF_CENTER_SIZE[2])
    end
    for _, fs in ipairs({ f.Distance, f.Time, f.MoverHint }) do
        RestoreFont(fs)
        RestoreColor(fs)
    end
    Tint(f.Bend)
    Tint(f.Next)
    StyleBackdrop(f)
end

local compassStyled = false

-- SPF 1.25.0+ paints the ticks and then the centre again whenever a stop's area is reached or left (Compass.lua Paint),
-- over our colours: the centre's paint, the last of it, brings ours back in the same frame.
local function HookCompassPaint(f)
    if S.centerHooked or type(f.Center) ~= "table" then return end
    S.centerHooked = true
    hooksecurefunc(f.Center, "SetColorTexture", function()
        if S.painting or not compassStyled then return end
        StyleCompass(f)
    end)
end

local function ApplyCompass()
    local f = CompassFrame()
    if not f then return false end
    HookCompass(f)
    HookCompassPaint(f)
    if CompassOn() then
        StyleCompass(f)
        compassStyled = true
    elseif compassStyled then
        UnstyleCompass(f)
        compassStyled = false
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Route and markers in the accent colour
--
-- SPF paints routes onto pooled lines, walks as dots and everything else as flat lines, and hands every line its
-- colour again on each redraw (ten times a second on the minimap). A hook on the line's SetVertexColor answers in the
-- same call, so no redraw shows SPF's colour, and keeps that colour for switching off. The dark outlines stay.
-- The pool grows during a redraw. On the minimap each redraw ends in SPF's Pulse on the stroke layer's animation (Stop,
-- or IsPlaying while a route is planning), on the world map in the pin's Draw: new lines are picked up there, before the
-- frame is rendered.
--
-- Markers are textures: the goal pin, ring and arrow marks, the lit stop button, their glows. A texture is tinted by
-- the atlas or file it shows, so a marker that turns into a transport or flight master icon gets its own look back.
-- Since SPF 1.22.46 the goal is SPF's own gold pin, a file (media\Pin) on the world map, minimap, compass and screen;
-- since 1.22.48 the stops and the compass's turns up to 25 wear gold numbered markers, files too (media\Numbers\<n>);
-- since 1.37.0 those files are ForeverCore's (ForeverCore.Art.Marker, ForeverCore\media\Numbers\<n>).
-- OpenMap draws the game's waypoint on its stitched map itself (Map/Nav.lua, pin set "waypoint"); while SPF guides,
-- that waypoint is SPF's next bend and takes the tint too, the player's own waypoint keeps its gold.
--
-- World map: SPF keeps its pins on frames of its own, because anything written into the map taints Forever's gamepad
-- interface (SPF: UI/MapCanvas.lua). We only read the canvas's children to find SPF's pin layer, and hook SPF's pins,
-- never the map. SPF hands out no signal for new pins, so a frame of ours counts the layer's children while the map is up.

local MARK_ATLAS = {
    ["Waypoint-MapPin-Tracked"] = true, -- goal pin
    ["Navigation-Tracked-Icon"] = true, -- walking mark
    ["adventureguide-ring"] = true, -- ring round a stop with a known mark on the minimap
    ["UI-QuestPoi-QuestNumber-SuperTracked"] = true, -- the lit button of the stop being travelled to
    ["UI-QuestPoi-InnerGlow"] = true,
    ["UI-QuestPoi-OuterGlow"] = true,
}
local STOP_MARKS = { "Texture", "Button", "Glow" }
local SPF_PIN = "Interface\\AddOns\\ShortestPathForever\\media\\Pin" -- SPF's own goal pin (UI/Art.lua ns.PIN_FILE)
local SPF_NUMBERS = "Interface\\AddOns\\ShortestPathForever\\media\\Numbers\\%d" -- its numbered markers up to 1.36
local SPF_NUMBER_MAX = 25

-- The numbered marker files SPF draws: ForeverCore's (SPF 1.37.0 and later, ns.NumberFile = ForeverCore.Art.Marker),
-- and SPF's own from before.
local function NumberFiles(n)
    local fc = rawget(_G, "ForeverCore")
    local art = type(fc) == "table" and type(fc.Art) == "table" and fc.Art
    local own = SPF_NUMBERS:format(n)
    if art and type(art.Marker) == "function" then
        local file = Try(art.Marker, n)
        if type(file) == "string" then return own, file end
    end
    return own
end
local SCAN_EVERY = 0.25 -- seconds between looks for the pin layer and for SPF's screen pin

local function MinimapRoute()
    local f = _G[MINIMAP_NAME]
    if type(f) == "table" and type(f.lines) == "table" then return f end
end

local function OnLineColor(line, r, g, b, a)
    if S.tinting then return end
    local c = spfLine[line]
    c[1], c[2], c[3], c[4] = r, g, b, a
    local tint = S.tint
    if tint then
        S.tinting = true
        line:SetVertexColor(tint[1], tint[2], tint[3], a or 1)
        S.tinting = false
    end
end

-- A colour set from outside SPF's own paint. SPF sets the real alpha after the colour (it fades later hops), and setting
-- a colour clears it, so it is put back. The colour's own alpha stays SPF's: never the one GetVertexColor reports, which
-- includes SetAlpha.
local function Recolour(line, r, g, b, a)
    local alpha = line:GetAlpha()
    line:SetVertexColor(r, g, b, a or 1)
    line:SetAlpha(alpha)
end

-- A line seen for the first time still wears SPF's colour; setting it again runs it through the hook.
local function WatchLines(owner)
    local lines = owner.lines
    for index = (lineOwners[owner] or 0) + 1, #lines do
        local line = lines[index]
        spfLine[line] = {}
        hooksecurefunc(line, "SetVertexColor", OnLineColor)
        local r, g, b = line:GetVertexColor()
        Recolour(line, r, g, b)
        lineOwners[owner] = index
    end
end

-- The pin with the boat and zeppelin routes hides them by alpha until their dock is hovered. SPF's own UpdateAlpha works
-- out which lines show, so what it decided never depends on what we read back from a line.
local function SettleAlpha(owner)
    if type(owner.UpdateAlpha) == "function" then owner:UpdateAlpha() end
end

local function OnPinDrawn(pin)
    WatchLines(pin)
    SettleAlpha(pin)
end

-- The route on screen may not redraw for a while: SPF's own colour again, which the hook turns into the tint.
local function RepaintLines(owner)
    WatchLines(owner)
    for index = 1, lineOwners[owner] or 0 do
        local line = owner.lines[index]
        local c = spfLine[line]
        Recolour(line, c[1], c[2], c[3], c[4])
    end
    SettleAlpha(owner)
end

-- What GetTexture reports for SPF's own art (a path or a file id, whichever this client hands out): the goal pin and the
-- numbered markers, read once from a hidden texture of ours.
local function ArtFiles()
    if not S.artFiles then
        local files = {}
        local probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        local function Learn(path)
            if not path then return end
            probe:SetTexture(path)
            local id = probe:GetTexture()
            if id ~= nil then files[id] = true end
        end
        Learn(SPF_PIN)
        for n = 1, SPF_NUMBER_MAX do
            local own, shared = NumberFiles(n)
            Learn(own)
            Learn(shared)
        end
        probe:SetTexture(nil)
        S.artFiles = files
    end
    return S.artFiles
end

local function ShowsPin(tex)
    local file = tex.GetTexture and tex:GetTexture()
    return file ~= nil and ArtFiles()[file] == true
end

local function PaintMark(tex)
    local m = marks[tex]
    local tint = S.tint
    if tint and not m.plain and (m.forced or m.pin or MARK_ATLAS[m.atlas]) then
        tex:SetDesaturated(true)
        tex:SetVertexColor(tint[1], tint[2], tint[3])
    else
        tex:SetDesaturated(m.desaturated)
        tex:SetVertexColor(m.r, m.g, m.b)
    end
end

-- SPF sets a marker's colour once, at most, so what the texture wears at first sight is SPF's.
local function Mark(tex)
    if type(tex) ~= "table" or marks[tex] then return end
    local r, g, b = tex:GetVertexColor()
    marks[tex] = { r = r or 1, g = g or 1, b = b or 1, desaturated = tex:IsDesaturated() and true or false,
        atlas = tex:GetAtlas(), pin = ShowsPin(tex) }
    hooksecurefunc(tex, "SetAtlas", function(self, atlas)
        marks[self].atlas, marks[self].pin = atlas, false
        PaintMark(self)
    end)
    hooksecurefunc(tex, "SetTexture", function(self)
        marks[self].atlas = nil
        marks[self].pin = ShowsPin(self)
        PaintMark(self)
    end)
    PaintMark(tex)
end

-- The numbers of the stops still ahead are yellow on a dark button: they take the tint, the dark ones on the lit
-- button of the current stop stay.
local function PaintStop(pin)
    local later = not pin.current
    if marks[pin.Numeral] then -- the numeral atlas of SPF up to 1.22.47
        marks[pin.Numeral].forced = later
        PaintMark(pin.Numeral)
    end
    local c, tint = stopNumber[pin], S.tint
    if tint and later then
        pin.Number:SetTextColor(tint[1], tint[2], tint[3])
    else
        pin.Number:SetTextColor(c[1], c[2], c[3])
    end
end

local function OnStopAcquired(pin)
    local r, g, b = pin.Number:GetTextColor()
    stopNumber[pin] = { r or 1, g or 1, b or 1 }
    PaintStop(pin)
end

local function WatchPin(pin)
    if seenPin[pin] then return end
    seenPin[pin] = true
    if type(pin.lines) == "table" and type(pin.underlines) == "table" and type(pin.Draw) == "function" then
        hooksecurefunc(pin, "Draw", OnPinDrawn)
        OnPinDrawn(pin)
        return
    end
    -- The journey's stops, the flight master's tracked marks and the glow of a hovered dock; the icons stay SPF's.
    -- A stop has its font number and disc (and up to SPF 1.22.47 a numeral atlas); from 1.22.48 its numbered marker is
    -- the file on its Texture.
    if type(pin.Number) == "table" and type(pin.Disc) == "table" and type(pin.OnAcquired) == "function" then
        for _, key in ipairs(STOP_MARKS) do Mark(pin[key]) end
        Mark(pin.Numeral)
        hooksecurefunc(pin, "OnAcquired", OnStopAcquired)
        OnStopAcquired(pin)
    elseif type(pin.SuperTrackMarker) == "table" then
        Mark(pin.SuperTrackMarker)
        Mark(pin.SuperTrackGlow)
    else
        Mark(pin.Glow)
    end
end

-- SPF's pin layer: canvas > SPF's frame > layer > pins, each pin naming its view, and the view its layer (UI/MapCanvas.lua
-- MapCanvas.Watch: SPF's frame holds the layer only, and every frame on the layer is a pin of a pool, with its view).
-- The canvas holds the pins of every addon, hundreds with Questie and OpenMap, and until SPF has drawn its first pin
-- the layer has none to recognise it by. So the canvas is only walked again when its number of children changed; the
-- frames found there with a few children of their own are kept as candidates, and the looks in between check only
-- those, without making a table.
local HOST_CHILDREN = 3 -- candidates: the children of canvas frames with at most this many (SPF's frame has one)
local candidates = setmetatable({}, { __mode = "k" }) -- possible layer -> true

local function IsSpfLayer(layer)
    if select("#", layer:GetChildren()) == 0 then return false end
    local pin = layer:GetChildren() -- the first one is enough (see above)
    local view = type(pin) == "table" and pin.view
    return type(view) == "table" and view.layer == layer
end

local function AddCandidates(host)
    local count = select("#", host:GetChildren())
    if count == 0 or count > HOST_CHILDREN then return end
    local a, b, c = host:GetChildren()
    if a then candidates[a] = true end
    if b then candidates[b] = true end
    if c then candidates[c] = true end
end

local function FindLayer()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" or type(map.GetCanvas) ~= "function" then return nil end
    local canvas = map:GetCanvas()
    if type(canvas) ~= "table" then return nil end
    local count = select("#", canvas:GetChildren())
    if count ~= S.canvasChildren then
        S.canvasChildren = count
        S.layerWalks = S.layerWalks + 1
        wipe(candidates)
        for _, host in ipairs({ canvas:GetChildren() }) do AddCandidates(host) end
    end
    for layer in pairs(candidates) do
        if IsSpfLayer(layer) then
            wipe(candidates)
            return layer
        end
    end
end

local function ScanMap()
    S.mapLayer = S.mapLayer or FindLayer()
    local layer = S.mapLayer
    if not layer then return end
    local count = select("#", layer:GetChildren())
    if count == S.pinCount then return end
    S.pinCount = count
    for _, pin in ipairs({ layer:GetChildren() }) do WatchPin(pin) end
end

local function MarkScreenPin()
    local f = _G[SCREEN_PIN_NAME]
    if type(f) == "table" then Mark(f.Pin) end
end

-- Runs only while the world map is open where Forever's map reports it (EventRegistry, see WatchMap).
local function OnWatch(_, elapsed)
    S.wait = S.wait - elapsed
    local map = _G.WorldMapFrame
    local shown = type(map) == "table" and map:IsVisible()
    if shown and S.mapLayer then ScanMap() end
    if S.wait > 0 then return end
    S.wait = SCAN_EVERY
    if shown then ScanMap() end
end

-- The frame that counts SPF's pins while the map is up. The map tells EventRegistry when it opens and closes ("WorldMapOnShow",
-- "WorldMapOnHide", as EllesmereUIQuestTracker and Waypoint UI use them); the callbacks only show and hide our own frame,
-- nothing is hooked onto the map. Without them the frame stays shown and checks the map itself.
local function WatchMap()
    if S.watcher then return end
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnUpdate", OnWatch)
    S.watcher = watcher
    local registry = rawget(_G, "EventRegistry")
    if type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then return end
    if not pcall(registry.RegisterCallback, registry, "WorldMapOnShow", function() watcher:Show() end, watcher) then return end
    if not pcall(registry.RegisterCallback, registry, "WorldMapOnHide", function() watcher:Hide() end, watcher) then return end
    local map = _G.WorldMapFrame
    if not (type(map) == "table" and map:IsVisible()) then watcher:Hide() end
end

-- Whether the game's waypoint is SPF's bend (one check with our arrow: SPFBridge.lua SPF.Bend).
local function IsBend()
    return ns.SPF.Bend() ~= nil
end

-- OpenMap's marker of the game's waypoint (a pin of its set "waypoint", made anew on every waypoint change).
local function HookOpenMap()
    if S.openMapHooked then return end
    local om = rawget(_G, "OpenMap")
    local stitch = type(om) == "table" and om.MapStitch
    if type(stitch) ~= "table" or type(stitch.AddPin) ~= "function" or type(stitch.GetPinSet) ~= "function" then return end
    S.openMapHooked = true
    hooksecurefunc(stitch, "AddPin", function(set)
        if set == nil or set ~= stitch.GetPinSet("waypoint") or type(set.pins) ~= "table" then return end
        local pin = set.pins[#set.pins]
        local icon = type(pin) == "table" and pin.Icon
        if type(icon) ~= "table" then return end
        Mark(icon)
        marks[icon].plain = not IsBend()
        PaintMark(icon)
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Minimap: the game's own waypoint. While SPF guides, the game's waypoint is SPF's next bend, and the client draws it on
-- the minimap itself: no texture an addon could tint. A marker of ours in the accent sits over it instead (addon
-- textures draw over the minimap's own icons), placed as SPF places its goal there (UI/Route.lua MinimapView and
-- MinimapPoint, inverted): the offset in yards over the minimap's view radius, turned with the player while the minimap
-- rotates, held on the rim (round, or square by the GetMinimapShape convention) when the bend is off the minimap, a
-- little faded there as SPF does. Only for SPF's bend: the player's own waypoint keeps the game's look.
local MINIMAP_WP_SIZE = 20
local MINIMAP_WP_EDGE_ALPHA = 0.6
local MINIMAP_WP_EVERY = 0.05 -- seconds between placements (the minimap turns with every step of a mouse turn)
local MINIMAP_WP_ATLAS = { "Waypoint-MapPin-Minimap-Tracked", "Waypoint-MapPin-Tracked" }

-- Secret values are never compared or calculated with: they count as unreadable.
local function Number(v)
    return ns.CanAccess(v) and type(v) == "number"
end

-- The bend's world position (continent, x, y) while the game's waypoint is SPF's bend.
local function BendWorldPos()
    local _, _, _, cont, wx, wy = ns.SPF.Bend()
    return cont, wx, wy
end

-- u, v on the minimap's face (-1..1 from its centre, east and north), and whether it is held on the rim.
local function MinimapSpot(cont, wx, wy)
    local px, py, inst = ns.PlayerPos()
    if not px or inst ~= cont then return nil end
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if not (Number(radius) and radius > 0) then return nil end
    local facing = 0
    if GetCVar("rotateMinimap") == "1" then
        facing = ns.PlayerFacing()
        if not facing then return nil end
    end
    local north, east = wx - px, -(wy - py) -- UnitPosition: x grows north, y grows west
    local cosine, sine = math.cos(facing), math.sin(facing)
    local u = (east * cosine + north * sine) / radius
    local v = (north * cosine - east * sine) / radius
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local reach = square and math.max(math.abs(u), math.abs(v)) or math.sqrt(u * u + v * v)
    if reach > 1 then
        return u / reach, v / reach, true
    end
    return u, v, false
end

local function MinimapWaypointFrame()
    if S.minimapWp then return S.minimapWp end
    local map = rawget(_G, "Minimap")
    if type(map) ~= "table" or type(map.CreateTexture) ~= "function" then return nil end
    local f = CreateFrame("Frame", nil, map)
    f:SetAllPoints(map)
    local level = map:GetFrameLevel()
    if type(level) == "number" then f:SetFrameLevel(level + 6) end
    f:EnableMouse(false)
    f.mark = f:CreateTexture(nil, "OVERLAY", nil, 6)
    f.mark:SetSize(MINIMAP_WP_SIZE, MINIMAP_WP_SIZE)
    for _, atlas in ipairs(MINIMAP_WP_ATLAS) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            f.mark:SetAtlas(atlas)
            break
        end
    end
    f.mark:SetDesaturated(true)
    f.mark:Hide()
    f.wait = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.wait = self.wait - elapsed
        if self.wait > 0 then return end
        self.wait = MINIMAP_WP_EVERY
        local tint = S.tint
        local cont, wx, wy
        if tint then cont, wx, wy = BendWorldPos() end
        local u, v, edge
        if cont then u, v, edge = MinimapSpot(cont, wx, wy) end
        if not u then
            self.mark:Hide()
            return
        end
        self.mark:ClearAllPoints()
        self.mark:SetPoint("CENTER", self, "CENTER", u * self:GetWidth() / 2, v * self:GetHeight() / 2)
        self.mark:SetVertexColor(tint[1], tint[2], tint[3])
        self.mark:SetAlpha(edge and MINIMAP_WP_EDGE_ALPHA or 1)
        self.mark:Show()
    end)
    S.minimapWp = f
    return f
end

local function HookMinimap(f)
    if S.minimapHooked then return end
    local layer = f.strokeLayer
    local animation = type(layer) == "table" and layer.animation
    if type(animation) ~= "table" then return end
    S.minimapHooked = true
    local function Redrawn() WatchLines(f) end
    hooksecurefunc(animation, "Stop", Redrawn)
    hooksecurefunc(animation, "IsPlaying", Redrawn)
end

local function ApplyMarks()
    local f = MinimapRoute()
    if not f then return false end
    local tint = MinimapRouteOn() and { ns.Accent() } or nil
    S.tint = tint
    HookMinimap(f)
    HookOpenMap()
    -- the minimap mark only with the tint: a hidden frame runs no OnUpdate
    local wp = MinimapWaypointFrame()
    if wp and tint then
        if not wp:IsShown() then
            wp.wait = 0
            wp:Show()
        end
    elseif wp then
        wp.mark:Hide()
        wp:Hide()
    end
    Mark(f.Goal)
    WatchLines(f)
    ScanMap()
    MarkScreenPin()
    local compass = CompassFrame()
    if compass then
        Mark(compass.Goal)
        Mark(compass.Stop)
        if not CompassOn() then -- the compass skin paints these itself
            if tint then
                Tint(compass.Bend, tint[1], tint[2], tint[3])
                Tint(compass.Next, tint[1], tint[2], tint[3])
            else
                Tint(compass.Bend)
                Tint(compass.Next)
            end
        end
    end
    -- Apply also runs when the compass or the screen pin turns up: only a new tint needs a repaint.
    local look = tint and ("%.3f %.3f %.3f"):format(tint[1], tint[2], tint[3]) or "off"
    if look ~= S.look then
        S.look = look
        for owner in pairs(lineOwners) do RepaintLines(owner) end
        for tex in pairs(marks) do PaintMark(tex) end
        for pin in pairs(stopNumber) do PaintStop(pin) end
    end
    WatchMap()
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Wiring: SPF builds the module and the minimap route at its init, so look once a second until both exist (and only
-- while SPF is loaded); the compass and the screen pin come only with a journey (see the looker below).

local ticker
local wired = false -- module and minimap route found: the ticker is not needed again

local function Apply()
    if not ns.db then return end
    local okJ, foundJourney = pcall(ApplyJourney)
    if not okJ then geterrorhandler()(foundJourney) end
    local okC, foundCompass = pcall(ApplyCompass)
    if not okC then geterrorhandler()(foundCompass) end
    local okM, foundMarks = pcall(ApplyMarks)
    if not okM then geterrorhandler()(foundMarks) end
    if foundJourney and foundMarks then
        wired = true
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end
end

local function StartWatching()
    if wired or ticker or not (ns.SPF and ns.SPF.Loaded()) then return end
    ticker = C_Timer.NewTicker(1, Apply)
end

-- SPF makes its compass (UI/Compass.lua RefreshCompass) and its screen pin (UI/DestinationPin.lua) only for a journey and
-- with their settings on: looked for twice a second while SPF guides, until both are there, each one styled as it comes.
local JOURNEY_LOOK = 0.5
local seenCompass, seenScreenPin = false, false

ns.SPF.LookWhileGuiding(JOURNEY_LOOK, function()
    local compass, screenPin = CompassFrame() ~= nil, type(_G[SCREEN_PIN_NAME]) == "table"
    if compass ~= seenCompass or screenPin ~= seenScreenPin then
        seenCompass, seenScreenPin = compass, screenPin
        Apply()
    end
    return compass and screenPin
end)

ns.SPFSkin = { Apply = Apply, ScanMap = ScanMap, MinimapWaypoint = MinimapWaypointFrame, Watcher = function() return S.watcher end,
    state = S }

ns.OnLoaded(function()
    Apply()
    StartWatching()
end)

ns.RegisterRefresh(function()
    Apply()
    StartWatching()
end)

-- /brxp spf: what the skin found and whether it is on.
function ns.SPFSkinDebug()
    local c = Cfg() or {}
    local module, compass = _G[TRACKER_NAME], CompassFrame()
    ns.Say(string.format(L["Journey: frame %s, hooked %s, skin %s (option %s)"],
        tostring(type(module) == "table"), tostring(S.trackerHooked), tostring(journeyStyled), tostring(c.journey)))
    ns.Say(string.format(L["Compass: frame %s, hooked %s, skin %s (option %s)"],
        tostring(compass ~= nil), tostring(S.compassHooked), tostring(compassStyled), tostring(c.compass)))
    ns.Say(string.format(L["Minimap route: frame %s, hooked %s, lines %s, skin %s (option %s)"],
        tostring(MinimapRoute() ~= nil), tostring(S.minimapHooked), tostring(lineOwners[MinimapRoute() or S] or 0),
        tostring(S.tint ~= nil),
        tostring(c.minimapRoute)))
    ns.Say(string.format(L["EllesmereUI skinning available: %s, quest tracker settings found: %s"],
        tostring(SkinAllowed()), tostring(TrackerDb() ~= nil)))
end
