-- Extras pack core: SavedVariables, events, refresh list and the skin modules with an error guard. Every skin lives
-- in Modules\ and only ever restyles the frames of the addon it belongs to; a skin whose addon is not loaded stays
-- silent. Look, language, options window and slash command belong to the host (ns.host).
local addonName, ns = ...
local L = ns.L
local host = ns.host

local DB_NAME = "BeautifulSkinsExtrasDB"
local DB_VERSION = 1
local MAX_ERRORS = 3

host.PackLocale(ns)

ns.DEFAULTS = {
    version = DB_VERSION,
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
local readyCallbacks = {}
local addonCallbacks = {}
local refreshers = {}







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
    local db = _G[DB_NAME]
    local backup = db and db.whisper and db.whisper.backup
    wipe(db)
    Fill(db, ns.DEFAULTS)
    db.whisper.backup = backup -- Whisper Messenger's own values must still go back to it one day
    ns.db = db
    ns.RefreshAll()
end

-- BeautifulSkins 0.1 kept these options in the host's SavedVariables; the host parks them in db.legacy and the pack
-- takes them over once (Whisper Messenger's remembered values included).
local function TakeLegacy(db)
    local legacy = host.db and host.db.legacy
    if type(legacy) ~= "table" or host.PACKAGE.legacyPack ~= "Extras" then return end
    for key, value in pairs(legacy) do
        if db[key] == nil then db[key] = value end
    end
    host.db.legacy = nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- This pack loads on demand from inside the host's ADDON_LOADED, so our own ADDON_LOADED is queued rather than
-- delivered during that call, and the client may hand us PLAYER_LOGIN first (BeautifulSkins_RestedXP hit exactly that
-- on the first start of the Forever release; Modules.EnableAll reads ns.db). Runs from whichever event is first, once.
local function Ready()
    if ns.db then return end
    local db = _G[DB_NAME]
    if type(db) ~= "table" then db = {} end
    TakeLegacy(db)
    Fill(db, ns.DEFAULTS)
    _G[DB_NAME] = db
    ns.db = db
    local list = readyCallbacks
    readyCallbacks = {}
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then geterrorhandler()(err) end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            Ready()
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
        Ready()
        ns.loggedIn = true
        Modules.EnableAll()
        ns.RefreshAll()
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

---------------------------------------------------------------------------
-- Status and registration with the host
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

local function Counts()
    local active, total = 0, 0
    for _, def in ipairs(Modules.order) do
        if def.status ~= "missing" then total = total + 1 end
        if def.status == "active" then active = active + 1 end
    end
    return active, total
end

host.RegisterPack(ns, {
    key = "Extras",
    title = L["More skins"],
    modules = function() return ns.Settings.Modules() end,
    status = function()
        local active, total = Counts()
        return L["%d of %d skins active"]:format(active, total)
    end,
    info = function()
        local lines = {}
        for _, def in ipairs(Modules.order) do
            local line = ("%s: %s"):format(L[def.label or def.id], ns.ModuleStatus(def))
            if def.firstError then line = line .. "  " .. def.firstError end
            lines[#lines + 1] = line
        end
        return lines
    end,
    commands = function()
        return { L["%s whisper - state of the Whisper Messenger button"]:format(host.PACKAGE.slash[1]) }
    end,
    actions = function()
        local list = {}
        if ns.GearQuestArrow and ns.Modules.IsActive("gqArrow") and ns.db.arrow.detached then
            list[#list + 1] = { text = ns.db.arrow.locked and L["Unlock the GearQuest arrow"] or L["Lock the GearQuest arrow"],
                fn = function()
                    ns.db.arrow.locked = not ns.db.arrow.locked
                    ns.RefreshAll()
                end }
        end
        return list
    end,
})

-- /bskins whisper: the host hands unknown sub-commands to the packs through ns.devCommands-like hooks.
host.devCommands = host.devCommands or {}
host.devCommands.whisper = function()
    if ns.WhisperButton and ns.WhisperButton.Debug then ns.WhisperButton.Debug() end
end
