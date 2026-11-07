-- Target switch: ShortestPathForever guides one journey at a time, and both the RestedXP guide and the player's own
-- journeys (a quest's "Plan journey", a map click, /way) use it, each replacing the other. Here the player's last own
-- journey is remembered, so one action sets the guide's target again or switches back and forth:
-- header button in the guide window, button in the Journey header of the tracker, Shift-click on the arrow,
-- key bindings and /brxp target.
-- The own journey is read from SPF's per-character SavedVariables (ShortestPathForeverCharDB.journey), which SPF
-- only writes with its "Keep journeys after a reload" setting on (option nav.rememberJourney switches it on).
local _, ns = ...
local L = ns.L

local Try = ns.Try

local GUIDE = "RestedXP" -- SPF's owner id for RXP guidance
local OWN = "Shortest Path Forever" -- SPF keeps API journeys under its own name as the player's own ones
local TRACKER_NAME = "ShortestPathForeverObjectiveTracker" -- SPF's Journey module
local ICON = "Interface\\Buttons\\UI-RefreshButton"

local Targets = {}
ns.Targets = Targets

-- The player's last own journey this session: { mapID, mx, my, label (SPF's, may be nil), name (label or zone),
-- questID, goal }; goal as ns.MakeGoal builds it.
local last
-- Who SPF guided after the last burst of changes: "guide", "other" or nil.
local running

local function Num(v)
    return ns.CanAccess(v) and type(v) == "number" and v == v
end

local function Api()
    local api = ns.SPF and ns.SPF.Api()
    if api and type(api.NavigateRoute) == "function" then return api end
end

local function GuideRunning(api)
    return Try(api.CurrentStop, GUIDE) ~= nil
end

-- A world point (continent, x, y) as zone map and 0-1 position. The answer may be the continent map; then the zone
-- under the point is asked for again.
local function ZonePos(cont, x, y)
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local world = CreateVector2D(x, y)
    local mapID, pos = Try(C_Map.GetMapPosFromWorldPos, cont, world)
    if not (Num(mapID) and pos) then return end
    local info = C_Map.GetMapInfo and Try(C_Map.GetMapInfo, mapID)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    if type(info) == "table" and zoneType and info.mapType ~= zoneType and C_Map.GetMapInfoAtPosition then
        local px, py = Try(pos.GetXY, pos)
        local zone = Num(px) and Try(C_Map.GetMapInfoAtPosition, mapID, px, py)
        if type(zone) == "table" and zone.mapType == zoneType then
            local zoneID, zonePos = Try(C_Map.GetMapPosFromWorldPos, cont, world, zone.mapID)
            if Num(zoneID) and zonePos then mapID, pos = zoneID, zonePos end
        end
    end
    local mx, my = Try(pos.GetXY, pos)
    if Num(mx) and Num(my) then return mapID, mx, my end
end

-- The own journey SPF keeps right now, or nothing.
local function OwnJourney()
    local db = _G.ShortestPathForeverCharDB
    local j = type(db) == "table" and db.journey
    if type(j) ~= "table" or not (Num(j.map) and Num(j.x) and Num(j.y)) then return end
    local mapID, mx, my = ZonePos(j.map, j.x, j.y)
    if not mapID then return end
    local label = ns.CanAccess(j.label) and type(j.label) == "string" and j.label ~= "" and j.label or nil
    -- a map click or /way without a title: the zone's name for the arrow and the tooltip
    local info = not label and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, mapID)
    local name = label or type(info) == "table" and ns.CanAccess(info.name) and type(info.name) == "string" and info.name or nil
    return {
        mapID = mapID, mx = mx, my = my, label = label, name = name,
        questID = Num(j.questID) and j.questID >= 1 and j.questID or nil,
        goal = ns.MakeGoal(mapID, mx, my, name),
    }
end

-- Goal of the journey under way when it is the remembered own one (SPFBridge: distance, name and time on the arrow).
function Targets.OtherGoal()
    return running == "other" and last and last.goal or nil
end

local RefreshButtons -- defined below the buttons

-- SPF tells us once per burst; by then SPF has written or cleared its kept journey.
local function OnChanges()
    local api = Api()
    if not api then return end
    if GuideRunning(api) then
        running = "guide"
    elseif Try(api.Active) then
        running = "other"
        local own = OwnJourney()
        if own then last = own end
    else
        if running == "other" then last = nil end -- arrived or cleared: nothing to go back to
        running = nil
    end
    RefreshButtons()
    if ns.Arrow then ns.RefreshAll() end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Actions

