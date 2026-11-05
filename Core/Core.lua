-- Host core: namespace, SavedVariables, locale, events, combat queue, skin packs, options router, slash command,
-- compartment. The host owns everything the packs share (look, fonts, options window, the EllesmereUI section); a pack
-- is a LoadOnDemand addon next to the host (BeautifulSkins_<Key>) that links its namespace to this one (Pack.lua in the
-- pack) and registers its options here. Which packs exist comes from Package.lua.
local addonName, ns = ...
local L = ns.L
local P = ns.PACKAGE

ns.name = addonName
_G[addonName] = ns -- the only addon global besides SavedVariables, slash and compartment callbacks; packs find it here

local PREFIX = "|cff" .. (P.color or "0cd29d") .. "[" .. P.title .. "]|r "
local DB_VERSION = 2

local defaults = {
    version = DB_VERSION,
    settings = {
        language = "auto",      -- "auto" | "enUS" | "deDE", applied at load
        integrateEUI = true,    -- options section in the EllesmereUI options window, applied at load
        minimap = { hide = false, angle = 215 },
        options = {},           -- options window geometry and last page
        packs = {},             -- [key] = false switches a pack off (takes effect after /reload)
        -- theme, font, accent = { mode, r, g, b }, statusScheme: written by UI/Theme.lua and UI/Fonts.lua
    },
}

local frame = CreateFrame("Frame")
local events = {}
local handlers = {}
local pending = {}
local readyCallbacks = {}

---------------------------------------------------------------------------
-- Small helpers every pack uses
---------------------------------------------------------------------------

-- Secret values may not be compared, branched on or printed. Guard before use.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) and true or false
end

function ns.CanAccess(value)
    if type(canaccessvalue) == "function" then return canaccessvalue(value) and true or false end
    return not ns.IsSecret(value)
end

function ns.SafeString(value, fallback)
    if value == nil or ns.IsSecret(value) then return fallback end
    return tostring(value)
end

function ns.Say(text)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text, 0.95, 0.95, 0.95)
end

function ns.Version(name)
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = type(getter) == "function" and getter(name or addonName, "Version") or nil
    return type(version) == "string" and version or "?"
end

function ns.IsLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end

