-- The EllesmereUI quest tracker look (fonts, sizes, colours, background) and a skin for sections built from Blizzard's
-- ObjectiveTrackerModuleTemplate, like the sections of the shared Forever tracker column. Values come from EllesmereUI
-- Quest Tracker's own settings when it is loaded, else from its defaults.
local _, ns = ...
local EUI = ns.EUI
local T = ns.T

local Track = {}
ns.TrackerStyle = Track

local QT_TITLE = { 1.0, 0.910, 0.471 }
local QT_BG = { 0.035, 0.035, 0.035 }
local QT_SIZE = { header = 13, title = 12, line = 10 }
Track.LINE = { 0.72, 0.72, 0.72 } -- objective grey
Track.DIM = { 0.45, 0.45, 0.45 }
Track.WHITE = { 1, 1, 1 }

local function Weak() return setmetatable({}, { __mode = "k" }) end

local fontSig = Weak()    -- FontString -> signature of the font we applied
local baseStyle = Weak()  -- FontString -> colour style the owner asked for
local hookedBlock = Weak()
local decor = Weak()      -- module -> { bg, divider }

local function Num(v, default)
    if type(v) == "number" and v == v then return v end
    return default
end

function Track.Sizes()
    local qt = EUI.TrackerSettings() or {}
    return Num(qt.headerFontSize, QT_SIZE.header), Num(qt.titleFontSize, QT_SIZE.title), Num(qt.objectiveFontSize, QT_SIZE.line)
end

function Track.TitleColor()
    local qt = EUI.TrackerSettings()
    if qt then return { Num(qt.titleR, QT_TITLE[1]), Num(qt.titleG, QT_TITLE[2]), Num(qt.titleB, QT_TITLE[3]) } end
    return QT_TITLE
end

function Track.BackgroundColor()
    local qt = EUI.TrackerSettings()
    if qt and type(qt.bgR) == "number" then return Num(qt.bgR, QT_BG[1]), Num(qt.bgG, QT_BG[2]), Num(qt.bgB, QT_BG[3]) end
    return QT_BG[1], QT_BG[2], QT_BG[3]
end

-- { path, flags, shadow, sig } of the quest tracker font (falls back to our font).
function Track.Font()
    local path, flags, shadow = EUI.TrackerFont()
    if type(path) ~= "string" or path == "" then path, flags = ns.Font() end
    if type(flags) ~= "string" then flags = "" end
    if shadow == nil then shadow = flags == "" end
    shadow = shadow and true or false
    return { path = path, flags = flags, shadow = shadow, sig = path .. "|" .. flags .. "|" .. tostring(shadow) .. "|" }
end

-- Returns true when the font actually changed (the owner may need a new layout).
function Track.StyleFont(fs, size, font)
    if not fs then return false end
    local sig = font.sig .. size
    if fontSig[fs] == sig then return false end
    EUI.PrimeShadow(fs, font.shadow) -- a drop shadow only renders when carried by a font object
    ns.SetFont(fs, font.path, size, font.flags)
    if not font.shadow and fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    fontSig[fs] = sig
    return true
end

function Track.SetColor(fs, c, highlight)
    if not fs then return end
    local r, g, b = c[1], c[2], c[3]
    if highlight then r, g, b = ns.Mix(r, 1, 0.35), ns.Mix(g, 1, 0.35), ns.Mix(b, 1, 0.35) end
    fs:SetTextColor(r, g, b)
end

-- Blank a decorative texture (as EllesmereUI does, no fade animation brings it back).
function Track.Blank(tex)
    if T(tex) and tex.SetTexture then tex:SetTexture("") end
end

function Track.Tint(tex, r, g, b)
    if not T(tex) then return end
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    if tex.SetVertexColor then tex:SetVertexColor(r, g, b) end
end

local function OnePixel(tex)
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(tex, 1) else tex:SetHeight(1) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- ObjectiveTrackerModuleTemplate sections

local function LineColor(style)
    local C = OBJECTIVE_TRACKER_COLOR
    if C and style == C.NormalHighlight then
        return Track.WHITE
    elseif style == GRAY_FONT_COLOR then
        return Track.DIM
    elseif C and (style == C.Header or style == C.HeaderHighlight) then
        return Track.TitleColor()
    elseif C and style ~= nil and style ~= C.Normal and style ~= C.Complete then
        return nil -- failed or timed lines keep Blizzard's colour
    end
    return Track.LINE
end