-- A waypoint still on the map (the player's own, another addon's, a bend left over from before) would stand in SPF's
-- way: SPF keeps a waypoint it finds when a journey starts as the player's, and the user saw journeys without bends and
-- the arrow aiming at the end. Every switch clears it first (only the game's own waypoint; ending its tracking is the
-- game's part of clearing it).
local function ClearWaypoint()
    if not (C_Map and type(C_Map.HasUserWaypoint) == "function" and type(C_Map.ClearUserWaypoint) == "function") then return end
    if Try(C_Map.HasUserWaypoint) then pcall(C_Map.ClearUserWaypoint) end
end

local function Navigate(owner, stop)
    local api = Api()
    if not api then
        ns.Say(L["ShortestPathForever is not loaded."])
        return
    end
    ClearWaypoint()
    local ok, started = pcall(api.NavigateRoute, owner, { stop })
    if not (ok and started) then ns.Say(L["ShortestPathForever could not plan this journey."]) end
end

local function GoGuide()
    local goal = ns.GuideGoal()
    if not goal then
        ns.Say(L["RestedXP has no target right now."])
        return
    end
    -- hold: RestedXP decides when the step is done, as for SPF's own guide journeys
    Navigate(GUIDE, { map = goal.mapID, x = goal.mx, y = goal.my, title = goal.name or "RestedXP", hold = true })
end

local function GoLast()
    Navigate(OWN, { map = last.mapID, x = last.mx, y = last.my, title = last.label, questID = last.questID })
end

-- What a click does now: "guide" or "other".
local function NextAction()
    local api = Api()
    if api and last and GuideRunning(api) then return "other" end
    return "guide"
end

-- Switch between the guide's target and the last own journey; guideOnly sets the guide's target again.
-- In combat SPF plans nothing: the action runs when combat ends.
function Targets.Switch(guideOnly)
    if InCombatLockdown() then ns.Say(L["The target changes after combat."]) end
    ns.Queue(function()
        if not guideOnly and NextAction() == "other" then GoLast() else GoGuide() end
    end)
end

-- Tooltip lines for every button that switches.
function Targets.AddTooltip(tooltip)
    tooltip:AddLine(L["Switch target"], 1, 0.82, 0.45)
    if not Api() then
        tooltip:AddLine(L["ShortestPathForever is not loaded."], 1, 1, 1, true)
        return
    end
    if NextAction() == "other" then
        tooltip:AddLine(L["Click: switch to your journey"] .. (last.name and (": " .. last.name) or ""), 1, 1, 1, true)
    else
        local goal = ns.GuideGoal()
        tooltip:AddLine(L["Click: set the guide's target again"] .. (goal and goal.name and (": " .. goal.name) or ""), 1, 1, 1, true)
    end
    if last then tooltip:AddLine(L["Shift-click: the guide's target"], 0.7, 0.7, 0.7, true) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Button in the Journey header of the tracker

local trackerButton
local trackerHover = false

-- Accent coloured like the guide window's cog: the desaturated icon tinted, the same texture added on top for full
-- brightness; lighter towards white under the mouse.
local function PaintTrackerButton()
    local r, g, b = ns.Accent()
    local k = trackerHover and 0.35 or 0
    r, g, b = r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
    trackerButton.icon:SetVertexColor(r, g, b, 1)
    trackerButton.glow:SetVertexColor(r, g, b, trackerHover and 0.6 or 0.4)
end

local function MakeTrackerButton(header)
    local b = CreateFrame("Button", nil, header)
    b:SetSize(16, 16)
    b:SetFrameLevel(header:GetFrameLevel() + 2)
    local anchor = header.MinimizeButton
    if type(anchor) == "table" and anchor.GetObjectType then
        b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    else
        b:SetPoint("RIGHT", header, "RIGHT", -24, 0)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ICON)
    b.icon:SetDesaturated(true)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints(b.icon)
    b.glow:SetTexture(ICON)
    b.glow:SetBlendMode("ADD")
    b.glow:SetDesaturated(true)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() Targets.Switch(IsShiftKeyDown()) end)
    b:SetScript("OnEnter", function(self)
        trackerHover = true
        PaintTrackerButton()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Targets.AddTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        trackerHover = false
        PaintTrackerButton()
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    return b
end

function RefreshButtons()
    if not trackerButton then
        local module = _G[TRACKER_NAME]
        local header = type(module) == "table" and module.Header
        if type(header) ~= "table" or type(header.GetFrameLevel) ~= "function" then return end
        trackerButton = MakeTrackerButton(header)
    end
    PaintTrackerButton()
    trackerButton:SetShown(Api() ~= nil)
end

-- ---------------------------------------------------------------------------------------------------------------
-- GearQuest Forever: its "arrow on" for a hunt (GQ.Guide:ShowEntry) becomes the player's own SPF journey, so the one
-- arrow shows the hunt (also across continents: boat, zeppelin ...) and the target switch toggles between the hunt
-- and the guide. GearQuest itself only sets a Blizzard waypoint. While this works, GearQuest's own arrow stays off
-- (ns.GQArrowShared, read by the Extras pack). With our arrow switched off nothing would show the hunt, so GearQuest
-- keeps its own arrow and its waypoint then.
local gqHooked = false
local gqOwned = false -- the running own journey is a GearQuest hunt we started

local function ArrowOn()
    return ns.db ~= nil and ns.db.nav.showArrow ~= false
end

-- On the host, not on this pack's namespace: the Extras pack reads it through its own fall-through to the host.
function ns.host.GQArrowShared()
    return gqHooked and Api() ~= nil and ArrowOn()
end

local function GearQuestJourney(entry)
    if not ArrowOn() then return end
    local api = Api()
    local gq = rawget(_G, "GearQuest")
    if not (api and type(entry) == "table" and type(gq) == "table" and type(gq.Map) == "table") then return end
    local spot = Try(gq.Map.SpotForEntry, gq.Map, entry)
    if type(spot) ~= "table" or not (Num(spot.mapId) and Num(spot.x) and Num(spot.y)) then return end
    local name = Try(function() return gq.Data:GetEntryDisplayName(entry) end)
    if type(name) ~= "string" or name == "" then name = type(entry.questName) == "string" and entry.questName or nil end
    gqOwned = true
    ns.Queue(function()
        -- GearQuest's own waypoint (a pin on the hunt's zone, tracked) would hide SPF's bends from the arrow
        if type(gq.Guide) == "table" and type(gq.Guide.ClearForeverPin) == "function" then
            pcall(gq.Guide.ClearForeverPin, gq.Guide)
        end
        ClearWaypoint()
        -- GearQuest's spot is in percent, SPF wants 0-1
        local ok, started = pcall(api.NavigateRoute, OWN, { { map = spot.mapId, x = spot.x / 100, y = spot.y / 100, title = name } })
        if not (ok and started) then
            gqOwned = false
            ns.Say(L["ShortestPathForever could not plan this journey."])
        end
    end)
