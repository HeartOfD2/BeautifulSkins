-- Themes for our own windows (options window) and the look the packs give skinned windows (Attune). A theme is plain data.
-- Theme.Bind registers a paint function per object; it reruns on theme, accent, status-scheme or font changes, so open
-- windows follow without a reload.
-- The accent is a setting of its own (settings.accent = { mode, r, g, b }) and applies to every theme:
--   "theme"  the theme's own accent        "eui"     the host's accent (only while EllesmereUI is loaded)
--   "class"  the player's class color      "custom"  r, g, b
-- EllesmereUI is optional and only reached through ns.Env: the "eui" theme and the "eui" accent exist only while it is loaded.
local _, ns = ...
local L = ns.L

local Theme = {}
ns.Theme = Theme

local FALLBACK_ACCENT = { 0.047, 0.824, 0.616 } -- EUI's default accent, used when EUI gives none
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Dark themes first, then the light ones, then the two with character (parchment, classic).
local ORDER = { "eui", "standard", "graphite", "midnight", "frost", "nord", "emerald", "ember", "contrast", "light", "rose",
    "parchment", "classic" }
local MODES = { "theme", "eui", "class", "custom" }

local function Hex(hex, alpha)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1 }
end

-- Quick picks for an own accent (12 colors, warm to cool).
Theme.PALETTE = {
    Hex("e5484d"), Hex("f76b15"), Hex("ffb224"), Hex("f5d90a"), Hex("8ed05a"), Hex("30a46c"),
    Hex("12a594"), Hex("3d9bff"), Hex("3e63dd"), Hex("8e4ec6"), Hex("d6409f"), Hex("c8ccd2"),
}

-- Blizzard frame art for the classic theme (paths checked in V-N8; tooltip border is assumed alongside).
local function ClassicBackdrops()
    local dialog = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 26,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    }
    local tooltip = {
        bgFile = WHITE,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }
    return {
        window = { def = dialog, color = { 1, 1, 1, 1 }, edge = { 1, 1, 1, 1 } },
        panel = { def = tooltip, color = { 0, 0, 0, 0.45 }, edge = { 0.62, 0.55, 0.42, 1 } },
        input = { def = tooltip, color = { 0, 0, 0, 0.6 }, edge = { 0.55, 0.55, 0.55, 1 } },
        button = { def = tooltip, color = { 0.42, 0.06, 0.03, 0.95 }, edge = { 0.75, 0.62, 0.38, 1 } },
        popup = { def = tooltip, color = { 0.08, 0.06, 0.035, 1 }, edge = { 0.62, 0.55, 0.42, 1 } },
    }
end

-- EUI-style tokens; used twice: as the selectable "EllesmereUI" theme and for the pages inside EllesmereUI's options window.
local function EUITokens(label)
    return {
        label = label, mode = "dark", live = true, inset = 1, pad = 8, borderSize = 1,
        bg = { 0.069, 0.058, 0.047, 0.97 }, bgAlt = { 0.094, 0.082, 0.070, 1 }, border = { 1, 1, 1, 0.08 },
        text = { 1, 1, 1, 0.92 }, textDim = { 1, 1, 1, 0.53 }, header = { 1, 1, 1, 0.78 },
        accent = { FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3], 1 }, onAccent = Hex("0b0907"),
        danger = Hex("e5484d"), control = { 0.089, 0.080, 0.072, 0.9 }, inputBg = { 0.030, 0.023, 0.018, 0.8 },
        canvasBg = Hex("0e0c0a"),
    }
end

