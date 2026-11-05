-- Font choice for every text of our own windows: the host's font (only while EllesmereUI is loaded), the game's fonts or one of
-- the bundled text fonts (Barlow, Fira Sans, Inter; SIL Open Font License, licenses next to the files). Stored as a key in
-- settings.font; keys are saved, never rename one.
local addonName, ns = ...
local L = ns.L

local Fonts = {}
ns.Fonts = Fonts

local DIR = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"

-- Client locales whose letters the bundled Latin/Cyrillic fonts cannot show: there only the game font is offered.
local CJK = { koKR = true, zhCN = true, zhTW = true }

-- latin = Latin only (no Cyrillic); file nil = STANDARD_TEXT_FONT (the game's font for the client language)
Fonts.LIST = {
    { key = "game", file = nil },
    { key = "arial", name = "Arial Narrow", file = "Fonts\\ARIALN.TTF", latin = true },
    { key = "barlow", name = "Barlow", file = DIR .. "Barlow-Regular.ttf", latin = true },
    { key = "barlowSemi", name = "Barlow SemiBold", file = DIR .. "Barlow-SemiBold.ttf", latin = true },
    { key = "barlowBold", name = "Barlow Bold", file = DIR .. "Barlow-Bold.ttf", latin = true },
    { key = "firaSans", name = "Fira Sans", file = DIR .. "FiraSans-Regular.ttf" },
    { key = "firaSansSemi", name = "Fira Sans SemiBold", file = DIR .. "FiraSans-SemiBold.ttf" },
    { key = "firaSansBold", name = "Fira Sans Bold", file = DIR .. "FiraSans-Bold.ttf" },
    { key = "inter", name = "Inter", file = DIR .. "Inter_18pt-Regular.ttf" },
    { key = "interSemi", name = "Inter SemiBold", file = DIR .. "Inter_18pt-SemiBold.ttf" },
    { key = "interBold", name = "Inter Bold", file = DIR .. "Inter_18pt-Bold.ttf" },
}

local byKey = {}
for _, f in ipairs(Fonts.LIST) do byKey[f.key] = f end

local function ClientLocale()
    return type(GetLocale) == "function" and GetLocale() or "enUS"
end

-- Default without a host font (with EllesmereUI: "eui").
function Fonts.Default()
    if CJK[ClientLocale()] then return "game" end
    return "firaSansSemi"
end

local usable = {}
local probe

-- Can the client load this file? Unknown or broken files are never offered and never an error.
function Fonts.Usable(file)
    if not file then return true end
    if usable[file] ~= nil then return usable[file] end
    local ok, result = pcall(function()
        probe = probe or CreateFont(addonName .. "FontProbe")
        return probe:SetFont(file, 12, "")
    end)
    usable[file] = ok and result ~= false
    return usable[file]
end

local function Offered(f)
    local locale = ClientLocale()
    if CJK[locale] and f.file then return false end
    if locale == "ruRU" and f.latin then return false end
    return Fonts.Usable(f.file)
end

-- File of a font key (nil key or unknown = nil); "game" = STANDARD_TEXT_FONT.
function Fonts.File(key)
    local f = byKey[key]
    if not f or not Offered(f) then return nil end
    return f.file or STANDARD_TEXT_FONT
end

function Fonts.Name(key)
    if key == "eui" then return L["EllesmereUI font"] end
    if key == "game" then return L["Game font"] end
    local f = byKey[key]
    return f and f.name or tostring(key)
end

-- The effective choice: "eui" only while EllesmereUI is loaded, unknown or unusable keys fall back to the default.
function Fonts.Current()
    local key = ns.db and ns.db.settings.font
    if key == "eui" then
        if ns.HasEUI() then return "eui" end
        key = nil
    end
    if key and Fonts.File(key) then return key end
    return Fonts.Default()
end

-- Dropdown data: labels { key = name }, order { key, ... }, files { key = path } (menus show each name in its font).
function Fonts.Values()
    local labels, order, files = {}, {}, {}
    if ns.HasEUI() then
        labels.eui, order[1] = Fonts.Name("eui"), "eui"
    end
    for _, f in ipairs(Fonts.LIST) do
        if Offered(f) then
            labels[f.key] = Fonts.Name(f.key)
            order[#order + 1] = f.key
            files[f.key] = f.file or STANDARD_TEXT_FONT
        end
    end
    return labels, order, files
end

ns.OnReady(function()
    local s = ns.db.settings
    if s.font == nil then s.font = ns.HasEUI() and "eui" or Fonts.Default() end
end)
