-- RestedXP pack core (formerly the addon EUI RestedXP Skin): SavedVariables, defaults, events, refresh, look sources and
-- the slash command. Look, language and the options window belong to the host (ns.host).
local addonName, ns = ...
local host = ns.host
host.PackLocale(ns) -- the host chose the language before it loads packs
local L = ns.L

local DB_NAME = "BeautifulSkinsRestedXPDB"

-- Missing keys are filled in recursively on ADDON_LOADED.
ns.DEFAULTS = {
    launches = 0, -- SavedVariables smoke counter for /euirxp probe
    guide = {
        enabled = true, layout = "COMPACT", alpha = 0.90,
        width = 0, -- 0 = keep RXP's current window width; 240-480 = width the user chose
        followAccent = true, customColor = { r = 12 / 255, g = 210 / 255, b = 157 / 255 },
        tint = 0.12, header = true, border = "THIN",
        growth = "UP", -- the window grows upwards (bottom edge stays) or "DOWN" (top edge stays)
        background = { r = 0x16 / 255, g = 0x16 / 255, b = 0x18 / 255 }, -- false = accent-tinted window colour; {r, g, b} = the user's own, default 161618
        upcoming = 3, stepNumbers = true, progress = true,
        lockBoxes = true,
        boxEdge = "AUTO", boxAlong = 0, -- window edge of the step boxes (AUTO|BOTTOM|TOP|LEFT|RIGHT) and the distance along it
        hideCombat = false, hideInstance = true, blockV2 = true, animations = "SUBTLE",
        font = "EUI", -- "EUI" = the font of the EllesmereUI skin, "GAME" = the game's own font (Fonts page)
        sizeTitle = 16, sizeGoal = 15, sizeRow = 14, -- title (12-20), goals of the current step (11-20), upcoming rows (11-16)
        progressColor = false, -- false = accent; {r, g, b} = the user's own colour for the progress bars
    },
    nav = {
        showArrow = true, -- off: our arrow stays hidden, e.g. when another addon such as TomTom shows the way
        source = "SPF", transports = true, stepEndOnly = false, hideRxpArrow = true,
        nextMarker = false, -- the arrow aims at the tracked map marker (SPF's next bend), whatever the journey
        rememberJourney = true, -- SPF's "Keep journeys after a reload", which lets the target switch see your own journey
        style = "CHEVRON", scale = 0.70, color = "ACCENT", customColor = nil, alpha = 1.0,
        showDistance = true, showETA = true, showName = true, unit = "m",
        hideCombat = false, locked = true, centerLock = false, point = { "TOP", "UIParent", "TOP", 0, -120 },
    },
    spfSkin = {
        journey = true, -- ShortestPathForever's Journey section in the tracker column in the EllesmereUI look
        journeyBackground = 75, -- opacity (%) of the panel behind the Journey; 0 = none
        currentAccent = true, -- the current journey step in the accent colour (off: white)
        compass = true, -- ShortestPathForever's compass in the EllesmereUI look
        minimapRoute = true, -- ShortestPathForever's routes and markers everywhere in the accent colour
    },
}

local frame = CreateFrame("Frame")
local events = {}

-- Secret values may not be compared, branched on or printed. Guard before use.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) and true or false
end

-- True when the value may be read, compared and calculated with.
function ns.CanAccess(value)
    if type(canaccessvalue) == "function" then return canaccessvalue(value) and true or false end
    return not ns.IsSecret(value)
end

function ns.SafeString(value, fallback)
    if value == nil or ns.IsSecret(value) then return fallback end
    return tostring(value)
end

-- Shared helpers (one copy for all modules).
function ns.Clamp(value, low, high, default)
    if type(value) ~= "number" then return default end
    return math.max(low, math.min(high, value))
end

function ns.Mix(base, target, amount)
    return base + (target - base) * amount
end