-- Token set per theme. bg = window fill, bgAlt = header/raised areas, control = button fill, onAccent = text on an
-- accent fill, inset = border thickness, pad = inner spacing. Labels resolve through L when listed (locale is final
-- only in ADDON_LOADED).
local themes = {
    eui = EUITokens("EllesmereUI"),
    standard = { -- neutral graphite, fresh blue accent: the default without EllesmereUI
        label = "Standard", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("15171b", 0.97), bgAlt = Hex("1d2025"), border = { 1, 1, 1, 0.11 },
        text = Hex("eceef2"), textDim = Hex("959ca7"), header = Hex("d3d8df"),
        accent = Hex("3d9bff"), onAccent = Hex("06121f"),
        danger = Hex("f15b58"), control = Hex("22262c"), inputBg = Hex("0e1013"),
        canvasBg = Hex("111316"),
    },
    classic = {
        label = "Classic", mode = "dark", inset = 8, pad = 8, borderSize = 1, backdrop = ClassicBackdrops(),
        bg = { 0, 0, 0, 0.8 }, bgAlt = { 0, 0, 0, 0.3 }, border = { 0.62, 0.55, 0.42, 0.7 },
        sheet = Hex("0d0a07"), popup = Hex("140f09"), -- the see-through fills above would let the list shine through
        text = Hex("f4ecdc"), textDim = Hex("b3a998"), header = { 1, 0.82, 0, 1 },
        accent = { 1, 0.82, 0, 1 }, onAccent = Hex("1a1206"),
        danger = Hex("ff7165"), control = Hex("6b0f07", 0.95), inputBg = { 0, 0, 0, 0.6 },
        canvasBg = Hex("17110a"),
    },
    parchment = { -- aged vellum, iron-gall ink, an oxblood seal as accent
        label = "Parchment", mode = "light", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("d8c7a0", 0.98), bgAlt = Hex("c9b68b"), border = Hex("6f5434", 0.55),
        text = Hex("33241a"), textDim = Hex("4f3e2c"), header = Hex("4e3420"), -- dim text >= 4.5:1 on every fill
        accent = Hex("76241a"), onAccent = Hex("f2e6c9"),
        danger = Hex("892117"), control = Hex("cdb98e"), inputBg = Hex("ebdfc2"),
        canvasBg = Hex("efe4c8"),
    },
    midnight = { -- deep indigo night sky, violet arcane accent
        label = "Midnight", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("0e0f24", 0.97), bgAlt = Hex("16173a"), border = Hex("6c6fd6", 0.28),
        text = Hex("e7e5ff"), textDim = Hex("9896c6"), header = Hex("cbbcff"),
        accent = Hex("9d7bff"), onAccent = Hex("120c2a"),
        danger = Hex("ff5c7a"), control = Hex("1b1c44"), inputBg = Hex("09091a"),
        canvasBg = Hex("0b0b1d"),
    },
    frost = { -- northern slate and rime, ice-blue accent
        label = "Frost", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("1b2228", 0.97), bgAlt = Hex("232d35"), border = Hex("9cc3d8", 0.2),
        text = Hex("e4eef3"), textDim = Hex("98abb6"), header = Hex("bce6f6"),
        accent = Hex("7fd3f5"), onAccent = Hex("0c1a22"),
        danger = Hex("ff6b6b"), control = Hex("27323b"), inputBg = Hex("12181d"),
        canvasBg = Hex("151c22"),
    },
    graphite = { -- quiet, modern monochrome: zinc greys and a white accent that lets a class or own colour stand out
        label = "Graphite", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("111214", 0.97), bgAlt = Hex("1a1b1f"), border = { 1, 1, 1, 0.10 },
        text = Hex("ededf0"), textDim = Hex("9b9ea6"), header = Hex("d6d8de"),
        accent = Hex("f4f4f5"), onAccent = Hex("111214"),
        danger = Hex("f26d6d"), control = Hex("222328"), inputBg = Hex("0b0c0d"),
        canvasBg = Hex("0f1012"),
    },
    nord = { -- arctic polar night with frost-blue accent
        label = "Nord", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("2e3440", 0.97), bgAlt = Hex("3b4252"), border = Hex("d8dee9", 0.14),
        text = Hex("eceff4"), textDim = Hex("c0c8d4"), header = Hex("d8dee9"),
        accent = Hex("92c7d6"), onAccent = Hex("1f2530"),
        danger = Hex("f4aab1"), control = Hex("434c5e"), inputBg = Hex("272c36"),
        canvasBg = Hex("2b303b"),
    },
    emerald = { -- deep forest green with a fresh emerald accent
        label = "Emerald", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("0c1512", 0.97), bgAlt = Hex("13201b"), border = Hex("6ee7b7", 0.16),
        text = Hex("e3f4ec"), textDim = Hex("8fb3a3"), header = Hex("b9ecd5"),
        accent = Hex("34d399"), onAccent = Hex("04130d"),
        danger = Hex("f87171"), control = Hex("172821"), inputBg = Hex("08100d"),
        canvasBg = Hex("0a120f"),
    },
    ember = { -- warm charcoal and glowing amber
        label = "Ember", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("18120e", 0.97), bgAlt = Hex("221913"), border = Hex("f59e0b", 0.18),
        text = Hex("f6ece2"), textDim = Hex("b39f8c"), header = Hex("ffd7a8"),
        accent = Hex("ff9f43"), onAccent = Hex("1e1205"),
        danger = Hex("ff5d5d"), control = Hex("2a1f17"), inputBg = Hex("100b08"),
        canvasBg = Hex("140f0b"),
    },
    contrast = { -- black and white with a signal-yellow accent, for the best readability
        label = "High contrast", mode = "dark", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("000000", 0.98), bgAlt = Hex("141414"), border = { 1, 1, 1, 0.45 },
        text = Hex("ffffff"), textDim = Hex("d0d0d0"), header = Hex("ffffff"),
        accent = Hex("ffd60a"), onAccent = Hex("000000"),
        danger = Hex("ff4d4d"), control = Hex("1f1f1f"), inputBg = Hex("000000"),
        canvasBg = Hex("000000"),
    },
    rose = { -- soft blush paper with a berry accent
        label = "Rosé", mode = "light", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("fbf4f5", 0.98), bgAlt = Hex("f1e3e6"), border = Hex("c9a3ab", 0.7),
        text = Hex("2b1d22"), textDim = Hex("6b5359"), header = Hex("4a2b34"),
        accent = Hex("a32b53"), onAccent = Hex("ffffff"), -- accent as text >= 4.5:1 on every fill
        danger = Hex("bb2626"), control = Hex("efdfe3"), inputBg = Hex("ffffff"),
        canvasBg = Hex("ffffff"),
    },
    light = { -- bright monitors: near-white paper, steel-blue accent
        label = "Light", mode = "light", inset = 1, pad = 8, borderSize = 1,
        bg = Hex("f5f6f8", 0.98), bgAlt = Hex("e7eaee"), border = Hex("aeb6c2", 0.8),
        text = Hex("1c2230"), textDim = Hex("525d6f"), header = Hex("2a3345"),
        accent = Hex("2558ba"), onAccent = Hex("ffffff"), -- accent as text >= 4.5:1 on every fill
        danger = Hex("bb2d2d"), control = Hex("e2e6eb"), inputBg = Hex("ffffff"),
        canvasBg = Hex("ffffff"),
    },
}
-- The views inside EllesmereUI's own options window always keep EUI's look and accent, next to EUI's widgets.
-- Surfaces that lie over other content (search results, menus, the zoom bar, the detail panel) must never be see-through:
-- sheet = an opaque bg, popup = an opaque bgAlt, unless a theme names its own.
local function Opaque(T)
    T.sheet = T.sheet or { T.bg[1], T.bg[2], T.bg[3], 1 }
    T.popup = T.popup or { T.bgAlt[1], T.bgAlt[2], T.bgAlt[3], 1 }
