-- BeautifulSkins core: namespace, SavedVariables, locale choice, events, combat queue, refresh list, skin modules with
-- an error guard, slash command and compartment. Every skin lives in Modules\ and only ever restyles the frames of the
-- addon it belongs to; a skin whose addon is not loaded stays silent.
local addonName, ns = ...
local L = ns.L

ns.name = addonName
BeautifulSkins = ns -- the only addon global besides SavedVariables, slash and compartment callbacks

local PREFIX = "|cff0cd29d[BeautifulSkins]|r "
local DB_VERSION = 1
local MAX_ERRORS = 3

ns.DEFAULTS = {
    version = DB_VERSION,
    language = "auto",          -- "auto" | "enUS" | "deDE", applied at load
    integrateEUI = true,        -- section in the EllesmereUI options window, applied at load
    accentMode = "eui",         -- "eui" (EllesmereUI accent, else jade) | "class" | "custom"
    accentCustom = { r = 0.047, g = 0.824, b = 0.616 },
    -- skins, each can be switched off (takes effect after /reload)
    modules = {
        whisper = true, whisperButton = true, skillup = true, waypoint = true,
        gqTracker = true, gqArrow = true, gqWindow = true, gqPopups = true,
    },
    whisper = {
        look = true,            -- Whisper Messenger's dark preset, flat frame and the EllesmereUI font
        hideOwnIcons = true,    -- hide Whisper Messenger's floating and minimap icons while our chat button exists
        corner = "TOPRIGHT",    -- chat button without EllesmereUI Chat: corner of the first chat window
        hover = true,           -- ... shown only while the mouse is over the chat (or a whisper is unread)
        glow = true,            -- the button glows while a whisper is unread
        offset = { x = 0, y = 0 }, -- chat button inside the EllesmereUI sidebar: moved by Shift-drag (free move)
        -- backup = { ... }     -- Whisper Messenger's own values before we changed them
    },
    skillup = { background = 75 },
    waypoint = { color = "accent", recolorIcon = true, font = true },
    gqTracker = { background = 60, column = false }, -- column: hunts in the Forever tracker column
    arrow = {
        style = "CHEVRON",      -- "CHEVRON" | "RING" | "PILL" | "CLASSIC"
        color = "ACCENT",       -- "ACCENT" | "DIRECTION" | "CUSTOM"
        customColor = { r = 1, g = 0.82, b = 0 },
        scale = 0.8,
        unit = "yd",            -- "yd" | "m"
        showDistance = true,
        showName = true,
        detached = false,       -- free arrow (own movable frame) instead of above GearQuest's tracker
        locked = true,          -- free arrow: no mouse (click-through) while locked
        -- point = { point, relPoint, x, y } -- free arrow position
    },
    gqWindow = { hidePortrait = true },
}

local frame = CreateFrame("Frame")
local handlers = {}
local pending = {}
local readyCallbacks = {}
local addonCallbacks = {}
local refreshers = {}

-- Secret values may not be compared, branched on or printed. Guard before use.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) and true or false
end

function ns.CanAccess(value)
    return not ns.IsSecret(value)
end

function ns.Say(text)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text, 0.95, 0.95, 0.95)
end

function ns.Version()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = type(getter) == "function" and getter(addonName, "Version") or nil
    return type(version) == "string" and version or "?"
end

function ns.IsLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end

