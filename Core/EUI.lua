-- EllesmereUI adapter: the ONLY place besides Integration/EUIPages.lua that touches EllesmereUI. EllesmereUI is optional
-- (## OptionalDeps: it loads before this file when it is enabled). Without it this file does nothing; with it, it answers
-- ns.Env with EllesmereUI's accent, font, language and panel colour and reports live changes. Every access is guarded:
-- the calls used here are public but undocumented (V-N4), so each one may be missing in a newer EllesmereUI.
local _, ns = ...
local Env = ns.Env

local function EUI()
    return type(EllesmereUI) == "table" and EllesmereUI or nil
end

if not EUI() then return end

local liveAccent -- accent as passed by the accent callback (it can arrive before GetAccentColor changes)
local skinApi    -- facade from RegisterSkin, only when EllesmereUI's skin child is active

local signals = { accent = 0, looks = 0, skinRan = false } -- read by the status command when something looks wrong
ns.EUISignals = signals

function Env.HasEUI()
    return EUI() ~= nil
end

function Env.Accent()
    local E = EUI()
    if not E then return nil end
    if liveAccent then return liveAccent[1], liveAccent[2], liveAccent[3] end
    if type(E.GetAccentColor) == "function" then
        local ok, r, g, b = pcall(E.GetAccentColor)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return nil
end

function Env.FontPath()
    local E = EUI()
    local path, flag
    if E and type(E.GetFontPath) == "function" then
        local ok, p = pcall(E.GetFontPath)
        if ok and type(p) == "string" and p ~= "" then path = p end
    end
    if E and type(E.GetFontOutlineFlag) == "function" then
        local ok, f = pcall(E.GetFontOutlineFlag)
        if ok and type(f) == "string" then flag = f end
    end
    if not path and skinApi and type(skinApi.GetFont) == "function" then
        local ok, p, f = pcall(skinApi.GetFont)
        if ok and type(p) == "string" and p ~= "" then path, flag = p, f end
    end
    return path, flag
end

function Env.Locale()
    local E = EUI()
    local locale = E and E.LOCALE
    if type(locale) == "string" and locale ~= "" then return locale end
    return nil
end

function Env.PanelColor()
    if skinApi and type(skinApi.GetPanelColor) == "function" then
        local ok, r, g, b = pcall(skinApi.GetPanelColor)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return nil
end

function Env.Poll()
    liveAccent = nil
end

ns.OnReady(function()
    local E = EUI()
    if not E then return end
    if type(E.RegAccent) == "function" then
        pcall(E.RegAccent, { type = "callback", fn = function(r, g, b)
            signals.accent = signals.accent + 1
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then liveAccent = { r, g, b } end
            Env.Changed()
        end })
    end
    -- Documented skin API; it runs only with the Blizzard skin child. Used as a signal and for the panel colour.
    if type(E.RegisterSkin) == "function" then
        pcall(E.RegisterSkin, ns.name, function(S)
            signals.skinRan = true
            if type(S) ~= "table" then return end
            skinApi = S
            if type(S.OnLooksChanged) == "function" then
                S.OnLooksChanged(function()
                    signals.looks = signals.looks + 1
                    liveAccent = nil
                    Env.Changed()
                end)
            end
            Env.Changed()
        end)
    end
end)