end

local panel = EUITokens("EllesmereUI")
panel.success = Hex("30a46c")
panel.white = { 1, 1, 1, 1 }
Opaque(panel)

-- Each theme remembers its own accent; the effective accent is computed from the accent setting. success (done marks,
-- completed progress) is the same green in every theme and independent of the accent.
for _, T in pairs(themes) do
    T.success = Hex("30a46c")
    T.white = { 1, 1, 1, 1 } -- marks on status colours (check on a done card)
    Opaque(T)
    T.baseAccent = { T.accent[1], T.accent[2], T.accent[3] }
    T.baseOnAccent = { T.onAccent[1], T.onAccent[2], T.onAccent[3], T.onAccent[4] or 1 }
end

-- Relative luminance and contrast ratio as WCAG defines them (colours 0..1).
local function Lum(c)
    local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end

local function Ratio(a, b)
    local la, lb = Lum(a), Lum(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end
Theme.ContrastRatio = Ratio

-- The accent as text: the accent itself while it reads on the theme's fills (>= 4.5:1), else mixed towards white
-- (dark themes) or black (light themes) until it does. Only a class or own colour ever needs the mix.
local function AccentText(T)
    local a = T.accent
    local target = T.mode == "light" and 0 or 1
    local c = { a[1], a[2], a[3], 1 }
    for step = 0, 20 do
        local t = step * 0.05
        c[1], c[2], c[3] = a[1] + (target - a[1]) * t, a[2] + (target - a[2]) * t, a[3] + (target - a[3]) * t
        if Ratio(c, T.bg) >= 4.5 and Ratio(c, T.bgAlt) >= 4.5 then break end
    end
    return c
end

-- Tokens computed from the accent and the mode; rerun whenever the accent changes.
local function Derive(T)
    local a = T.accent
    T.accentText = AccentText(T)
    T.accentSoft = { a[1], a[2], a[3], 0.22 }
    T.select = { a[1], a[2], a[3], 0.16 }
    T.thumb = { a[1], a[2], a[3], 0.6 }
    if T.mode == "light" then
        T.hover = { 0, 0, 0, 0.07 }
        T.track = { 0, 0, 0, 0.08 }
    else
        T.hover = { 1, 1, 1, 0.06 }
        T.track = { 1, 1, 1, 0.06 }
    end
end

Theme.signals = { repaints = 0 }
local liveSignature     -- host accent + panel + font as last painted
local bindings = setmetatable({}, { __mode = "k" })
local listeners = {}

-- Is the optional host (EllesmereUI) present?
local function EUI()
    return ns.Env.HasEUI() or nil
end

---------------------------------------------------------------------------
-- Accent
---------------------------------------------------------------------------

-- The host's accent, or nil without a host.
local function EUIAccent()
    if not EUI() then return nil end
    local r, g, b = ns.Env.Accent()
    if r then return r, g, b end
    return FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3]
end

-- The player's class color (the own class is never a secret value, guarded anyway).
local function ClassAccent()
    if type(UnitClass) ~= "function" then return nil end
    local _, class = UnitClass("player")
    if class == nil or ns.IsSecret(class) then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and type(c.r) == "number" then return c.r, c.g, c.b end
    return nil
end

local function AccentSettings()
    local s = ns.db and ns.db.settings
    return s and s.accent or nil
end

-- Effective mode: "eui" falls back to "theme" while EllesmereUI is not loaded.
function Theme.AccentMode()
    local a = AccentSettings()
    local mode = a and a.mode or "theme"
    if mode == "eui" and not EUI() then mode = "theme" end
    if mode ~= "theme" and mode ~= "eui" and mode ~= "class" and mode ~= "custom" then mode = "theme" end
    return mode
end

function Theme.CustomAccent()
    local a = AccentSettings()
    if a and type(a.r) == "number" and type(a.g) == "number" and type(a.b) == "number" then return a.r, a.g, a.b end
    return 0.24, 0.61, 1
end

