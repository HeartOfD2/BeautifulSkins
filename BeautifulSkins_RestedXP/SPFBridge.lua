-- ShortestPathForever bridge. Data only, no drawing:
-- navigation target (direction point plus RXP step target), own distance, cached arrival time, transport state,
-- and the sync of our options into SPF's settings with remembering and restoring the previous values.
local addonName, ns = ...
local L = ns.L

local OWNER = "RestedXP" -- SPF's owner id for RXP guidance
local ETA_INTERVAL = 1 -- seconds between SPF queries
local BEND_RADIUS = 30 -- yards to the SPF waypoint for the transport state
local SPF_ARROW_LOOK = 0.5 -- seconds between looks for the frame of SPF's own arrow
local TRANSPORT_MODES = {
    flight = true, boat = true, zeppelin = true, lift = true, tram = true,
    portal = true, passage = true, teleport = true,
}

local SPF = {}
ns.SPF = SPF

-- ---------------------------------------------------------------------------------------------------------------
-- Small helpers

local function IsNum(v)
    return ns.CanAccess(v) and type(v) == "number"
end

local Try = ns.Try

-- x, y of a map position: Vector2D object (GetXY) or a plain table with x/y (waypoint position on Forever).
local function RawXY(pos)
    if pos.GetXY then return pos:GetXY() end
    return pos.x, pos.y
end

local function PosXY(pos)
    local t = type(pos)
    if t ~= "table" and t ~= "userdata" then return end
    local ok, x, y = pcall(RawXY, pos) -- no closure: this runs at the arrow's 20 Hz
    if ok and IsNum(x) and IsNum(y) then return x, y end
end

-- Map position (uiMapID, 0-1 coordinates) to world position in UnitPosition coordinates.
-- Returns continentID, x, y or nothing.
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    if not (IsNum(mapID) and IsNum(x) and IsNum(y)) then return end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not IsNum(cont) then return end
    local wx, wy = PosXY(pos)
    if wx then return cont, wx, wy end
end

