-- Look sources shared by every skin: accent colour (EllesmereUI, class or own), panel colours, font. Values are read
-- through ns.Env, so the skins never know whether EllesmereUI answers.
local _, ns = ...
local Env = ns.Env

local JADE = { 0.047, 0.824, 0.616 } -- EllesmereUI's default accent, our accent without EllesmereUI

-- Flat colours of the EllesmereUI look (dark panel, hair-line borders, readable greys).
ns.Colors = {
    panel = { 0.067, 0.067, 0.067 },
    panelAlpha = 0.95,
    inset = { 0.035, 0.035, 0.035 },
    control = { 0.11, 0.11, 0.11 },
    border = { 0, 0, 0 },
    line = { 1, 1, 1, 0.08 },
    text = { 0.92, 0.92, 0.92 },
    soft = { 0.72, 0.72, 0.72 },
    dim = { 0.45, 0.45, 0.45 },
}

-- x when it is a table (a frame or region), else nil: fields of other addons' frames are checked before use.
function ns.T(x)
    return type(x) == "table" and x or nil
end

function ns.Mix(a, b, t)
    return a + (b - a) * t
end

function ns.Clamp(value, low, high, default)
    if type(value) ~= "number" or value ~= value then return default end
    if value < low then return low end
    if value > high then return high end
    return value
end

local function ClassColor()
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or type(classFile) ~= "string" or ns.IsSecret(classFile) then return nil end
    local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
    if c and c.r then return c.r, c.g, c.b end
    c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return nil
end

-- r, g, b of the accent the user chose.
function ns.Accent()
    local mode = ns.db and ns.db.accentMode or "eui"
    if mode == "custom" then
        local c = ns.db.accentCustom
        if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
            return c.r, c.g, c.b
        end
    elseif mode == "class" then
        local r, g, b = ClassColor()
        if r then return r, g, b end
    end
    local r, g, b = Env.Accent()
    if r then return r, g, b end
    return JADE[1], JADE[2], JADE[3]
end

-- Accent as a WaypointUI-style colour table.
function ns.AccentTable(alpha)
    local r, g, b = ns.Accent()
    return { r = r, g = g, b = b, a = alpha or 1 }
end

function ns.PanelColor()
    local r, g, b = Env.PanelColor()
    if r then return r, g, b end
    local p = ns.Colors.panel
    return p[1], p[2], p[3]
end

-- Font file and outline flags: EllesmereUI's font, else the game's.
function ns.Font()
    local path, flags = Env.FontPath()
    if type(path) == "string" and path ~= "" then return path, flags or "" end
    return STANDARD_TEXT_FONT, ""
end

-- SetFont that never leaves a FontString without a font (an unknown file falls back to the game font).
function ns.SetFont(fs, path, size, flags)
    if not (fs and fs.SetFont) then return end
    local ok, result = pcall(fs.SetFont, fs, path or STANDARD_TEXT_FONT, size or 12, flags or "")
    if not ok or result == false then
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size or 12, flags or "")
    end
end

-- Same face as ns.Font(), the size the FontString already has (layouts measured by the skinned addon stay valid).
function ns.KeepSizeFont(fs, flags)
    if not (fs and fs.GetFont) then return end
    local _, size, oldFlags = fs:GetFont()
    local path, ourFlags = ns.Font()
    ns.SetFont(fs, path, size or 12, flags or (ourFlags ~= "" and ourFlags) or oldFlags or "")
end

function ns.Luminance(r, g, b)
    return 0.299 * (r or 0) + 0.587 * (g or 0) + 0.114 * (b or 0)
end

-- A refresh of everything when EllesmereUI changes accent or looks.
Env.OnChange(function()
    ns.RefreshAll()
end)