local function StyleBlockText(block, fs, font)
    if not fs then return false end
    local _, titleSize, lineSize = Track.Sizes()
    local isTitle = fs == block.HeaderText
    local changed = Track.StyleFont(fs, isTitle and titleSize or lineSize, font)
    local C = OBJECTIVE_TRACKER_COLOR
    local style = baseStyle[fs] or (isTitle and C and C.Header) or (C and C.Normal)
    local color = LineColor(style)
    local highlight = block.isHighlighted and true or false
    if color then Track.SetColor(fs, color, highlight) end
    local line = not isTitle and fs:GetParent()
    if line and T(line.Dash) and line.Text == fs then
        changed = Track.StyleFont(line.Dash, lineSize, font) or changed
        if color then Track.SetColor(line.Dash, color, highlight) end
    end
    return changed
end

local function EachLine(block, fn)
    if type(block.usedLines) ~= "table" then return end
    for _, line in pairs(block.usedLines) do
        if type(line) == "table" and T(line.Text) then fn(line) end
    end
end

local function StyleBlock(block, font)
    local changed = StyleBlockText(block, T(block.HeaderText), font)
    EachLine(block, function(line)
        changed = StyleBlockText(block, line.Text, font) or changed
    end)
    return changed
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
    local d = decor[module]
    if not d then
        d = {}
        d.bg = module:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetPoint("TOPLEFT", module, "TOPLEFT", -6, 4)
        d.bg:SetPoint("BOTTOMRIGHT", module, "BOTTOMRIGHT", 4, -6)
        d.divider = module:CreateTexture(nil, "ARTWORK")
        OnePixel(d.divider)
        decor[module] = d
    end
    return d
end

local layoutQueued = Weak()

-- Line heights are measured when the owner sets a text; after a font change the section lays itself out again.
local function RequestLayout(module)
    if layoutQueued[module] then return end
    layoutQueued[module] = true
    C_Timer.After(0, function()
        layoutQueued[module] = nil
        if type(module.MarkDirty) == "function" then pcall(module.MarkDirty, module) end
    end)
end

local function HookBlock(block, module, isOn)
    if hookedBlock[block] then return end
    hookedBlock[block] = true
    if type(block.SetStringText) == "function" then
        hooksecurefunc(block, "SetStringText", function(self, fs, _, _, colorStyle)
            if not fs then return end
            local C = OBJECTIVE_TRACKER_COLOR
            baseStyle[fs] = colorStyle or (C and C.Normal)
            if not isOn() then return end
            if StyleBlockText(self, fs, Track.Font()) then RequestLayout(module) end
        end)
    end
    if type(block.UpdateHighlight) == "function" then
        hooksecurefunc(block, "UpdateHighlight", function(self)
            if isOn() then StyleBlock(self, Track.Font()) end
        end)
    end
end

-- Restyles a whole section: header in the accent with a divider, background, every block and line.
-- background = 0..100 (opacity), isOn() tells the block hooks whether the skin is still wanted.
function Track.StyleModule(module, background, isOn)
    local font = Track.Font()
    local headerSize = Track.Sizes()
    local r, g, b = ns.Accent()
    local header = T(module.Header)
    if header then
        Track.Blank(header.Background); Track.Blank(header.Shine); Track.Blank(header.Glow)
        Track.StyleFont(T(header.Text), headerSize, font)
        Track.SetColor(T(header.Text), { r, g, b })
        local mb = T(header.MinimizeButton)
        if mb then
            Track.Tint(mb.GetNormalTexture and mb:GetNormalTexture(), r, g, b)
            Track.Tint(mb.GetPushedTexture and mb:GetPushedTexture(), r, g, b)
            Track.Tint(mb.GetHighlightTexture and mb:GetHighlightTexture(), r, g, b)
        end
        local d = Decor(module)
        d.divider:ClearAllPoints()
        d.divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 7, 0)
        d.divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -1, 0)
        d.divider:SetColorTexture(r, g, b, 1)
        d.divider:Show()
        local opacity = ns.Clamp(background, 0, 100, 75) / 100
        local br, bgc, bb = Track.BackgroundColor()
        d.bg:SetColorTexture(br, bgc, bb, opacity)
        d.bg:SetShown(opacity > 0)
    end
    local changed = false
    EachBlock(module, function(block)
        HookBlock(block, module, isOn)
        changed = StyleBlock(block, font) or changed
    end)
    if changed then RequestLayout(module) end
end