-- RXP wraps names in colour tokens ("RXP_FRIENDLY_") and escape codes; keep the plain words.
local function CleanName(text)
    if type(text) ~= "string" or not ns.CanAccess(text) then return end
    text = text:gsub("RXP_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:match("^%s*(.-)%s*$")
    if text ~= "" then return text end
end

function ns.FormatTime(seconds)
    if not IsNum(seconds) or seconds < 0 then return end
    seconds = math.floor(seconds + 0.5)
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

-- Yards to the display unit (nav.unit "m" or "yd"). Since SPF 1.27.0 "metres" only changes the unit word, the number
-- stays the game's yards, as the game's own German and other metric clients show it (SPF Core/Distance.lua
-- FormatDistance); up to 1.26 SPF converted with 0.9144. Our arrow follows, so its number matches SPF's tracker,
-- compass and arrow.
function ns.ToUnit(yards, unit)
    return yards
end

-- ---------------------------------------------------------------------------------------------------------------
-- SPF presence

function SPF.Loaded()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return isLoaded and Try(isLoaded, "ShortestPathForever") == true or false
end

-- ShortestPathForever.API, only when it has the calls we use.
function SPF.Api()
    local spf = _G.ShortestPathForever
    local api = type(spf) == "table" and spf.API
    if type(api) == "table" and type(api.CurrentStop) == "function" and type(api.EstimateDetail) == "function" then
        return api
    end
end

function SPF.Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local v = get and Try(get, "ShortestPathForever", "Version")
    if type(v) == "string" and ns.CanAccess(v) and v ~= "" then return v end
end

-- Effective source: "SPF" only when chosen (SPF or AUTO) and SPF is there; else "RXP".
function ns.NavSource()
    local nav = ns.db and ns.db.nav
    local configured = nav and nav.source or "SPF"
    if configured ~= "RXP" and SPF.Api() then return "SPF", configured end
    return "RXP", configured
end

-- ---------------------------------------------------------------------------------------------------------------
-- Player

-- x (north), y (west), instance/continent id; nothing when not readable (instance, secret, loading).
function ns.PlayerPos()
    if type(UnitPosition) ~= "function" then return end
    local x, y, _, inst = UnitPosition("player")
    if not (IsNum(x) and IsNum(y) and IsNum(inst)) then return end
    return x, y, inst
end

function ns.PlayerFacing()
    if type(GetPlayerFacing) ~= "function" then return end
    local facing = GetPlayerFacing()
    if IsNum(facing) then return facing end
end

-- uiMapID and 0-1 coordinates of the player for SPF estimates.
local function PlayerMapPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not IsNum(mapID) then return end
    local x, y = PosXY(C_Map.GetPlayerMapPosition(mapID, "player"))
    if x then return mapID, x, y end
end

-- Straight-line yards from the player to a world point; nil plus a reason otherwise.
function ns.DistanceTo(cont, x, y)
    local px, py, inst = ns.PlayerPos()
    if not px then return nil, "unreadable" end
    if inst ~= cont then return nil, "continent" end
    local dx, dy = x - px, y - py
    return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Target: direction point plus the RXP step target ("goal") for distance, ETA and radius.

-- Last computed goal per RXP element and coordinates; the element changes only when RXP moves to another target.
local goalCache = {}

-- The RXP step target from zone/x/y, never wx/wy. Table with mapID, mx, my (0-1), cont, x, y, name, radius and
-- key (identifies the target for the ETA cache and the arrow's "arrived" latch). Read only: the table is shared.
local function RXPGoal()
    local frame = _G.RXP and _G.RXP.arrowFrame
    local e = type(frame) == "table" and frame.element
    if type(e) ~= "table" then return end
    if not (IsNum(e.zone) and IsNum(e.x) and IsNum(e.y)) then return end
    local c = goalCache
    if c.e == e and c.zone == e.zone and c.ex == e.x and c.ey == e.y then return c.value end
    local mx, my = e.x / 100, e.y / 100
    local cont, x, y = WorldPos(e.zone, mx, my)
    if not cont then return end -- not cached: may be readable again after a loading screen
    local step = type(e.step) == "table" and e.step or nil
    local value = {
        mapID = e.zone, mx = mx, my = my, cont = cont, x = x, y = y,
        name = CleanName(e.title) or (step and (CleanName(step.arrowtext) or CleanName(step.title))) or nil,
        radius = IsNum(e.radius) and e.radius > 0 and e.radius or nil,
        key = ("%d:%.5f:%.5f"):format(e.zone, mx, my),
    }
    c.e, c.zone, c.ex, c.ey, c.value = e, e.zone, e.x, e.y, value
    return value
end
ns.GuideGoal = RXPGoal

-- A goal table like RXPGoal's from a uiMapID and 0-1 coordinates (Targets.lua: the player's own journey).
function ns.MakeGoal(mapID, mx, my, name)
    local cont, x, y = WorldPos(mapID, mx, my)
    if not cont then return end
    return {
        mapID = mapID, mx = mx, my = my, cont = cont, x = x, y = y, name = CleanName(name),
        key = ("%d:%.5f:%.5f"):format(mapID, mx, my),
    }
end

local function WaypointUINavigation()
    local api = rawget(_G, "WaypointUIAPI")
    local navigation = type(api) == "table" and api.Navigation
    if type(navigation) == "table" then return navigation end
end

-- Waypoint UI holds a navigation of its own (shown by /brxp nav; tracked or not).
local function WaypointUIHolding()
    local navigation = WaypointUINavigation()
    if not navigation or type(navigation.GetUserNavigation) ~= "function" then return false end
    return Try(navigation.GetUserNavigation) ~= nil
end

-- Waypoint UI tracks its navigation: SPF then hands its bends to it instead of writing the waypoint (SPF
-- Journey/JourneyGuide.lua, WaypointUITracking -> HandOverToWaypointUI), so the native waypoint is SPF's bend all the
-- same. A navigation Waypoint UI only holds, untracked, is the player's: SPF writes its bends itself then.
local function WaypointUITracking()
    local navigation = WaypointUINavigation()
    if not navigation or type(navigation.IsUserNavigationTracked) ~= "function" then return false end
    return Try(navigation.IsUserNavigationTracked) == true
end

-- SPF guides a journey: RestedXP's (guide = true) or another one (the player's own, a quest, /way).
-- Returns journey, guide.
function SPF.Guiding()
    local api = SPF.Api()
    if not api then return false, false end
    local guide = Try(api.CurrentStop, OWNER) ~= nil
    return guide or (type(api.Active) == "function" and Try(api.Active) == true), guide
end

-- The game's waypoint: uiMapID and 0-1 x, y, or nothing when there is none or it cannot be read (on a restricted map
-- it may come back secret: never indexed or compared then).
function SPF.ReadWaypoint()
    local get = C_Map and C_Map.GetUserWaypoint
    local wp = get and Try(get)
    if type(wp) ~= "table" or not ns.CanAccess(wp) or not IsNum(wp.uiMapID) then return end
    local x, y = PosXY(wp.position)
    if x then return wp.uiMapID, x, y end