-- Run an action now, or after combat ends when it touches protected frames.
function ns.Queue(action)
    if InCombatLockdown() then
        pending[#pending + 1] = action
    else
        action()
    end
end

-- Work that needs the database and the final locale (runs at the end of our ADDON_LOADED, after the packs loaded).
function ns.OnReady(callback)
    if ns.ready then
        callback()
    else
        readyCallbacks[#readyCallbacks + 1] = callback
    end
end

-- Extra event handlers for host files (the frame dispatches to every registered function).
function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    local list = handlers[event]
    list[#list + 1] = fn
end

---------------------------------------------------------------------------
-- Saved variables and locale
---------------------------------------------------------------------------

local function MergeDefaults(db, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then db[key] = {} end
            MergeDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end
ns.MergeDefaults = MergeDefaults

-- Version 1 is the layout of BeautifulSkins 0.1 (every skin option at the top level). Those options belong to the
-- Extras pack now: they move to db.legacy, which the pack takes over once.
local ACCENT_V1 = { eui = "eui", class = "class", custom = "custom" }

local function Migrate(db)
    if (db.version or 1) < 2 and db.settings == nil then
        local legacy = {}
        for key, value in pairs(db) do
            if key ~= "version" then legacy[key] = value end
        end
        for key in pairs(legacy) do db[key] = nil end
        db.settings = {
            language = legacy.language,
            integrateEUI = legacy.integrateEUI,
        }
        if legacy.accentMode and ACCENT_V1[legacy.accentMode] then
            local c = type(legacy.accentCustom) == "table" and legacy.accentCustom or {}
            db.settings.accent = { mode = ACCENT_V1[legacy.accentMode], r = c.r, g = c.g, b = c.b }
        end
        legacy.language, legacy.integrateEUI, legacy.accentMode, legacy.accentCustom = nil, nil, nil, nil
        if next(legacy) then db.legacy = legacy end
    end
    db.version = DB_VERSION
end

-- Language: the setting, else the language of EllesmereUI (when loaded), else the client, else English.
local function ChooseLocale(choice)
    local locale
    if choice == "enUS" or choice == "deDE" then
        locale = choice
    else
        local preferred = type(ns.PreferredLocale) == "function" and ns.PreferredLocale() or nil
        locale = (type(preferred) == "string" and preferred ~= "") and preferred or GetLocale()
    end
    if type(locale) ~= "string" or locale == "" or locale == "enGB" then locale = "enUS" end
    ns.locale = locale
    ns.activeLocale = ns.locales[locale] or ns.locales.enUS
end

-- A pack's locale table follows the host's choice (packs keep their own texts).
function ns.PackLocale(pack)
    pack.activeLocale = pack.locales and (pack.locales[ns.locale] or pack.locales.enUS) or {}
    return pack.activeLocale
end

---------------------------------------------------------------------------
-- Skin packs
-- A pack calls ns.RegisterPack(packNs, def) from its own files while it loads:
--   def = { key, title, desc, modules = function() -> option modules (see Settings/Settings.lua),
--           info = function() -> lines, commands = function() -> lines, actions = function() -> { { text, fn } },
--           status = function() -> "active" | "idle" | text }
-- Status of a pack: off (setting), missing (the skinned addon is not installed), absent (pack not installed),
-- yielded (another host runs it), failed (error while loading), loaded.
---------------------------------------------------------------------------

local Packs = { order = {}, byKey = {} }
ns.Packs = Packs

for _, p in ipairs(P.packs) do
    local entry = { key = p.key, addon = p.addon, title = p.title, requires = p.requires, imports = p.imports,
        status = "waiting" }
    Packs.byKey[p.key] = entry
    Packs.order[#Packs.order + 1] = entry
end

function ns.RegisterPack(pack, def)
    local entry = Packs.byKey[def.key]
    if not entry then
        entry = { key = def.key, addon = pack.name, title = def.title, status = "waiting" }
        Packs.byKey[def.key] = entry
        Packs.order[#Packs.order + 1] = entry
    end
    entry.ns, entry.def = pack, def
    entry.title = def.title or entry.title
    return entry
end

function Packs.SwitchedOn(key)
    local s = ns.db and ns.db.settings.packs
    return not (s and s[key] == false)
end

-- Installed at all (in the AddOns folder, any enable state)?
local function Installed(name)
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if type(info) ~= "function" then return true end
    local ok, title, _, _, _, reason = pcall(info, name)
    if not ok then return true end
    return title ~= nil and reason ~= "MISSING"
end

-- Another host (the BeautifulSkins suite next to a single package) already runs this pack.
local function Yield(entry)
    local other = P.yieldTo and rawget(_G, P.yieldTo)
    if type(other) ~= "table" or other == ns or type(other.Packs) ~= "table" then return false end
    local theirs = other.Packs.byKey and other.Packs.byKey[entry.key]
    return theirs ~= nil and theirs.status == "loaded"
end

-- The addon this pack replaces (the former single addon) is still running: it is not one of our hosts, and not the
-- transfer folder of that name a package ships (X-Transfer in its TOC), which only loads the old saved settings.
local function Replaced(entry)
    local old = entry.imports and entry.imports.addon
    if not old or not ns.IsLoaded(old) then return false end
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata
    if meta and meta(old, "X-Transfer") then return false end
    local g = rawget(_G, old)
    return not (type(g) == "table" and type(g.Packs) == "table")
end

local function CopyTable(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do c[k] = CopyTable(v, seen) end
    return c
end

-- Settings of the former single addon for a pack whose own SavedVariables are still empty: the old addon's table
-- while it runs (a copy is kept, so the import still works after it is switched off), else that copy, else nil.
function ns.ImportedSettings(key)
    local entry = Packs.byKey[key]
    local imports = entry and entry.imports
    if not imports then return nil end
    local old = imports.db and rawget(_G, imports.db)
    if type(old) == "table" then return old end
    local kept = ns.db and ns.db.settings.imported
    return kept and kept[key] or nil
end

local function KeepImport(entry)
    local old = entry.imports.db and rawget(_G, entry.imports.db)
    if type(old) ~= "table" or not ns.db then return end
    ns.db.settings.imported = ns.db.settings.imported or {}
    ns.db.settings.imported[entry.key] = CopyTable(old)
end

local function LoadPack(entry)
    if not Packs.SwitchedOn(entry.key) then
        entry.status = "off"
    elseif Replaced(entry) then
        -- both would skin the same windows: the old addon keeps running until it is switched off
        entry.status = "replaced"
        KeepImport(entry)
    elseif Yield(entry) then
        entry.status = "yielded"
    elseif entry.requires and not ns.IsLoaded(entry.requires) then
        entry.status = "missing"
    elseif not Installed(entry.addon) then
        entry.status = "absent"
    elseif ns.IsLoaded(entry.addon) then
        entry.status = "loaded"
    else
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        local ok, loaded, reason = pcall(load, entry.addon)
        if ok and loaded then
            entry.status = "loaded"
        else
            entry.status = "failed"
            entry.reason = ok and tostring(reason) or tostring(loaded)
        end
    end
end

function Packs.LoadAll()
    for _, entry in ipairs(Packs.order) do LoadPack(entry) end
end

local STATUS_TEXT = {
    loaded = { "3fbf5f", "active" }, off = { "999999", "off" }, missing = { "999999", "addon not installed" },
    absent = { "999999", "not part of this installation" }, yielded = { "999999", "runs in BeautifulSkins" },
    failed = { "e5534b", "failed" }, waiting = { "999999", "waiting" },
    replaced = { "e5a24b", "the former addon is still active: switch it off and /reload" },
}

function Packs.StatusText(entry)
    local s = STATUS_TEXT[entry.status] or { "999999", tostring(entry.status) }
    local text = ("|cff%s%s|r"):format(s[1], L[s[2]])
    if entry.status == "failed" and entry.reason then text = text .. " (" .. entry.reason .. ")" end
    return text
end

-- One chat line per login for a pack whose former single addon still runs.
ns.RegisterEvent("PLAYER_LOGIN", function()
    for _, entry in ipairs(Packs.order) do
        if entry.status == "replaced" then
            ns.Say(L["%s: the former addon %s is still active. Switch it off in the addon list and /reload; its settings are taken over."]
                :format(entry.title or entry.key, entry.imports.addon))
        end
    end
end)

-- Loaded packs in package order (for the options, the info page and the minimap menu).
function Packs.Loaded()
    local list = {}
    for _, entry in ipairs(Packs.order) do
        if entry.status == "loaded" and entry.def then list[#list + 1] = entry end
    end
    return list
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function events:ADDON_LOADED(loaded)
    if loaded ~= addonName then return end
    local db = _G[P.db]
    if type(db) ~= "table" then db = {} end
    Migrate(db)
    MergeDefaults(db, defaults)
    _G[P.db] = db
    ns.db = db
    ChooseLocale(db.settings.language)
    -- Packs load inside our ADDON_LOADED: the skinned addons are OptionalDeps and already loaded, the packs then hook
    -- them as early as they did as addons of their own.
    Packs.LoadAll()
    -- A single package next to the suite: every pack runs in the suite, so this host shows nothing of its own
    -- (no minimap button, no EllesmereUI section) and hands its slash command and compartment entry over.
    local yielded, other = 0, 0
    for _, entry in ipairs(Packs.order) do
        if entry.status == "yielded" then yielded = yielded + 1 elseif entry.status == "loaded" then other = other + 1 end
    end
    ns.dormant = yielded > 0 and other == 0
    ns.ready = true
    local list = readyCallbacks
    readyCallbacks = {}
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then geterrorhandler()(err) end
    end
end

function events:PLAYER_REGEN_ENABLED()
    local list = pending
    pending = {}
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then geterrorhandler()(err) end
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    local handler = events[event]
    if handler then handler(self, ...) end
    local list = handlers[event]
    if list then
        for i = 1, #list do
            local ok, err = pcall(list[i], event, ...)
            if not ok then geterrorhandler()(err) end
        end
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

---------------------------------------------------------------------------
-- Options router: the same pages live in two hosts. "standalone" is our own options window (always there, works in
-- combat); "eui" is the section in the EllesmereUI options window (only when EllesmereUI is loaded and the integration
-- is on). A host registers ns.hosts[key] = { Open(pageKey) -> opened, IsShown(), Hide() }.
---------------------------------------------------------------------------

ns.hosts = {}

function ns.PreferredHost()
    return ns.hosts.eui and "eui" or "standalone"
end

local function Slash()
    return P.slash[1]
end

-- Opens the options on pageKey (nil = the last page) in hostKey (nil = preferred; in combat our own window, since
-- EllesmereUI's may not open then). Returns true when a window opened.
function ns.OpenOptions(pageKey, hostKey)
    if ns.dormant then
        local suite = rawget(_G, P.yieldTo)
        return type(suite) == "table" and type(suite.OpenOptions) == "function" and suite.OpenOptions(pageKey, hostKey) or false
    end
    local explicit = hostKey ~= nil
    hostKey = hostKey or ns.PreferredHost()
    if hostKey == "eui" then
        if not ns.hosts.eui then
            if not ns.HasEUI() then
                ns.Say(L["EllesmereUI is not loaded. %s options opens our own window."]:format(Slash()))
            elseif ns.db and ns.db.settings.integrateEUI then
                ns.Say(L["The EllesmereUI section is not active (%s). Try /reload."]:format(tostring(ns.registerResult)))
            else
                ns.Say(L["The EllesmereUI integration is off. Turn it on under General, then /reload."])
            end
            return false
        end
        if InCombatLockdown() then
            if explicit then
                ns.Say(L["The EllesmereUI window cannot be opened in combat. %s options works."]:format(Slash()))
                return false
            end
            hostKey = "standalone"
        end
    end
    local host = ns.hosts[hostKey]
    if not host then return false end
    return host.Open(pageKey) and true or false
end

-- Slash command without arguments: open the options; our own window closes again when it is already open.
function ns.ToggleOptions(pageKey)
    local host = ns.hosts.standalone
    if ns.PreferredHost() == "standalone" and host and host.IsShown() then
        host.Hide()
        return true
    end
    return ns.OpenOptions(pageKey)
end

---------------------------------------------------------------------------
-- Reset of the shared settings (look, language, minimap, window). Packs reset their own options themselves.
---------------------------------------------------------------------------

local RESET_WINDOW = 10
local resetAskedAt

function ns.ResetSettings()
    local packs = ns.db.settings.packs
    wipe(ns.db.settings)
    MergeDefaults(ns.db, defaults)
    ns.db.settings.packs = packs -- which packs run is not a look setting
    ReloadUI()
end

-- Asks first: a dialog, or the same request a second time when the dialog is missing. onAccept = what to do.
function ns.Confirm(key, text, onAccept)
    if type(StaticPopup_Show) == "function" and type(StaticPopupDialogs) == "table" then
        local id = (addonName .. "_" .. key):upper()
        StaticPopupDialogs[id] = {
            text = text,
            button1 = type(YES) == "string" and YES or L["Yes"],
            button2 = type(NO) == "string" and NO or L["No"],
            OnAccept = onAccept,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(id)
        return
    end
    local now = GetTime()
    if resetAskedAt and now - resetAskedAt <= RESET_WINDOW then
        resetAskedAt = nil
        onAccept()
        return
    end
    resetAskedAt = now
    ns.Say(L["Repeat within 10 seconds to confirm."])
end

function ns.AskReset()
    ns.Confirm("reset", L["Reset the look, language and window of %s to the defaults? The interface reloads."]:format(
        P.title), ns.ResetSettings)
end

---------------------------------------------------------------------------
-- Status, slash command, compartment
---------------------------------------------------------------------------

function ns.InfoLines()
    local lines = { ("%s %s"):format(P.title, ns.Version()) }
    lines[#lines + 1] = ns.HasEUI() and L["EllesmereUI found: accent, font and language can follow it."]
        or L["EllesmereUI not found: own window and own look."]
    return lines
end

function ns.PackLines()
    local lines = {}
    for _, entry in ipairs(Packs.order) do
        local title = entry.def and entry.def.title or L[entry.title] or entry.key
        local line = ("  %s: %s"):format(title, Packs.StatusText(entry))
        local d = entry.def
        if entry.status == "loaded" and d and d.status then
            local ok, text = pcall(d.status)
            if ok and type(text) == "string" and text ~= "" then line = line .. " · " .. text end
        end
        lines[#lines + 1] = line
    end
    return lines
end

function ns.PrintStatus()
    for _, line in ipairs(ns.InfoLines()) do ns.Say(line) end
    for _, line in ipairs(ns.PackLines()) do ns.Say(line) end
    for _, entry in ipairs(Packs.Loaded()) do
        if entry.def.info then
            local ok, lines = pcall(entry.def.info)
            if ok and type(lines) == "table" then
                for _, line in ipairs(lines) do ns.Say("    " .. line) end
            end
        end
    end
end

function ns.CommandLines()
    local s = Slash()
    local lines = {
        L["%s - options"]:format(s),
        L["%s options - our own options window"]:format(s),
    }
    if ns.HasEUI() then lines[#lines + 1] = L["%s eui - the options in EllesmereUI"]:format(s) end
    lines[#lines + 1] = L["%s status - state of every skin"]:format(s)
    lines[#lines + 1] = L["%s minimap - show or hide the minimap button"]:format(s)
    lines[#lines + 1] = L["%s reset - reset look and language"]:format(s)
    for _, entry in ipairs(Packs.Loaded()) do
        if entry.def.commands then
            local ok, extra = pcall(entry.def.commands)
            if ok and type(extra) == "table" then
                for _, line in ipairs(extra) do lines[#lines + 1] = line end
            end
        end
    end
    return lines
end

-- Quick actions of the loaded packs (minimap and compartment menu): { { text, fn } }.
function ns.Actions()
    local list = {}
    for _, entry in ipairs(Packs.Loaded()) do
        if entry.def.actions then
            local ok, actions = pcall(entry.def.actions)
            if ok and type(actions) == "table" then
                for _, a in ipairs(actions) do list[#list + 1] = a end
            end
        end
    end
    return list
end

local slashKey = addonName:upper() .. "HOST" -- packs use their own keys (BEAUTIFULATTUNE ...)
for i, cmd in ipairs(P.slash) do _G["SLASH_" .. slashKey .. i] = cmd end
SlashCmdList[slashKey] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.ToggleOptions()
    elseif cmd == "options" then
        ns.OpenOptions(rest ~= "" and rest or nil, "standalone")
    elseif cmd == "eui" then
        ns.OpenOptions(nil, "eui")
    elseif cmd == "status" or cmd == "diag" then
        ns.PrintStatus()
    elseif cmd == "minimap" and ns.MinimapButton then
        ns.MinimapButton.Toggle()
    elseif cmd == "reset" then
        ns.AskReset()
    elseif ns.devCommands and ns.devCommands[cmd] then -- registered by files of the development checkout only
        ns.devCommands[cmd](rest:lower())
    elseif cmd == "help" then
        ns.Say(L["Commands:"])
        for _, line in ipairs(ns.CommandLines()) do ns.Say("  " .. line) end
    else
        ns.Say(L["Unknown command."] .. " " .. L["%s help lists all commands."]:format(Slash()))
    end
end

-- Addon compartment callbacks must be real globals (named in the TOC): <addon>_OnCompartmentClick and so on.
_G[addonName .. "_OnCompartmentClick"] = function(_, mouseButton)
    if mouseButton == "RightButton" and ns.MinimapButton then
        ns.MinimapButton.Menu()
    else
        ns.OpenOptions()
    end
end

_G[addonName .. "_OnCompartmentEnter"] = function(_, owner)
    owner = owner or AddonCompartmentFrame
    if not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(P.title, 1, 1, 1)
    GameTooltip:AddLine(L["Left-click: options"], 0.9, 0.9, 0.9)
    if #ns.Actions() > 0 then GameTooltip:AddLine(L["Right-click: quick actions"], 0.9, 0.9, 0.9) end
    GameTooltip:Show()
end

_G[addonName .. "_OnCompartmentLeave"] = function()
    GameTooltip:Hide()
end