-- Dropdown data: values { key = label }, order { key, ... }.
function Theme.AccentModes()
    local values, order = {}, {}
    local labels = {
        theme = L["Theme default"], eui = L["EllesmereUI accent"], class = L["Class color"], custom = L["Own color"],
    }
    for _, key in ipairs(MODES) do
        if key ~= "eui" or EUI() then
            values[key] = labels[key]
            order[#order + 1] = key
        end
    end
    return values, order
end

-- Text color on an accent fill: near-black or white, whichever has the higher contrast.
local function OnAccentFor(r, g, b)
    local fill, dark, white = { r, g, b }, { 0.05, 0.05, 0.06 }, { 1, 1, 1 }
    if Ratio(dark, fill) >= Ratio(white, fill) then return 0.05, 0.05, 0.06 end
    return 1, 1, 1
end

local function SetAccent(T, r, g, b, onAccent)
    T.accent[1], T.accent[2], T.accent[3], T.accent[4] = r, g, b, 1
    if onAccent then
        T.onAccent[1], T.onAccent[2], T.onAccent[3], T.onAccent[4] = onAccent[1], onAccent[2], onAccent[3], onAccent[4] or 1
    else
        T.onAccent[1], T.onAccent[2], T.onAccent[3] = OnAccentFor(r, g, b)
        T.onAccent[4] = 1
    end
    Derive(T)
end

-- Apply the accent setting to every theme and EUI's accent to the panel look.
local function Recompute()
    local mode = Theme.AccentMode()
    local er, eg, eb = EUIAccent()
    local cr, cg, cb
    if mode == "class" then cr, cg, cb = ClassAccent() end
    if mode == "custom" then cr, cg, cb = Theme.CustomAccent() end
    if mode == "eui" then cr, cg, cb = er, eg, eb end
    for key, T in pairs(themes) do
        local base = T.baseAccent
        local br, bg, bb = base[1], base[2], base[3]
        if key == "eui" and er then br, bg, bb = er, eg, eb end
        if cr then
            SetAccent(T, cr, cg, cb)
        elseif key == "eui" then
            SetAccent(T, br, bg, bb)
        else
            SetAccent(T, br, bg, bb, T.baseOnAccent)
        end
    end
    SetAccent(panel, er or FALLBACK_ACCENT[1], eg or FALLBACK_ACCENT[2], eb or FALLBACK_ACCENT[3])
end
Recompute()

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

-- Context of a frame: "eui" inside EUI pages, "user" (the chosen theme) everywhere else.
function Theme.CtxOf(obj)
    local node = obj
    while node do
        if node.fnCtx then return node.fnCtx end
        node = node.GetParent and node:GetParent() or nil
    end
    return "user"
end

local SyncOwn -- builds the own themes from the settings (defined with the theme editor functions below)

-- Key of the theme in use. A saved "eui" without EllesmereUI falls back to "standard" (the setting stays, so the
-- theme returns once EUI is enabled again).
function Theme.Current()
    SyncOwn()
    local key = ns.db and ns.db.settings.theme
    if key == "eui" and not EUI() then key = "standard" end
    if themes[key] then return key end
    if EUI() then return "eui" end
    local fallback = ns.PACKAGE and ns.PACKAGE.defaultTheme
    return themes[fallback] and fallback or "standard"
end

function Theme.Get(ctx)
    if ctx == "eui" and EUI() then return panel end
    return themes[Theme.Current()]
end

-- Tokens of any theme with its own accent (previews such as the theme gallery), nil for an unknown key.
function Theme.Tokens(key)
    SyncOwn()
    local T = themes[key]
    if not T then return nil end
    if key == "eui" then return T end
    return setmetatable({ accent = T.baseAccent, onAccent = T.baseOnAccent }, { __index = T })
end

-- Ordered list for dropdowns: { { key = "standard", label = "Standard" }, ... }; "eui" only while EUI is loaded, the
-- own themes (theme editor) last.
function Theme.List()
    SyncOwn()
    local list = {}
    for _, key in ipairs(ORDER) do
        if key ~= "eui" or EUI() then
            list[#list + 1] = { key = key, label = key == "eui" and themes.eui.label or L[themes[key].label] }
        end
    end
    for _, entry in ipairs(Theme.OwnList()) do list[#list + 1] = entry end
    return list
end

---------------------------------------------------------------------------
-- Font: the choice in settings.font (UI/Fonts.lua); "eui" = EllesmereUI's font while it is loaded
---------------------------------------------------------------------------

-- Chosen bundled/game font, else for "eui": the host's font; last STANDARD_TEXT_FONT.
function Theme.FontPath()
    local key = ns.Fonts and ns.Fonts.Current() or "eui"
    if key ~= "eui" then
        return ns.Fonts.File(key) or STANDARD_TEXT_FONT, ""
    end
    local path, flag = ns.Env.FontPath()
    return path or STANDARD_TEXT_FONT, flag or ""
end

function Theme.SetFont(fontObject, size)
    local path, flag = Theme.FontPath()
    if fontObject:SetFont(path, size, flag) == false then
        fontObject:SetFont(STANDARD_TEXT_FONT, size, flag)
    end
end

---------------------------------------------------------------------------
-- Painting primitives
---------------------------------------------------------------------------

-- Color a texture, line, font string or edit box with a token ({r, g, b, a}); alpha multiplies.
function Theme.Paint(region, color, alpha)
    if not (region and color) then return end
    local a = (color[4] or 1) * (alpha or 1)
    local kind = region:GetObjectType()
    if kind == "FontString" or kind == "EditBox" then
        region:SetTextColor(color[1], color[2], color[3], a)
    else
        region:SetColorTexture(color[1], color[2], color[3], a)
    end
end

local function PixelSize(frame, size)
    if PixelUtil and type(PixelUtil.GetNearestPixelSize) == "function" then
        return PixelUtil.GetNearestPixelSize(size, frame:GetEffectiveScale(), size)
    end
    return size
end

-- Thin lines at fractional pixel positions come out 1 or 2 px thick; snapping them to the pixel grid keeps them even.
function Theme.Crisp(texture)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(true) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

local function EnsureBox(frame)
    local box = frame.fnBox
    if box then return box end
    box = { edges = {} }
    box.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    box.bg:SetAllPoints()
    for i = 1, 4 do
        box.edges[i] = frame:CreateTexture(nil, "BORDER", nil, 7)
        Theme.Crisp(box.edges[i])
    end
    local top, bottom, left, right = box.edges[1], box.edges[2], box.edges[3], box.edges[4]
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    frame.fnBox = box
    return box
end

-- Fill and 1px edge from tokens. With a role ("window", "panel", "input", "button") a theme may use Blizzard art
-- instead (classic); the frame then needs BackdropTemplate. bgKey/edgeKey nil = no fill/edge.
function Theme.Box(frame, T, bgKey, edgeKey, role)
    local box = EnsureBox(frame)
    local art = role and T.backdrop and T.backdrop[role]
    if art and frame.SetBackdrop then
        frame:SetBackdrop(art.def)
        frame:SetBackdropColor(unpack(art.color))
        frame:SetBackdropBorderColor(unpack(art.edge))
        box.art = art
        box.bg:Hide()
        for i = 1, 4 do box.edges[i]:Hide() end
        return
    end
    if box.art then
        frame:SetBackdrop(nil)
        box.art = nil
    end
    if bgKey and T[bgKey] then
        Theme.Paint(box.bg, T[bgKey])
        box.bg:Show()
    else
        box.bg:Hide()
    end
    local size = PixelSize(frame, T.borderSize or 1)
    for i = 1, 4 do
        local edge = box.edges[i]
        if edgeKey and T[edgeKey] then
            if i <= 2 then edge:SetHeight(size) else edge:SetWidth(size) end
            Theme.Paint(edge, T[edgeKey])
            edge:Show()
        else
            edge:Hide()
        end
    end
end

-- Recolor the edge only (focus, selection); nil restores the art's own edge color.
function Theme.Edge(frame, color)
    local box = frame.fnBox
    if not box then return end
    if box.art then
        frame:SetBackdropBorderColor(unpack(color or box.art.edge))
    elseif color then
        for i = 1, 4 do Theme.Paint(box.edges[i], color) end
    end
end

---------------------------------------------------------------------------
-- Bindings and live refresh
---------------------------------------------------------------------------

local function Run(obj, fn)
    local ok, err = pcall(fn, obj, Theme.Get(Theme.CtxOf(obj)))
    if not ok then geterrorhandler()(err) end
end

-- fn(obj, T) paints obj now and again on every change. Context is resolved at paint time (frames may move hosts).
function Theme.Bind(obj, fn)
    local list = bindings[obj]
    if not list then
        list = {}
        bindings[obj] = list
    end
    list[#list + 1] = fn
    Run(obj, fn)
end

-- Repaint one object (after a state change such as hover, selection, enable).
function Theme.Refresh(obj)
    local list = bindings[obj]
    if not list then return end
    for i = 1, #list do Run(obj, list[i]) end
end

local function RepaintAll(userOnly)
    Theme.signals.repaints = Theme.signals.repaints + 1
    for obj, list in pairs(bindings) do
        if not userOnly or Theme.CtxOf(obj) == "user" then
            for i = 1, #list do Run(obj, list[i]) end
        end
    end
end

local function Notify()
    local key = Theme.Current()
    for i = 1, #listeners do listeners[i](key) end
end

-- fn(key) after the user theme or the accent changed (code that caches colors).
function Theme.OnChange(fn)
    listeners[#listeners + 1] = fn
end

function Theme.Set(key)
    if not (themes[key] and ns.db) then return false end
    if key == "eui" and not EUI() then return false end
    if ns.db.settings.theme == key then return true end
    ns.db.settings.theme = key
    RepaintAll(true)
    Notify()
    return true
end

---------------------------------------------------------------------------
-- Own themes (theme editor): settings.ownThemes = { own1 = { name, mode = "dark" | "light", colors = { bg = "rrggbb",
-- ... } }, ... }. Each becomes a theme like the built-in ones (key "own<n>"); the colors are opaque hex values.
---------------------------------------------------------------------------

-- Colors an own theme sets, in the editor's order.
Theme.OWN_TOKENS = { "bg", "bgAlt", "control", "inputBg", "border", "text", "textDim", "header", "accent", "onAccent",
    "danger" }
local OWN_PREFIX = "BT1:"
local ownRef -- the saved table the own themes were last built from

local function OwnStore(create)
    local s = ns.db and ns.db.settings
    if not s then return nil end
    if create and type(s.ownThemes) ~= "table" then s.ownThemes = {} end
    return type(s.ownThemes) == "table" and s.ownThemes or nil
end

local function ToHex(c)
    local function ch(v) return math.floor(math.max(0, math.min(1, v or 0)) * 255 + 0.5) end
    return string.format("%02x%02x%02x", ch(c[1]), ch(c[2]), ch(c[3]))
end

local function ValidHex(v)
    return type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil
end

-- A color over a fill, as one opaque color (see-through borders of the built-in themes become plain colors).
local function Over(fg, bg)
    local a = fg[4] or 1
    return { fg[1] * a + bg[1] * (1 - a), fg[2] * a + bg[2] * (1 - a), fg[3] * a + bg[3] * (1 - a), 1 }
end

local function Mix(c, target, t)
    return { c[1] + (target - c[1]) * t, c[2] + (target - c[2]) * t, c[3] + (target - c[3]) * t, 1 }
end

-- Theme tokens of an own theme; a missing color comes from Standard (dark) or Light.
local function BuildOwn(def)
    local light = def.mode == "light"
    local base = light and themes.light or themes.standard
    local T = { label = tostring(def.name or "?"), own = true, mode = light and "light" or "dark", inset = 1, pad = 8,
        borderSize = 1 }
    local colors = type(def.colors) == "table" and def.colors or {}
    for _, token in ipairs(Theme.OWN_TOKENS) do
        local hex = colors[token]
        if ValidHex(hex) then
            T[token] = Hex(hex)
        else
            local c = token == "accent" and base.baseAccent or token == "onAccent" and base.baseOnAccent or base[token]
            T[token] = { c[1], c[2], c[3], 1 }
        end
    end
    T.bg[4] = light and 0.98 or 0.97
    T.canvasBg = Mix(T.bg, light and 1 or 0, 0.25)
    T.success = Hex("30a46c")
    T.white = { 1, 1, 1, 1 }
    Opaque(T)
    T.baseAccent = { T.accent[1], T.accent[2], T.accent[3] }
    T.baseOnAccent = { T.onAccent[1], T.onAccent[2], T.onAccent[3], 1 }
    return T
end

local function OwnNumber(key)
    return tonumber(tostring(key):match("^own(%d+)$"))
end

-- (Re)builds the own themes when the saved table is new (login, reset). Cheap when nothing changed.
SyncOwn = function(force)
    local store = OwnStore(false)
    if store == ownRef and not force then return end
    ownRef = store
    for key, T in pairs(themes) do
        if T.own then themes[key] = nil end
    end
    if store then
        for key, def in pairs(store) do
            if OwnNumber(key) and type(def) == "table" then themes[key] = BuildOwn(def) end
        end
    end
    Recompute()
end

-- Own themes in the order they were made: { { key, label } }.
function Theme.OwnList()
    SyncOwn()
    local list = {}
    for key, T in pairs(themes) do
        if T.own then list[#list + 1] = { key = key, label = T.label, n = OwnNumber(key) } end
    end
    table.sort(list, function(a, b) return a.n < b.n end)
    for _, entry in ipairs(list) do entry.n = nil end
    return list
end

function Theme.IsOwn(key)
    SyncOwn()
    return themes[key] ~= nil and themes[key].own == true
end

-- The saved definition of an own theme (nil for other keys).
function Theme.OwnDef(key)
    local store = OwnStore(false)
    if not (store and OwnNumber(key)) then return nil end
    return store[key]
end

-- Rebuild after an edit and repaint every window that shows it.
local function OwnChanged()
    SyncOwn(true)
    RepaintAll(false)
    Notify()
end

local function NextKey(store)
    local n = 1
    while store["own" .. n] do n = n + 1 end
    return "own" .. n
end

-- A name not yet used by an own theme ("Name", "Name 2", ...).
local function FreeName(store, name)
    local used = {}
    for _, def in pairs(store) do
        if type(def) == "table" and def.name then used[def.name] = true end
    end
    if not used[name] then return name end
    local n = 2
    while used[name .. " " .. n] do n = n + 1 end
    return name .. " " .. n
end

-- Adds an own theme from a definition, returns its key.
local function AddOwn(def)
    local store = OwnStore(true)
    if not store then return nil end
    local key = NextKey(store)
    def.name = FreeName(store, def.name or L["Own theme"])
    store[key] = def
    OwnChanged()
    return key
end

-- New own theme as a copy of a theme (its own accent, see-through colors made opaque). Returns the key.
function Theme.NewOwn(fromKey)
    local T = Theme.Tokens(fromKey or Theme.Current()) or Theme.Tokens("standard")
    local fill = { T.bg[1], T.bg[2], T.bg[3], 1 }
    local colors = {}
    for _, token in ipairs(Theme.OWN_TOKENS) do
        local c = T[token]
        if token == "bg" then
            c = fill
        elseif token == "bgAlt" or token == "control" or token == "inputBg" or token == "border" then
            c = Over(c, fill)
        end
        colors[token] = ToHex(c)
    end
    local label = T.own and T.label or (fromKey == "eui" and T.label or L[T.label])
    return AddOwn({ name = label, mode = T.mode == "light" and "light" or "dark", colors = colors })
end

function Theme.SetOwnColor(key, token, r, g, b)
    local def = Theme.OwnDef(key)
    if not def or type(r) ~= "number" then return false end
    def.colors = type(def.colors) == "table" and def.colors or {}
    def.colors[token] = ToHex({ r, g, b })
    OwnChanged()
    return true
end

-- r, g, b of a color of an own theme (the built value, also for a missing one).
function Theme.OwnColor(key, token)
    SyncOwn()
    local T = themes[key]
    local c = T and T.own and (token == "accent" and T.baseAccent or token == "onAccent" and T.baseOnAccent or T[token])
    if not c then return 0.5, 0.5, 0.5 end
    return c[1], c[2], c[3]
end

function Theme.RenameOwn(key, name)
    local def = Theme.OwnDef(key)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if not def or name == "" then return false end
    if name ~= def.name then
        def.name = nil
        def.name = FreeName(OwnStore(false), name:sub(1, 40))
        OwnChanged()
    end
    return true
end

function Theme.SetOwnMode(key, mode)
    local def = Theme.OwnDef(key)
    if not def or (mode ~= "dark" and mode ~= "light") then return false end
    def.mode = mode
    OwnChanged()
    return true
end

-- Deletes an own theme; while it is in use, the theme falls back to the default.
function Theme.DeleteOwn(key)
    local store = OwnStore(false)
    if not (store and store[key]) then return false end
    store[key] = nil
    if ns.db.settings.theme == key then ns.db.settings.theme = nil end
    OwnChanged()
    return true
end

-- Contrast pairs the editor reports: { label, ratio, ok } (WCAG: 4.5:1 for text).
function Theme.OwnContrast(key)
    SyncOwn()
    local T = themes[key]
    if not (T and T.own) then return {} end
    local fill = { T.bg[1], T.bg[2], T.bg[3], 1 }
    local pairs_ = {
        { L["Text on the window"], T.text, fill },
        { L["Secondary text on the window"], T.textDim, fill },
        { L["Text on buttons"], T.text, T.control },
        { L["Headings on the header area"], T.header, T.bgAlt },
        { L["Accent as text"], T.baseAccent, fill },
        { L["Text on the accent"], T.baseOnAccent, T.baseAccent },
        { L["Warning on buttons"], T.danger, T.control },
    }
    local out = {}
    for i, p in ipairs(pairs_) do
        local ratio = Ratio(p[2], p[3])
        out[i] = { label = p[1], ratio = ratio, ok = ratio >= 4.5 }
    end
    return out
end

---------------------------------------------------------------------------
-- Sharing an own theme as one line of text: "BT1:" + Base64 of "name|mode|token=rrggbb;token=rrggbb;...".
---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, 64 do B64_VALUE[B64:byte(i)] = i - 1 end

local function Encode64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

-- nil when the text is no valid Base64
local function Decode64(text)
    text = text:gsub("%s", "")
    if #text == 0 or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local n, pad = 0, 0
        for j = 0, 3 do
            local ch = text:byte(i + j)
            local v = B64_VALUE[ch]
            if ch == 61 and i + j > #text - 2 then
                v, pad = 0, pad + 1
            elseif not v or pad > 0 then
                return nil
            end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a) .. (pad < 2 and string.char(b) or "") .. (pad < 1 and string.char(c) or "")
    end
    return table.concat(out)
end

function Theme.ExportOwn(key)
    SyncOwn()
    local def, T = Theme.OwnDef(key), themes[key]
    if not (def and T) then return nil end
    local parts = {}
    for _, token in ipairs(Theme.OWN_TOKENS) do
        parts[#parts + 1] = token .. "=" .. ToHex({ Theme.OwnColor(key, token) })
    end
    local name = tostring(def.name or ""):gsub("|", "/")
    return OWN_PREFIX .. Encode64(name .. "|" .. T.mode .. "|" .. table.concat(parts, ";"))
end

-- Imports a code as a new own theme (never overwrites one). Returns key, or nil + "code" | "data".
function Theme.ImportOwn(text)
    text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text:sub(1, #OWN_PREFIX) ~= OWN_PREFIX then return nil, "code" end
    local data = Decode64(text:sub(#OWN_PREFIX + 1))
    if not data then return nil, "data" end
    local name, mode, list = data:match("^([^|]*)|([^|]*)|(.*)$")
    if not name or (mode ~= "dark" and mode ~= "light") then return nil, "data" end
    local colors, count = {}, 0
    for token, hex in list:gmatch("(%w+)=(%x%x%x%x%x%x)") do
        for _, known in ipairs(Theme.OWN_TOKENS) do
            if known == token then
                colors[token] = hex:lower()
                count = count + 1
            end
        end
    end
    if count == 0 then return nil, "data" end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = L["Own theme"] end
    return AddOwn({ name = name:sub(1, 40), mode = mode, colors = colors })
end

-- Font choice: store it and repaint every text (Kit texts set their font in their paint functions).
function Theme.SetFontChoice(key)
    if not (ns.db and ns.Fonts) then return false end
    if key == "eui" and not EUI() then return false end
    if key ~= "eui" and not ns.Fonts.File(key) then return false end
    ns.db.settings.font = key
    liveSignature = nil
    Theme.CheckLive()
    return true
end

-- Recompute every accent from the setting and repaint everything (accent setting, class color after login).
function Theme.RefreshAccent()
    Recompute()
    RepaintAll(false)
    Notify()
end

function Theme.SetAccentMode(mode)
    local a = AccentSettings()
    if not a then return false end
    if mode == "eui" and not EUI() then return false end
    if mode ~= "theme" and mode ~= "eui" and mode ~= "class" and mode ~= "custom" then return false end
    a.mode = mode
    Theme.RefreshAccent()
    return true
end

-- Picking an own color switches the mode to "custom".
function Theme.SetCustomAccent(r, g, b)
    local a = AccentSettings()
    if not (a and type(r) == "number" and type(g) == "number" and type(b) == "number") then return false end
    a.r = math.max(0, math.min(1, r))
    a.g = math.max(0, math.min(1, g))
    a.b = math.max(0, math.min(1, b))
    a.mode = "custom"
    Theme.RefreshAccent()
    return true
end

-- Re-read the host's accent, panel colour and font; repaint everything when any of them changed. Called by the host's
-- change callbacks (poll = false) and on every OnShow of our windows (poll = true: the host drops values it cached).
local function CheckLive(poll)
    if poll then ns.Env.Poll() end
    local er, eg, eb = EUIAccent()
    local pr, pg, pb = ns.Env.PanelColor()
    local path, flag = Theme.FontPath()
    local signature = ("%s %s %s|%s|%s|%s"):format(tostring(er), tostring(eg), tostring(eb), tostring(pr), path, flag)
    if signature == liveSignature then return end
    liveSignature = signature
    if type(pr) == "number" then
        themes.eui.bg[1], themes.eui.bg[2], themes.eui.bg[3] = pr, pg, pb
        panel.bg[1], panel.bg[2], panel.bg[3] = pr, pg, pb
    end
    Recompute()
    RepaintAll(false)
    Notify() -- the skins of the packs restyle on accent, panel colour and font changes
end

function Theme.CheckLive()
    CheckLive(true)
end

ns.Env.OnChange(function() CheckLive(false) end)

---------------------------------------------------------------------------
-- Status palette: how the skin colours the states of Attune's cards and lines (see Adapters/Attune.lua NodeState).
-- Two schemes: "modern" (own palette) and "classic" (Attune's own tones). stripe = left card stripe and check mark,
-- fill / edge = card surface and border (nil = the theme's own bgAlt / border), edgeSize in px at 100 %,
-- line = connector colour, dim = muted title and desaturated icon, alpha = overall opacity.
---------------------------------------------------------------------------

local STATUS_ORDER = { "modern", "classic" }

local STATUS = {
    modern = {
        done = { stripe = Hex("30a46c"), line = Hex("30a46c") },
        ready = { stripe = Hex("ffb224"), fill = Hex("ffb224", 0.07), edge = Hex("ffb224", 0.55), line = Hex("ffb224") },
        locked = { stripe = Hex("4b5058"), line = Hex("4b5058"), dim = true },
        key_open = { stripe = Hex("e5484d"), fill = Hex("e5484d", 0.10), edge = Hex("e5484d"), edgeSize = 2,
            line = Hex("e5484d") },
        key_done = { stripe = Hex("3d9bff"), fill = Hex("3d9bff", 0.10), edge = Hex("3d9bff"), edgeSize = 2,
            line = Hex("3d9bff") },
        other_class = { stripe = Hex("4b5058"), line = Hex("4b5058"), dim = true, alpha = 0.5 },
        unknown = { stripeKey = "textDim", lineKey = "textDim" },
    },
    classic = {
        done = { stripe = Hex("5fba46"), fill = Hex("5fba46", 0.30), edge = Hex("5fba46"), line = Hex("63af63") },
        ready = { stripe = Hex("d99b00"), fill = Hex("d99b00", 0.30), edge = Hex("d99b00"), line = Hex("d99b00") },
        locked = { stripe = Hex("666666"), fill = Hex("1a1a1a", 0.5), edge = Hex("666666"), line = Hex("737373") },
        key_open = { stripe = Hex("8e0e13"), fill = Hex("8e0e13", 0.70), edge = Hex("ffffff"), line = Hex("8e0e13") },
        key_done = { stripe = Hex("0e4e93"), fill = Hex("0e4e93", 0.70), edge = Hex("ffffff"), line = Hex("0e4e93") },
        other_class = { stripe = Hex("666666"), fill = Hex("1a1a1a", 0.5), edge = Hex("666666"), line = Hex("737373"),
            alpha = 0.5 },
        unknown = { stripeKey = "textDim", lineKey = "textDim" },
    },
}

function Theme.StatusScheme()
    local key = ns.db and ns.db.settings.statusScheme
    return STATUS[key] and key or "modern"
end

-- Palette entry of a card/line state ("done", "ready", "locked", "key_open", "key_done", "other_class", "unknown").
-- Spacers have none. Unknown states get the neutral entry.
function Theme.Status(state)
    local scheme = STATUS[Theme.StatusScheme()]
    return scheme[state] or scheme.unknown
end

-- Dropdown data: values { key = label }, order { key, ... }.
function Theme.StatusSchemes()
    local labels = { modern = L["Modern"], classic = L["Attune classic"] }
    local values, order = {}, {}
    for _, key in ipairs(STATUS_ORDER) do
        values[key] = labels[key]
        order[#order + 1] = key
    end
    return values, order
end

function Theme.SetStatusScheme(key)
    if not (STATUS[key] and ns.db) then return false end
    if ns.db.settings.statusScheme == key then return true end
    ns.db.settings.statusScheme = key
    RepaintAll(false)
    Notify()
    return true
end

ns.OnReady(function()
    local s = ns.db.settings
    if not themes[s.theme] then
        local fallback = ns.PACKAGE and ns.PACKAGE.defaultTheme
        s.theme = EUI() and "eui" or (themes[fallback] and fallback or "standard")
    end
    if type(s.accent) ~= "table" then s.accent = { r = 0.24, g = 0.61, b = 1 } end
    local mode = s.accent.mode
    if mode ~= "theme" and mode ~= "eui" and mode ~= "class" and mode ~= "custom" then
        s.accent.mode = EUI() and "eui" or "theme"
    end
    if not STATUS[s.statusScheme] then s.statusScheme = "modern" end
    Recompute()
    CheckLive(true)
end)


-- The class color is certain only after login; repaint once then if the accent follows it.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if ns.db and Theme.AccentMode() == "class" then Theme.RefreshAccent() end
end)
