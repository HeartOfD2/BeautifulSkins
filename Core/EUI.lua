-- EllesmereUI adapter: the only file besides Settings\EUIPages.lua that touches EllesmereUI. EllesmereUI is optional
-- (## OptionalDeps: it loads before this file when it is enabled). Every access is guarded: the calls are public but
-- mostly undocumented, so each may be missing in a newer EllesmereUI. Without it this file does nothing.
local _, ns = ...
local Env, EUI = ns.Env, ns.EUI

local function Lib()
    local e = rawget(_G, "EllesmereUI")
    return type(e) == "table" and e or nil
end

if not Lib() then return end

local liveAccent -- accent as passed by the accent callback (it can arrive before GetAccentColor changes)
local skinApi    -- facade from RegisterSkin, only when EllesmereUI's skin child is active

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

function Env.HasEUI()
    return Lib() ~= nil
end

function Env.Accent()
    if liveAccent then return liveAccent[1], liveAccent[2], liveAccent[3] end
    local E = Lib()
    local r, g, b = Call(E and E.GetAccentColor)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil
end

function Env.FontPath()
    local E = Lib()
    local path = Call(E and E.GetFontPath)
    local flag = Call(E and E.GetFontOutlineFlag)
    if (type(path) ~= "string" or path == "") and skinApi then
        path, flag = Call(skinApi.GetFont)
    end
    if type(path) ~= "string" or path == "" then return nil end
    return path, type(flag) == "string" and flag or ""
end

function Env.Locale()
    local E = Lib()
    local locale = E and E.LOCALE
    if type(locale) == "string" and locale ~= "" then return locale end
    return nil
end

function Env.PanelColor()
    local r, g, b = Call(skinApi and skinApi.GetPanelColor)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil
end

-- ------------------------------------------------------------------------------------------- chat and quest tracker

local function Loaded(name)
    return ns.IsLoaded(name)
end

-- EllesmereUI's per-chat-frame data (sidebar, its buttons, background); internal, read only.
function EUI.ChatData(cf)
    if not (Loaded("EllesmereUIChat") and cf) then return nil end
    local E = Lib()
    local d = Call(E and E._chatCFD, cf)
    return type(d) == "table" and d or nil
end

function EUI.ChatSettings()
    if not Loaded("EllesmereUIChat") then return nil end
    local db = rawget(_G, "_ECHAT_DB")
    local p = type(db) == "table" and type(db.profile) == "table" and db.profile or nil
    return p and type(p.chat) == "table" and p.chat or nil
end

function EUI.TrackerSettings()
    if not Loaded("EllesmereUIQuestTracker") then return nil end
    local db = rawget(_G, "_EQT_DB")
    local p = type(db) == "table" and type(db.profile) == "table" and db.profile or nil
    return p and type(p.questTracker) == "table" and p.questTracker or nil
end

function EUI.TrackerFont()
    local E = Lib()
    local path = Call(E and E.GetFontPath, "questTracker")
    local flags = Call(E and E.GetFontOutlineFlag, "questTracker")
    local shadow = Call(E and E.GetFontUseShadow, "questTracker")
    if type(path) ~= "string" or path == "" then return nil end
    return path, type(flags) == "string" and flags or "", shadow
end

function EUI.PrimeShadow(fs, shadow)
    local E = Lib()
    if E and type(E.PrimeFontShadow) == "function" then pcall(E.PrimeFontShadow, fs, shadow) end
end

-- Sidebar keys (visibility setting -> button field of the chat data), in EllesmereUI's default chain order.
local CHAIN = {
    { key = "showFriends", btn = "friendsBtn", tail = "friendsCount" },
    { key = "showGuild", btn = "guildBtn", tail = "guildCount" },
    { key = "showDurability", btn = "durabilityBtn", tail = "durabilityPct" },
    { key = "showCopy", btn = "copyBtn" },
    { key = "showPortals", btn = "portalBtn" },
    { key = "showVoice", btn = "voiceBtn" },
    { key = "showChatMenu", btn = "chatMenuBtn" },
    { key = "showSettings", btn = "settingsBtn" },
}

-- { { button, tail } ... } of ChatFrame1's sidebar in the order EllesmereUI chained them at login, plus the sidebar.
function EUI.SidebarOrder()
    local d = EUI.ChatData(rawget(_G, "ChatFrame1"))
    local sidebar = d and d.sidebar
    if type(sidebar) ~= "table" then return nil end
    local byKey = {}
    for _, entry in ipairs(CHAIN) do byKey[entry.key] = entry end
    local order = type(d._iconChainOrder) == "table" and d._iconChainOrder or nil
    local list = {}
    local function Add(entry)
        local btn = entry and d[entry.btn]
        if type(btn) == "table" and type(btn.IsShown) == "function" then
            list[#list + 1] = { button = btn, tail = entry.tail and d[entry.tail] or nil }
        end
    end
    if order then
        for _, key in ipairs(order) do Add(byKey[key]) end
    else
        for _, entry in ipairs(CHAIN) do Add(entry) end
    end
    return list, sidebar, d
end

-- --------------------------------------------------------------------------------------------- live changes

ns.OnReady(function()
    local E = Lib()
    if not E then return end
    if type(E.RegAccent) == "function" then
        pcall(E.RegAccent, { type = "callback", fn = function(r, g, b)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then liveAccent = { r, g, b } end
            Env.Changed()
        end })
    end
    if type(E.RegisterSkin) == "function" then
        pcall(E.RegisterSkin, "BeautifulSkins", function(S)
            if type(S) ~= "table" then return end
            skinApi = S
            if type(S.OnLooksChanged) == "function" then
                S.OnLooksChanged(function()
                    liveAccent = nil
                    Env.Changed()
                end)
            end
            Env.Changed()
        end)
    end
end)
