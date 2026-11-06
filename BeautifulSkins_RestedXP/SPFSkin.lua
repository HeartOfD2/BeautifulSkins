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

-- SPF's own compass colours (UI/Compass.lua), put back when the compass skin is switched off.
local SPF_TICK = { 0.72, 0.67, 0.55, 0.7 }
local SPF_CENTER = { 1, 0.82, 0, 0.85 }

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
    minimapHooked = false, tint = nil, tinting = false, watcher = nil, wait = 0, mapLayer = nil, pinCount = nil,
    look = nil,
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
        f.Center:SetColorTexture(r, g, b, 1)
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
    for _, tick in ipairs(f.ticks) do
        tick:SetColorTexture(SPF_TICK[1], SPF_TICK[2], SPF_TICK[3], SPF_TICK[4])
        if tick.label then
            RestoreFont(tick.label)
            RestoreColor(tick.label)
        end
    end
    if f.Center then
        f.Center:SetColorTexture(SPF_CENTER[1], SPF_CENTER[2], SPF_CENTER[3], SPF_CENTER[4])
        f.Center:SetSize(1, 6)
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

local function ApplyCompass()
    local f = CompassFrame()
    if not f then return false end
    HookCompass(f)
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
-- the atlas it shows, so a marker that turns into a transport or flight master icon gets its own look back.
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

local function PaintMark(tex)
    local m = marks[tex]
    local tint = S.tint
    if tint and (m.forced or MARK_ATLAS[m.atlas]) then
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
        atlas = tex:GetAtlas() }
    hooksecurefunc(tex, "SetAtlas", function(self, atlas)
        marks[self].atlas = atlas
        PaintMark(self)
    end)
    hooksecurefunc(tex, "SetTexture", function(self)
        marks[self].atlas = nil
        PaintMark(self)
    end)
    PaintMark(tex)
end

-- The numbers of the stops still ahead are yellow on a dark button: they take the tint, the dark ones on the lit
-- button of the current stop stay.
local function PaintStop(pin)
    local later = not pin.current
    marks[pin.Numeral].forced = later
    PaintMark(pin.Numeral)
    local c, tint = stopNumber[pin], S.tint
    if tint and later then
        pin.Number:SetTextColor(tint[1], tint[2], tint[3])
    else
        pin.Number:SetTextColor(c[1], c[2], c[3])
    end
end

local function OnStopAcquired(pin)
    stopNumber[pin] = { pin.Number:GetTextColor() }
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
    if type(pin.Numeral) == "table" and type(pin.Number) == "table" and type(pin.OnAcquired) == "function" then
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

-- SPF's pin layer: canvas > SPF's frame > layer > pins, each pin naming its view, and the view its layer.
local function FindLayer()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" or type(map.GetCanvas) ~= "function" then return nil end
    local canvas = map:GetCanvas()
    if type(canvas) ~= "table" then return nil end
    for _, host in ipairs({ canvas:GetChildren() }) do
        for _, layer in ipairs({ host:GetChildren() }) do
            for _, pin in ipairs({ layer:GetChildren() }) do
                local view = pin.view
                if type(view) == "table" and view.layer == layer then return layer end
            end
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

local function OnWatch(_, elapsed)
    S.wait = S.wait - elapsed
    local map = _G.WorldMapFrame
    local shown = type(map) == "table" and map:IsVisible()
    if shown and S.mapLayer then ScanMap() end
    if S.wait > 0 then return end
    S.wait = SCAN_EVERY
    if shown then ScanMap() end
    MarkScreenPin()
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
    -- Apply also runs once a second while SPF's compass was never shown: only a new tint needs a repaint.
    local look = tint and ("%.3f %.3f %.3f"):format(tint[1], tint[2], tint[3]) or "off"
    if look ~= S.look then
        S.look = look
        for owner in pairs(lineOwners) do RepaintLines(owner) end
        for tex in pairs(marks) do PaintMark(tex) end
        for pin in pairs(stopNumber) do PaintStop(pin) end
    end
    if not S.watcher then
        S.watcher = CreateFrame("Frame")
        S.watcher:SetScript("OnUpdate", OnWatch)
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Wiring: SPF builds the module and the minimap route at its init and the compass the first time it shows, so look
-- once a second until all three exist (and only while SPF is loaded).

local ticker

local function Apply()
    if not ns.db then return end
    local okJ, foundJourney = pcall(ApplyJourney)
    if not okJ then geterrorhandler()(foundJourney) end
    local okC, foundCompass = pcall(ApplyCompass)
    if not okC then geterrorhandler()(foundCompass) end
    local okM, foundMarks = pcall(ApplyMarks)
    if not okM then geterrorhandler()(foundMarks) end
    if foundJourney and foundCompass and foundMarks and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function StartWatching()
    if ticker or not (ns.SPF and ns.SPF.Loaded()) then return end
    ticker = C_Timer.NewTicker(1, Apply)
end

ns.SPFSkin = { Apply = Apply, ScanMap = ScanMap }

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