end

-- The game's waypoint is SPF's bend, the next turn of its route: the one check for our arrow, the minimap mark and
-- OpenMap's marker. SPF keeps its last write in ShortestPathForeverCharDB.guideWaypoint and clears it when it stops
-- guiding. When SPF starts the player's own journey it first gives back the waypoint that stood before the guide's
-- (often one at the RestedXP target); until SPF writes its first bend, and for good when the new journey's guide yields
-- or stops, that waypoint is someone else's. Same tolerance as SPF's SameWaypoint: one yard. While Waypoint UI tracks
-- its navigation SPF hands each bend to it and clears guideWaypoint (JourneyGuide.lua GuideWaypoint): then the waypoint
-- is SPF's bend while SPF guides.
-- Returns uiMapID, x, y, continent, world x, world y of the waypoint, or nothing. guiding: SPF.Guiding() when the
-- caller knows it already. Runs at 20 Hz: with neither guideWaypoint nor a tracked Waypoint UI it reads nothing else.
function SPF.Bend(guiding)
    local db = rawget(_G, "ShortestPathForeverCharDB")
    local saved = type(db) == "table" and db.guideWaypoint
    if type(saved) ~= "table" then saved = nil end
    local handed
    if not saved then
        handed = WaypointUITracking()
        if not handed then return end
    end
    local mapID, x, y = SPF.ReadWaypoint()
    if not mapID then return end
    local cont, wx, wy = WorldPos(mapID, x, y)
    if not cont then return end
    if saved then
        local sc, sx, sy = WorldPos(saved.uiMapID, saved.x, saved.y)
        if sc and sc == cont then
            local dx, dy = sx - wx, sy - wy
            if dx * dx + dy * dy <= 1 then return mapID, x, y, cont, wx, wy end
        end
        handed = WaypointUITracking()
        if not handed then return end
    end
    if guiding == nil then guiding = SPF.Guiding() end
    if guiding then return mapID, x, y, cont, wx, wy end
end

-- SPF's current waypoint (the next bend of its route) while SPF guides a journey and that waypoint is tracked.
-- guide: the journey is RestedXP's; otherwise it is another one (the player's own, a quest, /way).
local function SPFWaypoint()
    local journey, guide = SPF.Guiding()
    -- "Arrow to the next map marker": without a journey of SPF's, whatever marker is tracked counts
    local anyMarker = ns.db and ns.db.nav and ns.db.nav.nextMarker == true
    if not journey and not anyMarker then return end
    local tracking = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint
    if not (tracking and Try(tracking)) then return end
    -- During a journey a waypoint SPF did not set is no bend of its route, also with anyMarker (SPF's own arrow never
    -- follows it either): ns.Target then aims straight at the journey's goal.
    if journey then
        local _, _, _, cont, wx, wy = SPF.Bend(true)
        if cont then return cont, wx, wy, guide end
        return
    end
    local mapID, x, y = SPF.ReadWaypoint()
    if not mapID then return end
    local cont, wx, wy = WorldPos(mapID, x, y)
    if cont then return cont, wx, wy, guide end
end

local targetCache = { time = -1 }

-- Returns { source = "SPF"|"RXP", cont, x, y, goal = <RXP step target or nil> } or nil.
-- Cached for the current frame; callers may run at 20 Hz.
function ns.Target()
    local now = GetTime()
    if targetCache.time == now then return targetCache.value end
    local value
    local goal = RXPGoal()
    if ns.NavSource() == "SPF" then
        local cont, x, y, guide = SPFWaypoint()
        -- another journey than the guide's: its goal when Targets.lua knows it, else the direction alone
        if cont then
            value = { source = "SPF", cont = cont, x = x, y = y, goal = guide and goal or ns.Targets.OtherGoal() }
        else
            -- SPF sets no native waypoint while the bend lies off the current zone map or a tracked quest has the
            -- super-track: then straight at the own journey's goal, as for the guide's target below
            local other = ns.Targets.OtherGoal()
            if other then value = { source = "JOURNEY", cont = other.cont, x = other.x, y = other.y, goal = other } end
        end
    end
    if not value and goal then
        value = { source = "RXP", cont = goal.cont, x = goal.x, y = goal.y, goal = goal } -- fallback
    end
    targetCache.time, targetCache.value = now, value
    return value
end

-- ---------------------------------------------------------------------------------------------------------------
-- Arrival time: EstimateDetail at most once per second, held in combat.

local eta = { time = -ETA_INTERVAL, key = nil, seconds = nil, legs = nil, reason = nil, stale = false }