-- pcall that returns the first four results, or nothing on an error.
function ns.Try(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

function ns.Rxp()
    local rxp = _G.RXP
    if type(rxp) == "table" then return rxp end
end

-- RXP's active profile table (and RXP itself), or nothing while RXP's settings are not ready.
function ns.RxpProfile()
    local rxp = ns.Rxp()
    local settings = rxp and rxp.settings
    local profile = type(settings) == "table" and settings.profile
    if type(profile) == "table" then return profile, rxp end
end

-- Inside a dungeon, raid, battleground, arena or scenario (not the open world); false when unreadable.
function ns.InInstance()
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or not ns.CanAccess(inside) or not inside then return false end
    return not (ns.CanAccess(kind) and kind == "none")
end


local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end

local function MergeDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then
                db[key] = DeepCopy(value)
            else
                MergeDefaults(db[key], value)
            end
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

-- "Reset to defaults": only our SavedVariables. The values we changed in RXP and SPF go back first (the remembered
-- originals), then our options are replaced by the defaults. RXP's own settings stay as they are.
function ns.ResetToDefaults()
    if not ns.db then return end
    if ns.RXPArrow then ns.RXPArrow.Restore() end
    if ns.SPF then ns.SPF.RestoreAll() end
    ns.db.guide = DeepCopy(ns.DEFAULTS.guide)
    ns.db.nav = DeepCopy(ns.DEFAULTS.nav)
    ns.db.spfSkin = DeepCopy(ns.DEFAULTS.spfSkin)
    ns.db.rxpArrowBackup = nil
    ns.db.rememberJourneySynced = nil -- the reset option is synced into SPF again
    if ns.SPF then ns.SPF.OnOptionChanged("showArrow") end -- SPF's direction arrow follows the reset option
    ns.RefreshAll()
end

-- Refresh modules (theme, guide window, arrow) register here; RefreshAll runs them
-- in registration order, at most once per frame however often it is requested.
local refreshers = {}
local refreshQueued = false

function ns.RegisterRefresh(fn)
    refreshers[#refreshers + 1] = fn
end

function ns.RefreshAll()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        for i = 1, #refreshers do
            local ok, err = pcall(refreshers[i])
            if not ok then geterrorhandler()(err) end
        end
    end)
end

-- Modules that need SavedVariables (ns.db) register here; run once on our ADDON_LOADED.
local loadedHooks = {}

function ns.OnLoaded(fn)
    loadedHooks[#loadedHooks + 1] = fn
end

-- Colour/font source: the EllesmereUI skinning facade S, handed to the
-- callback once per session. ns.Accent/ns.Font read from it with a safe fallback.
ns.FALLBACK_ACCENT = { 12 / 255, 210 / 255, 157 / 255 } -- #0CD29D (the only hard-coded accent)
ns.FALLBACK_FONT = STANDARD_TEXT_FONT
ns.skin = nil
ns.skinRan = false
if EllesmereUI and type(EllesmereUI.RegisterSkin) == "function" then
    EllesmereUI.RegisterSkin(addonName, function(S)
        ns.skin = S
        ns.skinRan = true
        if type(S.OnLooksChanged) == "function" then
            S.OnLooksChanged(function() ns.RefreshAll() end)
        end
        ns.RefreshAll()
    end)
end

local function SkinCall(name)
    local S = ns.skin
    if S and type(S[name]) == "function" then
        local ok, a, b, c = pcall(S[name])
        if ok then return a, b, c end
    end
end

local function IsChannel(v)
    return type(v) == "number" and v >= 0 and v <= 1
end

-- Accent colour r, g, b (0-1): the guide's own colour, else the host's accent (EllesmereUI's, the theme's, the class
-- colour or the one picked in General > Appearance), else the fallback.
function ns.Accent()
    local guide = ns.db and ns.db.guide
    if guide and not guide.followAccent and type(guide.customColor) == "table" then
        local c = guide.customColor
        if IsChannel(c.r) and IsChannel(c.g) and IsChannel(c.b) then return c.r, c.g, c.b end
    end
    local T = host.Theme.Get("user")
    local a = T and T.accent
    if a and IsChannel(a[1]) and IsChannel(a[2]) and IsChannel(a[3]) then return a[1], a[2], a[3] end
    local r, g, b = SkinCall("GetAccentColor")
    if IsChannel(r) and IsChannel(g) and IsChannel(b) then return r, g, b end
    local f = ns.FALLBACK_ACCENT
    return f[1], f[2], f[3]
end

-- Font path and outline flags: the host's font choice (EllesmereUI's font by default when it is loaded), else EUI's
-- skin font, else the game's.
function ns.Font()
    local path, outline = host.Theme.FontPath()
    if type(path) ~= "string" or path == "" then path, outline = SkinCall("GetFont") end
    if type(path) ~= "string" or path == "" then return ns.FALLBACK_FONT, "" end
    return path, type(outline) == "string" and outline or ""
end

-- SetFont with the game font as fallback when the path cannot be loaded.
function ns.SetFont(fs, path, size, flags)
    if not fs:SetFont(path, size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end

-- Seconds after PLAYER_LOGIN in which EUI's skin callback may still be pending.
local SKIN_GRACE = 3

-- Is EUI's third-party skinning switched off for us? There is no public getter. Without EllesmereUI or without its
-- Blizzard skin child the pack draws its own look (host accent and font), so only an explicit "off" in EllesmereUI counts.
-- Returns false, or true plus a reason: "MASTER" / "ADDON" (switched off in EUI's saved variables, read-only),
-- "SILENT" (EUI's skin callback never ran although the skin child is loaded).
function ns.SkinningOff()
    if ns.skinRan then return false end
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if not (EllesmereUI and isLoaded and isLoaded("EllesmereUIBlizzardSkin")) then return false end
    if not ns.loginTime or GetTime() - ns.loginTime < SKIN_GRACE then return false end
    local eui = _G.EllesmereUIDB
    if type(eui) == "table" then
        if eui.thirdPartySkinsOff == true then return true, "MASTER" end
        if type(eui.thirdPartySkinAddons) == "table" and eui.thirdPartySkinAddons[addonName] == false then
            return true, "ADDON"
        end
    end
    return true, "SILENT"
end

-- Remembered at file load: had RXP already run OnInitialize (themes table present)?
ns.rxpThemesAtLoad = RXP ~= nil and RXP.themes ~= nil

-- Our pages in the host's options (its own window or the EllesmereUI section).
function ns.OpenOptions(pageKey)
    host.OpenOptions(pageKey or "rxp.general")
end

-- SavedVariables exist only from ADDON_LOADED on; never touch them at file scope.
-- This pack loads on demand from inside the host's ADDON_LOADED, so our own ADDON_LOADED is queued rather than
-- delivered during that call, and the client may hand us PLAYER_LOGIN first (seen on the first start of the Forever
-- release, 04.11.2026: ns.db was still false). The setup therefore runs from whichever event arrives first and does
-- nothing the second time.
local function Ready()
    if ns.db then return end
    local db = _G[DB_NAME]
    if type(db) ~= "table" then
        -- first start: take over the settings of the former addon EUI RestedXP Skin (same layout)
        db = {}
        local old = host.ImportedSettings("RestedXP")
        if type(old) == "table" then
            for key, value in pairs(old) do db[key] = value end
            db.importedFrom = "EUI_RestedXP_Skin"
        end
    end
    MergeDefaults(db, ns.DEFAULTS)
    _G[DB_NAME] = db
    ns.db = db
    frame:UnregisterEvent("ADDON_LOADED")
    for i = 1, #loadedHooks do
        local ok, err = pcall(loadedHooks[i])
        if not ok then geterrorhandler()(err) end
    end
end

function events:ADDON_LOADED(loaded)
    if loaded ~= addonName then return end
    Ready()
end

function events:PLAYER_LOGIN()
    Ready()
    ns.db.launches = ns.db.launches + 1
    ns.loggedIn = true
    ns.loginTime = GetTime()
    ns.RefreshAll()
    -- Once the grace period is over a missing EUI skin callback counts as "skinning off" (ns.SkinningOff), which
    -- switches the guide skin off; nothing else would notice that moment.
    C_Timer.After(SKIN_GRACE + 0.5, ns.RefreshAll)
end

frame:SetScript("OnEvent", function(self, event, ...)
    local handler = events[event]
    if handler then handler(self, ...) end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

SLASH_BEAUTIFULRESTEDXP1 = "/brxp"
SLASH_BEAUTIFULRESTEDXP2 = "/euirxp"
SlashCmdList["BEAUTIFULRESTEDXP"] = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$") -- arg: the rest of the line ("guide set upcoming 2")
    if cmd == "" or cmd == "options" then
        ns.OpenOptions()
    elseif cmd == "probe" then
        ns.Probe()
    elseif cmd == "nav" then
        ns.NavDebug()
    elseif cmd == "lock" or cmd == "unlock" then
        ns.SetArrowLocked(cmd == "lock")
    elseif cmd == "guide" then
        ns.GuideCommand(arg)
    elseif cmd == "spf" then
        ns.SPFSkinDebug()
    elseif cmd == "target" then
        ns.TargetCommand(arg)
    else
        ns.Say(L["Usage: /brxp [probe|nav|lock|unlock|guide|spf|target [guide]]"])
    end
end

-- Registration with the host: options, status line, quick actions.
host.RegisterPack(ns, {
    key = "RestedXP",
    title = "RestedXP",
    modules = function() return ns.OptionModules() end,
    status = function()
        local off = ns.SkinningOff()
        if off then return L["guide skin off in EllesmereUI"] end
        return ns.db and ns.db.guide.enabled and L["guide window skinned"] or L["guide window skin off"]
    end,
    commands = function()
        return { L["/brxp lock | unlock - lock or unlock the arrow"], L["/brxp target - switch the arrow target"] }
    end,
    actions = function()
        local locked = ns.db and ns.db.nav.locked
        return {
            { text = locked and L["Unlock the RestedXP arrow"] or L["Lock the RestedXP arrow"],
                fn = function() ns.SetArrowLocked(not locked) end },
            { text = L["Reset the RestedXP arrow position"], fn = function() ns.ResetArrowPosition() end },
        }
    end,
})
