-- Look sources shared by every skin: accent colour and font follow the host (ns.Theme), the flat panel colours are the
-- EllesmereUI look. The skins never know whether EllesmereUI answers.
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

-- r, g, b of the accent: the host's accent setting (EllesmereUI, theme, class or own colour) for every skin.
function ns.Accent()
    local T = ns.Theme.Get("user")
    local c = T and T.accent
    if c then return c[1], c[2], c[3] end
    return JADE[1], JADE[2], JADE[3]
end

-- Accent as a WaypointUI-style colour table.
function ns.AccentTable(alpha)
    local r, g, b = ns.Accent()
    return { r = r, g = g, b = b, a = alpha or 1 }
end

-- Panel colour of the EllesmereUI look (EllesmereUI's own when its skin child runs).
function ns.PanelColor()
    local r, g, b = Env.PanelColor()
    if r then return r, g, b end
    local p = ns.Colors.panel
    return p[1], p[2], p[3]
end

-- Font file and outline flags: the host's font choice (EllesmereUI's font by default when it is loaded).
function ns.Font()
    local path, flags = ns.Theme.FontPath()
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

-- A refresh of every skin when the host's accent, theme or font changes (EllesmereUI's changes arrive the same way).
ns.Theme.OnChange(function()
    ns.RefreshAll()
end)