local function ClearETA(reason)
    eta.seconds, eta.legs, eta.reason, eta.stale = nil, nil, reason, false
end

-- The time left of the journey SPF guides, as SPF's tracker header and compass give it (API.Journey().secondsLeft, the
-- plan under way from the current leg); nil while the arrow follows no SPF journey or SPF has no plan yet.
local function JourneySeconds(api, t)
    if not (t.source == "SPF" or t.source == "JOURNEY") or type(api.Journey) ~= "function" then return end
    local journey = Try(api.Journey)
    if type(journey) ~= "table" or type(journey.legs) ~= "table" or #journey.legs == 0 then return end
    if IsNum(journey.secondsLeft) then return journey.secondsLeft end
end

-- Returns the shared table { seconds, legs, reason, stale }; read only. seconds is nil when unknown. seconds is the
-- journey's time left while SPF guides it, else SPF's estimate to the goal; legs always the estimate's (transport state).
function ns.ETA()
    local api = SPF.Api()
    local t = ns.Target()
    local goal = t and t.goal
    if not api or not goal then
        eta.key = nil
        ClearETA(api and "nogoal" or "nospf")
        return eta
    end
    local key = goal.key
    if InCombatLockdown() then -- SPF answers "combat"; keep the last value for the same goal
        if key ~= eta.key then eta.key = key; ClearETA("combat") else eta.stale = eta.seconds ~= nil end
        return eta
    end
    local now = GetTime()
    if key == eta.key and now - eta.time < ETA_INTERVAL then return eta end
    eta.time, eta.key = now, key
    local mapID, mx, my = PlayerMapPos()
    local ok, detail, reason = false, nil, "unreadable"
    if mapID then ok, detail, reason = pcall(api.EstimateDetail, mapID, mx, my, goal.mapID, goal.mx, goal.my) end
    if ok and type(detail) == "table" and IsNum(detail.seconds) then
        eta.seconds, eta.legs, eta.reason, eta.stale = detail.seconds, detail.legs, nil, false
    elseif ok and reason == "combat" then
        eta.stale = eta.seconds ~= nil
    else
        ClearETA(mapID and (ok and type(reason) == "string" and reason or "error") or "unreadable")
    end
    local left = JourneySeconds(api, t)
    if left then eta.seconds, eta.reason, eta.stale = left, nil, false end
    return eta
end

