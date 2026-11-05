-- EllesmereUI reads of the Extras skins (chat sidebar, quest tracker settings and font). Accent, font, language and
-- panel colour come from the host (ns.Env). EllesmereUI is optional; every access is guarded: the calls are public but
-- mostly undocumented, so each may be missing in a newer EllesmereUI. Without it this file does nothing.
local _, ns = ...

-- EllesmereUI specific reads the skins use (all nil without EllesmereUI).
local EUI = {
    ChatData = function() return nil end,       -- EllesmereUI's per-chat-frame data (sidebar and its buttons)
    ChatSettings = function() return nil end,   -- chat settings of the active EllesmereUI profile
    TrackerSettings = function() return nil end, -- quest tracker settings of the active profile
    TrackerFont = function() return nil end,    -- path, flags, shadow of the quest tracker font
    PrimeShadow = function() end,               -- lets a FontString carry EllesmereUI's text shadow
    SidebarOrder = function() return nil end,   -- sidebar icon buttons of ChatFrame1 in chain order
}
ns.EUI = EUI

local function Lib()
    local e = rawget(_G, "EllesmereUI")
    return type(e) == "table" and e or nil
end

if not Lib() then return end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
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