end

local function GearQuestDismissed()
    local api = Api()
    if gqOwned and api and running == "other" then pcall(api.Cancel, OWN) end
    gqOwned = false
end

local function HookGearQuest()
    if gqHooked then return end
    local gq = rawget(_G, "GearQuest")
    local guide = type(gq) == "table" and gq.Guide
    if type(guide) ~= "table" or type(guide.ShowEntry) ~= "function" or type(guide.Dismiss) ~= "function" then return end
    gqHooked = true
    hooksecurefunc(guide, "ShowEntry", function(_, entry) ns.Try(GearQuestJourney, entry) end)
    hooksecurefunc(guide, "Dismiss", function() ns.Try(GearQuestDismissed) end)
    ns.RefreshAll() -- the Extras pack drops its own arrow now
end

-- ---------------------------------------------------------------------------------------------------------------
-- Wiring

-- Key bindings (Bindings.xml) need real globals.
BINDING_HEADER_BRXP = "BeautifulRestedXP"
BINDING_NAME_BRXP_SWITCH_TARGET = L["Switch target (guide / your journey)"]
BINDING_NAME_BRXP_GUIDE_TARGET = L["Set the guide's target again"]

function BeautifulRestedXP_SwitchTarget()
    Targets.Switch(false)
end

function BeautifulRestedXP_GuideTarget()
    Targets.Switch(true)
end

-- /brxp target [guide]
function ns.TargetCommand(arg)
    Targets.Switch(arg == "guide")
end

ns.OnLoaded(function()
    local api = Api()
    if api and type(api.Subscribe) == "function" then pcall(api.Subscribe, OnChanges) end
    HookGearQuest()
end)

local spfArrowChecked = false

ns.RegisterRefresh(function()
    if not ns.db then return end
    -- once, after the option arrived: switch SPF's "Keep journeys after a reload" on (remembered, put back by Reset)
    if ns.loggedIn and not ns.db.rememberJourneySynced and ns.SPF.Loaded() then
        ns.db.rememberJourneySynced = true
        ns.SPF.OnOptionChanged("rememberJourney")
    end
    -- once per session: SPF's "Show direction arrow" on for the bends of our arrow, also when it was switched off in SPF
    if ns.loggedIn and not spfArrowChecked and ns.SPF.Loaded() then
        spfArrowChecked = true
        ns.SPF.OnOptionChanged("showArrow")
    end
    RefreshButtons()
    HookGearQuest() -- GearQuest may load after us
end)

-- /brxp nav: the switch's state.
local baseNavDebug = ns.NavDebug
function ns.NavDebug()
    if baseNavDebug then baseNavDebug() end
    ns.Say(("switch: running %s  next %s  last journey %s"):format(tostring(running), NextAction(),
        last and ("'%s' map %d %.1f/%.1f quest %s"):format(tostring(last.name), last.mapID, last.mx * 100, last.my * 100,
            tostring(last.questID)) or "-"))
end