-- Transport state, data only: first leg walking, the SPF bend within 30 yards, second leg a
-- vehicle. Returns { mode, to, wait } or nil. Needs SPF guidance (the bend is SPF's waypoint).
function ns.Transport()
    local t = ns.Target()
    if not t or t.source ~= "SPF" then return end
    local legs = ns.ETA().legs
    if type(legs) ~= "table" or type(legs[1]) ~= "table" or type(legs[2]) ~= "table" then return end
    if legs[1].mode ~= "walk" or not TRANSPORT_MODES[legs[2].mode] then return end
    local bend = ns.DistanceTo(t.cont, t.x, t.y)
    if not bend or bend >= BEND_RADIUS then return end
    local second = legs[2]
    return {
        mode = second.mode,
        to = type(second.to) == "string" and second.to or nil,
        wait = IsNum(second.wait) and second.wait or nil, -- only when SPF reports >= 60 s
    }
end

-- ---------------------------------------------------------------------------------------------------------------
-- SPF settings sync

local SPF_TYPE = {
    arrow = "boolean", restedxp = "boolean", journey = "boolean", teleports = "boolean", guideStops = "boolean",
    metres = "boolean", compass = "boolean", pins = "boolean", mapRoutes = "boolean", minimapPins = "boolean",
    compassScale = "number", compassBackground = "number", mapPinScale = "number",
    transit = "boolean", portals = "boolean", mapFlightMasters = "boolean",
    flightPinScale = "number", minimapPinScale = "number", -- only where this SPF version has them (Write checks)
    journeyTracker = "boolean", compassTime = "boolean", resumeJourney = "boolean",
}

local reloadHinted = false

local function SettingObject(key)
    local get = Settings and Settings.GetSetting
    local s = get and Try(get, "ShortestPathForever_" .. key)
    if type(s) == "table" and type(s.GetValue) == "function" and type(s.SetValue) == "function" then return s end
end

function SPF.Has(key)
    return SPF.Loaded() and SPF.Get(key) ~= nil
end

function SPF.Get(key)
    local s = SettingObject(key)
    if s then
        local ok, value = pcall(s.GetValue, s)
        if ok then return value end
    end
    local db = _G.ShortestPathForeverDB
    if type(db) == "table" then return db[key] end
end

-- Writes through the Settings API so SPF runs its own callbacks; without it, straight into SPF's DB plus a
-- /reload hint. With remember, the previous value is stored once in our SavedVariables.spfBackup.
local function Write(key, value, remember)
    if SPF_TYPE[key] == nil or type(value) ~= SPF_TYPE[key] or not SPF.Loaded() then return false end
    local previous = SPF.Get(key)
    if previous == value then return true end
    if remember and ns.db and previous ~= nil then
        ns.db.spfBackup = ns.db.spfBackup or {}
        if ns.db.spfBackup[key] == nil then ns.db.spfBackup[key] = previous end
    end
    local s = SettingObject(key)
    if s and pcall(s.SetValue, s, value) then
        -- SPF ran its own refresh. It may have normalized the value (a slider's step, a clamp): SPF's answer wins.
        -- Only a setting that left the value unchanged did not reach SPF's DB, and the DB is written below.
        local now = SPF.Get(key)
        if now == value or now ~= previous then return true end
    end
    local db = _G.ShortestPathForeverDB
    if type(db) ~= "table" or db[key] == nil then return false end -- never invent a key this SPF version does not know
    db[key] = value
    if not reloadHinted then
        reloadHinted = true
        ns.Say(L["ShortestPathForever settings were saved directly. Type /reload to apply them."])
    end
    return true
end

-- Set an SPF setting on behalf of the user; deferred until combat ends (settings callbacks stay out of combat).
function SPF.Set(key, value)
    if SPF_TYPE[key] == nil or type(value) ~= SPF_TYPE[key] or not SPF.Loaded() then return false end
    ns.Queue(function() Write(key, value, true) end)
    return true
end

-- Put one remembered SPF value back (e.g. arrow when the source leaves RXP).
function SPF.RestoreKey(key)
    ns.Queue(function()
        local backup = ns.db and ns.db.spfBackup
        if type(backup) ~= "table" or backup[key] == nil then return end
        -- forget the remembered value only once it is back in SPF (SPF may be missing this session)
        if Write(key, backup[key], false) then backup[key] = nil end
    end)
end

-- "Reset to defaults": write all remembered values back and forget them. Call before wiping our SavedVariables.
function SPF.RestoreAll()
    local backup = ns.db and ns.db.spfBackup
    if type(backup) ~= "table" then return end
    local snapshot = {}
    for key, value in pairs(backup) do snapshot[key] = value end
    ns.db.spfBackup = nil
    ns.Queue(function()
        for key, value in pairs(snapshot) do Write(key, value, false) end
    end)
end

-- SPF's own screen arrow. SPF places the bends our arrow follows only with "Show direction arrow" on, and with it off our
-- arrow would point straight at the final target. So the setting stays on while our arrow is in use and SPF's arrow, which
-- would be a second, yellow one, is made invisible instead. Its frame has no name: it is found among UIParent's children
-- by its parts, once SPF created it. SPF only ever sets the alpha of the frame itself, never that of these parts.
local SPF_ARROW_PARTS = { "Icon", "Arrow", "Distance", "Progress" }
local spfArrow

local function IsSpfArrow(frame)
    local arrow = frame.Arrow
    return type(arrow) == "table" and type(frame.MoverHint) == "table" and type(arrow.GetAtlas) == "function"
        and arrow:GetAtlas() == "Navigation-Tracked-Arrow"
end

local function ApplySpfArrow()
    if not spfArrow then return end
    local alpha = ns.db and ns.db.nav.showArrow ~= false and 0 or 1
    for _, key in ipairs(SPF_ARROW_PARTS) do
        local part = spfArrow[key]
        if type(part) == "table" and type(part.SetAlpha) == "function" then part:SetAlpha(alpha) end
    end
end

-- With our arrow off the user's own value goes back, and SPF's arrow is theirs again.
local function SyncArrow(nav)
    if nav.showArrow ~= false then SPF.Set("arrow", true) else SPF.RestoreKey("arrow") end
    ApplySpfArrow()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Looking for frames SPF makes only for a journey (its arrow, compass and screen pin). A looker runs every `every`
-- seconds while SPF guides and, with `wanted`, while that says yes; it stops for good once look() returns true. Nothing
-- runs without SPF or between journeys: SPF's bursts (API.Subscribe; they come a frame after the change) wake the lookers
-- when guidance starts, and our refresh and load catch an SPF that loaded late or a change of our options.
local lookers = {}
local subscribed = false

local function Wanted(looker)
    return not looker.done and SPF.Guiding() and (looker.wanted == nil or looker.wanted()) and true or false
end

-- true once the looker is done (look found what it looks for); an error ends it too, reported once.
local function Look(looker)
    local ok, found = pcall(looker.look)
    if not ok then geterrorhandler()(found) end
    if found == true or not ok then looker.done = true end
    return looker.done
end

local function StopLooking(looker)
    if looker.ticker then
        looker.ticker:Cancel()
        looker.ticker = nil
    end
end

local function WakeLookers()
    for _, looker in ipairs(lookers) do
        if not Wanted(looker) then
            StopLooking(looker)
        elseif not looker.ticker and not Look(looker) then
            looker.ticker = C_Timer.NewTicker(looker.every, function()
                if not Wanted(looker) or Look(looker) then StopLooking(looker) end
            end)
        end
    end
end

-- Once: SPF tells us about every burst. SPF loads first (OptionalDeps); the refresh only catches a late one.
local function Subscribe()
    if subscribed then return end
    local api = SPF.Api()
    if api and type(api.Subscribe) == "function" and pcall(api.Subscribe, WakeLookers) then subscribed = true end
end

function SPF.LookWhileGuiding(every, look, wanted)
    lookers[#lookers + 1] = { every = every, look = look, wanted = wanted }
end

ns.OnLoaded(function()
    Subscribe()
    WakeLookers()
end)

ns.RegisterRefresh(function()
    Subscribe()
    WakeLookers()
end)

-- SPF creates its arrow with the first journey, and only with "Show direction arrow" on: looked for while our arrow is on
-- (which keeps that setting on). With our arrow off a frame never found was never touched.
SPF.LookWhileGuiding(SPF_ARROW_LOOK, function()
    for _, child in ipairs({ UIParent:GetChildren() }) do
        if Try(IsSpfArrow, child) then
            spfArrow = child
            ApplySpfArrow()
            return true
        end
    end
    return false
end, function()
    return ns.db ~= nil and ns.db.nav.showArrow ~= false
end)

-- Source SPF/AUTO needs restedxp + journey on; source RXP gives those back.
local function SyncSource(nav)
    if nav.source == "RXP" then
        SPF.RestoreKey("restedxp")
        SPF.RestoreKey("journey")
    else
        SPF.Set("restedxp", true)
        SPF.Set("journey", true)
    end
    SyncArrow(nav)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Waypoint UI's options that take the game's one waypoint from SPF while our arrow is on
-- RestedXPSupportEnabled: Waypoint UI makes a navigation of its own to RestedXP's target after every step change and
--   reload, because RXP's arrow frame is shown (Arrow.lua keeps it shown, only invisible); while it is tracked SPF hands
--   its bends to Waypoint UI instead of writing them (docs/spf-wegpunkte-analyse.md). Our arrow shows RXP's targets.
-- AutoTrackPlacedPinEnabled: tracks every new waypoint one frame later. When SPF gives an old pin of the player's back
--   untracked, that tracking makes SPF's next guide yield before its first bend (docs/spf-issue-wegpunkt-rueckgabe.md).
--   Read at Waypoint UI's load only (Code/Map/AutoTrackPlacedPin.lua): we set it on its ADDON_LOADED, before it reads;
--   a later change works after /reload.
-- AutoTrackChatLinkPinEnabled: sets and tracks a waypoint from a chat link (only shown with the one above off).
-- CustomMapPinsEnabled: Waypoint UI's own map pins write the game's waypoint and its tracking themselves.
-- All go off while our arrow is on; the user's values come back when our arrow is switched off or our settings are
-- reset. The user's working setup (12.11.2026); Waypoint UI reads the others from WaypointDB_Global on every use.
local WUI_DB, WUI_FLAG = "WaypointDB_Global", "RestedXP_Waypoint"
local WUI_KEYS = { -- key -> Waypoint UI's default (Preload.lua), for a value it never saved
    RestedXPSupportEnabled = false,
    AutoTrackPlacedPinEnabled = true,
    AutoTrackChatLinkPinEnabled = true,
    CustomMapPinsEnabled = false,
}
local WUI_ORDER = { "RestedXPSupportEnabled", "AutoTrackPlacedPinEnabled", "AutoTrackChatLinkPinEnabled", "CustomMapPinsEnabled" }
local UNSET = "unset" -- backup of a value Waypoint UI never saved (its default applied)
local WUI = {}
ns.WaypointUI = WUI

local function WuiDB()
    local db = rawget(_G, WUI_DB)
    return type(db) == "table" and db or nil
end

local function ClearWuiRestedNavigation()
    local api = rawget(_G, "WaypointUIAPI")
    local nav = type(api) == "table" and api.Navigation
    if type(nav) ~= "table" or type(nav.IsUserNavigationFlagged) ~= "function" or type(nav.ClearUserNavigation) ~= "function" then
        return
    end
    if Try(nav.IsUserNavigationFlagged, WUI_FLAG) then pcall(nav.ClearUserNavigation) end
end

-- ns.db.wuiBackups[key] = the user's value (true, or UNSET for Waypoint UI's default) that we switched off.
-- ns.db.wuiBackup = true is the older note for RestedXPSupportEnabled alone.
local function Backups()
    local b = ns.db.wuiBackups
    if type(b) ~= "table" then b = nil end
    if ns.db.wuiBackup == true then
        b = b or {}
        b.RestedXPSupportEnabled = true
        ns.db.wuiBackup = nil
    end
    ns.db.wuiBackups = b
    return b
end

function WUI.Restore()
    local db = WuiDB()
    if not (db and ns.db) then return end -- Waypoint UI missing this session: keep the notes
    local b = Backups()
    if not b then return end
    for key, value in pairs(b) do
        if db[key] == false then -- the user did not change it since
            if value == UNSET then db[key] = nil else db[key] = value end
        end
    end
    ns.db.wuiBackups = nil
end

function WUI.Sync()
    local db = WuiDB()
    if not (db and ns.db) then return end
    if ns.db.nav.showArrow == false then
        WUI.Restore()
        return
    end
    local b = Backups()
    for _, key in ipairs(WUI_ORDER) do
        local value = db[key]
        if value == true or (value == nil and WUI_KEYS[key] == true) then
            b = b or {}
            if b[key] == nil then b[key] = value == nil and UNSET or true end
            db[key] = false
        end
    end
    ns.db.wuiBackups = b
    if b and b.RestedXPSupportEnabled then ClearWuiRestedNavigation() end
end

-- Waypoint UI's settings exist from its ADDON_LOADED on (ours runs first there: our frame was made earlier, so Waypoint UI
-- starts with the options already off); PLAYER_LOGIN covers a Waypoint UI that loaded before our database was ready.
local wuiWatch = CreateFrame("Frame")
wuiWatch:RegisterEvent("ADDON_LOADED")
wuiWatch:RegisterEvent("PLAYER_LOGIN")
wuiWatch:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= "WaypointUI" then return end
    if ns.db then Try(WUI.Sync) end
    if event == "PLAYER_LOGIN" then self:UnregisterAllEvents() end
end)