-- Run an action now, or after combat ends.
function ns.Queue(action)
    if InCombatLockdown() then
        pending[#pending + 1] = action
    else
        action()
    end
end

function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    local list = handlers[event]
    list[#list + 1] = fn
end

-- Work that needs the database and the final locale (runs at the end of our ADDON_LOADED).
function ns.OnReady(callback)
    if ns.db then
        callback()
    else
        readyCallbacks[#readyCallbacks + 1] = callback
    end
end

-- fn() when another addon finishes loading; at once when it is already loaded. Our frame was created before the other
-- addon's files ran, so this usually runs before that addon's own ADDON_LOADED handler.
function ns.OnAddonLoaded(name, fn)
    if ns.IsLoaded(name) then
        fn(true)
        return
    end
    local list = addonCallbacks[name] or {}
    addonCallbacks[name] = list
    list[#list + 1] = fn
end

-- Refreshers re-apply looks after an option, the accent or the font changed.
function ns.OnRefresh(fn)
    refreshers[#refreshers + 1] = fn
end

function ns.RefreshAll()
    for i = 1, #refreshers do
        local ok, err = pcall(refreshers[i])
        if not ok then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Modules: Modules.Register(id, { addon = "<folder>", setting = "<key in modules>", Enable = fn })
-- Enable runs once, at login or when the addon loads later. A module whose handlers fail MAX_ERRORS times is switched
-- off for the session; the first error goes to the error handler (BugSack), the skinned addon never sees it.
-- Status: off (setting), missing (addon not loaded), active, failed.
---------------------------------------------------------------------------

local Modules = { order = {}, byId = {} }
ns.Modules = Modules

function Modules.Register(id, def)
    def.id = id
    def.status = "registered"
    def.errors = 0
    Modules.byId[id] = def
    Modules.order[#Modules.order + 1] = def
    return def
end

function Modules.IsActive(id)
    local def = Modules.byId[id]
    return def ~= nil and def.status == "active"
end

function Modules.SwitchedOn(id)
    local def = Modules.byId[id]
    if not (def and ns.db) then return false end
    return ns.db.modules[def.setting or id] ~= false
end

function Modules.Fail(id, err)
    local def = Modules.byId[id]
    if not def then
        geterrorhandler()(err)
        return
    end
    def.errors = def.errors + 1
    if def.errors == 1 then
        def.firstError = tostring(err)
        geterrorhandler()(("%s [%s]: %s"):format(addonName, id, tostring(err)))
    end
    if def.errors >= MAX_ERRORS and def.status == "active" then
        def.status = "failed"
    end
end

-- Runs a handler of a module through pcall; does nothing while the module is not active.
function ns.Run(id, handler, ...)
    if not Modules.IsActive(id) then return end
    local ok, err = pcall(handler, ...)
    if not ok then Modules.Fail(id, err) end
end

-- A function for hooksecurefunc / HookScript that runs guarded for module id.
function ns.Guard(id, handler)
    return function(...)
        ns.Run(id, handler, ...)
    end
end

local function TryEnable(def)
    if def.status ~= "registered" and def.status ~= "missing" then return end
    if not Modules.SwitchedOn(def.id) then
        def.status = "off"
        return
    end
    if def.addon and not ns.IsLoaded(def.addon) then
        def.status = "missing"
        return
    end
    def.status = "active"
    if def.Enable then
        local ok, err = pcall(def.Enable)
        if not ok then
            Modules.Fail(def.id, err)
            def.status = "failed"
        end
    end
end

function Modules.EnableAll()
    for _, def in ipairs(Modules.order) do TryEnable(def) end
end

---------------------------------------------------------------------------
-- Database, locale
---------------------------------------------------------------------------

local function Fill(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Fill(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ns.ResetSettings()
    local backup = ns.db and ns.db.whisper and ns.db.whisper.backup
    wipe(BeautifulSkinsDB)
    Fill(BeautifulSkinsDB, ns.DEFAULTS)
    BeautifulSkinsDB.whisper.backup = backup -- Whisper Messenger's own values must still go back to it one day
    ns.db = BeautifulSkinsDB
    ns.RefreshAll()
end

local function ApplyLocale()
    local code = ns.db.language
    if code == "auto" then
        code = ns.PreferredLocale and ns.PreferredLocale() or nil
        if type(code) ~= "string" then code = GetLocale() end
    end
    if code == "enGB" then code = "enUS" end
    ns.locale = code
    local catalog = ns.locales[code]
    if catalog then
        for key, text in pairs(catalog) do rawset(L, key, text) end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            if type(BeautifulSkinsDB) ~= "table" then BeautifulSkinsDB = {} end
            Fill(BeautifulSkinsDB, ns.DEFAULTS)
            ns.db = BeautifulSkinsDB
            ApplyLocale()
            local list = readyCallbacks
            readyCallbacks = {}
            for i = 1, #list do
                local ok, err = pcall(list[i])
                if not ok then geterrorhandler()(err) end
            end
        elseif addonCallbacks[name] then
            local list = addonCallbacks[name]
            addonCallbacks[name] = nil
            for i = 1, #list do
                local ok, err = pcall(list[i], false)
                if not ok then geterrorhandler()(err) end
            end
            if ns.loggedIn then Modules.EnableAll() end -- a skinned addon that loads on demand
        end
    elseif event == "PLAYER_LOGIN" then
        ns.loggedIn = true
        Modules.EnableAll()
        ns.RefreshAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local list = pending
        pending = {}
        for i = 1, #list do
            local ok, err = pcall(list[i])
            if not ok then geterrorhandler()(err) end
        end
    end
    local list = handlers[event]
    if list then
        for i = 1, #list do
            local ok, err = pcall(list[i], event, ...)
            if not ok then geterrorhandler()(err) end
        end
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

---------------------------------------------------------------------------
-- Status, slash command, compartment
---------------------------------------------------------------------------

local STATUS_TEXT = {
    active = { "3fbf5f", "active" }, off = { "999999", "off" }, missing = { "999999", "addon not loaded" },
    failed = { "e5534b", "failed" }, registered = { "999999", "waiting" },
}

function ns.ModuleStatus(def)
    local s = STATUS_TEXT[def.status]
    if not s then return tostring(def.status) end
    return ("|cff%s%s|r"):format(s[1], L[s[2]])
end

function ns.PrintStatus()
    ns.Say(("%s %s, EllesmereUI: %s"):format(L["Version"], ns.Version(), ns.HasEUI() and L["yes"] or L["no"]))
    for _, def in ipairs(Modules.order) do
        local line = ("  %s: %s"):format(def.label and L[def.label] or def.id, ns.ModuleStatus(def))
        if def.firstError then line = line .. "  " .. def.firstError end
        ns.Say(line)
    end
end

function ns.OpenOptions()
    if InCombatLockdown() then
        ns.Say(L["Options open after combat."])
        ns.Queue(ns.OpenOptions)
        return
    end
    if ns.hosts and ns.hosts.eui and ns.hosts.eui.Open() then return end
    if ns.OpenSettingsPanel and ns.OpenSettingsPanel() then return end
    ns.PrintStatus()
end

SLASH_BEAUTIFULSKINS1 = "/bskins"
SLASH_BEAUTIFULSKINS2 = "/beautifulskins"
SlashCmdList.BEAUTIFULSKINS = function(msg)
    local cmd = type(msg) == "string" and msg:lower():match("^%s*(%S*)") or ""
    if cmd == "status" then
        ns.PrintStatus()
    elseif cmd == "whisper" then
        if ns.WhisperButton and ns.WhisperButton.Debug then ns.WhisperButton.Debug() end
    elseif cmd == "reset" then
        ns.ResetSettings()
        ns.Say(L["Settings reset. /reload applies every part."])
    elseif cmd == "help" then
        ns.Say("/bskins - " .. L["options"])
        ns.Say("/bskins status - " .. L["state of every skin"])
        ns.Say("/bskins reset - " .. L["reset all settings"])
        ns.Say("/bskins whisper - " .. L["state of the Whisper Messenger button"])
    else
        ns.OpenOptions()
    end
end

function BeautifulSkins_OnCompartmentClick(_, button)
    if button == "RightButton" then
        ns.PrintStatus()
    else
        ns.OpenOptions()
    end
end

function BeautifulSkins_OnCompartmentEnter(_, menuButton)
    local owner = menuButton or AddonCompartmentFrame
    if not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("BeautifulSkins")
    GameTooltip:AddLine(L["Left-click: options"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: state of every skin"], 1, 1, 1)
    GameTooltip:Show()
end

function BeautifulSkins_OnCompartmentLeave()
    GameTooltip:Hide()
end