local SYNC = {
    source = SyncSource,
    -- SPF's "Keep journeys after a reload" is what writes the player's own journey to where Targets.lua can read it
    rememberJourney = function(nav)
        if nav.rememberJourney ~= false then SPF.Set("resumeJourney", true) else SPF.RestoreKey("resumeJourney") end
    end,
    showArrow = SyncArrow,
    transports = function(nav) SPF.Set("teleports", nav.transports == true) end, -- teleports only
    stepEndOnly = function(nav) SPF.Set("guideStops", nav.stepEndOnly == true) end,
    unit = function(nav) SPF.Set("metres", nav.unit == "m") end,
}

-- Call after the user changed one of nav.source, showArrow, transports, stepEndOnly, unit, rememberJourney
-- (no argument: all of them). Not called on load: SPF's values are only touched on a user change.
function SPF.OnOptionChanged(name)
    local nav = ns.db and ns.db.nav
    if not nav then return end
    targetCache.time = -1
    eta.key = nil
    if name == nil or name == "showArrow" then Try(WUI.Sync) end
    if SPF.Loaded() then
        if name then
            if SYNC[name] then SYNC[name](nav) end
        else
            SyncSource(nav)
            SYNC.transports(nav)
            SYNC.stepEndOnly(nav)
            SYNC.unit(nav)
            SYNC.rememberJourney(nav)
        end
    end
    ns.RefreshAll()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Debug: /brxp nav prints the route source and arrow target

local function S(v) return tostring(v) end

local function Num(v, decimals)
    if not IsNum(v) then return "-" end
    return (("%%.%df"):format(decimals or 1)):format(v)
end

function ns.NavDebug()
    local say = ns.Say
    local effective, configured = ns.NavSource()
    local t = ns.Target()
    local api = SPF.Api()
    local stop = api and Try(api.CurrentStop, OWNER)
    local tracking = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and Try(C_SuperTrack.IsSuperTrackingUserWaypoint)
    say(("source: configured %s  effective %s  actual %s"):format(S(configured), S(effective), S(t and t.source or "none")))
    say(("SPF: loaded %s  version %s  API %s  CurrentStop(%s) %s  waypoint tracked %s"):format(
        S(SPF.Loaded()), S(SPF.Version()), S(api ~= nil), OWNER, S(stop), S(tracking)))
    local wmap, wx, wy = SPF.ReadWaypoint()
    local wuiDB = WuiDB()
    local off = {}
    for _, key in ipairs(WUI_ORDER) do
        off[#off + 1] = ("%s %s%s"):format(key:gsub("Enabled$", ""), S(wuiDB and wuiDB[key]),
            ns.db and type(ns.db.wuiBackups) == "table" and ns.db.wuiBackups[key] ~= nil and " (ours)" or "")
    end
    say("Waypoint UI: " .. table.concat(off, "  "))
    say(("waypoint: %s  SPF's bend %s  Waypoint UI holding %s  tracked %s"):format(
        wmap and ("map %s %s / %s"):format(S(wmap), Num(wx * 100, 2), Num(wy * 100, 2)) or "none",
        S(SPF.Bend() ~= nil), S(WaypointUIHolding()), S(WaypointUITracking())))
    -- SPF's last bend (guideWaypoint): empty while a pin of the player's is tracked during a journey means SPF wrote
    -- no bend (docs/spf-issue-wegpunkt-rueckgabe.md)
    local spfDB = rawget(_G, "ShortestPathForeverCharDB")
    local saved = type(spfDB) == "table" and type(spfDB.guideWaypoint) == "table" and spfDB.guideWaypoint or nil
    local journey = api and type(api.Journey) == "function" and Try(api.Journey)
    say(("SPF bend saved: %s  journey owner %s  guided %s"):format(
        saved and IsNum(saved.x) and IsNum(saved.y)
            and ("map %s %s / %s"):format(S(saved.uiMapID), Num(saved.x * 100, 2), Num(saved.y * 100, 2)) or "none",
        S(type(journey) == "table" and journey.owner or nil), S(type(journey) == "table" and journey.guided or nil)))
    say(("SPF arrow: setting %s  frame found %s  shown %s  alpha %s  arrow part alpha %s"):format(
        S(SPF.Get("arrow")), S(spfArrow ~= nil), S(spfArrow and spfArrow:IsShown()),
        Num(spfArrow and spfArrow:GetAlpha(), 2), Num(spfArrow and spfArrow.Arrow:GetAlpha(), 2)))
    local px, py, inst = ns.PlayerPos()
    say(("player: instance %s  x %s  y %s  facing %s"):format(S(inst), Num(px), Num(py), Num(ns.PlayerFacing(), 2)))
    if not t then
        say("target: none (no RXP step target and no SPF waypoint)")
        return
    end
    say(("direction point: continent %s  x %s  y %s"):format(S(t.cont), Num(t.x), Num(t.y)))
    local goal = t.goal
    if goal then
        local yards, why = ns.DistanceTo(goal.cont, goal.x, goal.y)
        local unit = ns.db.nav.unit
        say(("goal: map %s  %s / %s  name %s  radius %s"):format(
            S(goal.mapID), Num(goal.mx * 100, 2), Num(goal.my * 100, 2), S(goal.name), S(goal.radius)))
        if yards then
            say(("distance: %s yd  (arrow shows %s %s, game yards as SPF counts them)"):format(
                Num(yards, 0), Num(ns.ToUnit(yards, unit), 0), S(unit)))
        else
            say("distance: none (" .. S(why) .. ")")
        end
    else
        say("goal: none (SPF waypoint only)")
    end
    if t.source == "SPF" then
        say(("next bend: %s yd away"):format(Num((ns.DistanceTo(t.cont, t.x, t.y)), 0)))
    end
    local e = ns.ETA()
    if e.seconds then
        local modes = {}
        for i, leg in ipairs(type(e.legs) == "table" and e.legs or {}) do modes[i] = S(leg.mode) end
        say(("ETA: %s  (%s s)%s  legs: %s"):format(
            S(ns.FormatTime(e.seconds)), Num(e.seconds, 0), e.stale and "  held (combat)" or "",
            #modes > 0 and table.concat(modes, " > ") or "-"))
    else
        say("ETA: none (" .. S(e.reason) .. ")")
    end
    local tr = ns.Transport()
    if tr then
        say(("transport: %s to %s  wait %s s"):format(S(tr.mode), S(tr.to), Num(tr.wait, 0)))
    else
        say("transport: no")
    end
end
